import { BlockData } from '../../core/models/Block';
import { BlockView } from './BlockView';
import { BlockSelection } from './BlockSelection';
import { FindInPage } from './FindInPage';
import { BlockDragLayer, forwardRowGrab } from './BlockDragLayer';
import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';
import { SlashMenu } from './SlashMenu';
import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';

/**
 * BlockDataSource — LazyForEach 数据源。
 * 管理**可见行**序列（顶层块 + 已展开子块，屏幕从上到下的顺序）。
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
 * **所有可见行**（顶层块 + 已展开子块）使用 LazyForEach 虚拟列表优化性能。
 * 展平在 `WorkspaceService.getVisibleBlocks`（BlockTree 单一实现）完成；
 * `BlockChildren` 组件仍保留（供其它调用方/后续复用），但本组件的渲染路径已不再经过它。
 *
 * 对应 Logseq components/block.cljs 的列表层。
 *
 * S1-B：顶层 LazyForEach 的宿主由普通 Column 改为 List。
 * 依据 SDK `lazy_for_each.d.ts:881-883` —— LazyForEach 的组件创建/销毁回收
 * （即虚拟化）以「位于滚动容器内」为前提。此前宿主是不滚动的 Column，
 * 外层滚动由 ContentArea 的 Scroll 承担，导致虚拟化完全未生效。
 * 现在 List 自身即滚动容器，虚拟化条件成立，同时不再有 List 套 Scroll 的双层滚动。
 *
 * S1-B 后续（本次修复）：List 宿主要求 **每个 ListItem 的高度由内容确定**，而原先
 * 「一行 = 顶层块，子块树由 BlockChildren 塞进同一个 item」的结构满足不了这一点：
 * List 测量该 item 时拿不到确定高度，会把整个视口高度分给它，该高度沿 Column 链传播到
 * 每个子行 → 子行被拉到数百 vp、文字被推到容器底部，表现为**嵌套子块不渲染**。
 * 实测最小复现：两行页面 `- 父块` / `  - 子块`；把子行换成纯 Text 即恢复正常
 * （⇒ 由自定义组件链的高度契约触发，属结构性问题，局部属性改法无效）。
 * 现改为**预先展平可见行**：每个可见行各占 1 个 ListItem、只含 1 个 BlockView，
 * item 高度恒定。展平走 `WorkspaceService.getVisibleBlocks`（BlockTree 单一实现），
 * 与 U2.1a 的 scrollToIndex 下标空间同源。
 */
@Component
export struct BlockList {
  @Prop pageId: string = '';
  /**
   * 页面名。**必须 watch**：`AppState.setCurrentPage`（AppState.ets）只写 currentPage
   * 与历史栈，**不会** bump `callaite_blocksVersion`；而本组件的刷新入口只有
   * `aboutToAppear` 与 blocksVersion 的 @Watch 两个。两个**页面路由**之间切换时
   * （同一个 PageView 复用同一个 BlockList 实例）二者都不触发 → 列表会继续显示
   * 上一页的行（实测：__S1_long → 未命名笔记 后仍显示 300 行「测试块 N」）。
   * 补齐 pageName 的 watch 后，切页即重算。
   */
  @Prop @Watch('onPageNameChanged') pageName: string = '';
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
  /**
   * 顶层块（`getPageBlocks`）。**不是** List 的数据源，只用于两件事：
   *   · 空态判定（顶层为空 ⇔ 无可见行）；
   *   · 尾部新增块时取 leftId —— 必须取顶层块的最后一个，取错层级会把新块挂到别人孩子下面。
   */
  @State blocks: BlockData[] = [];
  /** 可见行序列（List 的数据源；顶层块 + 已展开子块，屏幕顺序）。 */
  @State rows: BlockData[] = [];
  @State slashMenuVisible: boolean = false;
  @State slashMenuBlockUuid: string = '';
  @State findInPageVisible: boolean = false;
  /**
   * S1-H：当前页 uuid。
   *
   * 拖拽层需要它做「幽灵行」的跨页校验（命中表是模块级共享的，换页/复用后
   * 若残留了别的页面的行记录，不得成为落点）。refreshBlocks 每次刷新都会同步它。
   */
  @State pageUuidForDrag: string = '';
  // 监听 blocksVersion 变化，触发刷新
  @StorageLink('callaite_blocksVersion') @Watch('onBlocksVersionChanged') private blocksVersion: number = 0;
  // LazyForEach 数据源
  private dataSource: BlockDataSource = new BlockDataSource();
  // 自持 Scroller：未注入外部 Scroller 时使用（ArkTS 不支持 ??=）。
  // 成员初始化先于 aboutToAppear / build，故 build() 中一定非空。
  private ownScroller: Scroller = new Scroller();
  /**
   * S1-H：整页拖拽层的注册键（**整页只对应 1 个实例**）。
   *
   * ArkTS 不允许把 UI 组件实例化语句写成赋值表达式
   * （编译器报 "'this.x = BlockDragLayer({...})' does not meet UI component syntax"），
   * 因此父组件无法用成员变量持有子组件实例。改为：拖拽层在 aboutToAppear 时按本 key
   * 自注册到模块级实例表（BlockDragLayer.ets 的 bindDragLayer），
   * 行内长按回调按同一 key 路由（forwardRowGrab）—— 「整页 1 个实例」的语义不变。
   *
   * 每个 BlockList（含分屏的另一窗格 / feed 内嵌）生成各自的 key，
   * 但只有整页分支会实例化拖拽层，故实际绑定数 == 整页大纲数。
   */
  private dragLayerId: string = '';

