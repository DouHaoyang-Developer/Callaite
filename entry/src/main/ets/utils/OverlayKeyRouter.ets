import { KeyCode } from '@kit.InputKit';

/**
 * OverlayKeyRouter — U2.2 浮层键盘导航的**单一路由入口**。
 *
 * ─── 解决什么问题 ───
 * 迁移前每个浮层各写一套按键处理（`CommandPalette.handleNavKey` /
 * `SearchPanel.handleNavKey` 是复制关系，`SlashMenu`/`FindInPage` 则完全没有）：
 *   · 「谁该收到这个键」的判据散落在各组件里，多层浮层叠加时无人裁决；
 *   · 每个浮层各持一份 `lastHandledKeyCode` 去重标记，语义靠注释口口相传；
 *   · 没有任何一处能表达「输入法正在组词，这个 Enter 不该被我们抢」。
 * 本类把这四件事收敛到一处：**开合态登记 → 顶层判定 → 守卫 → 去重 → 交付**。
 *
 * ─── 三条硬约束（本类的存在理由）───
 * ① **只在 overlayOpen 态路由**：没有任何浮层打开时 `handle()` 恒返回 false
 *    ⇒ 调用方不得 `stopPropagation`，也不得吞掉按键（无浮层 ⇒ 全局快捷键与
 *    编辑器输入的一切行为与接线前逐字节相同）。
 * ② **顶层优先**：多层同时打开时只有 `topOverlayId()` 接收按键，其余浮层
 *    即使 `handle()` 被调用到也拿不到键（判据 `top !== callerId` 直接返回 false）。
 * ③ **组词/合成态绝不抢键**：见 §IME 守卫。
 *
 * ─── SDK 依据（均为本机 SDK 原文，逐条可复查）───
 * · `onKeyPreIme` 是「早于输入法」的拦截点，一旦返回 true：
 *   "the key event is considered consumed, and subsequent event callbacks
 *    (**keyboardShortcut**, **input method events**, **onKeyEventDispatch**, and **onKeyEvent**)
 *    will be intercepted and no longer triggered."
 *   ⇒ `$SDK/default/openharmony/ets/component/common.d.ts:18672-18687`
 *   这就是「拦截太早会抢走 IME 的键」的机制性证据：**回车既可能是「打开选中项」，
 *   也可能是「拼音组词上屏」，二者在 KeyEvent 里长得一模一样** —— 所以必须另找信号。
 * · `KeyEvent` **没有任何字段**可用于判断合成态。全部字段为：
 *   type / keyCode / keyText / keySource / deviceId / metaKey / timestamp /
 *   stopPropagation / intentionCode / getModifierKeyState / unicode /
 *   isNumLockOn / isCapsLockOn / isScrollLockOn
 *   ⇒ `common.d.ts:11038-11182`（逐字段核对，无 composing/preedit/preview 类字段）
 *   ⚠️ 也正因如此，本类**不使用** `event.timestamp` 作第二判据
 *     （CommandPalette.ets:67 已记录：该字段在本机 SDK 的手机/平板/2in1 形态上被判不可用）。
 * · 应用侧唯一的合成态读信号是 `TextInput.onChange` 的**第二个实参**：
 *   `EditableTextOnChangeCallback = (value: string, previewText?: PreviewText, options?) => void`
 *   ⇒ `ets/component/text_common.d.ts:481`；`PreviewText { offset: number; value: string }`
 *   ⇒ 同文件 `:625-646`（`value` = "Content of the preview text"）。
 *   其语义在 `TextInputAttribute.enablePreviewText` 的原文里写明：
 *   "The preview content is defined as a temporary, **uncommitted** input state"，
 *   且**默认为 true（开启）** ⇒ `ets/component/text_input.d.ts:2028-2043`。
 *   绑定点：`TextInputAttribute.onChange(callback: EditableTextOnChangeCallback)`
 *   ⇒ 同文件 `:1107`。
 *   ⚠️ 只有 onchange 这条**读取**通道：`TextContentControllerBase.clearPreviewText()`
 *   是只写（`common.d.ts:25065`），而带 `getPreviewText?()` 的 `TextEditControllerEx`
 *   （`text_common.d.ts:614`）**不是** `TextInputController` 的父类
 *   （后者 extends `TextContentControllerBase`，`text_input.d.ts:677`）。
 * · 输入法侧控制器不可用：`@ohos.inputMethod` 的 `InputMethodController`
 *   （`on('setPreviewText')` / `on('finishTextPreview')`，`@ohos.inputMethod.d.ts:1242/1263`）
 *   文档原文要求「订阅必须发生在 attach 之前」，即**输入法应用**侧才能用；
 *   其 `getInputMethodState()` 的报错码更是 `12800004 - not an input method application`
 *   （同文件 `:462`）⇒ **普通应用查不到「是否正在合成」**，只能用 ①的 onChange 通道。
 *
 * ─── §IME 守卫（W11 设备实测结论：为什么最终**不在 `onKeyPreIme` 路由**）───
 * 上面那条 onChange 通道在本机**实测不成立**，因此不能作为唯一守卫。实测过程（MatePad Pro 13，
 * 命令面板 + 平板自带中文输入法，注入 + 直接点软键盘按键；路由器临时插 hilog 探针 `W11PROBE`）：
 *   a) 组词态**确实可以复现**：点软键盘 n i h a o 后，键盘上方出现候选条「你好/你号/泥嚎…」、
 *      左下角出现 `ni'hao` 预编辑气泡 —— 这一刻是真正的「未上屏合成态」。
 *   b) 此刻应用侧**收不到任何信号**：`onChange` **一次都没触发**（探针里没有任何 `C`/`P` 行），
 *      因此 `previewText` 从未被投递，`isImeComposing()` 恒为 false。
 *      ⇒ 组词时输入框**内容没变**（预编辑文本在输入法气泡里，不属于内容），
 *        而 `previewText` 只搭在 onChange 上 —— **内容不变 ⇒ 回调不触发 ⇒ 信号拿不到**。
 *   c) 后果（实测、可复现）：候选条在屏时注入 Enter ⇒ 探针 `H type=0 code=2054 … comp=F`
 *      两次（第一次消费、第二次被去重），**面板直接打开高亮项并关闭**，候选被丢弃
 *      —— 正是冲刺文档点名要守住的「组词回车上屏被破坏」✗。
 *   d) 反证（同一次实测）：拼音字母键**从未进入本类**（探针 0 行）⇒ **输入法消费掉的键不会
 *      到达 `onKeyEvent`**。这就是可用的「让位」机制：把路由落点从 pre-IME 换成 **post-IME**，
 *      输入法先拒绝，它不要的键才轮到浮层 —— 无需任何合成态信号。
 * 因此本类的定位是：**接收 post-IME 落点投来的键**（各浮层的 `onKeyEvent`、宿主兜底
 * `handleFromHost` 也挂在 `onKeyEvent` 上），并在自己这一层再保留两道与信号无关的保险：
 *   · 只路由导航键（↑↓/↵/小键盘↵/esc）——字母、Tab、退格等一律放行，永远进不了本类；
 *   · 若某个输入法**确实**投递了预览文本（onChange 第二实参非空），本类立即把该浮层标记为
 *     合成中并放行回车的**这一次按压**（见 `handle` ③）—— 对实现了该协议的输入法再兜一层。
 *
 * ─── 分层与优先级（越上层越先拿到键）───
 * | id             | 浮层           | 优先级 | 依据                                        |
 * |----------------|----------------|--------|---------------------------------------------|
 * | searchPanel    | SearchPanel    | 400    | ContentArea Stack 中后于命令面板绘制 ⇒ 更上 |
 * | commandPalette | CommandPalette | 300    | 带遮罩的居中模态                            |
 * | slashMenu      | SlashMenu      | 200    | 块内联弹层（在内容层内）                    |
 * | findInPage     | FindInPage     | 100    | 页内搜索条（非模态，最底）                  |
 * 优先级**只在本类维护**：新增浮层要显式改 `priorityOf()`，不允许各组件自报高低
 * （自报会让「谁在上面」重新散落到各处，正是本轮要消灭的东西）。
 *
 * ─── 与 `PLAN-UI-Alignment.md` §U2.2 草案的差异（有意为之，逐条说明）───
 * 草案写的是「拦截 → 写 AppStorage('callaite_overlayKey'/'callaite_overlayKeySeq')
 * → 各浮层 @Watch 收键」。本实现改为**注册表 + 同步直接交付**，理由三条：
 *   ① 草案的版本号通道是**广播**：所有打开着的浮层都会收到同一个键，
 *      而验收要求「只有最上层消费」—— 广播做不到，除非每层再自己判一次「我是不是最上层」
 *      （那又把判据散回去了）。本实现对非顶层直接返回 false。
 *   ② 草案用 `event.key`（'ArrowUp' 等字符串），**本机 SDK 的 KeyEvent 没有 `key` 字段**
 *      （字段表见上）。`keyText` 是随键盘布局变化的键名，不可作判据 ⇒ 一律用 `keyCode`
 *      （数值见 `@ohos.multimodalInput.keyCode.d.ts`：UP=2012/DOWN=2013/ENTER=2054/
 *      NUMPAD_ENTER=2119/ESCAPE=**2070**）。
 *   ③ @Watch 的触发时机（是否同帧、是否早于本帧渲染）在本机未验证，
 *      而按键响应要求「一次按压一步状态变化」的确定性 ⇒ 改同步调用，行为可推理。
 *   AppStorage 通道的价值（与 TextInput 焦点解耦）在本实现里由「注册表」同样获得。
 */

