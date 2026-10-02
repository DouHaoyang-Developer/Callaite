import { BlockData } from '../../core/models/Block';
import { BlockView } from '../outliner/BlockView';
import {
  bindSlashMenuSlot,
  unbindSlashMenuSlot,
  SlashMenuRequestHandler
} from '../outliner/BlockListSlashSlot';
import { SlashMenu } from '../outliner/SlashMenu';
import { TaskDashboard } from '../search/TaskDashboard';
import { JournalService } from '../../services/JournalService';
import { WorkspaceService } from '../../services/WorkspaceService';
import { AppState } from '../../state/AppState';
import { t } from '../../utils/i18n';
import { display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * JournalFeed — 日志流首页，对应 Logseq journal.cljs 的 all-journals。
 *
 * 首页不再只显示今天，而是「最近日期在上」的无限滚动时间流：
 * 初始加载最近 7 天，滚动到底部（onReachEnd）时每次向前追加 7 天。
 * 每一天一节：日期标题（点击进入单日页）+ 该日的块行。
 * 日期标题格式与单日页一致（yyyy-MM-dd）。
 *
 * 追加受两道约束（见 appendDays）：
 *  1) 节流时间窗 APPEND_COOLDOWN_MS：一次滚动会话内的连续触底只追加一次；
 *  2) 可回溯天数上限 MAX_JOURNAL_DAYS：触达后不再追加，且只在首次触达时打一条 NO_MORE。
 *
 * ─── S3-W16（W6-F2）：单一扁平 `List`（本文件的结构性改动）───
 * 此前本页的容器链是 `Scroll > Column > Column > ForEach(days) > Column > BlockList(embedded)`
 * —— **两级宿主都不是滚动容器**，而 `LazyForEach` 只在 `List`/`Grid`/`WaterFall` 里才虚拟化
 * （AGENTS §7 陷阱 8）⇒ 每一节的块行**全量实例化**。
 * 实测代价（S3-W6，同构建/同 vault/同机/只换落点）：vault 里 `2026-09-30.md` = **1037 块**
 * 且它恰好是一个日志日期 ⇒ 首页一次实例化 1046 行 ⇒ **22,322 个 a11y 节点 / 756 MB**，
 * `uitest dumpLayout` 与 `-uiLayout -i` **两条 UI 枚举通道同时丢失应用子树**；
 * 而同一个页面以**文档页**打开（`BlockList` 整页模式 = `List` + `LazyForEach`）只实例化 **14 行** /
 * **662 节点 / 116.3 MB** ⇒ **膨胀的唯一变量是「容器是否虚拟化」**。
 *
 * W6 的临时修法是给内嵌模式加 `EMBEDDED_MAX_ROWS = 30` 的行数上限（+ 节尾截断提示），
 * 它解除了阻断，但**不构成 Pss 硬上界**（最坏 7 节 × 30 行 = 210 行 ⇒ 实测 209 行 = 261 MB，W6-F1）。
 *
 * 本窗口按 W6 自己给出的结构性正解（W6-F2）重构：
 * **把「天 × 块行」拍平成一个序列**，用一个 `List` + `LazyForEach` 承载
 * 「日期标题 / 任务面板 / 空态 / 块行」四种 item ⇒ 每个块行都是 `List` 的**直接 item**
 * ⇒ 虚拟化真正生效 ⇒ 实例化行数 ≈ 视口行数，**与 vault 里有多少块无关**。
 * ⇒ 行数上限与截断提示一并撤销（内容恢复全量内联）。
 *
 * ⚠️ 为什么不能只把外层 `Scroll` 换成 `List`（W6 已排除的候选①）：
 * 外层只有 7 个 item，而「某一天」本身就是**一个** item ⇒ `List` 仍会把它整体构建。
 * 本改动不是「换外层容器」，而是**改变 item 的粒度**：一个 item = 一个块行。
 */
