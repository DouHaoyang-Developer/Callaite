import { EditorService } from './EditorService';
import { WorkspaceService } from './WorkspaceService';
import { JournalService } from './JournalService';
import { AppState } from '../state/AppState';
import { OverlayKeyRouter } from '../utils/OverlayKeyRouter';
import { KeyCode } from '@kit.InputKit';

/**
 * ShortcutDef — 快捷键定义。
 *
 * 描述一个键盘快捷键的完整信息：按键组合、描述、以及触发时执行的动作。
 * 用于 ShortcutService 集中管理所有键盘快捷键映射。
 */
export interface ShortcutDef {
  /** 唯一标识符（如 'editor.create-below'） */
  id: string;
  /** 主键名称（如 'Enter', 'Tab', 'B'） */
  key: string;
  /** 是否需要 Ctrl/Cmd 修饰键 */
  ctrl: boolean;
  /** 是否需要 Shift 修饰键 */
  shift: boolean;
  /** 是否需要 Alt 修饰键 */
  alt: boolean;
  /** 描述文本（用于设置页展示） */
  description: string;
  /** 触发时执行的动作 */
  action: () => void;
  /**
   * 等价键（U2.3 快捷键重排）：与 `key` **共用同一组修饰键与同一个动作** 的其它键名。
   *
   * 为什么用「一个动作 + 多个等价键」而不是注册多条同 id 的 ShortcutDef：
   *   `getAllShortcuts()` 按 id 去重（设置页以 id 为键／`rebind(id, …)` 也按 id 定位），
   *   多条同 id 会让设置页只显示最后一条、且改键时只改一条、其余成为幽灵绑定。
   *   等价键在本字段里表达，注册表 / 注销 / 改键 / 设置页四条路径自然都对。
   *
   * 依据（计划 §U2.3 目标键位表）：
   *   · Ctrl+K = Ctrl+P = Ctrl+O ⇒ 同一个「快速切换」（VS Code 与 Obsidian 的双惯例位）
   */
  aliases?: string[];
}

/**
 * 按键名称 → HarmonyOS keyCode 映射表（真实值，见 @ohos.multimodalInput.keyCode.d.ts）。
 *
 * ⚠️ 键码**不是**「Tab/Enter/Backspace/Esc 连号」的猜法，必须逐个对 SDK 枚举核对
 *    （W12 逐个核对结论，括号内是 `@ohos.multimodalInput.keyCode.d.ts` 的行号）：
 *      数字 0-9   = 2000-2009 ✓（KEYCODE_0..KEYCODE_9，d.ts:586-640）
 *      DPAD U/D/L/R = 2012/2013/2014/2015 ✓（同文件 :667-691）
 *      字母 A-Z   = 2017-2042 ✓（KEYCODE_A=2017 … KEYCODE_Z=2042，:694-767；中间无洞）
 *      Tab        = 2049 ✓（KEYCODE_TAB，:793）
 *      Enter      = 2054 ✓（KEYCODE_ENTER，:818；小键盘回车另为 KEYCODE_NUMPAD_ENTER=2119）
 *      Backspace  = 2055 ✓（SDK 里叫 KEYCODE_DEL，:826 —— 名字像 Delete，实为退格）
 *      Esc        = **2070** ✓（KEYCODE_ESCAPE，:854）
 *
 * 本表在 W12 之前把 Esc 写成 2082，而 2082 是 **KEYCODE_MOVE_END**（移动光标到行尾，:888）
 * ⇒ 全局 `editor.escape` 实际绑在 End 键上、真 Esc 永不触发（本次修正）。
 */
const KEY_CODE_MAP: Map<string, number> = new Map<string, number>();

// 特殊键
KEY_CODE_MAP.set('Enter', 2054);
KEY_CODE_MAP.set('Tab', 2049);
// Backspace = KEYCODE_DEL(2055)（SDK 命名如此；KEYCODE_FORWARD_DEL=2071 才是「向后删除」）
KEY_CODE_MAP.set('Backspace', 2055);
// Esc = KEYCODE_ESCAPE(2070)。⚠️ 曾误写 2082 = KEYCODE_MOVE_END（W12 修正）
KEY_CODE_MAP.set('Esc', 2070);