/** 浮层标识（路由目标）。字符串常量而非 enum：需与 `priorityOf` 的判据逐字一致。 */
export class OverlayId {
  /** CommandPalette（Ctrl+K，快速切换/命令面板） */
  static readonly COMMAND_PALETTE: string = 'commandPalette';
  /** SearchPanel（Ctrl+F，全局搜索） */
  static readonly SEARCH_PANEL: string = 'searchPanel';
  /** SlashMenu（块内 `/` 命令菜单） */
  static readonly SLASH_MENU: string = 'slashMenu';
  /** FindInPage（页内搜索条） */
  static readonly FIND_IN_PAGE: string = 'findInPage';
}

/**
 * 浮层按键契约。
 *
 * 为什么要一个接口 + 一个 Binding 适配类：ArkTS 的 `@Component struct` **不能**
 * `implements` 接口，故由浮层在 `aboutToAppear` 里 `new OverlayKeyBinding(handler)`
 * 注册；`aboutToDisappear` 里注销。
 */
export interface OverlayKeyHandler {
  /**
   * 交付一个导航键。
   * @param keyCode 按键码（本类已判定属于导航键集合）
   * @param event 原始 KeyEvent（需要修饰键时用 `event.getModifierKeyState!([...])`）
   * @returns true = 本浮层消费（本类据此 return true，调用方应 `stopPropagation`）
   */
  onOverlayKey(keyCode: number, event: KeyEvent): boolean;
}