const APPEND_COOLDOWN_MS: number = 500;

/**
 * 可回溯天数上限。180 天 ≈ 半年：
 * 日志流定位是「最近的日志上下文」，半年之外靠日期跳转而非无限下拉。
 * S3-W16 起本页是单一扁平 `List`（虚拟化生效）⇒ 天数上限只关系到「枚举与读取成本」，
 * 不再关系到「实例化多少行」。
 */
const MAX_JOURNAL_DAYS: number = 180;

/**
 * 扁平序列里的 item 种类。
 *
 * 为什么要有「种类」而不是直接放 BlockData：一个 item 除了块行之外还可能是
 * 日期标题、今天的任务面板、或空日期节的空态 —— 它们是**同一层**的兄弟节点，
 * 这样每一个块行才是 `List` 的直接 item（虚拟化的前提）。
 */
class FeedRowKind {
  static readonly HEADER: string = 'header';
  static readonly TASKS: string = 'tasks';
  static readonly EMPTY: string = 'empty';
  static readonly BLOCK: string = 'block';
}

/**
 * 扁平序列的一个 item。
 *
 * `index` 是该行的日期在 `days` 里的下标（**不是** item 在序列里的下标）——
 * 日期标题的 padding/opacity 与「今天才挂 TaskDashboard」都按它判定，
 * 与改造前 `ForEach(days, (day, index) => …)` 的语义逐字对齐。
 */
class FeedRow {
  kind: string = FeedRowKind.BLOCK;
  /** 所属日期（yyyy-MM-dd） */
  day: string = '';
  /** 该日期在 days 中的下标 */
  index: number = 0;
  /** BLOCK 行：块 uuid；其余种类为空串 */
  uuid: string = '';
}

/**
 * FeedDataSource — 扁平序列的 `LazyForEach` 数据源。
 * 与 `BlockList.BlockDataSource` 同形（同一套 IDataSource 约定），
 * 差别只在元素类型是 FeedRow 而不是 BlockData。
 */