// 方向键
KEY_CODE_MAP.set('Up', 2012);
KEY_CODE_MAP.set('Down', 2013);
KEY_CODE_MAP.set('Left', 2014);
KEY_CODE_MAP.set('Right', 2015);

// 字母键 A-Z（2017-2042）
KEY_CODE_MAP.set('A', 2017);
KEY_CODE_MAP.set('B', 2018);
KEY_CODE_MAP.set('C', 2019);
KEY_CODE_MAP.set('D', 2020);
KEY_CODE_MAP.set('E', 2021);
KEY_CODE_MAP.set('F', 2022);
KEY_CODE_MAP.set('G', 2023);
KEY_CODE_MAP.set('H', 2024);
KEY_CODE_MAP.set('I', 2025);
KEY_CODE_MAP.set('J', 2026);
KEY_CODE_MAP.set('K', 2027);
KEY_CODE_MAP.set('L', 2028);
KEY_CODE_MAP.set('M', 2029);
KEY_CODE_MAP.set('N', 2030);
KEY_CODE_MAP.set('O', 2031);
KEY_CODE_MAP.set('P', 2032);
KEY_CODE_MAP.set('Q', 2033);
KEY_CODE_MAP.set('R', 2034);
KEY_CODE_MAP.set('S', 2035);
KEY_CODE_MAP.set('T', 2036);
KEY_CODE_MAP.set('U', 2037);
KEY_CODE_MAP.set('V', 2038);
KEY_CODE_MAP.set('W', 2039);
KEY_CODE_MAP.set('X', 2040);
KEY_CODE_MAP.set('Y', 2041);
KEY_CODE_MAP.set('Z', 2042);

// 数字键 0-9（2000-2009）
KEY_CODE_MAP.set('0', 2000);
KEY_CODE_MAP.set('1', 2001);
KEY_CODE_MAP.set('2', 2002);
KEY_CODE_MAP.set('3', 2003);
KEY_CODE_MAP.set('4', 2004);
KEY_CODE_MAP.set('5', 2005);
KEY_CODE_MAP.set('6', 2006);
KEY_CODE_MAP.set('7', 2007);
KEY_CODE_MAP.set('8', 2008);
KEY_CODE_MAP.set('9', 2009);

/**
 * ShortcutService — 快捷键服务（单例）。
 *
 * 集中管理所有键盘快捷键映射，支持注册、注销、重新绑定和处理按键事件。
 * 在组件的 onKeyEvent 回调中调用 handleKeyEvent 即可将按键路由到对应动作。
 *
 * 使用方式：
 *   const consumed = ShortcutService.getInstance().handleKeyEvent(event);
 *   if (consumed) return;
 *
 * 默认快捷键列表（U2.3 快捷键重排后的键位表）：
 *   编辑器：Enter / Shift+Enter / Tab / Shift+Tab / Backspace / Alt+↑ / Alt+↓
 *   历史：Ctrl+Z / Ctrl+Shift+Z
 *   标记：Ctrl+M（循环任务标记）
 *   文件：Ctrl+K / Ctrl+P / Ctrl+O（快速切换，三键等价）/ Ctrl+F（全局搜索）/ Ctrl+S
 *   格式：Ctrl+B / Ctrl+I
 *   退出：Esc（退出编辑 / 清除选择）
 *
 * ⚠️ 循环优先级（原 Ctrl+P）已按 U2.3 移入 SlashMenu 的块级命令，不在此表内。
 */
export class ShortcutService {
  private static instance: ShortcutService | undefined;

  /** 快捷键映射表，key 为 makeKey 生成的组合字符串 */
  private shortcuts: Map<string, ShortcutDef> = new Map<string, ShortcutDef>();

  /** 全局启用/禁用开关 */
  private enabled: boolean = true;

  private constructor() {
    this.registerDefaults();
  }

  static getInstance(): ShortcutService {
    if (!ShortcutService.instance) {
      ShortcutService.instance = new ShortcutService();
    }
    return ShortcutService.instance;
  }

  // ─── 注册 / 注销 ───