/** 把 struct 的回调适配成 `OverlayKeyHandler`（struct 无法 implements 接口）。 */
export class OverlayKeyBinding implements OverlayKeyHandler {
  private fn: (keyCode: number, event: KeyEvent) => boolean;

  constructor(fn: (keyCode: number, event: KeyEvent) => boolean) {
    this.fn = fn;
  }

  onOverlayKey(keyCode: number, event: KeyEvent): boolean {
    return this.fn(keyCode, event);
  }
}

export class OverlayKeyRouter {
  private static instance: OverlayKeyRouter | undefined;

  static getInstance(): OverlayKeyRouter {
    if (!OverlayKeyRouter.instance) {
      OverlayKeyRouter.instance = new OverlayKeyRouter();
    }
    return OverlayKeyRouter.instance;
  }

  /** id → 按键处理者（注册即存在，与开合态解耦） */
  private handlers: Map<string, OverlayKeyHandler> = new Map<string, OverlayKeyHandler>();
  /** id → 是否打开（**路由的总开关**：全 false 时 `handle()` 恒 false） */
  private openStates: Map<string, boolean> = new Map<string, boolean>();
  /**
   * id → 该浮层的输入框是否处于 IME 组词/合成态。
   * 由浮层在自己的 `TextInput.onChange(value, previewText)` 里上报（见类头 §IME 守卫）。
   */
  private composing: Map<string, boolean> = new Map<string, boolean>();
  /**
   * 上一次已被消费的按键码；-1 表示当前没有「已消费待复位」的按键。
   *
   * 去重语义**沿用** CommandPalette/SearchPanel 既有的 `lastHandledKeyCode`：
   *   · 一次按压只被消费一次（同一个物理按键可能经 preIme / onKeyEvent / 宿主兜底
   *     多个落点各到达一次）；
   *   · 收到**不同**按键码即复位 ⇒ 换键后立刻恢复。
   * 与迁移前的差别有两点，都是 W11 在设备上实测后有意为之：
   *   ① 标记由「每个浮层各一份」收敛为「路由器一份」。浮层之间**互斥**
   *      （AppState.setCommandPaletteOpen/setSearchPanelOpen 保证，AppState.ets:583-603），
   *      故合并不会造成跨浮层串扰；且关闭任何浮层时都会复位（见 setOverlayOpen/unregisterOverlay），
   *      不会出现「上一个浮层留下的标记吃掉新浮层的第一次按键」。
   *   ② **新增「同键 Up 复位」**：把「一次按压」的边界显式落在 KeyType.Up 上。
   *      ⚠️ 迁移前的实现在这里是**有缺陷**的（W11 设备实测，非推测）：
   *      平板（MatePad Pro 13，2880×1920）上装本 HAP，点 Ribbon 放大镜开 SearchPanel 后
   *        注入 ↓(2013) → 高亮 1→2 ✓
   *        再次注入 ↓(2013) → 高亮**不动** ✗（标记仍等于 2013）
   *        注入 ↑(2012)   → 高亮 2→1 ✓（换键才复位）
   *      ⇒ 「连按同一个方向键只走一格」。旧注释写的「收到不同按键码即复位，从而不会阻塞
   *      用户连按同一个键」推理有误：不同键才复位，恰恰意味着**连续同键会被阻塞**。
   *      修法不是换判据（`event.timestamp` 在本机 SDK 被判不可用，见下），而是把标记的
   *      生命周期收紧到一次按压：Down 消费 → 同键 Up 复位。语义仍是「一次按压只消费一次」，
   *      但连按恢复为「按几次走几格」。
   */
  private lastHandledKeyCode: number = -1;

