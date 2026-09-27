import { BlockData } from '../../core/models/Block';
import { BlockView } from './BlockView';
import { BlockChildren } from './BlockChildren';
import { BlockSelection } from './BlockSelection';
import { FindInPage } from './FindInPage';
import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';
import { SlashMenu } from './SlashMenu';
import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';

/**
 * BlockDataSource — LazyForEach 数据源。
 * 仅管理顶层 Block，子 Block 由 BlockChildren 组件递归管理。
 */
class BlockDataSource implements IDataSource {
  private blocks: BlockData[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.blocks.length;
  }

  getData(index: number): BlockData {
    return this.blocks[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  setBlocks(blocks: BlockData[]): void {
    this.blocks = blocks;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  getBlocks(): BlockData[] {
    return this.blocks;
  }
}

/**
 * BlockList — Block 列表组件。
 *
 * 管理页面的 Block 列表显示、焦点、键盘快捷键、Slash 菜单、页内搜索。
 * 顶层 Block 使用 LazyForEach 虚拟列表优化性能。
 * 子 Block 由 BlockChildren 组件递归渲染。
 *
 * 对应 Logseq components/block.cljs 的列表层。
 *
 * S1-B：顶层 LazyForEach 的宿主由普通 Column 改为 List。
 * 依据 SDK `lazy_for_each.d.ts:881-883` —— LazyForEach 的组件创建/销毁回收
 * （即虚拟化）以「位于滚动容器内」为前提。此前宿主是不滚动的 Column，
 * 外层滚动由 ContentArea 的 Scroll 承担，导致虚拟化完全未生效。
 * 现在 List 自身即滚动容器，虚拟化条件成立，同时不再有 List 套 Scroll 的双层滚动。
 */
@Component
export struct BlockList {
  @Prop pageId: string = '';
  @Prop pageName: string = '';
  // embedded=true 时用于日志流 feed 内嵌：高度自适应内容、不渲染多选浮动栏
  @Prop embedded: boolean = false;
  /**
   * 可选外部 Scroller。
   * embedded=false（整页大纲）时由 ContentArea 注入，使上层可对 Block 列表定位
   * （U2.1a 块定位备用）；embedded=true（日志流 feed 内嵌）时必须留空 ——
   * feed 每一节都不能自建滚动容器，否则与外层 JournalFeed 的 Scroll 冲突。
   *
   * 该字段故意不加 @Prop：Scroller 是稳定引用对象，无需参与 ArkTS 状态观察，
   * 普通成员变量在父组件构造时同步赋值，build() 首次执行前已就绪。
   */
  scroller?: Scroller;
  @State blocks: BlockData[] = [];
  @State slashMenuVisible: boolean = false;
  @State slashMenuBlockUuid: string = '';
  @State findInPageVisible: boolean = false;
  // 监听 blocksVersion 变化，触发刷新
  @StorageLink('callaite_blocksVersion') @Watch('onBlocksVersionChanged') private blocksVersion: number = 0;
  // LazyForEach 数据源
  private dataSource: BlockDataSource = new BlockDataSource();
  // 自持 Scroller：未注入外部 Scroller 时使用（ArkTS 不支持 ??=）。
  // 成员初始化先于 aboutToAppear / build，故 build() 中一定非空。
  private ownScroller: Scroller = new Scroller();

  /**
   * 实际使用的 Scroller。
   * ArkTS 禁用 any/unknown，scroller 为可选字段，需显式收窄类型后才能传给 List。
   */
  private activeScroller(): Scroller {
    const s = this.scroller;
    if (s !== undefined) {
      return s;
    }
    return this.ownScroller;
  }

  /**
   * 供上层取用的滚动控制器（S1-B 第 3 项：仅暴露，不实现定位逻辑）。
   * 整页模式下返回 ContentArea 注入的同一实例，保证上下层拿到同一个 Scroller。
   */
  getScroller(): Scroller {
    return this.activeScroller();
  }

  aboutToAppear(): void {
    this.refreshBlocks();
  }

  /**
   * blocksVersion 变化时刷新 Block 列表。
   * 由 BlockView 的折叠/缩进/移动/删除等操作触发。
   */
  onBlocksVersionChanged(): void {
    this.refreshBlocks();
  }

  refreshBlocks(): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.pageName);
    if (page) {
      this.blocks = ws.getPageBlocks(page.uuid);
    } else {
      this.blocks = [];
    }
    this.dataSource.setBlocks(this.blocks);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.embedded) {
        // ─── 内嵌模式（JournalFeed 日志流每一节）───
        // 不自建滚动容器：高度自适应内容，滚动由外层 JournalFeed 的 Scroll 承担。
        // 此处 LazyForEach 宿主仍是 Column —— 内嵌场景本就处于滚动容器之外，
        // 虚拟化无法生效（S1-B 之前整页模式同样如此），行为与迁移前完全一致。
        Column({ space: 0 }) {
          // 页内搜索栏
          if (this.findInPageVisible) {
            FindInPage({ pageId: this.pageId })
          }

          if (this.blocks.length === 0) {
            this.EmptyState()
          } else {
            // 顶层 Block 使用 LazyForEach 虚拟列表（宿主即上层 List）
            LazyForEach(this.dataSource, (block: BlockData) => {
              Column() {
                BlockView({ blockUuid: block.uuid, depth: block.level })

                // 子 Block 由 BlockChildren 组件递归渲染
                if (!block.collapsed) {
                  BlockChildren({ parentUuid: block.uuid, depth: block.level })
                }
              }
              .width('100%')
            }, (block: BlockData) => block.uuid)
          }

          // 底部添加按钮（feed 内嵌模式不渲染 — Logseq 无显式添加按钮，回车即新建）
          if (!this.embedded) {
            this.AddBlockButton()
          }

          // Slash 命令菜单
          if (this.slashMenuVisible) {
            SlashMenu({ blockUuid: this.slashMenuBlockUuid })
          }
        }
        .width('100%')
        .height('auto')
      } else {
        // ─── 整页模式（PageView 大纲页）───
        // List 自身即滚动容器，LazyForEach 的虚拟化在此条件下才真正生效。
        Column({ space: 0 }) {
          // 页内搜索栏（浮动在顶部）
          if (this.findInPageVisible) {
            FindInPage({ pageId: this.pageId })
          }

          List({ space: 0, scroller: this.activeScroller() }) {
            if (this.blocks.length === 0) {
              // 空态也必须是 ListItem —— List 的直接子节点只能是 ListItem/ListItemGroup
              ListItem() {
                this.EmptyState()
              }
            } else {
              // 顶层 Block 使用 LazyForEach 虚拟列表。
              // List 宿主下 itemGenerator 必须直接产出 ListItem，虚拟化在此条件下生效
              // （SDK lazy_for_each.d.ts:881-883：组件回收以「位于滚动容器内」为前提）。
              LazyForEach(this.dataSource, (block: BlockData) => {
                ListItem() {
                  Column() {
                    BlockView({ blockUuid: block.uuid, depth: block.level })

                    // 子 Block 由 BlockChildren 组件递归渲染
                    if (!block.collapsed) {
                      BlockChildren({ parentUuid: block.uuid, depth: block.level })
                    }
                  }
                  .width('100%')
                }
              }, (block: BlockData) => block.uuid)
            }

            // 底部添加按钮：作为列表尾项，位置/外观与迁移前一致
            // （迁移前它在 Column 尾部，随内容滚动到最下方）
            if (!this.embedded) {
              ListItem() {
                this.AddBlockButton()
              }
            }
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)

          // Slash 命令菜单
          if (this.slashMenuVisible) {
            SlashMenu({ blockUuid: this.slashMenuBlockUuid })
          }
        }
        .width('100%')
        .height('100%')
      }

      // 多选批量操作浮动栏（feed 内嵌模式不渲染，避免每个日期节叠一层）
      if (!this.embedded) {
        BlockSelection({ pageId: this.pageId })
      }
    }
    .width('100%')
    .height(this.embedded ? 'auto' : '100%')
  }

  // ─── 空页面状态 ───
  // Logseq 风格：左对齐的项目符号点 + 弱化占位提示，而非居中的大图标。

  @Builder
  EmptyState() {
    Row({ space: 10 }) {
      // 项目符号点（Logseq 的标志性视觉元素）
      Circle({ width: 5, height: 5 })
        .fill($r('app.color.bullet'))
      Text(t('placeholder_block'))
        .fontSize(15)
        .fontColor($r('app.color.muted_text'))
    }
    .width('100%')
    .height(40)
    .padding({ left: 6, top: 12 })
    .onClick(() => {
      this.addTopLevelBlock();
    })
  }

  // ─── 底部添加按钮 ───
  // Logseq 无显式添加按钮（回车即新建），这里弱化为幽灵行。

  @Builder
  AddBlockButton() {
    Row({ space: 10 }) {
      Circle({ width: 5, height: 5 })
        .fill($r('app.color.bullet'))
      TablerIcon('plus', 15, $r('app.color.muted_text'))
      Text(t('add'))
        .fontSize(14)
        .fontColor($r('app.color.muted_text'))
    }
    .width('100%')
    .height(36)
    .padding({ left: 6, top: 4 })
    .onClick(() => {
      this.addTopLevelBlock();
    })
  }

  // ─── 操作 ───

  addTopLevelBlock(): void {
    const ws = WorkspaceService.getInstance();
    // 页面不存在时懒创建（日志流 feed 中的空日期页首次编辑时落库）
    let page = ws.getPageByName(this.pageName);
    if (!page) {
      page = ws.createPage(this.pageName);
    }

    const result = ws.executeOp({
      type: 'insert-block',
      content: '',
      pageId: page.uuid,
      parentId: page.uuid,
      leftId: this.blocks.length > 0 ? this.blocks[this.blocks.length - 1].uuid : '',
      level: 0
    });

    this.refreshBlocks();
  }

  openSlashMenu(blockUuid: string): void {
    this.slashMenuBlockUuid = blockUuid;
    this.slashMenuVisible = true;
  }

  // ─── 页内搜索 ───

  toggleFindInPage(): void {
    this.findInPageVisible = !this.findInPageVisible;
  }

  showFindInPage(): void {
    this.findInPageVisible = true;
  }

  hideFindInPage(): void {
    this.findInPageVisible = false;
  }
}
