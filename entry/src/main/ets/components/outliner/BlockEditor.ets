import { hilog } from '@kit.PerformanceAnalysisKit';
import { EditorService } from '../../services/EditorService';
import { WorkspaceService } from '../../services/WorkspaceService';
import { DirtyPageTracker } from '../../services/DirtyPageTracker';
import { BlockAnchorService } from '../../services/BlockAnchorService';
import { BlockData } from '../../core/models/Block';
import { PageData } from '../../core/models/Page';
import { LivePreviewHelper } from '../../utils/LivePreviewHelper';
import { FenceOpenCache } from '../../utils/FenceOpenCache';

/**
 * BlockEditor —— **B 形态（块级按需实例化）的原生块编辑器**。
 *
 * 取代 `BlockView.ets` 里 `isEditing` 分支上的 `WebEditor`（WebView + contenteditable）：
 * 同一时刻每个窗格**至多 1 个实例**（只有焦点行才有实例），实例由 `BlockView.isEditing`
 * 这一个 `if` 分支的求值决定生死。
 *
 * 【参数面刻意与 `WebEditor` 逐字对齐】`blockUuid / initialContent / pageName / fontSize /
 * `onSave / onAction` ⇒ `BlockView` 侧只需改类名，参数与回调不动（改动面最小化）。
 * `WebEditor` **保留不删**：二者按 `BlockView` 的一个模式常量二选一。
 *
 * ────────────────────────────────────────────────────────────────────────────
 * 【三条硬要求各自怎么落地】（设计文档 §2.2 / §2.3 / §2.6）
 * ────────────────────────────────────────────────────────────────────────────
 *
 * **① 回填闸（对应设计文档 C3 ✗：`addTextSpan` 回填也会触发 `onDidChange`）**
 *    本组件所有「程序化改文本」的路径（`onReady` 首次回填、光标移动后的重建、
 *    MarkdownToolbar 命令）都必须先 `beginProgrammaticUpdate()` 再 `endProgrammaticUpdate()`。
 *    闸门是**两重**的：
 *      · `programmaticDepth > 0` —— 同步期间的回调直接丢弃；
 *      · `text === this.snapshotText` —— 闸门落下之后的**迟到回调**（实测 `onDidChange`
 *        可能晚于 `addTextSpan` 返回）按「文本与快照逐字符相同 ⇒ 这不是一次内容变更」丢弃。
 *    第二重是关键：它不依赖时序假设，因此不引入「回填 → onDidChange → 回写 → 再回填」的自激，
 *    也不会像 `IntegralEditor` 那样退化成「每次按键都触发一次重建」。
 *
 * **② 销毁前四步（顺序不可交换）**
 *    `aboutToDisappear()` 里：读回 → 与 `BlockData.content` 比对、**不同才写** →
 *    `DirtyPageTracker` 触发的落盘 → 释放（清计时器 / 反注册 / 清空 span）。
 *    ⚠️ 第 2 步的「不同才写」是硬要求：回填本身也会让编辑器持有一段文本，
 *    若无脑回写就会凭空制造一次「内容变更」。
 *
 * **③ `caretOffset` 必须是块内相对 offset**
 *    本组件的 `caretOffset` 全部来自 `RichEditorController.getCaretOffset()`，
 *    而该控制器的坐标原点就是**本块文本的第 0 个字符** ⇒ 天然是块内相对量。
 *    绝不能把 `IntegralEditor` 的「全页绝对 offset」搬过来：那样第一个块之后的任何位置
 *    都会判成「不在任何段内」⇒ `**` / `` ` `` / `==` 的语法标记**永不显示**。
 *
 * 【焦点模型】权威只有一个 = `EditorService.focusedBlockUuid`（镜像到 AppStorage
 * `callaite_focusedBlock`）。`focusControl.requestFocus(id)` **只是手段、单向派生**：
 * 只有「本块就是权威焦点块」时才去请求，反向（onFocus → 改焦点）**刻意不做**，
 * 否则会形成「焦点回调 → setFocusedBlock → 焦点回调」的回环。
 * 必须用 `.id()` 而不是 `defaultFocus`：后者只在构建期生效，而本实例的创建时刻由焦点迁移决定。
 * 实测时序：请求 → `onFocus` ≈620ms，且 `aboutToAppear` 阶段请求会落空
 * ⇒ 在 `onReady` 之后的**下一帧**请求，并接受它是异步的（请求后不同步断言已获焦）。
 */
@Component
export struct BlockEditor {
  // ─── 参数面：与 WebEditor 逐字对齐 ───
  @Prop blockUuid: string = '';
  @Prop initialContent: string = '';
  @Prop pageName: string = '';
  @Prop fontSize: number = 15;
  @Prop focusOnReady: boolean = true;
  onSave: () => void = () => {};
  onAction: (action: string, data: string) => void = (_a: string, _d: string) => {};

  // ─── 与既有装置对齐的存储通道 ───
  /** 权威焦点块（`EditorService.setFocusedBlock` 写入，见 §焦点模型） */
  @StorageLink('callaite_focusedBlock') focusedBlock: string = '';
  /**
   * Markdown 工具条命令通道（与 `WebEditor` 同一把键，格式 `命令|序号`）。
   * 序号保证「连续点同一个按钮」也能触发 @Watch。
   */
  @StorageLink('callaite_editorCommand') @Watch('onEditorCommand') editorCommand: string = '';

  /** 状态栏/边框用：编辑器内文本长度（不参与任何数据判定） */
  @State textLen: number = 0;

  private controller: RichEditorController = new RichEditorController();
  private livePreview: LivePreviewHelper = new LivePreviewHelper();
  /** 焦点请求的目标 id（`.id()` 与 `focusControl.requestFocus(…)` 共用同一常量） */
  private focusId: string = '';
  /**
   * 程序化更新闸门深度（>0 ⇒ 期间的一切 `onDidChange` 都是「我们自己改的文本」）。
   * 用深度而非布尔：重建内部还可能再触发一层（setCaretOffset 的同步回调）。
   */
  private programmaticDepth: number = 0;
  /** 闸门落下之后的迟到回调仍按「文本与快照相同」二次拦（见类头 ①） */
  private snapshotText: string = '';
  /** 最近一次渲染进编辑器的纯文本（等价于 spans 求和，避免反复 getSpans()） */
  private lastRenderedText: string = '';
  /**
   * 块内相对 caret offset（见类头 ③）。-1 = 未知（尚未读到）。
   * 必须在 onSelectionChange / onDidChange 两处都维护：前者是光标移动（用户可以只移动
   * 光标而不改字），后者是编辑（`rangeAfter.end` 即新光标位置）。
   */
  private caretOffset: number = -1;
  /** 上一次重建所用的 (text, caret) 快照 —— 二者都没变就不重建（自激防护，同 IntegralEditor） */
  private lastSpanText: string = '';
  private lastSpanCaret: number = -2;
  /** rebuildSpans 重入闸：setCaretOffset 会**同步**回调 onSelectionChange */
  private isRebuildingSpans: boolean = false;
  private focusedOnce: boolean = false;
  private readyScheduled: boolean = false;
  /** `refreshBlock()` 里读出的本块数据（销毁前比对用，避免销毁时再去 store 查） */
  private blockData: BlockData | undefined = undefined;
  /** W5：键路由的观测计数（仅 hilog，不参与任何判定） */
  private keyRouted: number = 0;
  /** W5：组件是否已销毁（焦点重试的守卫） */
  private destroyed: boolean = false;
  /**
   * ★ W9 新增 ★ 「刚收到过一个**应用能看见的**字母键」—— 组词态守卫的判据（仅 Enter 用）。
   *
   * 推导见 `routeKeyPreIme()` 头：本机上**输入法会先于应用消费按键**，因此
   *   · 组词中：字母被输入法吞掉 ⇒ `onKeyPreIme` **收不到**它 ⇒ 本标记保持 false
   *   · 非组词：字母到达 `onKeyPreIme` ⇒ 本标记置 true
   * 于是「Enter 到达 preIme 时本标记是否为 true」就把两种态分开了。
   * ⚠️ 只在焦点离开本块时复位（`handleBlur`），**刻意不在提交时复位**，理由见 `routeKeyPreIme()` 头。
   */
  private sawLetterKey: boolean = false;
  /** W5：焦点重试的间隔与次数上限（实测 `requestFocus`→`onFocus` ≈620ms，见方法头） */
  private static readonly FOCUS_RETRY_MS: number = 320;
  private static readonly FOCUS_MAX_ATTEMPTS: number = 4;

