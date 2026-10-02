import { BlockData } from '../../core/models/Block';
import { BlockView } from './BlockView';
import { BlockSelection } from './BlockSelection';
import { BlockDragLayer, forwardRowGrab } from './BlockDragLayer';
import {
  bindSlashMenuSlot,
  unbindSlashMenuSlot,
  SlashMenuRequestHandler
} from './BlockListSlashSlot';
import { WorkspaceService } from '../../services/WorkspaceService';
import { BlockAnchorService } from '../../services/BlockAnchorService';
import { EditorService } from '../../services/EditorService';
import { SlashMenu } from './SlashMenu';
import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { t } from '../../utils/i18n';

/**
 * 日志流内嵌模式（embedded=true，JournalFeed 的「每天一节」）**每节最多实例化的行数**。
 *
 * ─── 为什么必须有这个上限（S3-W6 实测，硬证据）───
 * 内嵌模式的 LazyForEach 宿主是普通 `Column`（见 build() 内嵌分支注释），
 * 而 `LazyForEach` **只在 List/Grid/WaterFall 等滚动容器内才虚拟化**（AGENTS §7 陷阱 8）
 * ⇒ 该分支的「可见行序列」是**全量实例化**的。
 * 平时这没问题（一天的日志通常几块到几十块），但只要**某一天的页面很大**，
 * 它就会把整页的行塞进「默认落点」的首页：
 *   实测夹具 `2026-09-30.md` = 1037 块（W8 遗留的 1000 块压测页，**恰好是一个日志日期**），
 *   落在日志流默认的 7 天窗口（2026-09-26…2026-10-02）内
 *   ⇒ 首页一次实例化 1046 行（1037 + 今天 9）
 *   ⇒ **22,322 个 a11y 节点 / Total Pss 774,134 kB (≈756 MB)**，a11y 树被压垮，
 *      `uitest dumpLayout` 与 `-uiLayout -i` **两条通道同时丢失应用子树**（阻断验收本身）。
 *
 * ─── 对照组（同一构建 / 同一 vault / 同一台机，只换落点）───
 * 同一个 1037 块页面以**文档页**打开时，走的是 `List` + LazyForEach（真虚拟化）
 * ⇒ 只实例化 **14 行** ⇒ **662 个 a11y 节点 / 119,119 kB (≈116.3 MB)** ✓
 * （与 W8 的 116.9 MB 基线吻合）。
 * ⇒ **膨胀的唯一变量是「容器是否虚拟化」，不是数据量、不是日期枚举范围。**
 *
 * ─── 取值 ───
 * 30 行/节 × 7 节上限 = 210 行（现实中最坏情形），仍比 1046 行低一个数量级；
 * 单日日志通常远小于 30 行 ⇒ 正常用户**看不到本上限的存在**。
 * 超出部分不丢失：节尾渲染 `TruncationFooter()`，点击进入该日单日页
 * （那里是虚拟化的 List，可浏览与编辑全部块）。
 */
