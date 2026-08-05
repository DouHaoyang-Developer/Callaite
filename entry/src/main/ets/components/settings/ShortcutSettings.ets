import { ShortcutService, ShortcutDef } from '../../services/ShortcutService';
import { TablerIcon } from '../common/Icons';

/**
 * ShortcutItem — 快捷键展示项（UI 层数据结构）。
 */
interface ShortcutItem {
  id: string;
  label: string;
  category: string;
  defaultKeys: string;
  currentKeys: string;
  description: string;
}

/**
 * ShortcutOverride — 用户自定义快捷键覆盖（持久化结构）。
 */
interface ShortcutOverride {
  id: string;
  keys: string;
}

/**
 * ParsedKeys — 解析后的快捷键组合。
 */
interface ParsedKeys {
  key: string;
  ctrl: boolean;
  shift: boolean;
  alt: boolean;
}

const STORAGE_KEY_OVERRIDES = 'callaite_shortcutOverrides';

/**
 * ShortcutSettings — 快捷键自定义设置页。
 *
 * 功能：
 *  - 显示所有快捷键列表（按分类分组）
 *  - 搜索过滤
 *  - 自定义绑定（按键监听模式）
 *  - 冲突检测（红色警告）
 *  - 恢复默认
 *  - 持久化到 AppStorage 'callaite_shortcutOverrides'
 */
@Component
export struct ShortcutSettings {
  onBack: () => void = () => {};

  @State searchQuery: string = '';
  @State items: ShortcutItem[] = [];
  @State listeningId: string = '';
  @State conflictId: string = '';
  @State conflictMessage: string = '';

  private categories: string[] = ['编辑', '导航', '视图', '其他'];
  private defaultsMap: Map<string, string> = new Map<string, string>();

  aboutToAppear(): void {
    this.loadShortcuts();
  }

  // ─── 数据加载 ───

  private loadShortcuts(): void {
    const defs = ShortcutService.getInstance().getAllShortcuts();
    const overrides = this.loadOverrides();

    this.defaultsMap.clear();
    for (let i = 0; i < defs.length; i++) {
      const dk = this.formatKeys(defs[i].key, defs[i].ctrl, defs[i].shift, defs[i].alt);
      this.defaultsMap.set(defs[i].id, dk);
    }

    const merged: ShortcutItem[] = [];
    for (let i = 0; i < defs.length; i++) {
      const def = defs[i];
      const defaultKeys = this.defaultsMap.get(def.id) ?? '';
      const override = overrides.get(def.id);
      const currentKeys = override !== undefined ? override : defaultKeys;
      const item: ShortcutItem = {
        id: def.id,
        label: def.description,
        category: this.getCategory(def.id),
        defaultKeys: defaultKeys,
        currentKeys: currentKeys,
        description: def.description
      };
      merged.push(item);
    }
    this.items = merged;
  }

  private loadOverrides(): Map<string, string> {
    const result = new Map<string, string>();
    const raw = AppStorage.get<string>(STORAGE_KEY_OVERRIDES);
    if (!raw) return result;
    try {
      const arr = JSON.parse(raw) as ShortcutOverride[];
      if (arr) {
        for (let i = 0; i < arr.length; i++) {
          result.set(arr[i].id, arr[i].keys);
        }
      }
    } catch (e) {
      // ignore parse errors
    }
    return result;
  }