  /** W5：本组件在键路由里是否处于「主控」位置（正文编辑器在编辑态且焦点权威在本块） */
  private static readonly K_ENTER: number = 2054;
  private static readonly K_NUMPAD_ENTER: number = 2119;
  private static readonly K_TAB: number = 2049;
  private static readonly K_DEL: number = 2055;
  private static readonly K_DPAD_UP: number = 2012;
  private static readonly K_DPAD_DOWN: number = 2013;

  /**
   * ★ W9 新增 ★ `keyCode` 是否为**字母键**（`KEYCODE_A`…`KEYCODE_Z` = 2017…2042）。
   * 用于组词态守卫的「用户刚打过字吗」判据 —— 见 `routeKeyPreIme()` 头。
   */
  private static isLetterKeyCode(code: number): boolean {
    return code >= 2017 && code <= 2042;
  }

  private static readonly TAG = 'BlockEditor';
  private static readonly DOMAIN = 0x0002;
  /** 内联格式命令的标记对：顺序固定，`cmd` 是命令名 */
  private static readonly TOKEN_BOLD: string = '**';
  private static readonly TOKEN_CODE: string = '`';
  private static readonly TOKEN_HIGHLIGHT: string = '==';

  aboutToAppear(): void {
    this.focusId = 'callaite_blockEditor_' + this.blockUuid;
    this.refreshBlock();
  }

  aboutToDisappear(): void {
    // ─── ② 销毁前四步（顺序固定，不可交换）───
    // ⓪ 先释放排程，避免销毁后还有回调打进来
    this.readyScheduled = false;
    this.destroyed = true;   // W5：让焦点重试的排程失效
    // ① 读回文本（控制器已不可读时 extractText 返回 ''，配合 ② 的比对不会误写）
    const text = LivePreviewHelper.extractText(this.controller);
    // ② 与 BlockData.content 比对 —— **不同才写**（硬要求）
    this.refreshBlock();
    const current = this.blockData !== undefined ? this.blockData.content : '';
    this.lastRenderedText = '';
    // 走 EditorService（而非直接 executeOp）：与 WebEditor.NativeBridge 的接线同构，
    // 结构操作/脏页/undo 语义全部照旧，零漂移。
    if (text !== '' && current !== text) {
      EditorService.getInstance().updateBlockContent(this.blockUuid, text);
    }
    // ③ 落盘：`update-block` 属文本类，只标脏；此处立即 flush（失焦/销毁是既有 flush 点）
    //    后再触发宿主回调，保证「组件消失时数据已经在新家」。
    DirtyPageTracker.getInstance().flushNow();
    try {
      // 主动清空跨度，尽早释放原生侧引用（不依赖 GC 时机）。
      // 失败可忽略：此时组件正在销毁，控制器可能已失效。
      this.controller.deleteSpans();
    } catch (e) { /* 销毁期忽略 */ }
    // ④ 释放：清空跨度引用之外的本地状态
    this.blockData = undefined;
    hilog.info(BlockEditor.DOMAIN, BlockEditor.TAG,
      'disposed block=%{public}s written=%{public}s', this.blockUuid,
      (text !== '' && current !== text) ? 'yes' : 'no');
    this.onAction('dispose', '');
  }

  /** 读本块数据（行自读原则：不靠父组件传参，W10 修法一致） */
  private refreshBlock(): void {
    this.blockData = WorkspaceService.getInstance().getBlock(this.blockUuid);
  }

  // ─── 程序化更新闸门（类头 ①）───

  private beginProgrammaticUpdate(): void {
    this.programmaticDepth = this.programmaticDepth + 1;
  }

  private endProgrammaticUpdate(): void {
    if (this.programmaticDepth > 0) {
      this.programmaticDepth = this.programmaticDepth - 1;
    }
  }

  /**
   * 用「块内整块重建」（前置 A 的 **A-0** 层）刷新本编辑器。
   *
   * A-0 = `deleteSpans()`（无参，只作用于本实例）+ 对本块文本 `parseMarkdownSegments`
   * + 逐段 `addTextSpan`。复杂度 `O(该块段数)`（典型 1–6 段），零增量机器、零 offset 维护。
   * A-1（块内脏段增量）**刻意不做**：块内段数是个位数，增量版与整块版的实际收益差在微秒级，
   * 却会引入「段数组 ↔ 字符 offset 映射表」这一新的可错状态。
   *
   * 唯一必须外挂的一层是**围栏播种**：`inCodeBlock` 是迁移前唯一的跨块传播项
   * （见设计文档 §2.6 的表），块级化后由 `FenceOpenCache` 这个页面级缓存的派生属性提供。
   */
  private rebuildSpans(): void {
    if (this.isRebuildingSpans || this.livePreview.getIsRebuilding()) {
      return;
    }
    this.isRebuildingSpans = true;
    this.beginProgrammaticUpdate();
    try {
      const fenceOpen: boolean = this.fenceOpenForThisBlock();
      this.livePreview.buildSpans(this.controller, this.lastRenderedText, this.caretOffset, fenceOpen);
      this.snapshotText = this.lastRenderedText;
      this.lastSpanText = this.lastRenderedText;
      this.lastSpanCaret = this.caretOffset;
      this.textLen = this.lastRenderedText.length;
      // 光标回位（块内相对 offset，见类头 ③）
      if (this.caretOffset >= 0 && this.caretOffset <= this.lastRenderedText.length) {
        try {
          this.controller.setCaretOffset(this.caretOffset);
        } catch (e) {
          // 光标回位失败不影响文本正确性
        }
      }
    } finally {
      this.endProgrammaticUpdate();
      this.isRebuildingSpans = false;
    }
  }

  /**
   * 本块第一行是否处在未闭合围栏内（`FenceOpenCache` 的页面级缓存查询）。
   *
   * 缓存键是「可见行序列的签名」（页 uuid + 行数 + 各行 uuid 的滚动 hash）：
   * 结构性变更 ⇒ 签名变 ⇒ 自动失效；**文本输入 ⇒ 签名不变 ⇒ 零重算**
   * ——与 W10「每次按键不重算可见行」的性能前提一致。
   */
  private fenceOpenForThisBlock(): boolean {
    const ws = WorkspaceService.getInstance();
    const pageId = ws.getPageUuidForBlock(this.blockUuid);
    if (!pageId) {
      return false;
    }
    const rows: BlockData[] = ws.getVisibleBlocks(pageId);
    return FenceOpenCache.getInstance().isFenceOpenAt(pageId, rows, this.blockUuid);
  }

  // ─── 编辑器回调 ───