const EMBEDDED_MAX_ROWS: number = 30;

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
  // ─── S3-W4（W13-4 清理）：`@Prop pageId` 已**整段删除** ───
  // 它曾是本组件的对外入参，但消费方在 W13 就已被替换掉、传入方在 W3 也被删掉了：
  //   · 消费侧：唯一读点曾是 `FindInPage({ pageId: this.pageId })`（本文件内联挂载）；
  //     W13 把该挂载改为 `pageUuidForDrag`（见下方 `BlockSelection` 的同址注释）。
  //   · 传入侧：W3 把 `FindInPage` 迁到 `MainContainer` 顶层 Stack 时，连这两处内联挂载
  //     一起删除 ⇒ 本仓两个构造点（`PageView.ets:254` / `JournalFeed.ets:146`）**都不传它**。
  // ⇒ 字段成为「零读 + 零写 + 零传参」的完全孤立字段，清除无行为变化 ✓（详见
  //   `docs/S3-W4-死字段清理.md`）。页 uuid 的来源仍是 `pageUuidForDrag`（唯一来源）。
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
   * U2.1b：本列表所属窗格（分屏语义）。由 ContentArea → PageView 逐层透传，
   * 仅用于把「本组件真正交给 List 的那个 Scroller」登记到 BlockAnchorService 的对应窗格上。
   */
  paneId: string = 'primary';
  /**
   * 顶层块（`getPageBlocks`）。**不是** List 的数据源，只用于两件事：
   *   · 空态判定（顶层为空 ⇔ 无可见行）；
   *   · 尾部新增块时取 leftId —— 必须取顶层块的最后一个，取错层级会把新块挂到别人孩子下面。
   */
  @State blocks: BlockData[] = [];
  /** 可见行序列（List 的数据源；顶层块 + 已展开子块，屏幕顺序）。 */
  @State rows: BlockData[] = [];
  /**
   * 内嵌模式（日志流）下**未被实例化**的行数 —— 即 `rows.length - EMBEDDED_MAX_ROWS`。
   * 恒为 0 表示本节未截断（整页模式恒为 0）。驱动节尾 `TruncationFooter()` 的显隐与文案。
   */
  @State hiddenRowCount: number = 0;
  // ─── U2.4 第 2 件后半（S3-W3）：本组件已**不再挂载 `FindInPage`** ───
  // 计划 §U2.4 第 2 条（`PLAN-UI-Alignment.md (v1.md:321`）要求把页内搜索条
  // 「从 BlockList 内联移到 MainContainer 顶部 Stack」——S3-W3 已迁走：
  // 挂载点唯一化到 `MainContainer.build()` 的顶层 `Stack`（右上角浮动小卡）。
  //
  // 随之删掉的是 W12 加在本组件上的 `@StorageLink('callaite_findInPageOpen')`：
  // 它当时**唯一**的用途就是给下方两处 `if (this.findInPageVisible) FindInPage(...)`
  // 当门（`BlockList.ets` 内除此以外 0 读取点）。留着它只会让「每条块列表都因
  // 搜索条开合重跑一次 `build()`」——而迁移后那一次重跑**什么都不会变**（搜索条已不在本组件内）。
  // 显隐统一本身（`AppState.open/closeFindInPage` 单一写入口）**未变**，只是消费方换成了 MainContainer。
  /**
   * U2.3：Slash 菜单开合态与目标块 —— **改由 AppStorage 单一来源**。
   *
   * 为什么不是本组件的 @State：入口有两个，其中一个在 BlockView 内部（行内常显按钮），
   * 而 BlockView 够不到父组件的 @State（且 LazyForEach 复用会让传参型 @Prop 陈旧）。
   * 开合态还必须能被 **SlashMenu 自己**关掉（执行完命令后宿主卸载它），
   * 内部 @State 宿主观察不到 —— 这正是旧实现的缺陷：`dismissMenu()` 只把组件
   * 自己画成 0×0，组件仍挂在树上，路由开合态与视觉状态由此分叉。
   */
  @StorageLink('callaite_slashMenuOpen') private slashMenuOpen: boolean = false;
  @StorageLink('callaite_slashMenuBlockUuid') private slashMenuUuid: string = '';
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
   * U2.3：Slash 入口的注册键（惰性生成，与 dragLayerId 同一手法）。
   * 行内入口按它找到本 BlockList 实例。
   */
  private slashMenuListId: string = '';
  /** 本实例登记到入口注册表的回调（卸载时按同一引用撤回）。 */
  private slashMenuHandler: SlashMenuRequestHandler | undefined;

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
    // U2.3：登记 Slash 菜单入口（BlockView 的行内按钮按 listId 找到本实例）。
    // 与 S1-H 拖拽层同一形态：只登记一个函数类型的回调，不需要在 BlockView 里
    // 引用 BlockList 这个 struct（避免模块环）。回调存字段是为了卸载时能原样撤回
    // （unbind 按「同一函数引用」判等，见 unbindSlashMenuSlot）。
    this.slashMenuHandler = (blockUuid: string) => {
      this.openSlashMenu(blockUuid);
    };
    bindSlashMenuSlot(this.ensureSlashMenuListId(), this.slashMenuHandler);
    // U2.1b 关键修复：把**本组件真正交给 List 的那个 Scroller** 直接登记给锚点服务。
    //
    // 为什么必须由本组件自报、而不是让 ContentArea 发布到 AppStorage：
    // 实测（hilog A02110/U21B 探针）`AppStorage.get<Scroller>('callaite_blockScroller_primary')`
    // 取回来的对象 `currentOffset()` **直接抛异常** —— 它没有被任何滚动组件绑定，
    // 于是 `scrollToIndex()` 静默无效（「搜索/大纲/反链点结果不跳块」的根因）。
    // 本组件手里的 `activeScroller()` 才是真正绑定到 `List({scroller})` 的那一个。
    BlockAnchorService.getInstance().registerScroller(this.paneId, this.activeScroller());
  }

  /**
   * U2.3：惰性生成本实例的 Slash 入口注册键（与 ensureDragLayerId 同一手法）。
   * 用 ArkUI 的组件唯一 id 而不是页面名：分屏时两个窗格各有实例，
   * 用页面名会互相覆盖（点 A 窗格的行、开在 B 窗格上）。
   */
  private ensureSlashMenuListId(): string {
    if (this.slashMenuListId === '') {
      this.slashMenuListId = 'callaite_slashSlot_' + this.getUniqueId();
    }
    return this.slashMenuListId;
  }

  aboutToDisappear(): void {
    // U2.3：本实例卸载 → 撤回入口回调（否则行内按钮会打到一个已销毁的实例上）。
    const handler = this.slashMenuHandler;
    if (handler !== undefined) {
      unbindSlashMenuSlot(this.ensureSlashMenuListId(), handler);
      this.slashMenuHandler = undefined;
    }
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
    const shown: BlockData[] = this.rowsForDisplay();
    this.hiddenRowCount = this.rows.length - shown.length;
    this.dataSource.setBlocks(shown);
  }

  /**
   * 交给 LazyForEach 的行序列。
   *
   * 整页模式（embedded=false）宿主是 `List`（真虚拟化）⇒ **原样返回，不截断**；
   * 内嵌模式（embedded=true）宿主是普通 `Column`（陷阱 8：不虚拟化）⇒ 按
   * `EMBEDDED_MAX_ROWS` 截断（理由与取值见该常量注释）。
   *
   * 只影响「实例化多少行」，不改 `this.rows` 本身 —— 依赖完整行序列的
   * `slashEntryTargetUuid()` 等只出现在整页分支，语义不受影响。
   */
  private rowsForDisplay(): BlockData[] {
    if (this.embedded && this.rows.length > EMBEDDED_MAX_ROWS) {
      return this.rows.slice(0, EMBEDDED_MAX_ROWS);
    }
    return this.rows;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.embedded) {
        // ─── 内嵌模式（JournalFeed 日志流每一节）───
        // 不自建滚动容器：高度自适应内容，滚动由外层 JournalFeed 的 Scroll 承担。
        // 此处 LazyForEach 宿主仍是 Column —— 内嵌场景本就处于滚动容器之外，
        // 虚拟化无法生效（S1-B 之前整页模式同样如此）。
        // ⚠️ 正因如此，本分支的**行数必须自带上限**（S3-W6）：数据源改为
        //    `rowsForDisplay()`，最多 EMBEDDED_MAX_ROWS 行（理由/取证见该常量注释）。
        //    此前这里是全量 `this.rows` —— 一个 1037 块的日志日就把首页推到
        //    22,322 个 a11y 节点 / 756 MB，两条 UI 枚举通道同时失效。
        Column({ space: 0 }) {
          // ─── 页内搜索条已迁走（S3-W3）───
          // 原先此处内联 `FindInPage({ pageId: this.pageUuidForDrag })`：它占据 Column
          // 的纵向空间 ⇒ 打开搜索条会把**整个 List 往下推**（这正是迁移前
          // `Ctrl+Shift+F` 像素差分覆盖整条内容列的原因）。现挂在 `MainContainer`
          // 顶层 Stack 的右上角，成为真正的浮动小卡（计划 §U2.4 第 2 条）。

          if (this.blocks.length === 0) {
            this.EmptyState()
          } else {
            // 可见行序列使用 LazyForEach（宿主是 Column，不做虚拟化）。
            // 与整页分支同样展平：每个可见行只含一个 BlockView ⇒ 行高由内容确定，
            // 不会出现「父行把整棵子树包在一个容器里」导致的高度传播。
            LazyForEach(this.dataSource, (row: BlockData) => {
              Column() {
                BlockView({
                  blockUuid: row.uuid,
                  slashMenuListId: this.ensureSlashMenuListId()
                })
              }
              .width('100%')
            }, (row: BlockData) => row.uuid)
          }

          // 截断提示行：本节行数超过 EMBEDDED_MAX_ROWS 时出现（否则 hiddenRowCount 恒为 0，
          // 本行不渲染 ⇒ 正常日志日的渲染结果与加本上限之前**逐节点相同**）。
          if (this.hiddenRowCount > 0) {
            this.TruncationFooter()
          }

          // 底部添加按钮（feed 内嵌模式不渲染 — Logseq 无显式添加按钮，回车即新建）
          if (!this.embedded) {
            this.AddBlockButton()
          }
        }
        .width('100%')
        .height('auto')

        // Slash 命令菜单（U2.3）。放在 **Stack 层**而不是上面的 Column 里：
        // Stack 的子组件默认叠放，菜单才会「浮」在行内容之上；
        // 放进 Column 会与 List 争抢纵向空间（List 是 layoutWeight(1) 的吸收项，
        // 300vp 的菜单只能把它挤扁或者自己滚到视口之外）。
        if (this.slashMenuOpen) {
          SlashMenu({ blockUuid: this.slashMenuUuid })
            .align(Alignment.BottomEnd)
            .margin({ right: 16, bottom: 16 })
        }
      } else {
        // ─── 整页模式（PageView 大纲页）───
        // List 自身即滚动容器，LazyForEach 的虚拟化在此条件下才真正生效。
        Column({ space: 0 }) {
          // ─── 页内搜索条已迁走（S3-W3，同上）───

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
                    //
                    // ⚠️ 不再传 `depth: row.level`：键未变的行不会重跑本 itemGenerator，
                    //    传参型 @Prop 因此在缩进/反缩进后收不到新值（缺陷 2）。
                    //    层级改为 BlockView 从块数据自读（见 BlockView.depth / onBlocksVersionChanged）。
                    BlockView({
                      blockUuid: row.uuid,
                      // U2.3：行内 Slash 入口的宿主路由键（值恒定，不会被结构性刷新影响）
                      slashMenuListId: this.ensureSlashMenuListId(),
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

        // Slash 命令菜单（U2.3）。放在 **Stack 层**、BottomEnd 位：
        //   · 浮在行内容之上（Stack 子组件默认叠放）；
        //   · 不参与 Column 的纵向分配 —— 放进 Column 会与 layoutWeight(1) 的 List
        //     争空间（要么把 List 挤扁，要么菜单自己被推到视口之外）；
        //   · 右下角避开底部居中的多选入口胶囊（BlockSelection.SelectionEntry，
        //     同样常显、同样在 Stack 底部），两个常显入口不叠在一起。
        if (this.slashMenuOpen) {
          SlashMenu({ blockUuid: this.slashMenuUuid })
            .align(Alignment.BottomEnd)
            .margin({ right: 16, bottom: 16 })
        }
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

      // ─── U2.3：页面级 Slash 命令入口（常显）───
      // 位置：Stack 的 BottomStart（左下角）—— 与右下角的菜单本体、底部居中的多选入口
      // 各占一角，三个常显元素互不遮挡。
      //
      // 为什么需要它（除了行内按钮）：行内按钮在**每一行**上，长列表里要滚到目标行才点得到；
      // 页面级入口始终在屏，是「菜单存在」这件事本身的可见入口（与多选入口同一设计取舍）。
      // 目标块 = 当前焦点块；无焦点时退回可见行第一行（无行则不可点，点击无副作用）。
      if (!this.embedded && this.blocks.length > 0) {
        this.SlashEntryButton()
      }
    }
    .width('100%')
    .height(this.embedded ? 'auto' : '100%')
  }

  /**
   * U2.3：页面级 Slash 命令入口。
   *
   * 常显、无 hover 依赖（AGENTS §7 陷阱 11：触屏不产生 onHover）——
   * 这是本窗口对「SlashMenu 触发源全仓 0 调用」的正面修复：
   *   ① 本入口（页面级，常显）；
   *   ② BlockView 的行内入口（每行一个，常显，见 BlockView.SlashEntryButton）。
   * 两者都写 `AppState.openSlashMenu(blockUuid)`，开合态只有一份。
   */
  @Builder
  SlashEntryButton() {
    Row({ space: 6 }) {
      TablerIcon('command', 16, $r('app.color.primary'))
      Text('命令')
        .fontSize(13)
        .fontColor($r('app.color.primary'))
        .fontWeight(FontWeight.Medium)
    }
    .padding({ left: 12, right: 14, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.surface1'))
    .borderRadius(18)
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({ radius: 10, color: '#20000000', offsetX: 0, offsetY: 2 })
    .margin({ left: 16, bottom: 16 })
    .align(Alignment.BottomStart)
    .id('callaite_slashEntry')
    .onClick(() => {
      const target = this.slashEntryTargetUuid();
      if (target === '') {
        return;
      }
      this.openSlashMenu(target);
    })
  }

  /**
   * 页面级入口的目标块：优先当前焦点块（在屏且属于本页时才有意义），
   * 否则退回可见行第一行。两者都取不到时返回 ''（点击无副作用）。
   */
  private slashEntryTargetUuid(): string {
    const focused = EditorService.getInstance().getFocusedBlockUuid();
    if (focused !== '') {
      for (let i = 0; i < this.rows.length; i++) {
        if (this.rows[i].uuid === focused) {
          return focused;
        }
      }
    }
    if (this.rows.length > 0) {
      return this.rows[0].uuid;
    }
    return '';
  }

  // ─── 空页面状态 ───
  // Logseq 风格：左对齐的项目符号点 + 弱化占位提示，而非居中的大图标。

  /**
   * 内嵌模式（日志流）的「本节已截断」行。
   *
   * 只在 `hiddenRowCount > 0` 时被调用（见 build() 内嵌分支）。点击 = 打开该日单日页，
   * 那里的 BlockList 走 `List` + LazyForEach（真虚拟化，实测 1037 块只实例化 14 行），
   * 可以浏览/编辑本节未展开的全部块 ⇒ **内容不丢失，只是不在首页铺开**。
   *
   * 用 `.id()` 暴露给 uitest：本行的存在与否，就是「上限是否生效」的可枚举判据
   * （a11y 通道恢复后，`dumpLayout` 里能按 id 精确定位 —— AGENTS 验证纪律 8）。
   */
  @Builder
  TruncationFooter() {
    Row({ space: 6 }) {
      TablerIcon('dots', 15, $r('app.color.muted_text'))
      Text('还有 ' + this.hiddenRowCount + ' 块未展开 —— 打开当日页查看')
        .fontSize(13)
        .fontColor($r('app.color.primary'))
    }
    .width('100%')
    .height(34)
    .padding({ left: 6 })
    .borderRadius(4)
    .id('callaite_feedTruncated_' + this.pageName)
    .onClick(() => {
      AppState.setCurrentPage(this.pageName);
    })
  }

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
    // U2.3：开合态写入 AppStorage（BlockView 的行内入口与 SlashMenu 的关闭路径都读它）。
    AppState.openSlashMenu(blockUuid);
  }

  // ─── 页内搜索（U2.4 / W12：开合态统一走 AppState，与 FindInPage 同一个键）───

  toggleFindInPage(): void {
    if (AppState.isFindInPageOpen()) {
      AppState.closeFindInPage();
    } else {
      AppState.openFindInPage();
    }
  }

  showFindInPage(): void {
    AppState.openFindInPage();
  }

  hideFindInPage(): void {
    AppState.closeFindInPage();
  }
}
