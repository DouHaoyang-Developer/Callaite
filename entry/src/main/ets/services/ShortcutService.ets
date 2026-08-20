import { EditorService } from './EditorService';
import { WorkspaceService } from './WorkspaceService';
import { JournalService } from './JournalService';

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
}

/**
 * 按键名称 → HarmonyOS keyCode 映射表（真实值，见 @ohos.multimodalInput.keyCode）。
 *
 * 数字键 0-9：2000-2009
 * 方向键：Up=2012, Down=2013, Left=2014, Right=2015
 * 字母键 A-Z：2017-2042
 * 特殊键：Tab=2049, Enter=2054, Backspace(DEL)=2055, Esc=2082
 */
const KEY_CODE_MAP: Map<string, number> = new Map<string, number>();

// 特殊键
KEY_CODE_MAP.set('Enter', 2054);
KEY_CODE_MAP.set('Tab', 2049);
KEY_CODE_MAP.set('Backspace', 2055);
KEY_CODE_MAP.set('Esc', 2082);

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
 * 默认快捷键列表：
 *   编辑器：Enter / Shift+Enter / Tab / Shift+Tab / Backspace / Alt+↑ / Alt+↓
 *   历史：Ctrl+Z / Ctrl+Shift+Z
 *   标记：Ctrl+M / Ctrl+P
 *   文件：Ctrl+F / Ctrl+S
 *   格式：Ctrl+B / Ctrl+I
 *   退出：Esc
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
   */
  register(def: ShortcutDef): void {
    const compositeKey = this.makeKey(def.key, def.ctrl, def.shift, def.alt);
    this.shortcuts.set(compositeKey, def);
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
   * @param id 要重新绑定的快捷键 ID
   * @param newKey 新的主键名称
   * @param ctrl 是否需要 Ctrl
   * @param shift 是否需要 Shift
   * @param alt 是否需要 Alt
   */
  rebind(id: string, newKey: string, ctrl: boolean, shift: boolean, alt: boolean): void {
    let foundDef: ShortcutDef | undefined;
    let oldCompositeKey: string = '';

    this.shortcuts.forEach((def: ShortcutDef, k: string) => {
      if (def.id === id) {
        foundDef = def;
        oldCompositeKey = k;
      }
    });

    if (!foundDef) {
      return;
    }

    // 移除旧绑定
    this.shortcuts.delete(oldCompositeKey);

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

    // Ctrl+P — 循环优先级（A → B → C → 无）
    self.register({
      id: 'editor.cycle-priority',
      key: 'P',
      ctrl: true,
      shift: false,
      alt: false,
      description: '循环优先级',
      action: () => {
        EditorService.getInstance().cyclePriority();
      }
    });

    // ─── 文件操作 ───

    // Ctrl+K — 全局搜索（Logseq mod+K）
    self.register({
      id: 'app.search-global',
      key: 'K',
      ctrl: true,
      shift: false,
      alt: false,
      description: '全局搜索',
      action: () => {
        AppStorage.setOrCreate('callaite_searchPanelOpen', true);
      }
    });

    // Ctrl+F — 页内搜索
    self.register({
      id: 'app.search',
      key: 'F',
      ctrl: true,
      shift: false,
      alt: false,
      description: '页内搜索',
      action: () => {
        AppStorage.setOrCreate('callaite_searchPanelOpen', true);
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