  private onReady(): void {
    if (this.readyScheduled) {
      return;
    }
    this.readyScheduled = true;
    // 首次回填：把块内容写进原生编辑器（此后以编辑器为准，直到销毁前比对）
    this.refreshBlock();
    const seed: string = this.blockData !== undefined ? this.blockData.content : this.initialContent;
    this.lastRenderedText = seed;
    this.caretOffset = -1;
    this.rebuildSpans();
    // 焦点请求放在 **onReady 之后的下一帧**：实测 `aboutToAppear` 阶段组件尚未完成布局，
    // 立即 requestFocus 会落空；请求 → onFocus 本身还有 ≈620ms 异步延迟，故不做同步断言。
    setTimeout(() => {
      this.requestFocusIfAuthoritative();
    }, 0);
  }

  /**
   * 仅当「本块就是权威焦点块」时才请求系统焦点。
   * `focusOnReady=false`（嵌入式/日志流等复用场景）时完全不请求，保持与接线前等价。
   *
   * ★ W5：**带幂等重试**（AGENTS 陷阱 20 的同一纪律）★
   *   实测（本窗口）：回车「建兄弟块」之后，ArkUI 会把焦点从 RichEditor 移到它所在的行
   *   （`AceFocus: RichEditor/secure_field trigger onBlurInternal by 2` →
   *    `FocusSwitch end, RichEditor/secure_field onBlur, Row/secure_field onFocus`），
   *   新块那一行的 `BlockEditor.onReady` 里那一次 `requestFocus` 于是**落空**
   *   ⇒ 新块看着建出来了、光标却不在里面，后续键入全部丢失（`dumpLayout` 里一个 RichEditor 都没有）。
   *   而 W1/W2 早已实测「`requestFocus` → `onFocus` 是**异步**的（≈620ms）」且可能落空
   *   ⇒ 与 `BlockAnchorService.revealBlockDeferred` 同一手法：**幂等**地补几次。
   *   `requestFocus` 是幂等的（重复请求同一 id 无副作用），且一旦 `handleFocus` 到了就停。
   */
  private requestFocusIfAuthoritative(): void {
    if (!this.focusOnReady) {
      return;
    }
    this.requestFocusAttempt(0);
  }

  /** `requestFocusIfAuthoritative` 的分步实现（attempt 从 0 开始，上限 `FOCUS_MAX_ATTEMPTS`） */
  private requestFocusAttempt(attempt: number): void {
    setTimeout(() => {
      if (this.destroyed) {
        return;
      }
      // 已经拿到过焦点 ⇒ 不再打扰（`handleFocus` 会置位，`handleBlur` 会复位）
      if (this.focusedOnce) {
        return;
      }
      if (this.focusedBlock !== this.blockUuid) {
        return;
      }
      try {
        focusControl.requestFocus(this.focusId);
      } catch (e) {
        console.error('[BlockEditor] requestFocus failed: block=' + this.blockUuid);
      }
      if (attempt + 1 < BlockEditor.FOCUS_MAX_ATTEMPTS) {
        this.requestFocusAttempt(attempt + 1);
      }
    }, BlockEditor.FOCUS_RETRY_MS);
  }

  /**
   * 内容变更回调。
   *
   * ⚠️ 这里**不做 span 重建**（与 `IntegralEditor` 的做法**刻意不同**，理由见类头）：
   *   迁移前每一次 `onDidChange` 都跑一遍全量重建，单键成本 `O(全页段数)`，是历史卡顿的
   *   一条线索；而 live preview 的视觉效果（语法标记显隐 / 行内渲染态）**只依赖
   *   (文本, 光标) 两个输入** —— 因此：
   *     · 文本变了 → 交给 `rebuildSpans()`（仍然整块重建，但只重建**本块**，且由
   *       `lastSpanText` 短路保证一次变更只重建一次）；
   *     · 文本没变（纯样式回写、回填回声）→ 直接丢弃。
   *
   * `rangeAfter.end` 就是编辑后的块内相对光标位置，直接用于 `caretOffset`。
   */
  private onDidChange(rangeBefore: TextRange, rangeAfter: TextRange): void {
    if (this.programmaticDepth > 0) {
      // 我们自己正在写 span（回填 / 重建 / 工具条命令）—— 丢弃，见类头 ①
      return;
    }
    const text = LivePreviewHelper.extractText(this.controller);
    // ⚠️ **空提取一律丢弃**（W5 实测踩出来的硬闸 ✗）：native 在「span 被清、还没写回」的
    //    窗口里 `getSpans()` 会返回空 ⇒ `extractText()` 得 `''`。
    //    若在这里把 `''` 当成「用户清空了本块」同步进数据模型，就会**静默抹掉整块内容**
    //    （W5 实测：`__S1_long.md` 首行 `- 测试块 2` → `- `，4664 → 4653，**−11 字节**）。
    //    与 `onSelectionChange` / `aboutToDisappear` 的 `text !== ''` 是同一道闸，三处必须一致。
    if (text === '') {
      if (this.blockData !== undefined && this.blockData.content !== '') {
        return;
      }
    }
    if (text === this.snapshotText) {
      // 闸门落下之后的迟到回声（实测可能发生）：逐字符相同 ⇒ 这不是内容变更
      return;
    }
    this.lastRenderedText = text;
    // `TextRange.end` 在 SDK 里是可选字段 ⇒ 必须显式收窄（ArkTS 禁 any / 禁隐式 undefined）
    const afterEnd: number | undefined = rangeAfter !== undefined && rangeAfter !== null
      ? rangeAfter.end : undefined;
    if (afterEnd !== undefined) {
      this.caretOffset = afterEnd;
    }
    // 把内存里的块内容**就地**同步（只在这一处写，且只在文本真的变化时）：
    // 这样 `BlockView.onGlobalFocusChanged` 退出编辑态后重渲染能立刻读到新内容。
    this.refreshBlock();
    const current = this.blockData !== undefined ? this.blockData.content : '';
    if (current !== text) {
      EditorService.getInstance().updateBlockContent(this.blockUuid, text);
    }
    this.snapshotText = text;
    if (text !== this.lastSpanText) {
      this.rebuildSpans();
    }
  }