  // ─── 注册 / 注销 ───

  /**
   * 登记一个浮层（幂等：重复登记只替换处理者，不动开合态）。
   * 不改变开合态 —— 开合是 `setOverlayOpen` 的事，二者分开才能让
   * 「组件挂载」与「浮层可见」不一致的情况（如 SearchPanel 内部 isOpen 已 false
   * 但尚未卸载）有明确表达。
   */
  registerOverlay(id: string, handler: OverlayKeyHandler): void {
    this.handlers.set(id, handler);
    if (!this.openStates.has(id)) {
      this.openStates.set(id, false);
    }
  }

  /**
   * 注销浮层（组件 `aboutToDisappear` 调用）。连同开合态、合成态一并清理，
   * 并复位去重标记 —— 否则「关掉浮层时的最后一个按键码」会跨浮层残留。
   */
  unregisterOverlay(id: string): void {
    this.handlers.delete(id);
    this.openStates.delete(id);
    this.composing.delete(id);
    if (this.topOverlayId() === '') {
      this.lastHandledKeyCode = -1;
    }
  }

  /**
   * 上报浮层开合态。**这是「只在 overlayOpen 态路由」的唯一数据来源**：
   * 全部为 false（或从未登记）时 `topOverlayId()` 返回 ''，`handle()` 恒 false。
   */
  setOverlayOpen(id: string, open: boolean): void {
    this.openStates.set(id, open);
    if (!open) {
      if (this.topOverlayId() === '') {
        this.lastHandledKeyCode = -1;
      }
    }
  }