  /**
   * 注册一个快捷键。如果 key+modifier 组合已存在，将覆盖原有定义。
   * `def.aliases` 里的等价键**同时注册**到同一份定义（同一动作、同一修饰键组合）。
   */
  register(def: ShortcutDef): void {
    const compositeKey = this.makeKey(def.key, def.ctrl, def.shift, def.alt);
    this.shortcuts.set(compositeKey, def);
    const aliases = def.aliases;
    if (aliases !== undefined) {
      for (let i = 0; i < aliases.length; i++) {
        this.shortcuts.set(this.makeKey(aliases[i], def.ctrl, def.shift, def.alt), def);
      }
    }
  }

  /**
   * 按 id 注销快捷键。
   */
  unregister(id: string): void {
    const keysToRemove: string[] = [];
    this.shortcuts.forEach((def: ShortcutDef, k: string) => {
      if (def.id === id) {
        keysToRemove.push(k);
      }
    });
    for (let i = 0; i < keysToRemove.length; i++) {
      this.shortcuts.delete(keysToRemove[i]);
    }
  }

  // ─── 按键事件处理 ───

  /**
   * 处理按键事件。如果匹配到已注册的快捷键，执行对应动作并返回 true。
   * 仅处理 KeyType.Down 事件。
   *
   * ⚠️ **浮层守卫**（U2.3 新增，设备实测驱动）：任何浮层打开时，
   * 回车 / Tab **一律不进全局快捷键表**（理由见 isOverlayBlockedKey）。
   *
   * @param event ArkUI KeyEvent
   * @returns 是否消费了该事件（true = 已处理，调用方应停止后续处理）
   */
  handleKeyEvent(event: KeyEvent): boolean {
    if (!this.enabled) {
      return false;
    }
    if (event.type !== KeyType.Down) {
      return false;
    }
    if (ShortcutService.isOverlayBlockedKey(event.keyCode)) {
      return false;
    }

    // 将 Map values 转为数组以支持提前 break
    const defs: ShortcutDef[] = [];
    this.shortcuts.forEach((def: ShortcutDef, k: string) => {
      defs.push(def);
    });

    for (let i = 0; i < defs.length; i++) {
      if (this.matchShortcut(defs[i], event)) {
        defs[i].action();
        return true;
      }
    }
    return false;
  }

  /**
   * 浮层打开时**必须让位**的键。
   *
   * ─── 为什么需要（W12 设备实测的真缺陷，非推测）───
   * 缺陷：Slash 菜单打开、高亮停在「切换优先级」时注入回车（2054），
   * 菜单**没有执行命令**，而是被本服务的 `editor.create-below` 接走，
   * 在**浮层下面那一行**上插入了新块。
   * 实测证据：`__S1_long.md` 由 4661 字节（首行 `- 测试块 2`）变成 4664 字节
   * （首行变成 `- `、原内容被下移一行），而菜单里的优先级命令一次都没跑。
   * ⇒ 根因不是浮层，而是**全局快捷键没有「浮层优先」的判据**：
   *   `ContentArea` 的 `onKeyEvent`（post-IME）无条件把键转给本服务，
   *   而回车不在 `OverlayKeyRouter.isNavKey` 里（W11 刻意排除）⇒
   *   没有任何一层拦得住它。
   *
   * 因此判据放在**服务这一层**（而不是某个调用点）：本仓有多处落点会转发按键
   * （`ContentArea` 的 `onKeyEvent` 与 `onKeyPreIme`），只堵一处会留下同一缺陷的副本。
   *
   * ─── 为什么只挡这几个键 ───
   *   · 回车 / 小键盘回车：浮层里回车的归属是输入法（各浮层的动作挂在 `onSubmit` 上，
   *     见 `OverlayKeyRouter` 类头 §IME 守卫）。真实键盘上这个回车被输入法先拿到，
   *     注入键不过输入法 ⇒ 它漏到全局表 —— 挡掉它正是「让注入路径与真实路径同语义」。
   *   · Tab：全局表里是「缩进当前块」，同样是**改浮层下面那块数据**的破坏性动作。
   *   · ↑ ↓ Esc：**不需要列在这里** —— `OverlayKeyRouter.isNavKey` 已把它们限定在浮层内，
   *     浮层消费后调用方会 `stopPropagation`，到不了本服务。
   *   · 其余键（字母/退格/Ctrl 组合）一律放行：它们要么归浮层的输入框，要么是
   *     与浮层无关的全局动作（Ctrl+S 保存等），挡掉反而制造新缺陷。
   */
  private static isOverlayBlockedKey(keyCode: number): boolean {
    if (OverlayKeyRouter.getInstance().topOverlayId() === '') {
      return false;
    }
    if (keyCode === KeyCode.KEYCODE_ENTER || keyCode === KeyCode.KEYCODE_NUMPAD_ENTER) {
      return true;
    }
    if (keyCode === KeyCode.KEYCODE_TAB) {
      return true;
    }
    return false;
  }