  /**
   * 选区/光标变更。
   * ⚠️ 光标动了但文本没动时**也必须重建** —— live preview 的「语法标记是否显示」
   * 是光标位置的函数（`cursorInside`），不重建就会出现「点进 `**bold**` 里看不到 `**`」。
   * 用 `lastSpanCaret` 短路：只有 (text, caret) 真的变了才重建。
   *
   * ★★ S3-W5 归因（本窗口设备实测）：`spanIndex error` 与 `onSelectionChange` 的关系 ★★
   *   native 在「提交一次输入」时的顺序是（hilog `AceRichText` 逐行）：
   *     `insertLen=1` → `caret:6->7` → **`GetCaretPosition`**（= 本回调）
   *     → `delete spans`（= 本方法的重建）→ `AddTextSpan(len=6)` → `AddTextSpan(len=1, themeFC=1)`
   *     → **`spanIndex error, return`**
   *   ⚠️ **本窗口试过把重建推到下一帧（0ms / 120ms / 400ms 三档），结论是行不通 ✗**：
   *     · 0ms / 120ms：重建仍落在那次输入提交之内（`delete spans` 与 native 的
   *       `AddTextSpan(len=1)` 仍同毫秒），`spanIndex error` 照旧；
   *     · 400ms：虽然避开了那次提交，但**键盘输入整个失效** ——
   *       实测 `AceFocus` 里 `node: RichEditor handle OnKeyPreIme` 之后
   *       **没有 `OnKeyEventInteral Node process self: Node RichEditor`**，
   *       键被 `List/Column/Stack/page` 直接接走（`insertLen` 再也没出现）。
   *   ⇒ **保持同步重建**（W2/W4 的既有形态），本窗口**不在这里做时序改造** ✗。
   *   真正让 Enter 可用的办法是**不让 native 去插那个换行**（见 `routeKeyEnter`），
   *   而不是跟 native 抢时序。
   */
  private onSelectionChange(): void {
    if (this.programmaticDepth > 0) {
      return;
    }
    let caret: number = -1;
    try {
      caret = this.controller.getCaretOffset();
    } catch (e) {
      caret = -1;
    }
    if (caret < 0) {
      return;
    }
    this.caretOffset = caret;
    // ★ 对症修复（S3-W4 实测）：native 在「插入字符」时**先报光标、后报内容变更**
    //   （系统日志顺序恒为 `insertLen=1 → caret:5->6 → OnSelectionChange`，`onDidChange` 在其后）。
    //   旧实现只看 `caret !== lastSpanCaret` 就重建，而 `rebuildSpans()` 用的是
    //   **上一次的 `lastRenderedText`** ⇒ 把刚输入的字符用一个旧快照覆盖掉：
    //   实测 native 侧 `delete spans, range=[0,6]` 之后只 `AddTextSpan len=5`，
    //   字符被静默丢弃、磁盘逐字节不变（`__S1_long.md` 4661B / MD5 不变）。
    //   ⇒ 这里先与编辑器**真实内容**对齐（并在内容真的变了时同步数据模型），
    //     再决定是否重建；重建时用的就是新文本，不会再覆盖。
    const live: string = LivePreviewHelper.extractText(this.controller);
    // ⚠️ 空提取必须丢弃（与 `aboutToDisappear` 的 `text !== ''` 同一道闸）：
    //    重建窗口内控制器可能读回空串，那不是「用户清空了本块」。
    if (live !== '' && live !== this.lastRenderedText) {
      this.lastRenderedText = live;
      this.refreshBlock();
      const current = this.blockData !== undefined ? this.blockData.content : '';
      if (current !== live) {
        EditorService.getInstance().updateBlockContent(this.blockUuid, live);
      }
      this.snapshotText = live;
    }
    if (this.lastRenderedText !== this.lastSpanText || caret !== this.lastSpanCaret) {
      this.rebuildSpans();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // W5 · B 形态按键归属（恢复 WebEditor 时代的块级键契约）
  // ═══════════════════════════════════════════════════════════════════════════
  //
  // ─── 为什么落点是「本组件自己的 RichEditor」，而不是 ContentArea ───
  //   · 实测（W5 探针）：ContentArea 根的 `onKeyPreIme` **确实**能收到这些键
  //     （`Tab`/`Enter`/`↑`/`↓`/`←`/`Backspace` 全部命中）⇒ W4「键到不了 ContentArea」
  //     只对**没有挂 `onKeyPreIme`** 的那个形态成立（它挂的是默认尺寸的 `onKeyEvent`）。
  //   · 但**落点仍必须最窄**：`onKeyPreIme` 返回 true 会连 **input method events**
  //     一起拦（SDK `common.d.ts:18672-18687` 原文逐条列出 `keyboardShortcut` /
  //     `input method events` / `onKeyEventDispatch` / `onKeyEvent`）⇒ 挂在 ContentArea
  //     等于给**所有**输入目标（含各浮层输入框）装了一层 pre-IME 拦截，
  //     误伤面从「一个块的编辑器」扩大到「全页」。挂在本组件上则天然带
  //     「本块正在编辑」这一个作用域。
  //
  // ─── 三条落点各自的理由（**为什么不是全都用同一个回调**）───
  //   ① `Tab` / `Shift+Tab` ⇒ **必须在 `onKeyPreIme` 拦，且返回 true**。
  //      实测：Tab 会触发 ArkUI 的焦点遍历
  //      （`AceFocus: Request next focus by custom focus algorithm. Next focus node is ListItem/1489`,
  //        随后 `FocusSwitch end, Row/secure_field onBlur, RichEditor/secure_field onFocus`），
  //      焦点漂到别的行 ⇒ 该行 `onClick` 被焦点系统当成「点击」触发 ⇒ 那行也进编辑态
  //      并把它自己的内容落盘（实测污染：`__S1_long.md` 首行变成 `- 测试块 3b`，**跨行串台**）。
  //      这是**独立于缩进功能的破坏性**，所以 Tab 必须在 pre-IME 就截住。
  //      Tab **不是输入法会用到的键** ⇒ 拦它不碰组词。
  //   ② `↑` / `↓` / `Backspace` ⇒ 走 **post-IME 的 `onKeyEvent`**，**不碰 preIme**。
  //      理由：`↑↓` 在组词态是**选候选**、`Backspace` 在组词态是**删候选字母**
  //      —— 这两件事都必须由输入法先拿到。`onKeyEvent` 晚于输入法事件
  //      （SDK 同段原文的顺序：preIme → keyboardShortcut → **input method events** →
  //        onKeyEventDispatch → onKeyEvent），**输入法消费掉的键不会到达 onKeyEvent**
  //      （W11 已实测「拼音字母键 0 次进入路由器」就是这条机制的旁证）
  //      ⇒ 「让输入法先拒绝」这条 W11 用代价换来的纪律在这里**被完整保留** ✓。
  //   ③ `Enter` ⇒ **落在 `onKeyPreIme`，并带一个组词态守卫**（★ W9 定稿 ★）。
  //      ⚠️ 本条经历了三次结论变化，务必读全，否则会重复走弯路：
  //      · W5 写：「Enter 放 preIme」+ 用「输入法消费掉的键不会到达应用回调」排除组词风险
  //      · W8 实测**证伪**：preIme 消费 ⇒ 输入法永远拿不到回车 ⇒ 判据④判负 ✗
  //      · W9 先按「把 Enter 整段搬到 post-IME 的 `onKeyEventDispatch`」实现，实测发现
  //        **本机上输入法会把 Enter 的 Down 在 post-IME 之前吃掉**（`W9PROBE dispatch code=2054
  //        type=1` —— 只到抬起；同会话里 ↑↓ 两相都到、Tab 的 Up 也到 ⇒ 不是回调没挂上）
  //        ⇒ **非组词态的 Enter 整个失效** ✗ ⇒ 该方案不可行，回到 preIme。
  //      · W9 定稿：**留在 preIme**，但用「**应用是否看得见字母键**」判组词态
  //        （推导与实测见 `routeKeyPreIme()` 头）⇒ 两种态各自正确 ✓
  //      ⚠️ 与 ②的区别：`onKeyEvent` **晚于 native** ⇒ 不能放 Enter（W5 实测「太晚」，
  //        native 的换行插入已经发生、且必然 `spanIndex error`）。
  //      ⇒ 顺便回答「RichEditor 自己先吃掉 Enter 是否天然满足 IME 优先」：**不成立** ✗
  //        —— 实测 Enter 的 Down 也能到 ContentArea 的 `onKeyPreIme`，并不是「RichEditor 独吞」。
  //
  // ─── 与 WebEditor 时代的语义对齐（`WebEditor.ets` 的 HTML `keydown`）───
  //   | 键            | WebEditor（HTML 侧）        | 本实现（B 形态）              |
  //   |---------------|-----------------------------|-------------------------------|
  //   | Enter（末尾） | `newBlock`（建兄弟块）      | `editor.create-below` ✓       |
  //   | Enter（行中） | `newBlock`（切分）          | **块内换行**（更贴近 Sprint-02 §3 风险 5）|
  //   | Shift+Enter   | 默认行为 = 块内换行         | 块内换行 ✓                    |
  //   | Tab           | `indent`                    | `editor.indent` ✓             |
  //   | Shift+Tab     | `outdent`                   | `editor.outdent` ✓            |
  //   | Backspace(空) | `delete`（删空块）          | `editor.delete-empty` ✓       |
  //   | ↑↓（块首/末） | `focusPrev`/`focusNext`     | 跨块迁移 ✓                    |

  /** 键路由是否处于主控态（正文编辑器在编辑态 + 焦点权威就是本块 + 没有浮层在跑） */
  private ownsKeyboard(): boolean {
    if (!this.focusedOnce) {
      return false;
    }
    if (this.focusedBlock !== this.blockUuid) {
      return false;
    }
    return true;
  }

  /**
   * ★ W9 新增 ★ 本组件此刻是否处于 **IME 合成态**（预编辑缓冲区里有未上屏的字）。
   *
   * ⚠️ 定位说明：**这不是主要判据**（主要判据是 `sawLetterKey`，见 `routeKeyPreIme()` 头），
   * 而是「万一某个输入法**确实**走 previewText 协议」时的另一条独立信号 —— 两条都判「非合成」
   * 才由应用接管回车。本机上它**恒为 false**（实测见下），所以它不改变任何行为。
   *
   * W9 逐条核查了 `rich_editor.d.ts` 的全部 IME 通道，结论是**没有一条能在合成期间报出状态**：
   *   | 通道 | 时机 | 本机实测（W9，2in1） |
   *   |---|---|---|
   *   | `getPreviewText()`（`rich_editor.d.ts:2295-2307`，返回 `PreviewText{offset,value}`，`text_common.d.ts:625+`）| 任意时刻可读 | 控制器可用（不抛异常），但组词态 **value 恒为空（len=0）** ⇒ 拿不到合成文本 |
   *   | `aboutToIMEInput`（`:2786-2807`，入参含 `previewText?`）| IME **提交**之前 | 组词期间 **0 次**；只在上屏那一次触发 |
   *   | `onIMEInputComplete` / `onDidIMEInput`（`:2808-2853`）| IME **提交完成**之后 | 属于「已上屏」信号，无法用于「上屏前」判断 |
   *   | `onWillChange` / `onDidChange` | 内容**将要/已经**变化 | 组词不改变内容 ⇒ 不触发 |
   *   | `KeyEvent` 字段（`common.d.ts:11038-11182`：type/keyCode/keyText/keySource/deviceId/metaKey/timestamp/unicode/…）| — | **没有**任何合成态字段 ✗ |
   *   | `@ohos.inputMethod` 公开面（`getInputMethodState()` 只回 `EnabledState`；`on('setPreviewText')`/`on('finishTextPreview')` 是**输入法应用**侧，`getInputMethodState` 对普通应用直接报 `12800004 - not an input method application`）| — | 普通应用查不到「是否正在合成」✗ |
   * W9 实测日志（组词 `ni'hao` + Enter，探针 `W9PROBE`）：
   *   `preIme code=2054 … prev=ok len=0 off=0 comp=0`
   *   → `aboutToIMEInput off=8 val=n prevText=` → `onIMEInputComplete val=…` → `onDidIMEInput start=8 end=9`
   * ⇒ **合成期间应用侧一个信号都收不到**（W8/W11 的登记被 W9 用「轮询式接口 + 提交回调」
   *   两个方向同时证实 ✓）。
   *
   * ⚠️ 出错/不可用一律**判为「非合成」**：宁可退回 W5 行为，也不能让守卫把回车永久吃掉 ✗。
   */
  private isComposingNow(): boolean {
    try {
      const pt: PreviewText = this.controller.getPreviewText();
      if (pt === undefined || pt === null) {
        return false;
      }
      return pt.value !== undefined && pt.value !== null && pt.value.length > 0;
    } catch (e) {
      return false;
    }
  }

  /** 编辑器当前文本（spans 求和）；空提取时退回「最近一次渲染文本」 */
  private editorText(): string {
    const t = LivePreviewHelper.extractText(this.controller);
    if (t !== '') {
      return t;
    }
    return this.lastRenderedText;
  }

  /**
   * 光标是否在**首行**（纯文本判据，不需要 native 坐标 —— 设计文档 §3.2 已定）。
   * 首行 ⇔ 光标之前没有 `\n`。
   */
  private caretOnFirstLine(text: string, caret: number): boolean {
    if (caret <= 0) {
      return true;
    }
    const head = text.substring(0, Math.min(caret, text.length));
    return head.indexOf('\n') < 0;
  }

  /** 光标是否在**末行**：光标之后没有 `\n` */
  private caretOnLastLine(text: string, caret: number): boolean {
    if (caret >= text.length) {
      return true;
    }
    const tail = text.substring(Math.max(0, caret));
    return tail.indexOf('\n') < 0;
  }

  /**
   * 邻居解析：用**可见行序列**（`getVisibleBlocks`，与 `scrollToIndex` 同一坐标空间）
   * 现算前后行。刻意不新增任何缓存/装置 —— 与 `fenceOpenForThisBlock()` 同一手法。
   *
   * @returns 下标；不在可见集里返回 -1
   */
  private visibleRowIndex(): number {
    const ws = WorkspaceService.getInstance();
    const pageId = ws.getPageUuidForBlock(this.blockUuid);
    if (!pageId) {
      return -1;
    }
    const rows: BlockData[] = ws.getVisibleBlocks(pageId);
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].uuid === this.blockUuid) {
        return i;
      }
    }
    return -1;
  }

  /**
   * 把编辑焦点迁到相邻可见行（跨块 ↑↓ 的实现）。
   *
   * 顺序（与设计文档 §3.2 一致）：
   *   ① 写权威焦点 `EditorService.setFocusedBlock(uuid)`（AppStorage 随之变化 ⇒
   *      目标行 `BlockView` 的 `@Watch` 把它切进编辑态、本行切出并落盘）；
   *   ② `BlockAnchorService.revealBlockDeferred` 保证目标行**已被 LazyForEach 创建**
   *      （离屏行没有实例 ⇒ `requestFocus` 会落空）。它自带**幂等重试**
   *      （80ms / +240ms，上限 2 次，AGENTS 陷阱 20）⇒ **不要自己再写一套** ✓
   *   ③ 目标行 `BlockEditor.onReady` 的下一帧自己去 `requestFocus`
   *      （实测请求→`onFocus` ≈620ms，是异步的，不做同步断言）。
   */
  private focusAdjacentBlock(delta: number): boolean {
    const idx = this.visibleRowIndex();
    if (idx < 0) {
      return false;
    }
    const ws = WorkspaceService.getInstance();
    const pageId = ws.getPageUuidForBlock(this.blockUuid);
    if (!pageId) {
      return false;
    }
    const rows: BlockData[] = ws.getVisibleBlocks(pageId);
    const target = idx + delta;
    if (target < 0 || target >= rows.length) {
      return false;
    }
    const targetUuid = rows[target].uuid;
    if (targetUuid === this.blockUuid || targetUuid === '') {
      return false;
    }
    EditorService.getInstance().setFocusedBlock(targetUuid);
    // 离屏行可能还没实例化 ⇒ 先让它进可见区（幂等重试由服务内部保证）
    const page = ws.getDataStore().getIndexStore().getPage(pageId);
    const pageName = page !== undefined ? page.originalName : this.pageName;
    BlockAnchorService.getInstance().revealBlockDeferred(pageId, pageName, targetUuid);
    return true;
  }

  /**
   * pre-IME 键路由（**Tab / Shift+Tab / Enter**，见本节头 ①②③ 的分工说明）。
   *
   * ★ W9 定稿（对症，判据④）★：Enter **留在本函数**，但加一个**组词态守卫**
   *   （`sawLetterKey` / `isComposingNow()`）——
   *   理由与三组 A/B 实测见函数体内的长注释，结论是「Enter 整段搬到 post-IME」在本环境
   *   **不可行**（输入法会把 Enter 的 Down 在 post-IME 之前吃掉）。
   *
   * @returns true = 已消费（调用方 `return true` ⇒ 键不再交给输入法与 native 编辑器）
   */
  private routeKeyPreIme(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) {
      return false;
    }
    if (!this.ownsKeyboard()) {
      return false;
    }
    const code = event.keyCode;
    // ─── ★ W9（判据④，对症）★ 组词态守卫 + Enter 归属 ───
    // 背景（W9 在 MateBook Pro / 2in1 上的实测，三组对照）：
    //   ① **preIme 消费 Enter**（W5 形态）⇒ 组词 `ni'hao` + Enter ⇒ `enter->create-below`、
    //      磁盘 3196→3199（+3，只建块）、**拼音原文未上屏** ✗ —— 判据④判负
    //   ② **preIme 放行 Enter**（W9 首版，改由 post-IME 的 `onKeyEventDispatch` 接）⇒
    //      组词态 ✓ 通过（IME 拿到回车并上屏：`aboutToIMEInput val=…` →
    //      `onIMEInputComplete`，磁盘 3278→3283 = +5 字节的 `nihao`，`od -c` 无 `\n` ✓）
    //      但**非组词态 Enter 整个失效** ✗：`W9PROBE dispatch code=2054 **type=1**` —— 只到
    //      **抬起**、Down 从未到达 post-IME。同一次会话里 `↓/↑` 两相都到（`type=0/1`）、
    //      `Tab` 的 Down 被 preIme 自己消费而 Up 到达 ⇒ **不是回调没挂上，是 Enter 的 Down
    //      被输入法在 post-IME 之前就拿走了** ✗
    //   ⇒ 两条硬事实的夹缝：**应用只能在 preIme 看到 Enter 的 Down；而只要放行，输入法就会
    //     把它吃掉（不分是否组词）** ⇒「把 Enter 整段搬到 post-IME」在本环境**不可行**，
    //     必须留在 preIme，并在 preIme 里区分组词态。
    //
    // ─── 区分组词态的判据：`sawLetterKey`（不是猜，是同一台设备上的对照事实）───
    //   · 逐条核查过 `RichEditor` 的全部合成态通道，**没有一个能用**（证据见 `isComposingNow()` 头）：
    //     `getPreviewText()` 组词中恒为 `len=0`；`aboutToIMEInput`/`onIMEInputComplete`/
    //     `onDidIMEInput` 都只在**上屏之后**才来；`KeyEvent` 无合成态字段。
    //   · 但有一条**结构性**事实可用：**输入法先把键吃掉，应用才看得到剩下的**。
    //     组词期间拼音字母由输入法消费 ⇒ 应用在 preIme **收不到字母**；
    //     非组词时字母直达 preIme ⇒ 应用**收得到**（W9 实测：注入 5 个字母全部命中 preIme ✓）。
    //   · 于是：Enter 到达 preIme 时，若**刚见过字母键** ⇒ 输入法手里很可能有未上屏的拼音 ⇒ 放行；
    //     若**没见过** ⇒ 光标处没有待上屏内容 ⇒ 应用接管（W5/W6/W7 的 Enter 语义全部保住）。
    //     ⚠️ 刻意**不在「输入法提交文本」时复位**（例如挂在 `onDidChange` 上）：
    //        本机的组词**提交发生在回车的那一刻**（实测：preIme 收到 2054 → 紧接着
    //        `aboutToIMEInput val=n`/`onIMEInputComplete`）⇒ 若在提交时复位，会得到一个
    //        **复位后紧跟着回车**的序列，而「放行之后输入法会把回车吃掉」这条事实
    //        （见上 ②）意味着那个回车会**凭空消失** ✗ —— 恰好又制造出「回车没反应」的 bug。
    //        复位点因此只有**焦点离开本块**（见 `handleBlur`），与实测装置一一对应。
    //        （副作用：块内打字后回车也会先让给输入法一次 —— 见交付文档「未验证项/保守项」。）
    if (BlockEditor.isLetterKeyCode(code)) {
      this.sawLetterKey = true;
    }
    if (code === BlockEditor.K_ENTER || code === BlockEditor.K_NUMPAD_ENTER) {
      // 两条独立判据，**任一**判为「合成中」就放行（纵深防护，见 `isComposingNow()` 头）：
      //   ① `sawLetterKey` —— 本机唯一有效的判据（结构性事实，见上）
      //   ② `isComposingNow()` —— 走 previewText 协议的输入法的兜底（本机恒 false）
      if (this.sawLetterKey || this.isComposingNow()) {
        hilog.info(BlockEditor.DOMAIN, BlockEditor.TAG,
          'W9KEY enter->let-ime letter=%{public}s prev=%{public}s block=%{public}s',
          this.sawLetterKey ? '1' : '0', this.isComposingNow() ? '1' : '0', this.blockUuid);
        return false;
      }
      return this.routeKeyEnter(event);
    }
    if (code !== BlockEditor.K_TAB) {
      return false;
    }
    let shift = false;
    try {
      shift = event.getModifierKeyState !== undefined
        ? event.getModifierKeyState(['shift']) : false;
    } catch (e) {
      shift = false;
    }
    this.keyRouted = this.keyRouted + 1;
    hilog.info(BlockEditor.DOMAIN, BlockEditor.TAG,
      'W5KEY preIme tab shift=%{public}s n=%{public}d', shift ? '1' : '0', this.keyRouted);
    // 先与编辑器真实内容对齐（缩进是结构操作，之前打的字必须先落到数据模型里）
    this.alignTextWithEditor();
    const editor = EditorService.getInstance();
    editor.setFocusedBlock(this.blockUuid);
    if (shift) {
      editor.outdentBlock();
      this.onAction('outdent', '');
    } else {
      editor.indentBlock();
      this.onAction('indent', '');
    }
    return true;
  }

  /** 把编辑器真实内容对齐进数据模型（游标移动/程序化写入都不会漏） */
  private alignTextWithEditor(): void {
    const live = LivePreviewHelper.extractText(this.controller);
    // ⚠️ 空提取一律丢弃（与 `aboutToDisappear` 的 `text !== ''` 同一道闸）：
    //    销毁/重建窗口内控制器可能读回空串，那不是「用户清空了本块」。
    //    W5 实测过一次代价（`__S1_long.md` 4664 → 4653，首行内容被 `''` 盖掉）⇒ 这道闸是硬的 ✗。
    if (live === '') {
      return;
    }
    if (live === this.lastRenderedText) {
      return;
    }
    this.lastRenderedText = live;
    this.refreshBlock();
    const current = this.blockData !== undefined ? this.blockData.content : '';
    if (current !== live) {
      EditorService.getInstance().updateBlockContent(this.blockUuid, live);
    }
    this.snapshotText = live;
  }

  /**
   * post-IME 键路由（**只放 ↑ / ↓ / Backspace**，见本节头 ② 的分工说明）。
   *
   * 到达这里即意味着**输入法没有消费这个键**（post-IME 落点的语义）
   * ⇒ 组词态的「↑↓ 选候选」「Backspace 删候选字母」天然不受影响 ✓。
   *
   * @returns true = 已消费
   */
  private routeKeyPostIme(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) {
      return false;
    }
    if (!this.ownsKeyboard()) {
      return false;
    }
    const code = event.keyCode;
    const text = this.editorText();
    let caret = this.caretOffset;
    if (caret < 0 || caret > text.length) {
      caret = text.length;
    }

    // ─── ↑：光标在首行 ⇒ 越界到上一块 ───
    if (code === BlockEditor.K_DPAD_UP) {
      if (!this.caretOnFirstLine(text, caret)) {
        return false; // 块内换行 ⇒ 让 native 自己移光标
      }
      const moved = this.focusAdjacentBlock(-1);
      if (moved) {
        hilog.info(BlockEditor.DOMAIN, BlockEditor.TAG,
          'W5KEY up->prev block=%{public}s', this.blockUuid);
      }
      return moved;
    }

    // ─── ↓：光标在末行 ⇒ 越界到下一块 ───
    if (code === BlockEditor.K_DPAD_DOWN) {
      if (!this.caretOnLastLine(text, caret)) {
        return false;
      }
      const moved = this.focusAdjacentBlock(1);
      if (moved) {
        hilog.info(BlockEditor.DOMAIN, BlockEditor.TAG,
          'W5KEY down->next block=%{public}s', this.blockUuid);
      }
      return moved;
    }

    // ─── Backspace：**块为空且光标在 0** ⇒ 删空块（与 WebEditor 的 `delete` 同语义）───
    //   ⚠️ 判据刻意收紧到「空块」：有内容时 Backspace 是普通删除，
    //      **必须交给 native**（否则连输入法删候选字母都会被打断，且要自己实现删字）。
    if (code === BlockEditor.K_DEL) {
      if (text !== '' || caret > 0) {
        return false;
      }
      this.refreshBlock();
      const model = this.blockData !== undefined ? this.blockData.content : '';
      if (model !== '') {
        return false; // 数据模型里还有内容 ⇒ 不是空块，交给 native
      }
      const editor = EditorService.getInstance();
      editor.setFocusedBlock(this.blockUuid);
      const removed = editor.deleteEmptyBlock();
      if (!removed) {
        return false;
      }
      hilog.info(BlockEditor.DOMAIN, BlockEditor.TAG,
        'W5KEY backspace->delete-empty block=%{public}s', this.blockUuid);
      this.onAction('deleteEmpty', '');
      return true;
    }
    return false;
  }

  /**
   * Enter / 小键盘 Enter 的接管（落点 = `onKeyPreIme`，**门外有一道组词态守卫**）。
   *
   * ─── ★★ W9：为什么最终留在 pre-IME（而不是搬到 post-IME）★★ ───
   * W5 把 Enter 放在 pre-IME 的**理由**（「只有 pre-IME 能拦住 native 插换行」）依然成立 ✓，
   * 但 W5 用来**排除组词态风险**的那条旁证不成立 ✗ —— 它写的是
   * 「输入法消费掉的键不会到达应用的按键回调（W11 实测拼音字母键 0 次进入路由器）」，
   * 而这条机制**只对 post-IME 回调成立**（同一文件 `:442-448` 正是为此把 ↑↓/Backspace 放 post-IME）。
   * W8 在 2in1 上实测证伪：preIme 里 `return true` ⇒ **IME 从来没拿到过回车** ✗。
   *
   * W9 先按「**换落点**」实现（Enter 搬到 post-IME 的 `onKeyEventDispatch`），
   * 组词态确实修好了 ✓，但**非组词态 Enter 整个失效** ✗ —— 实测本机上
   * 输入法会把 Enter 的 **Down** 在 post-IME 之前吃掉（`W9PROBE dispatch code=2054 type=1`：
   * 只到**抬起**；同一会话里 `↑/↓` 两相都到、`Tab` 的 Up 也到 ⇒ 不是回调没挂上）。
   * ⇒ **「换落点」在本环境不可行**，只能留在 preIme + 在 preIme 里判组词态
   *   （判据与实测见 `routeKeyPreIme()` 头）。
   * ⇒ 本函数体**一行未改**：语义（行中/Shift ⇒ 块内换行；末尾 ⇒ 建兄弟块）逐字保持 W5 形态 ✓。
   *
   * @returns true = 已消费
   */
  private routeKeyEnter(event: KeyEvent): boolean {
    let shift = false;
    try {
      shift = event.getModifierKeyState !== undefined
        ? event.getModifierKeyState(['shift']) : false;
    } catch (e) {
      shift = false;
    }
    // 先把编辑器真实内容对齐进数据模型（结构操作前的硬要求）
    this.alignTextWithEditor();
    const text = this.lastRenderedText;
    let caret = this.caretOffset;
    if (caret < 0 || caret > text.length) {
      caret = text.length;
    }
    const atEnd: boolean = caret >= text.length;

    if (shift || !atEnd) {
      // ─── 块内换行：把 `\n` 插到光标处（整块重建时 `addTextSpan` 接受含 `\n` 的文本，实测可用）───
      const out = text.substring(0, caret) + '\n' + text.substring(caret);
      this.keyRouted = this.keyRouted + 1;
      hilog.info(BlockEditor.DOMAIN, BlockEditor.TAG,
        'W5KEY enter->newline caret=%{public}d len=%{public}d n=%{public}d',
        caret, text.length, this.keyRouted);
      this.applyTextEdit(out, caret + 1);
      return true;
    }

    // ─── 末尾回车：建兄弟块（`editor.create-below` 的等价动作）───
    const ws = WorkspaceService.getInstance();
    const pageId = ws.getPageUuidForBlock(this.blockUuid);
    if (pageId === undefined || pageId === '') {
      return false;
    }
    const editor = EditorService.getInstance();
    // 权威焦点必须是本块，`createBlockBelow` 才会挂在正确的位置
    editor.setFocusedBlock(this.blockUuid);
    const newUuid = editor.createBlockBelow(pageId);
    this.keyRouted = this.keyRouted + 1;
    hilog.info(BlockEditor.DOMAIN, BlockEditor.TAG,
      'W5KEY enter->create-below new=%{public}s ok=%{public}s n=%{public}d',
      newUuid, newUuid !== '' ? '1' : '0', this.keyRouted);
    if (newUuid === '') {
      return false;
    }
    // ★★ W5 必补的一步（实测，非推测）：`EditorService.createBlockBelow` **只写了自己的
    //   私有字段 `focusedBlockUuid`，没有走 `setFocusedBlock`**（见 `EditorService.ets:254-257`）
    //   ⇒ **`AppStorage['callaite_focusedBlock']` 不会变** ⇒
    //     · 本行的 `BlockView` 收不到 `@Watch`、`isEditing` 一直是 true（旧编辑器不销毁）；
    //     · 新行的 `BlockView` 也收不到 ⇒ 新块**永远不进编辑态**。
    //   实测后果：回车建的块在磁盘上**确实存在**（4661→4664→4667 逐次 +3），
    //   但随后注入的字符一个都进不去（`b`/`n` 注入后磁盘逐字节不变、`W5KEY` 也不再有行），
    //   最终 `dumpLayout` 里连一个 `RichEditor` 都没有（编辑态整体退出）✗。
    //
    // ⚠️⚠️ 但**权威写入必须推到下一帧**，不能在 pre-IME 回调里同步做（这是实测踩出来的）：
    //   同步 `setFocusedBlock` ⇒ AppStorage 立刻变 ⇒ 本行 `BlockView.isEditing=false` ⇒
    //   本编辑器在**本次按键事件还没走完**时就被销毁，其 `aboutToDisappear` 读回文本
    //   （此时 native 侧 span 已被清、`extractText()` 返回 `''`）⇒ 用 `''` 盖掉本块内容。
    //   实测后果（不可接受）：`__S1_long.md` 首行由 `- 测试块 2` 变成 `- `，**4664 → 4653（−11 字节）**。
    //   ⇒ 排到下一帧：本回调先把 Enter 消费掉、native 处理完这一帧，再切焦点。
    setTimeout(() => {
      EditorService.getInstance().setFocusedBlock(newUuid);
    }, 0);
    // 新块的编辑器由 `callaite_focusedBlock` 变化驱动挂载；
    // 离屏时先把它带进可见区（幂等重试由服务内部保证，AGENTS 陷阱 20）
    const page = ws.getDataStore().getIndexStore().getPage(pageId);
    const pageName = page !== undefined ? page.originalName : this.pageName;
    BlockAnchorService.getInstance().revealBlockDeferred(pageId, pageName, newUuid);
    this.onAction('createBelow', newUuid);
    return true;
  }

  // ⚠️ 方法名刻意**不叫** `onFocus` / `onBlur`：`CustomComponent` 基类型上已有同名的
  //    属性（`(event: () => void) => CommonAttribute`），自定义 struct 里再声明一个
  //    同名方法会直接编译报错（实测 `10505001 Property 'onFocus' in type 'BlockEditor'
  //    is not assignable to the same property in base type 'CustomComponent'`）。
  private handleFocus(): void {
    this.focusedOnce = true;
    // ⚠️ 刻意**不**改写 `focusedBlockUuid`：权威由点击/快捷键写入，焦点回调只上报
    //    （否则会形成「焦点回调 → setFocusedBlock → 焦点回调」的回环）。
  }

  private handleBlur(): void {
    this.focusedOnce = false;
    // ★ W9 ★ 焦点离开本块 ⇒ 组词守卫复位（下一次聚焦后「没见过字母」是全新的判断）。
    //   这是**唯一**的复位点，理由见 `routeKeyPreIme()` 头（提交时复位会让 bug 复现）。
    this.sawLetterKey = false;
  }

  // ─── MarkdownToolbar 命令通道（与 WebEditor 同一把 AppStorage 键 / 同一套命令名）───

  /**
   * 命令格式 `cmd|seq`。命令面与 `WebEditor` 的 HTML 侧 `applyFormat` **逐条对齐**，
   * 四条命令（`undo` / `redo` / `heading` / `bold`）全部实做，不留空壳。
   * 其余（`[[]]` / `#` / `[](url)` 等插入类）按「光标处插入字面量」处理。
   */
  private onEditorCommand(): void {
    if (this.focusedBlock !== this.blockUuid || this.editorCommand === '') {
      return;
    }
    const parts: string[] = this.editorCommand.split('|');
    const cmd: string = parts[0];
    if (cmd === '') {
      return;
    }
    if (cmd === 'undo' || cmd === 'redo') {
      // 撤销/重做归 `OutlinerEngine`（Sprint-01 已验收的落盘 + 行刷新链路）——
      // 原生编辑器内部没有历史栈，这里**不去动它**，直接转给引擎。
      const editor = EditorService.getInstance();
      if (cmd === 'undo') {
        editor.undo();
      } else {
        editor.redo();
      }
      this.refreshBlock();
      this.lastRenderedText = this.blockData !== undefined ? this.blockData.content : '';
      this.snapshotText = this.lastRenderedText;
      this.rebuildSpans();
      this.onAction('undoRedo', cmd);
      return;
    }
    if (cmd === 'heading') {
      this.applyHeadingCycle();
      return;
    }
    if (cmd === 'bold') {
      this.toggleInlineSyntax(BlockEditor.TOKEN_BOLD);
      return;
    }
    // 插入类命令：把字面量插到光标处（`[](/.md)` 等也只是普通文本）
    this.applyTextEdit(cmd, cmd.length);
  }

  private currentText(): string {
    const t = LivePreviewHelper.extractText(this.controller);
    return t !== '' ? t : this.lastRenderedText;
  }

  /**
   * 标题层级循环：正文 → H1 → H2 → H3 → 正文（与 WebEditor 的 `formatBlock` 循环同构）。
   * 只改行首的 `#{1,3} ` 前缀，不动其余内容。
   */
  private applyHeadingCycle(): void {
    const text = this.currentText();
    const nl = text.indexOf('\n');
    const first = nl >= 0 ? text.substring(0, nl) : text;
    const rest = nl >= 0 ? text.substring(nl) : '';
    let level = 0;
    for (let n = 3; n >= 1; n--) {
      if (first.startsWith('#'.repeat(n) + ' ')) {
        level = n;
        break;
      }
    }
    const body = level > 0 ? first.substring(level + 1) : first;
    const next = level >= 3 ? 0 : level + 1;
    const head = next === 0 ? body : '#'.repeat(next) + ' ' + body;
    const out = head + rest;
    // 光标跟着前缀长度横向平移，落在标题文字起点
    this.applyTextEdit(out, next === 0 ? Math.max(0, this.caretOffset - level - 1)
      : Math.max(0, this.caretOffset - level + next));
  }

  /**
   * 光标处插入字面量（`[[` / `#` / `[](url)` 等）。
   * ⚠️ 必须先 `deleteSpans()` 写回全文、再 `setCaretOffset()`：`addTextSpan(content, {offset})`
   * 的 offset 是**字符坐标**，而 `RichEditorController` 没有「在光标处插入文本」的原生 API。
   * 与设计文档 §1.4 的顺序（deleteSpans → 逐段 addTextSpan）一致。
   */
  private applyTextEdit(newText: string, caret: number): void {
    this.lastRenderedText = newText;
    this.snapshotText = newText;
    this.caretOffset = caret;
    this.lastSpanCaret = caret;
    this.rebuildSpans();
  }

  /**
   * 行内格式标记的「渲染态 ↔ 标记态」翻转（`**` / `` ` `` / `==`）。
   *
   * 语义与 WebEditor 的 `execCommand('bold')` 近似：无选区时在光标处插入一对标记并把
   * 光标放到**两个标记之间**（用户接着打字即为加粗内容）；若光标两侧正是同一对标记，
   * 则移除它们（二次点击 = 取消）。
   */
  private toggleInlineSyntax(token: string): void {
    const text = this.currentText();
    let caret = this.caretOffset;
    if (caret < 0 || caret > text.length) {
      caret = text.length;
    }
    const before = text.substring(0, caret);
    const after = text.substring(caret);
    const lw = token.length;
    let out = '';
    let next = caret;
    if (before.endsWith(token) && after.startsWith(token)) {
      // 已在标记对内 ⇒ 取消
      out = before.substring(0, before.length - lw) + after.substring(lw);
      next = caret - lw;
    } else {
      out = before + token + token + after;
      next = caret + lw;
    }
    this.applyTextEdit(out, next);
  }

  build() {
    RichEditor({ controller: this.controller })
      .id(this.focusId)
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
      .backgroundColor(Color.Transparent)
      .onReady(() => {
        this.onReady();
      })
      .onDidChange((rangeBefore: TextRange, rangeAfter: TextRange) => {
        this.onDidChange(rangeBefore, rangeAfter);
      })
      .onSelectionChange(() => {
        this.onSelectionChange();
      })
      .onFocus(() => {
        this.handleFocus();
      })
      .onBlur(() => {
        this.handleBlur();
      })
      .onKeyPreIme((event: KeyEvent): boolean => {
        // W9：Tab / Shift+Tab + Enter（Enter 带组词态守卫，见 routeKeyPreIme 头）
        return this.routeKeyPreIme(event);
      })
      .onKeyEvent((event: KeyEvent) => {
        // W5：只放 ↑ / ↓ / Backspace；**Enter 刻意不在任何路由里**（见小节头 ③）
        if (this.routeKeyPostIme(event)) {
          event.stopPropagation();
        }
      })
  }
}