  /** 浮层是否打开（诊断用）。 */
  isOverlayOpen(id: string): boolean {
    const open = this.openStates.get(id);
    return open === true;
  }

  /**
   * 当前应当接收按键的浮层 id；没有任何浮层打开时返回 ''。
   * 判据 = 已打开集合中优先级最高者（同优先级时先登记的先胜，实际不会发生）。
   */
  topOverlayId(): string {
    const openIds: string[] = [];
    this.openStates.forEach((open: boolean, id: string) => {
      if (open) {
        openIds.push(id);
      }
    });
    let best: string = '';
    let bestPriority: number = -1;
    for (let i = 0; i < openIds.length; i++) {
      const p = this.priorityOf(openIds[i]);
      if (p > bestPriority) {
        bestPriority = p;
        best = openIds[i];
      }
    }
    return best;
  }

  /**
   * 层级表（唯一出处）。数值只用于比大小，不参与任何 UI 布局。
   * 顺序 = ContentArea/BlockList 的 Stack 绘制顺序（后绘制者在上）。
   */
  private priorityOf(id: string): number {
    if (id === OverlayId.SEARCH_PANEL) {
      return 400;
    }
    if (id === OverlayId.COMMAND_PALETTE) {
      return 300;
    }
    if (id === OverlayId.SLASH_MENU) {
      return 200;
    }
    if (id === OverlayId.FIND_IN_PAGE) {
      return 100;
    }
    return 0;
  }

  // ─── IME 守卫 ───

  /**
   * 上报输入法预览文本（合成态）。浮层在自己的 `TextInput.onChange` 里调用：
   *
   * ```ts
   * .onChange((value: string, previewText?: PreviewText) => {
   *   OverlayKeyRouter.getInstance().reportImePreviewText(OverlayId.SEARCH_PANEL, previewText);
   *   ...既有逻辑...
   * })
   * ```
   *
   * 判据：`previewText` 存在且 `value` 非空 ⇒ **输入法正持有未上屏的合成串**
   * （`text_common.d.ts:625-646`；`enablePreviewText` 默认 true ⇒ 无需额外开启）。
   * @param previewText SDK 回调第二实参原文，`undefined` 表示当前无预览文本
   */
  reportImePreviewText(overlayId: string, previewText: PreviewText | undefined): void {
    if (previewText === undefined) {
      this.composing.set(overlayId, false);
      return;
    }
    this.composing.set(overlayId, previewText.value !== '');
  }

  /** 该浮层是否处于 IME 组词/合成态。 */
  isImeComposing(overlayId: string): boolean {
    const flag = this.composing.get(overlayId);
    return flag === true;
  }

  // ─── 路由 ───