  // ─── 启用 / 禁用 ───

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  // ─── 查询 / 重新绑定 ───

  /**
   * 获取所有已注册的快捷键列表（用于设置页展示）。
   */
  getAllShortcuts(): ShortcutDef[] {
    const result: ShortcutDef[] = [];
    this.shortcuts.forEach((def: ShortcutDef, k: string) => {
      result.push(def);
    });
    return result;
  }

  /**
   * 重新绑定快捷键。保留原动作和描述，仅替换按键组合。
   *
   * ⚠️ 等价键（`aliases`）在改键时**一并作废**：用户既已显式指定新键，
   *    旧等价键若继续生效就成了「改不掉的幽灵绑定」。
   * @param id 要重新绑定的快捷键 ID
   * @param newKey 新的主键名称
   * @param ctrl 是否需要 Ctrl
   * @param shift 是否需要 Shift
   * @param alt 是否需要 Alt
   */
  rebind(id: string, newKey: string, ctrl: boolean, shift: boolean, alt: boolean): void {
    let foundDef: ShortcutDef | undefined;

    // 先收集该 id 的**全部**绑定（主键 + 等价键指向同一个 def 对象，故可能命中多条）
    const oldCompositeKeys: string[] = [];
    this.shortcuts.forEach((def: ShortcutDef, k: string) => {
      if (def.id === id) {
        foundDef = def;
        oldCompositeKeys.push(k);
      }
    });

    if (!foundDef) {
      return;
    }

    // 移除全部旧绑定
    for (let i = 0; i < oldCompositeKeys.length; i++) {
      this.shortcuts.delete(oldCompositeKeys[i]);
    }

    // 创建新绑定，保留原动作和描述
    const newDef: ShortcutDef = {
      id: id,
      key: newKey,
      ctrl: ctrl,
      shift: shift,
      alt: alt,
      description: foundDef.description,
      action: foundDef.action
    };
    this.register(newDef);
  }

  // ─── 默认快捷键注册 ───

