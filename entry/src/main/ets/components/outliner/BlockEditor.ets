import { hilog } from '@kit.PerformanceAnalysisKit';
import { EditorService } from '../../services/EditorService';
import { WorkspaceService } from '../../services/WorkspaceService';
import { DirtyPageTracker } from '../../services/DirtyPageTracker';
import { BlockData } from '../../core/models/Block';
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
   */
  private requestFocusIfAuthoritative(): void {
    if (!this.focusOnReady) {
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
    if (caret !== this.lastSpanCaret) {
      this.rebuildSpans();
    }
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
  }
}