  private saveOverrides(): void {
    const arr: ShortcutOverride[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].currentKeys !== this.items[i].defaultKeys) {
        const o: ShortcutOverride = { id: this.items[i].id, keys: this.items[i].currentKeys };
        arr.push(o);
      }
    }
    AppStorage.setOrCreate(STORAGE_KEY_OVERRIDES, JSON.stringify(arr));
  }

  // ─── 分类 / 过滤 ───

  private getCategory(id: string): string {
    if (id === 'app.search') return '导航';
    if (id === 'app.save' || id === 'editor.escape') return '其他';
    if (id.startsWith('editor.') || id.startsWith('format.')) return '编辑';
    return '其他';
  }

  private getItemsByCategory(category: string): ShortcutItem[] {
    const result: ShortcutItem[] = [];
    const q = this.searchQuery.toLowerCase();
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].category !== category) continue;
      if (q !== '') {
        const labelMatch = this.items[i].label.toLowerCase().includes(q);
        const keysMatch = this.items[i].currentKeys.toLowerCase().includes(q);
        if (!labelMatch && !keysMatch) continue;
      }
      result.push(this.items[i]);
    }
    return result;
  }

  // ─── 快捷键格式化 / 解析 ───

  private formatKeys(key: string, ctrl: boolean, shift: boolean, alt: boolean): string {
    let label = '';
    if (ctrl) label = label + 'Ctrl+';
    if (shift) label = label + 'Shift+';
    if (alt) label = label + 'Alt+';
    label = label + key;
    return label;
  }

  private parseKeys(keysStr: string): ParsedKeys {
    const parts: string[] = keysStr.split('+');
    let key = '';
    let ctrl = false;
    let shift = false;
    let alt = false;
    for (let i = 0; i < parts.length; i++) {
      const p = parts[i];
      if (p === 'Ctrl') {
        ctrl = true;
      } else if (p === 'Shift') {
        shift = true;
      } else if (p === 'Alt') {
        alt = true;
      } else {
        key = p;
      }
    }
    const result: ParsedKeys = { key: key, ctrl: ctrl, shift: shift, alt: alt };
    return result;
  }

  private keyCodeToName(code: number): string {
    if (code === 2050) return 'Enter';
    if (code === 2049) return 'Tab';
    if (code === 2057) return 'Backspace';
    if (code === 2070) return 'Esc';
    if (code === 2084) return 'Up';
    if (code === 2085) return 'Down';
    if (code === 2086) return 'Left';
    if (code === 2087) return 'Right';
    const letters: string[] = ['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'];
    if (code >= 2031 && code <= 2056) {
      return letters[code - 2031];
    }
    const digits: string[] = ['0','1','2','3','4','5','6','7','8','9'];
    if (code >= 2073 && code <= 2082) {
      return digits[code - 2073];
    }
    return '';
  }

  // ─── 冲突检测 ───

  private findConflict(keysStr: string, excludeId: string): string {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id !== excludeId && this.items[i].currentKeys === keysStr) {
        return this.items[i].id;
      }
    }
    return '';
  }

  private getLabelById(id: string): string {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) return this.items[i].label;
    }
    return '';
  }

  // ─── 绑定操作 ───

  private applyBinding(id: string, keysStr: string): void {
    const newList: ShortcutItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === id) {
        newList.push({
          id: this.items[i].id,
          label: this.items[i].label,
          category: this.items[i].category,
          defaultKeys: this.items[i].defaultKeys,
          currentKeys: keysStr,
          description: this.items[i].description
        });
      } else {
        newList.push(this.items[i]);
      }
    }
    this.items = newList;
    const parsed = this.parseKeys(keysStr);
    ShortcutService.getInstance().rebind(id, parsed.key, parsed.ctrl, parsed.shift, parsed.alt);
    this.saveOverrides();
  }

  private restoreDefaults(): void {
    const newList: ShortcutItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      const defaultKeys = this.defaultsMap.get(item.id) ?? item.defaultKeys;
      const parsed = this.parseKeys(defaultKeys);
      ShortcutService.getInstance().rebind(item.id, parsed.key, parsed.ctrl, parsed.shift, parsed.alt);
      newList.push({
        id: item.id,
        label: item.label,
        category: item.category,
        defaultKeys: item.defaultKeys,
        currentKeys: defaultKeys,
        description: item.description
      });
    }
    this.items = newList;
    AppStorage.setOrCreate(STORAGE_KEY_OVERRIDES, JSON.stringify([]));
    this.conflictId = '';
    this.conflictMessage = '';
    this.listeningId = '';
  }

  // ─── 按键监听 ───

  private startListening(id: string): void {
    this.listeningId = id;
    this.conflictId = '';
    this.conflictMessage = '';
  }

  private handleKey(event: KeyEvent): void {
    if (this.listeningId === '') return;
    if (event.type !== KeyType.Down) return;

    // Esc 取消监听
    if (event.keyCode === 2070) {
      this.listeningId = '';
      this.conflictId = '';
      this.conflictMessage = '';
      return;
    }

    const keyName = this.keyCodeToName(event.keyCode);
    if (keyName === '') return;

    // KeyEvent 无 ctrlKey/shiftKey/altKey 属性，使用 getModifierKeyState 检测修饰键（API 12+）
    // 该方法在接口中为可选成员，运行时必然存在，用 ! 非空断言
    const keysStr = this.formatKeys(keyName,
      event.getModifierKeyState!(['ctrl']),
      event.getModifierKeyState!(['shift']),
      event.getModifierKeyState!(['alt']));

    // 冲突检测
    const conflictWith = this.findConflict(keysStr, this.listeningId);
    if (conflictWith !== '') {
      this.conflictId = this.listeningId;
      const otherLabel = this.getLabelById(conflictWith);
      this.conflictMessage = '快捷键「' + keysStr + '」已被「' + otherLabel + '」占用';
      return;
    }

    this.applyBinding(this.listeningId, keysStr);
    this.listeningId = '';
    this.conflictId = '';
    this.conflictMessage = '';
  }

  // ─── UI ───

  build() {
    Column({ space: 0 }) {
      // 标题栏
      Row({ space: 12 }) {
        Row() {
          TablerIcon('arrow-left', 18, $r('app.color.text'))
        }
        .width(36).height(36)
        .onClick(() => {
          this.onBack();
        })

        Text('快捷键设置')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 24, bottom: 12, left: 24, right: 24 })

      // 搜索框
      TextInput({ text: this.searchQuery, placeholder: '搜索快捷键...' })
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .margin({ left: 24, right: 24, bottom: 8 })
        .fontSize(14)
        .fontColor($r('app.color.text'))
        .backgroundColor($r('app.color.surface1'))
        .borderRadius(8)
        .onChange((value: string) => {
          this.searchQuery = value;
        })

      // 冲突警告
      if (this.conflictMessage !== '') {
        Row({ space: 8 }) {
          TablerIcon('alert-triangle', 16, $r('app.color.danger'))
          Text(this.conflictMessage)
            .fontSize(13)
            .fontColor($r('app.color.danger'))
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 4, bottom: 4 })
      }

      // 可滚动列表
      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.categories, (cat: string) => {
            Column({ space: 4 }) {
              // 分类标题
              Text(cat)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.muted_text'))
                .padding({ top: 8, bottom: 4 })

              // 快捷键项
              ForEach(this.getItemsByCategory(cat), (item: ShortcutItem) => {
                this.ShortcutRow(item)
              }, (item: ShortcutItem) => item.id)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (cat: string) => cat)

          Blank().height(16)
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .focusable(true)
      .focusOnTouch(true)
      .onKeyEvent((event: KeyEvent) => {
        this.handleKey(event);
      })

      // 底部操作栏
      Row({ space: 12 }) {
        Text('共 ' + this.items.length + ' 个快捷键')
          .fontSize(13)
          .fontColor($r('app.color.muted_text'))
          .layoutWeight(1)
        Text('恢复默认')
          .fontSize(13)
          .fontColor($r('app.color.danger'))
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.border') })
          .onClick(() => {
            this.restoreDefaults();
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .focusable(true)
    .focusOnTouch(true)
    .onKeyEvent((event: KeyEvent) => {
      this.handleKey(event);
    })
  }

  @Builder
  ShortcutRow(item: ShortcutItem) {
    Column({ space: 4 }) {
      Row({ space: 12 }) {
        // 标签 + 描述
        Column({ space: 2 }) {
          Text(item.label)
            .fontSize(14)
            .fontColor($r('app.color.text'))
          Text(item.description)
            .fontSize(11)
            .fontColor($r('app.color.muted_text'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 当前快捷键徽章
        Text(item.currentKeys)
          .fontSize(12)
          .fontColor($r('app.color.text'))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(6)
          .backgroundColor($r('app.color.surface2'))

        // 修改 / 监听按钮
        Row() {
          Text(this.listeningId === item.id ? '按下快捷键...' : '修改')
            .fontSize(12)
            .fontColor(this.listeningId === item.id ? $r('app.color.primary') :
                       (this.conflictId === item.id ? $r('app.color.danger') : $r('app.color.primary')))
        }
        .focusable(true)
        .focusOnTouch(true)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .onClick(() => {
          if (this.listeningId !== item.id) {
            this.startListening(item.id);
          }
        })
        .onKeyEvent((event: KeyEvent) => {
          this.handleKey(event);
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(8)
      .backgroundColor($r('app.color.surface0'))

      // 监听提示
      if (this.listeningId === item.id) {
        Text('请按下快捷键组合（按 Esc 取消）')
          .fontSize(11)
          .fontColor($r('app.color.primary'))
          .padding({ left: 12, bottom: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