  /**
   * 路由一个按键。**所有浮层的按键落点都必须调用本方法**（preIme / onKeyEvent /
   * 宿主兜底三处都调同一个入口，靠去重标记保证一次按压只走一步）。
   *
   * 判定顺序（顺序本身是语义，逐条都有理由）：
   *   ① `type !== Down` ⇒ false。迁移前各浮层同款（只处理按下，Up 放行）。
   *   ② 顶层判定：无浮层打开（top === ''）或调用者不是顶层 ⇒ **false，不拦截**。
   *      「无浮层时不得拦截任何键」与「只有最上层消费」是同一条判据的两面。
   *   ③ **合成态守卫**：顶层浮层正在组词 ⇒ false，并**复位去重标记**后返回。
   *      复位是必要的：否则「组词前那次被消费的 Enter」标记会一直挂着，
   *      上屏之后用户再按 Enter 会被误判为重复而被吃掉。
   *   ④ 去重：同一按键码连续到达只认第一次；未消费则复位（连按语义）。
   *   ⑤ 只路由导航键（↑ ↓ ↵ 小键盘↵ esc）。**其余按键一律放行** ——
   *      拼音字母、Tab、退格、Ctrl 组合等必须原样落到输入框/全局快捷键，
   *      这是「组词回车上屏」之外的第二道保险（即使合成态信号失效，
   *      字母键也永远不会被本类吞掉）。
   *   ⑥ 交付给顶层浮层；**它的返回值决定本方法返回值**（浮层不消费 ⇒ 不拦截）。
   *
   * @param event ArkUI KeyEvent
   * @param callerId 调用者浮层 id（`OverlayId.*`）；宿主兜底入口传 `topOverlayId()`
   * @returns true = 已消费（调用方应 `event.stopPropagation()` 并返回 true）
   */
  handle(event: KeyEvent, callerId: string): boolean {
    // ① 只处理按下；Up 一律放行，但**同键的 Up 要复位去重标记**（理由见 lastHandledKeyCode）
    if (event.type !== KeyType.Down) {
      if (event.type === KeyType.Up && this.lastHandledKeyCode === event.keyCode) {
        this.lastHandledKeyCode = -1;
      }
      return false;
    }

    // ② 顶层判定（含「无浮层 ⇒ 不拦截」）
    const top: string = this.topOverlayId();
    if (top === '' || top !== callerId) {
      return false;
    }

    // ③ 守卫：合成态下这个键属于输入法。
    //    两件事都要做（W11 设备实测：只做前半段会把同一个回车用两次）：
    //      a) 返回 false ⇒ 调用方不 stopPropagation ⇒ 事件继续送进 IME（拼音组词上屏）；
    //      b) **把本次按压记为「已处理」**（而不是复位成 -1）—— 同一次按压在 IME 处理完之后
    //         还会到达 post-IME 的 `onKeyEvent` 落点（`onKeyEvent` 晚于输入法事件，
    //         SDK common.d.ts:18644-18656），而那一刻合成**已经结束**
    //         （onChange 已把 composing 置回 false）⇒ 不标记的话它会被当成一次全新的
    //         Enter 消费掉，表现为「拼音上了屏，但面板同时也跳转了」。
    //    实测对照（MatePad Pro 13 / 命令面板 + 中文输入法 / 注入 n i h a o 再 Enter）：
    //      · 只做 a)：上屏 `nihao` **同时**面板被关掉并新建了名为 `nihao` 的页面 ✗
    //      · 补上 b)：上屏后面板**保持打开**；再按一次 Enter 才走「打开/创建页面」✓
    if (this.isImeComposing(top)) {
      this.lastHandledKeyCode = event.keyCode;
      return false;
    }

    // ④ 去重
    if (this.lastHandledKeyCode === event.keyCode) {
      return false;
    }

    // ⑤ 只路由导航键
    if (!OverlayKeyRouter.isNavKey(event.keyCode)) {
      this.lastHandledKeyCode = -1;
      return false;
    }

    // ⑥ 交付
    const handler = this.handlers.get(top);
    if (handler === undefined) {
      this.lastHandledKeyCode = -1;
      return false;
    }
    const consumed: boolean = handler.onOverlayKey(event.keyCode, event);
    this.lastHandledKeyCode = consumed ? event.keyCode : -1;
    return consumed;
  }