  /**
   * 注册所有默认快捷键。在构造函数中调用。
   */
  private registerDefaults(): void {
    const self = this;

    // ─── 编辑器操作 ───

    // Enter — 创建兄弟 Block
    self.register({
      id: 'editor.create-below',
      key: 'Enter',
      ctrl: false,
      shift: false,
      alt: false,
      description: '创建兄弟 Block',
      action: () => {
        const editor = EditorService.getInstance();
        editor.createBlockBelow(self.getCurrentPageId());
      }
    });

    // Shift+Enter — 创建子 Block
    self.register({
      id: 'editor.create-child',
      key: 'Enter',
      ctrl: false,
      shift: true,
      alt: false,
      description: '创建子 Block',
      action: () => {
        const editor = EditorService.getInstance();
        const focusedUuid = editor.getFocusedBlockUuid();
        if (focusedUuid) {
          editor.createChildBlock(focusedUuid, self.getCurrentPageId());
        }
      }
    });

    // Tab — 缩进
    self.register({
      id: 'editor.indent',
      key: 'Tab',
      ctrl: false,
      shift: false,
      alt: false,
      description: '缩进当前 Block',
      action: () => {
        EditorService.getInstance().indentBlock();
      }
    });

    // Shift+Tab — 反缩进
    self.register({
      id: 'editor.outdent',
      key: 'Tab',
      ctrl: false,
      shift: true,
      alt: false,
      description: '反缩进当前 Block',
      action: () => {
        EditorService.getInstance().outdentBlock();
      }
    });

    // Backspace（空内容时）— 删除空 Block
    self.register({
      id: 'editor.delete-empty',
      key: 'Backspace',
      ctrl: false,
      shift: false,
      alt: false,
      description: '删除空 Block',
      action: () => {
        EditorService.getInstance().deleteEmptyBlock();
      }
    });

    // Alt+Up — 上移 Block
    self.register({
      id: 'editor.move-up',
      key: 'Up',
      ctrl: false,
      shift: false,
      alt: true,
      description: '上移当前 Block',
      action: () => {
        EditorService.getInstance().moveBlockUp();
      }
    });

    // Alt+Down — 下移 Block
    self.register({
      id: 'editor.move-down',
      key: 'Down',
      ctrl: false,
      shift: false,
      alt: true,
      description: '下移当前 Block',
      action: () => {
        EditorService.getInstance().moveBlockDown();
      }
    });

    // ─── 撤销 / 重做 ───

    // Ctrl+Z — 撤销
    self.register({
      id: 'editor.undo',
      key: 'Z',
      ctrl: true,
      shift: false,
      alt: false,
      description: '撤销',
      action: () => {
        EditorService.getInstance().undo();
      }
    });

    // Ctrl+Shift+Z — 重做
    self.register({
      id: 'editor.redo',
      key: 'Z',
      ctrl: true,
      shift: true,
      alt: false,
      description: '重做',
      action: () => {
        EditorService.getInstance().redo();
      }
    });

    // ─── 标记 / 优先级 ───

    // Ctrl+M — 循环 Marker（TODO → DOING → DONE → 无）
    self.register({
      id: 'editor.cycle-marker',
      key: 'M',
      ctrl: true,
      shift: false,
      alt: false,
      description: '循环任务标记',
      action: () => {
        EditorService.getInstance().cycleMarker();
      }
    });

    // ⚠️ U2.3：此处原有 `Ctrl+P = 循环优先级`，**已按计划移除**（键位让给快速切换）。
    // 循环优先级改由**块级上下文**承担：SlashMenu 的「切换优先级」命令
    // （见 components/outliner/SlashMenu.ets 的 selectCyclePriorityCmd 分支）。
    // 计划原文：「块级操作归块上下文；Ctrl+Shift+P 留给未来真命令面板」。
    //
    // 顺带修掉一个此前不可见的缺陷：`EditorService.cyclePriority()` 只认
    // `focusedBlockUuid`，而**从 SlashMenu 执行时菜单本身持有明确的 blockUuid**
    // ⇒ 菜单里的循环不能转调 EditorService（焦点可能不在目标块上），
    // 必须按菜单自己那个 uuid 算下一步（见 SlashMenu.cyclePriorityForBlock）。

    // ─── 文件操作 ───

    // Ctrl+K / Ctrl+P / Ctrl+O — 快速切换（QuickSwitcher，原「命令面板」正名）
    // 语义：过滤**页面名**，回车打开；无命中时按输入内容创建页面。
    //
    // U2.3 键位裁决（PLAN-UI-Alignment §U2.3 目标键位表）：
    //   · Ctrl+K = 原行为（现状保持，仅正名）
    //   · Ctrl+P = 同 Ctrl+K（VS Code 惯例位）—— **cyclePriority 让位**（原绑定在此）
    //   · Ctrl+O = 同 Ctrl+K（Obsidian 惯例位）
    //   三键等价 ⇒ 用 `aliases` 表达，注册表/设置页/改键三条路径都只看到一条动作。
    self.register({
      id: 'app.quick-switcher',
      key: 'K',
      ctrl: true,
      shift: false,
      alt: false,
      aliases: ['P', 'O'],
      description: '快速切换',
      action: () => {
        AppState.setCommandPaletteOpen(true);
      }
    });

    // Ctrl+F — 全局搜索（U1.6：Ctrl+F 打开 SearchPanel）
    // 语义：搜索**页面名 + 块内容**，结果点击/回车跳转，块结果走 BlockAnchorService 定位。
    // 注：快捷键重排是独立一轮的事；本轮先把两根键的归属定死 —— K = 命令面板、F = 搜索面板。
    self.register({
      id: 'app.search',
      key: 'F',
      ctrl: true,
      shift: false,
      alt: false,
      description: '全局搜索（页面 + 内容）',
      action: () => {
        AppState.setSearchPanelOpen(true);
      }
    });

    // Ctrl+S — 保存当前页面
    self.register({
      id: 'app.save',
      key: 'S',
      ctrl: true,
      shift: false,
      alt: false,
      description: '保存当前页面',
      action: () => {
        const ws = WorkspaceService.getInstance();
        const pageId = self.getCurrentPageId();
        if (pageId) {
          ws.savePage(pageId);
        }
      }
    });

    // ─── 文本格式 ───

    // Ctrl+B — 加粗（用 ** 包裹当前 Block 内容）
    self.register({
      id: 'format.bold',
      key: 'B',
      ctrl: true,
      shift: false,
      alt: false,
      description: '加粗',
      action: () => {
        self.wrapContent('**', '**');
      }
    });

    // Ctrl+I — 斜体（用 * 包裹当前 Block 内容）
    self.register({
      id: 'format.italic',
      key: 'I',
      ctrl: true,
      shift: false,
      alt: false,
      description: '斜体',
      action: () => {
        self.wrapContent('*', '*');
      }
    });

    // ─── 退出 ───

    // Esc — 退出编辑 / 清除选择
    self.register({
      id: 'editor.escape',
      key: 'Esc',
      ctrl: false,
      shift: false,
      alt: false,
      description: '退出编辑 / 清除选择',
      action: () => {
        EditorService.getInstance().clearFocus();
      }
    });
  }