  /**
   * 惰性生成本实例的注册键。
   * 用 ArkUI 的组件唯一 id（CustomComponent.getUniqueId，common.d.ts:24726）而不是随机数：
   * 天然每实例唯一、无需额外 import，也不会与其它实例撞键。
   */
  private ensureDragLayerId(): string {
    if (this.dragLayerId === '') {
      this.dragLayerId = 'callaite_blockDragLayer_' + this.getUniqueId();
    }
    return this.dragLayerId;
  }

  /**
   * S1-H：行长按回调 —— 转发给本整页唯一的拖拽层。
   * 行本身不做任何命中/落库，只上报「哪一行 + 按下点窗口坐标」。
   */
  private handleRowGrab(uuid: string, globalX: number, globalY: number): void {
    forwardRowGrab(this.ensureDragLayerId(), uuid, globalX, globalY);
  }

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

  /**
   * 页面名变化（切页）时刷新。
   * 必要性见 pageName 字段注释：切页不会 bump blocksVersion。
   */
  onPageNameChanged(): void {
    this.refreshBlocks();
  }

  /**
   * 刷新渲染序列。
   *
   * `blocks`（顶层）与 `rows`（可见行）职责分离，理由见各字段注释。
   * 折叠态**不落盘**（磁盘 .md 无 collapsed 字段），因此 rows 每次都从 BlockTree 现算，
   * 绝不缓存；折叠/展开经 `AppState.bumpBlocksVersion` → `onBlocksVersionChanged` 回到这里。
   */
  refreshBlocks(): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.pageName);
    if (page) {
      this.blocks = ws.getPageBlocks(page.uuid);
      this.rows = ws.getVisibleBlocks(page.uuid);
      this.pageUuidForDrag = page.uuid;
    } else {
      this.blocks = [];
      this.rows = [];
      this.pageUuidForDrag = '';
    }
    this.dataSource.setBlocks(this.rows);
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
            // 可见行序列使用 LazyForEach（宿主是 Column，不做虚拟化）。
            // 与整页分支同样展平：每个可见行只含一个 BlockView ⇒ 行高由内容确定，
            // 不会出现「父行把整棵子树包在一个容器里」导致的高度传播。
            LazyForEach(this.dataSource, (row: BlockData) => {
              Column() {
                BlockView({ blockUuid: row.uuid, depth: row.level })
              }
              .width('100%')
            }, (row: BlockData) => row.uuid)
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
              // 可见行序列使用 LazyForEach 虚拟列表。
              // List 宿主下 itemGenerator 必须直接产出 ListItem，虚拟化在此条件下生效
              // （SDK lazy_for_each.d.ts:881-883：组件回收以「位于滚动容器内」为前提）。
              //
              // 每个可见行 = 1 个 ListItem + 1 个 BlockView（**不再把子块树塞进同一个 item**）：
              // item 高度只由该行 BlockView 的内容决定，List 因此能正确测量并回收，
              // 同时消除了 S1-B 之后「List 把视口高度让给报不出确定高度的 item」的拉伸传播。
              LazyForEach(this.dataSource, (row: BlockData) => {
                ListItem() {
                  // ⚠️ 这个 Column 包装**不可省略**（实测）：
                  //   直接把自定义组件 BlockView 作为 ListItem 的唯一子节点时，BlockView 相当于
                  //   matchParent 子组件，List 仍会把剩余视口高度分给该 item（父行 400vp+，子行被推下去）；
                  //   套一层 `Column().width('100%')` 后，容器先被有确定尺寸的内容撑开、item 高度
                  //   回到内容高度 —— 与扁平页（`__S1_long` 每行 48vp）的结构完全一致。
                  Column() {
                    // S1-H：onRowGrab 指向**同一个**拖拽层实例（见 handleRowGrab），
                    // 行内不挂任何拖拽/Pan 手势，位移跟踪全部由该单实例承担。
                    // 展平后每行 uuid 唯一且明确，长按上报 / 命中表 / 落库三者的 uuid 一一对应。
                    BlockView({
                      blockUuid: row.uuid,
                      depth: row.level,
                      onRowGrab: (uuid: string, gx: number, gy: number) => {
                        this.handleRowGrab(uuid, gx, gy);
                      }
                    })
                  }
                  .width('100%')
                }
              }, (row: BlockData) => row.uuid)
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

        // ─── S1-H：块拖拽重排层 ───
        // 位置：整页分支的 Stack 内、**List 之外**，且整页只挂这 1 个实例。
        // 因此不存在「每行一个手势容器」与 List 纵向滚动竞争的问题；
        // 行内只保留一个 LongPressGesture（时长内不移动 → 滚动识别器判负），
        // 位移跟踪由本层的 onTouch 承担。
        // 命中模式为 Transparent（层内自设）：本层参与命中但不阻塞兄弟 List 的命中，
        // 滚动、行内点击、hover 全部照旧。
        BlockDragLayer({
          layerId: this.ensureDragLayerId(),
          pageUuid: this.pageUuidForDrag,
          scroller: this.activeScroller()
        })
      }

      // 多选批量操作浮动栏 + 多选入口（feed 内嵌模式不渲染，避免每个日期节叠一层）
      // U1.4：pageId 必须传**真实页面 uuid**。此前这里传的是 this.pageId，而 BlockList
      // 的唯一调用点（PageView.ets:249）根本没传 pageId ⇒ @Prop 恒为 ''，
      // 「全选」因此走 selectAll('') → getTopLevelBlocks('') → 空列表，点了没反应。
      // pageUuidForDrag 是 refreshBlocks 每次刷新的本页 uuid（S1-H 已备），直接复用，
      // 不再新增第二个 uuid 来源（避免两处漂移）。
      if (!this.embedded) {
        BlockSelection({ pageId: this.pageUuidForDrag })
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