class FeedDataSource implements IDataSource {
  private rows: FeedRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): FeedRow {
    return this.rows[index];
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

  setRows(rows: FeedRow[]): void {
    this.rows = rows;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  /**
   * 序列是否与当前内容**逐项等价**（种类 + 日期 + 下标 + uuid）。
   *
   * 用途：`callaite_blocksVersion` 每次 bump 都会重算序列，而**内容类**变更
   * （打字、自动落盘）不会改变序列本身。若此时仍 `onDataReloaded()`，
   * `LazyForEach` 会把整表重建 ⇒ 视口与焦点被打回顶部。
   * 逐项等价时保持不动；真正的结构性变更（增/删/折叠/切页）必然让比较为假。
   *
   * ⚠️ 安全性依据：行**内容**的刷新不依赖本函数 —— `BlockView` 自己挂了
   * `callaite_blocksVersion` 的 `@Watch`（`refreshBlock()`），键未变时它照样重算。
   */
  equalsRows(rows: FeedRow[]): boolean {
    if (this.rows.length !== rows.length) {
      return false;
    }
    for (let i = 0; i < rows.length; i++) {
      const a = this.rows[i];
      const b = rows[i];
      if (a.kind !== b.kind || a.day !== b.day || a.index !== b.index || a.uuid !== b.uuid) {
        return false;
      }
    }
    return true;
  }
}

@Component
export struct JournalFeed {
  @State days: string[] = [];
  /**
   * 扁平序列（`List` 的唯一数据源）。
   * 由 `refreshFeedRows()` 在 `days` 或块数据变化时重算。
   */
  @State feedRows: FeedRow[] = [];
  /** blocksVersion 变化 ⇒ 重算序列（块增删/折叠/缩进都会 bump 它）。 */
  @StorageLink('callaite_blocksVersion') @Watch('onBlocksVersionChanged') private blocksVersion: number = 0;
  /** Slash 菜单开合态（与 BlockList 同一把键，单一写入口是 AppState）。 */
  @StorageLink('callaite_slashMenuOpen') private slashMenuOpen: boolean = false;
  @StorageLink('callaite_slashMenuBlockUuid') private slashMenuUuid: string = '';

  /** 上次成功追加的时间戳（ms）；0 表示尚未追加过，保证初始加载不被节流。 */
  private lastAppendMs: number = 0;

  /** 上限日志只打一次的标记，避免每次触底刷屏。 */
  private limitReachedLogged: boolean = false;

  /** 本页唯一的滚动容器（`List`）—— 虚拟化的前提。 */
  private scroller: Scroller = new Scroller();

  private dataSource: FeedDataSource = new FeedDataSource();

  /**
   * Slash 入口的注册键（惰性生成，与 BlockList 同一手法：用组件唯一 id 而不是页面名）。
   * 本页所有块行共用**一个**宿主 —— 菜单挂载点也只有一个（见 build()）。
   */
  private slashMenuListId: string = '';
  private slashMenuHandler: SlashMenuRequestHandler | undefined;

  aboutToAppear(): void {
    JournalService.ensureTodayJournal();
    this.appendDays(7);
    this.refreshFeedRows();
    // 行内 `/` 入口 → 本页宿主：与 BlockList 同一注册表（BlockListSlashSlot），
    // 因此 BlockView 不需要知道宿主是谁（它只调 requestSlashMenu）。
    this.slashMenuHandler = (blockUuid: string) => {
      this.openSlashMenu(blockUuid);
    };
    bindSlashMenuSlot(this.ensureSlashMenuListId(), this.slashMenuHandler);
  }

  aboutToDisappear(): void {
    // 卸载 → 撤回入口回调（否则行内按钮会打到一个已销毁的实例上）
    const handler = this.slashMenuHandler;
    if (handler !== undefined) {
      unbindSlashMenuSlot(this.ensureSlashMenuListId(), handler);
      this.slashMenuHandler = undefined;
    }
  }

  /**
   * 惰性生成本实例的 Slash 入口注册键（与 BlockList.ensureSlashMenuListId 同一手法）。
   */
  private ensureSlashMenuListId(): string {
    if (this.slashMenuListId === '') {
      this.slashMenuListId = 'callaite_slashSlot_' + this.getUniqueId();
    }
    return this.slashMenuListId;
  }

  openSlashMenu(blockUuid: string): void {
    AppState.openSlashMenu(blockUuid);
  }

  onBlocksVersionChanged(): void {
    this.refreshFeedRows();
  }

  /**
   * 重算扁平序列。
   *
   * 遍历 `days`，对每一天产出：日期标题 →（仅今天）任务面板 → 该日的每一个可见块行
   * （顶层块 + 已展开子块，屏幕顺序，与整页模式**同一实现** `getVisibleBlocks`），
   * 或（该日无块时）一个空态行。
   *
   * 「可见行」的口径与整页模式完全一致 ⇒ 折叠/展开、缩进层级的表现不会分叉。
   */
  refreshFeedRows(): void {
    const ws = WorkspaceService.getInstance();
    const rows: FeedRow[] = [];
    for (let i = 0; i < this.days.length; i++) {
      const day = this.days[i];

      const header = new FeedRow();
      header.kind = FeedRowKind.HEADER;
      header.day = day;
      header.index = i;
      rows.push(header);

      if (i === 0) {
        const tasks = new FeedRow();
        tasks.kind = FeedRowKind.TASKS;
        tasks.day = day;
        tasks.index = i;
        rows.push(tasks);
      }

      const page = ws.getPageByName(day);
      const visible: BlockData[] = page ? ws.getVisibleBlocks(page.uuid) : [];
      if (visible.length === 0) {
        const empty = new FeedRow();
        empty.kind = FeedRowKind.EMPTY;
        empty.day = day;
        empty.index = i;
        rows.push(empty);
      } else {
        for (let j = 0; j < visible.length; j++) {
          const block = new FeedRow();
          block.kind = FeedRowKind.BLOCK;
          block.day = day;
          block.index = i;
          block.uuid = visible[j].uuid;
          rows.push(block);
        }
      }
    }
    this.feedRows = rows;
    if (!this.dataSource.equalsRows(rows)) {
      this.dataSource.setRows(rows);
    }
  }

  /**
   * 向前追加 N 天的日期（从当前最后一天的下一天开始）。
   * 不预创建页面（保持全部页面列表干净），空日期在编辑时由本组件懒创建。
   *
   * 入口处两道闸：
   *  - 上限闸在前：已达 MAX_JOURNAL_DAYS 就直接返回（首次触达打一条 NO_MORE，之后静默），
   *    这样触底噪声不会再叠出一串 SKIP；
   *  - 节流闸在后：用时间窗而非「追加中」布尔标记。
   *    原因：本函数是纯同步的（只有 for 循环 + push，无 await），
   *    布尔标记在 return 之前就已复位，下一次 onReachEnd 回调进来时它永远是 false，
   *    抑制不住任何东西；时间戳记录的是「上一次真的追加了」，
   *    与回调何时再次触发无关，才真正能覆盖一次滚动会话。
   */
  appendDays(count: number): void {
    const base: number = this.days.length;

    // ① 上限：达到可回溯天数上限后不再追加；只在首次触达时打一条日志
    if (base >= MAX_JOURNAL_DAYS) {
      if (!this.limitReachedLogged) {
        this.limitReachedLogged = true;
        hilog.info(0x0000, 'JOURNALFEED',
          'NO_MORE total=' + base + ' limit=' + MAX_JOURNAL_DAYS + ' first=1');
      }
      return;
    }

    // ② 节流：同一次滚动会话内被抑制的追加会打 SKIP，便于从日志确认节流生效
    const nowMs: number = Date.now();
    const delta: number = nowMs - this.lastAppendMs;
    if (this.lastAppendMs > 0 && delta < APPEND_COOLDOWN_MS) {
      hilog.info(0x0000, 'JOURNALFEED',
        'SKIP reason=cooldown delta=' + delta + ' threshold=' + APPEND_COOLDOWN_MS + ' total=' + base);
      return;
    }
    this.lastAppendMs = nowMs;

    // ③ 末尾夹取：距上限不足 count 天时只补到上限，保证 days.length 恒 <= MAX_JOURNAL_DAYS
    //    （正常区间 actual 恒等于 count，追加天数与既有行为一致）
    let actual: number = count;
    const remaining: number = MAX_JOURNAL_DAYS - base;
    if (actual > remaining) {
      actual = remaining;
    }

    const now: Date = new Date();
    hilog.info(0x0000, 'JOURNALFEED',
      'APPEND days=' + actual + ' from=' + JournalService.getDateAfter(-base)
        + ' total=' + base + ' today=' + now.getFullYear() + '-' + (now.getMonth() + 1) + '-' + now.getDate());
    for (let i = 0; i < actual; i++) {
      this.days.push(JournalService.getDateAfter(-(base + i)));
    }
    hilog.info(0x0000, 'JOURNALFEED',
      'APPEND_DONE added=' + actual + ' total=' + this.days.length + ' newest=' + this.days[0]
        + ' oldest=' + this.days[this.days.length - 1]);
  }

  /**
   * 响应式内容留白：与 PageView.getContentPadding 保持一致。
   */
  getContentPadding(): number {
    try {
      const d = display.getDefaultDisplaySync();
      if (d.width / d.densityPixels < 600) {
        return 20;
      }
    } catch (_e) {
      // 取不到显示信息时用窄屏值
    }
    return 48;
  }

  /**
   * 懒创建该日页面并新增一个空块（空日期节首次编辑时落库）。
   * 与改造前 `BlockList.addTopLevelBlock()` 的分支逐行等价。
   */
  private addTopLevelBlock(day: string): void {
    const ws = WorkspaceService.getInstance();
    let page = ws.getPageByName(day);
    if (!page) {
      page = ws.createPage(day);
    }
    const blocks: BlockData[] = ws.getPageBlocks(page.uuid);
    ws.executeOp({
      type: 'insert-block',
      content: '',
      pageId: page.uuid,
      parentId: page.uuid,
      leftId: blocks.length > 0 ? blocks[blocks.length - 1].uuid : '',
      level: 0
    });
    this.refreshFeedRows();
  }

  build() {
    // Stack：`List` 是唯一滚动容器；Slash 菜单浮在它之上（与 BlockList 的整页分支同一形态）。
    Stack({ alignContent: Alignment.BottomEnd }) {
      List({ space: 0, scroller: this.scroller }) {
        LazyForEach(this.dataSource, (row: FeedRow) => {
          ListItem() {
            // ⚠️ 这个 Column 包装不可省略（与整页模式同一实测结论）：
            //   直接把自定义组件当 ListItem 的唯一子节点时，它相当于 matchParent 子组件，
            //   List 会把剩余视口高度分给该 item ⇒ 行被拉伸、虚拟化测量失真。
            Column() {
              if (row.kind === FeedRowKind.HEADER) {
                this.DateHeaderRow(row)
              } else if (row.kind === FeedRowKind.TASKS) {
                TaskDashboard()
              } else if (row.kind === FeedRowKind.EMPTY) {
                this.EmptyStateRow(row)
              } else {
                // 块行：一行 = 一个 ListItem = 一个 BlockView（不再把整节塞进一个 item）
                BlockView({
                  blockUuid: row.uuid,
                  slashMenuListId: this.ensureSlashMenuListId()
                })
              }
            }
            .width('100%')
          }
        }, (row: FeedRow) => row.kind + '|' + row.day + '|' + row.uuid)
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: 960 })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .onReachEnd(() => {
        this.appendDays(7);
        this.refreshFeedRows();
      })

      // Slash 命令菜单（U2.3）。放在 **Stack 层**而不是 List 里：Stack 的子组件默认叠放，
      // 菜单才会「浮」在行内容之上；放进 List 会与行争抢纵向空间。
      if (this.slashMenuOpen) {
        SlashMenu({ blockUuid: this.slashMenuUuid })
          .align(Alignment.BottomEnd)
          .margin({ right: 16, bottom: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.getContentPadding(), right: this.getContentPadding() })
  }

  /**
   * 日期标题行（Logseq 本地化格式）— 点击进入该日单日页。
   * 字号/颜色/padding/opacity 与改造前 `ForEach` 内的标题**逐字段一致**。
   */
  @Builder
  DateHeaderRow(row: FeedRow) {
    Column({ space: 0 }) {
      Text(JournalService.formatJournalTitle(row.day))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text'))
        .opacity(row.index === 0 ? 1 : 0.85)
        .width('100%')
        .padding({ top: row.index === 0 ? 20 : 32, bottom: 8 })
        .onClick(() => {
          AppState.setCurrentPage(row.day);
        })
    }
    .width('100%')
    .constraintSize({ maxWidth: 960 })
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 空日期节的空态行 —— 可点 ⇒ 懒创建该日页面。
   * 与改造前 `BlockList.EmptyState()` 的观感与点击语义一致（文案仍走 t('placeholder_block')）。
   */
  @Builder
  EmptyStateRow(row: FeedRow) {
    Column({ space: 0 }) {
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
        this.addTopLevelBlock(row.day);
      })
    }
    .width('100%')
    .constraintSize({ maxWidth: 960 })
    .alignItems(HorizontalAlign.Start)
  }
}