  // ─── 内部工具方法 ───

  /**
   * 生成快捷键的组合键字符串，用于 Map 存储。
   * 格式：key|C?|S?|A?（C=Ctrl, S=Shift, A=Alt）
   */
  private makeKey(key: string, ctrl: boolean, shift: boolean, alt: boolean): string {
    let result = key;
    result = result + '|' + (ctrl ? 'C' : '-');
    result = result + '|' + (shift ? 'S' : '-');
    result = result + '|' + (alt ? 'A' : '-');
    return result;
  }

  /**
   * 检查 ShortcutDef 是否与 KeyEvent 匹配。
   * 比较 keyCode 和三个修饰键（ctrl/shift/alt）。
   */
  private matchShortcut(def: ShortcutDef, event: KeyEvent): boolean {
    const expectedCode = this.lookupKeyCode(def.key);
    if (expectedCode === -1) {
      return false;
    }
    if (event.keyCode !== expectedCode) {
      return false;
    }
    // KeyEvent 无 ctrlKey/shiftKey/altKey 属性，使用 getModifierKeyState 检测修饰键（API 12+）
    // 该方法在接口中为可选成员，运行时必然存在，用 ! 非空断言
    if (event.getModifierKeyState!(['ctrl']) !== def.ctrl) {
      return false;
    }
    if (event.getModifierKeyState!(['shift']) !== def.shift) {
      return false;
    }
    if (event.getModifierKeyState!(['alt']) !== def.alt) {
      return false;
    }
    return true;
  }

  /**
   * 按键名称 → keyCode 查找。未找到返回 -1。
   */
  private lookupKeyCode(keyName: string): number {
    const code = KEY_CODE_MAP.get(keyName);
    if (code !== undefined) {
      return code;
    }
    return -1;
  }

  /**
   * 获取当前页面的 UUID。
   * 从 AppStorage 读取当前页面名，Journal 自动解析为今天的日期。
   */
  private getCurrentPageId(): string {
    const ws = WorkspaceService.getInstance();
    const stored = AppStorage.get<string>('callaite_currentPage');
    const pageName = stored ?? 'Journal';

    let resolvedName = pageName;
    if (pageName === 'Journal') {
      resolvedName = JournalService.getTodayDateString();
    }

    const page = ws.getPageByName(resolvedName);
    if (page) {
      return page.uuid;
    }
    return '';
  }

  /**
   * 用前缀和后缀包裹当前焦点 Block 的内容。
   * 用于加粗（**text**）和斜体（*text*）等行内格式。
   * 注意：此方法包裹整个 Block 内容，而非选中文本。
   */
  private wrapContent(prefix: string, suffix: string): void {
    const editor = EditorService.getInstance();
    const ws = WorkspaceService.getInstance();
    const uuid = editor.getFocusedBlockUuid();
    if (!uuid) {
      return;
    }
    const block = ws.getBlock(uuid);
    if (!block) {
      return;
    }
    const newContent = prefix + block.content + suffix;
    editor.updateBlockContent(uuid, newContent);
  }
}
