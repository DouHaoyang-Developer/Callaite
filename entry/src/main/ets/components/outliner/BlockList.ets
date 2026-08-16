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
 */
@Component
export struct BlockList {
  @Prop pageId: string = '';
  @Prop pageName: string = '';
  @State blocks: BlockData[] = [];
  @State slashMenuVisible: boolean = false;
  @State slashMenuBlockUuid: string = '';
  @State findInPageVisible: boolean = false;
  // 监听 blocksVersion 变化，触发刷新
  @StorageLink('callaite_blocksVersion') @Watch('onBlocksVersionChanged') private blocksVersion: number = 0;
  // LazyForEach 数据源
  private dataSource: BlockDataSource = new BlockDataSource();

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
      Column({ space: 0 }) {
        // 页内搜索栏（浮动在顶部）
        if (this.findInPageVisible) {
          FindInPage({ pageId: this.pageId })
        }

        // Block 列表
        if (this.blocks.length === 0) {
          this.EmptyState()
        } else {
          // 顶层 Block 使用 LazyForEach 虚拟列表
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

        // 底部添加按钮
        this.AddBlockButton()

        // Slash 命令菜单
        if (this.slashMenuVisible) {
          SlashMenu({ blockUuid: this.slashMenuBlockUuid })
        }
      }
      .width('100%')
      .height('100%')

      // 多选批量操作浮动栏
      BlockSelection({ pageId: this.pageId })
    }
    .width('100%')
    .height('100%')
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
      this.addaopLevelBlock();
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
      this.addaopLevelBlock();
    })
  }

  // ─── 操作 ───

  addaopLevelBlock(): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.pageName);
    if (!page) {
      return;
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