  /**
   * 宿主兜底入口：由 ContentArea 根部的 `onKeyEvent`（post-IME 落点）调用，目标 = 当前顶层浮层。
   *
   * 为什么需要它：浮层自己的拦截点挂在**持焦节点**（输入框）上，若焦点因故
   * 落在浮层其它区域（列表、遮罩）或事件根本没到达输入框，那个落点就不会触发。
   * 兜底入口让「浮层开着但焦点漂移」时按键仍然可达顶层浮层。
   * 与浮层自身落点共用同一份去重标记 ⇒ 一次按压不会走两步。
   * ⚠️ 宿主侧**不挂 `onKeyPreIme`**（见类头 §IME 守卫）：preIme 早于输入法，
   *    会把组词的回车抢走；宿主那一处 `onKeyPreIme` 只保留 Ctrl/Alt 全局快捷键分支。
   */
  handleFromHost(event: KeyEvent): boolean {
    const top: string = this.topOverlayId();
    if (top === '') {
      return false;
    }
    return this.handle(event, top);
  }

  /**
   * 导航键集合 = **↑ ↓ esc**。
   *
   * ⚠️ **回车不在此列，而且是刻意排除的**（W11 设备实测，见类头 §IME 守卫）：
   *   组词/合成态下，`onKeyPreIme` 与 post-IME 的 `onKeyEvent` **都能拿到那个回车**，
   *   一旦在这两处消费掉它，输入法就再也收不到「上屏」指令 —— 实测表现为
   *   候选条「你好」在屏、回车后面板直接打开高亮项、候选被丢弃 ✗。
   *   而应用侧**没有任何信号**能判断「此刻是否正在合成」（同一次实测：组词期间
   *   `onChange` 一次都不触发、`previewText` 从未投递、`KeyEvent` 本身无相关字段）。
   *   ⇒ 结论不是「加判据」，而是**根本不要在按键层面接回车**。
   *
   * 回车的正确入口是 `TextInput.onSubmit`（`text_input.d.ts:1076-1091`：
   * "Triggered when the Enter key on the keyboard is pressed for submission"）——
   * 它由输入法在**处理完自己的合成之后**发出，天然带「先让输入法拒绝」的语义：
   * 组词时回车被输入法用于上屏（不触发 onSubmit），非组词时回车才触发 onSubmit。
   * 因此各浮层的回车动作一律挂在 onSubmit 上（CommandPalette/SearchPanel/SlashMenu/FindInPage）。
   */
  static isNavKey(keyCode: number): boolean {
    if (keyCode === KeyCode.KEYCODE_DPAD_UP) {
      return true;
    }
    if (keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      return true;
    }
    if (keyCode === KeyCode.KEYCODE_ESCAPE) {
      return true;
    }
    return false;
  }

  // ─── 诊断 ───

  /**
   * 一行式状态摘要（供 hilog 探针/自动化判据使用，不参与任何 UI）。
   * 例：`top=searchPanel open=[searchPanel:true] composing=[] last=-1`
   */
  describeState(): string {
    const openParts: string[] = [];
    this.openStates.forEach((open: boolean, id: string) => {
      if (open) {
        openParts.push(id + ':true');
      }
    });
    const composingParts: string[] = [];
    this.composing.forEach((composing: boolean, id: string) => {
      if (composing) {
        composingParts.push(id);
      }
    });
    return 'top=' + this.topOverlayId()
      + ' open=[' + openParts.join(',') + ']'
      + ' composing=[' + composingParts.join(',') + ']'
      + ' last=' + this.lastHandledKeyCode.toString();
  }

  /** 清空全部状态（仅测试/热重载复位用；正常运行路径不调用）。 */
  reset(): void {
    this.handlers.clear();
    this.openStates.clear();
    this.composing.clear();
    this.lastHandledKeyCode = -1;
  }
}
