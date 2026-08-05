import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { AppState } from '../../state/AppState';
import { ThemeManager, ThemeMode } from '../common/ThemeManager';
import { I18n, SupportedLanguage } from '../../utils/i18n';
import { ShortcutService, ShortcutDef } from '../../services/ShortcutService';
import { SubscriptionService } from '../../services/SubscriptionService';
import { CloudSyncService } from '../../services/CloudSyncService';
import { ShortcutSettings } from './ShortcutSettings';

/**
 * SettingsPage — 设置页。
 *
 * 分区：
 *  1. 外观：主题模式、字体大小
 *  2. 语言
 *  3. 编辑器：显示 bullet、自动保存间隔、Tab 缩进宽度
 *  4. 快捷键：快捷键列表、自定义
 *  5. 同步：云同步、协同编辑、同步状态
 *  6. 账户：Pro 订阅、升级
 *  7. 数据：导出、导入、清除缓存
 *  8. 关于：版本、开源许可、反馈
 *
 * 设置项变更持久化到 AppStorage。
 */

// AppStorage 键
const KEY_FONT_SIZE = 'callaite_fontSize';
const KEY_SHOW_BULLETS = 'callaite_showBullets';
const KEY_AUTO_SAVE_INTERVAL = 'callaite_autoSaveInterval';
const KEY_TAB_WIDTH = 'callaite_tabWidth';
const KEY_CLOUD_SYNC = 'callaite_cloudSyncEnabled';
const KEY_COLLAB = 'callaite_collabEnabled';

// 字体大小选项（pt）
const FONT_SIZES: number[] = [12, 13, 14, 15, 16];
// 自动保存间隔（毫秒，0 = 禁用）
const AUTO_SAVE_INTERVALS: number[] = [0, 1000, 3000, 5000, 10000];
// Tab 缩进宽度
const TAB_WIDTHS: number[] = [2, 4, 8];

// Select 组件选项
interface SelectOption {
  value: string;
}

@Component
export struct SettingsPage {
  @State selectedTheme: string = '';
  @State selectedLanguage: string = '';
  @State fontSizeIndex: number = 2;
  @State showBullets: boolean = true;
  @State autoSaveIntervalIndex: number = 3;
  @State tabWidthIndex: number = 1;
  @State cloudSyncEnabled: boolean = false;
  @State collabEnabled: boolean = false;
  @State syncStatus: string = '未同步';
  @State isPro: boolean = false;
  @State shortcuts: ShortcutDef[] = [];
  @State showShortcuts: boolean = false;
  @State currentSection: string = 'main';

  aboutToAppear(): void {
    this.selectedTheme = ThemeManager.getThemeMode();
    this.selectedLanguage = I18n.getLanguage();

    // 加载编辑器设置
    const fontSize = AppStorage.get<number>(KEY_FONT_SIZE);
    if (fontSize) {
      this.fontSizeIndex = this.indexOf(FONT_SIZES, fontSize);
    }
    this.showBullets = AppStorage.get<boolean>(KEY_SHOW_BULLETS) ?? true;
    const autoSave = AppStorage.get<number>(KEY_AUTO_SAVE_INTERVAL);
    if (autoSave !== undefined) {
      this.autoSaveIntervalIndex = this.indexOf(AUTO_SAVE_INTERVALS, autoSave);
    }
    const tabWidth = AppStorage.get<number>(KEY_TAB_WIDTH);
    if (tabWidth) {
      this.tabWidthIndex = this.indexOf(TAB_WIDTHS, tabWidth);
    }

    // 加载同步设置
    this.cloudSyncEnabled = AppStorage.get<boolean>(KEY_CLOUD_SYNC) ?? false;
    this.collabEnabled = AppStorage.get<boolean>(KEY_COLLAB) ?? false;
    this.refreshSyncStatus();

    // 加载账户状态
    this.isPro = SubscriptionService.checkPro();
    SubscriptionService.refreshProStatus().then((ok: boolean) => {
      this.isPro = ok;
    });

    // 加载快捷键
    this.shortcuts = ShortcutService.getInstance().getAllShortcuts();
  }

  /**
   * 在数组中查找元素索引，找不到返回 0。
   */
  private indexOf(arr: number[], target: number): number {
    for (let i = 0; i < arr.length; i++) {
      if (arr[i] === target) {
        return i;
      }
    }
    return 0;
  }

  /**
   * 刷新同步状态文本。
   */
  private refreshSyncStatus(): void {
    if (!this.cloudSyncEnabled) {
      this.syncStatus = '未启用';
      return;
    }
    const count = CloudSyncService.countSyncedGraphs();
    if (count > 0) {
      this.syncStatus = '已同步 ' + count + ' 个文件';
    } else {
      this.syncStatus = '已启用，暂无同步文件';
    }
  }

  /**
   * 构建字体大小 Select 选项。
   */
  private buildFontSizeOptions(): SelectOption[] {
    const result: SelectOption[] = [];
    for (let i = 0; i < FONT_SIZES.length; i++) {
      const opt: SelectOption = { value: FONT_SIZES[i].toString() + 'pt' };
      result.push(opt);
    }
    return result;
  }

  /**
   * 构建自动保存间隔 Select 选项。
   */
  private buildAutoSaveOptions(): SelectOption[] {
    const result: SelectOption[] = [];
    for (let i = 0; i < AUTO_SAVE_INTERVALS.length; i++) {
      const v = AUTO_SAVE_INTERVALS[i];
      const label = v === 0 ? '禁用' : (v / 1000).toString() + '秒';
      const opt: SelectOption = { value: label };
      result.push(opt);
    }
    return result;
  }

  /**
   * 构建 Tab 宽度 Select 选项。
   */
  private buildTabWidthOptions(): SelectOption[] {
    const result: SelectOption[] = [];
    for (let i = 0; i < TAB_WIDTHS.length; i++) {
      const opt: SelectOption = { value: TAB_WIDTHS[i].toString() + ' 空格' };
      result.push(opt);
    }
    return result;
  }

  /**
   * 格式化快捷键显示文本。
   */
  private shortcutLabel(def: ShortcutDef): string {
    let label = '';
    if (def.ctrl) {
      label = label + 'Ctrl+';
    }
    if (def.shift) {
      label = label + 'Shift+';
    }
    if (def.alt) {
      label = label + 'Alt+';
    }
    label = label + def.key;
    return label;
  }

  build() {
    if (this.currentSection === 'shortcuts') {
      ShortcutSettings({ onBack: () => {
        this.currentSection = 'main';
      } })
    } else {
    Column({ space: 0 }) {
      // 固定标题栏
      Row({ space: 12 }) {
        Row() {
          TablerIcon('arrow-left', 18, $r('app.color.text'))
        }
        .width(36).height(36)
        .onClick(() => {
          AppState.setCurrentPage('Journal');
        })

        Text(t('settings'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
      }
      .width('100%')
      .padding({ top: 24, bottom: 12, left: 24, right: 24 })

      // 可滚动内容
      Scroll() {
        Column({ space: 16 }) {
          // ─── 外观 ───
          this.SectionHeader('theme', 'palette')
          this.ThemeOption('theme_light', ThemeMode.LIGHT)
          this.ThemeOption('theme_dark', ThemeMode.DARK)
          this.ThemeOption('theme_system', ThemeMode.SYSTEM)
          this.SelectRow('字体大小', this.buildFontSizeOptions(), this.fontSizeIndex, (index: number) => {
            this.fontSizeIndex = index;
            AppStorage.setOrCreate(KEY_FONT_SIZE, FONT_SIZES[index]);
          })

          this.SectionDivider()

          // ─── 语言 ───
          this.SectionHeader('language', 'world')
          this.LanguageOption('中文 (zh-CN)', 'zh-CN')
          this.LanguageOption('English (en-US)', 'en-US')

          this.SectionDivider()

          // ─── 编辑器 ───
          this.SectionHeader('编辑器', 'edit')
          this.ToggleRow('显示 Bullet', this.showBullets, (on: boolean) => {
            this.showBullets = on;
            AppStorage.setOrCreate(KEY_SHOW_BULLETS, on);
          })
          this.SelectRow('自动保存间隔', this.buildAutoSaveOptions(), this.autoSaveIntervalIndex, (index: number) => {
            this.autoSaveIntervalIndex = index;
            AppStorage.setOrCreate(KEY_AUTO_SAVE_INTERVAL, AUTO_SAVE_INTERVALS[index]);
          })
          this.SelectRow('Tab 缩进宽度', this.buildTabWidthOptions(), this.tabWidthIndex, (index: number) => {
            this.tabWidthIndex = index;
            AppStorage.setOrCreate(KEY_TAB_WIDTH, TAB_WIDTHS[index]);
          })

          this.SectionDivider()

          // ─── 快捷键 ───
          this.SectionHeader('快捷键', 'keyboard')
          this.ButtonRow('自定义快捷键', 'keyboard', () => {
            this.currentSection = 'shortcuts';
          })
          Row({ space: 8 }) {
            Text('共 ' + this.shortcuts.length + ' 个快捷键')
              .fontSize(13)
              .fontColor($r('app.color.muted_text'))
              .layoutWeight(1)
            Text(this.showShortcuts ? '收起' : '展开')
              .fontSize(13)
              .fontColor($r('app.color.primary'))
              .onClick(() => {
                this.showShortcuts = !this.showShortcuts;
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })

          if (this.showShortcuts) {
            ForEach(this.shortcuts, (def: ShortcutDef) => {
              Row({ space: 8 }) {
                Text(def.description)
                  .fontSize(13)
                  .fontColor($r('app.color.text'))
                  .layoutWeight(1)
                Text(this.shortcutLabel(def))
                  .fontSize(11)
                  .fontColor($r('app.color.muted_text'))
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
                  .backgroundColor($r('app.color.surface2'))
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            }, (def: ShortcutDef) => def.id)
          }

          this.SectionDivider()

          // ─── 同步 ───
          this.SectionHeader('同步', 'cloud')
          this.ToggleRow('云同步', this.cloudSyncEnabled, (on: boolean) => {
            this.cloudSyncEnabled = on;
            AppStorage.setOrCreate(KEY_CLOUD_SYNC, on);
            this.refreshSyncStatus();
          })
          this.ToggleRow('协同编辑', this.collabEnabled, (on: boolean) => {
            this.collabEnabled = on;
            AppStorage.setOrCreate(KEY_COLLAB, on);
          })
          Row({ space: 8 }) {
            Text('同步状态')
              .fontSize(14)
              .fontColor($r('app.color.text'))
              .layoutWeight(1)
            Text(this.syncStatus)
              .fontSize(12)
              .fontColor($r('app.color.muted_text'))
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })

          this.SectionDivider()

          // ─── 账户 ───
          this.SectionHeader('账户', 'user')
          Row({ space: 8 }) {
            Text('Pro 订阅')
              .fontSize(14)
              .fontColor($r('app.color.text'))
              .layoutWeight(1)
            Text(this.isPro ? '已订阅' : '免费版')
              .fontSize(12)
              .fontColor(this.isPro ? $r('app.color.success') : $r('app.color.muted_text'))
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          if (!this.isPro) {
            this.ButtonRow('升级到 Pro', 'crown', () => {
              SubscriptionService.purchasePro().then((ok: boolean) => {
                this.isPro = ok;
              });
            })
          }

          this.SectionDivider()

          // ─── 数据 ───
          this.SectionHeader('数据', 'database')
          this.ButtonRow('导出数据', 'download', () => {})
          this.ButtonRow('导入数据', 'upload', () => {})
          this.ButtonRow('清除缓存', 'trash', () => {})

          this.SectionDivider()

          // ─── 关于 ───
          this.SectionHeader('about', 'info-circle')
          Row({ space: 12 }) {
            TablerIcon('info-circle', 18, $r('app.color.muted_text'))
            Column({ space: 4 }) {
              Text('Callaite v1.0.0')
                .fontSize(15)
                .fontColor($r('app.color.text'))
              Text('Logseq-style knowledge management for HarmonyOS')
                .fontSize(12)
                .fontColor($r('app.color.muted_text'))
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          this.ButtonRow('开源许可', 'license', () => {})
          this.ButtonRow('反馈', 'message', () => {})

          Blank().height(24)
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    }
  }

  // ─── 通用 Builder ───

  @Builder
  SectionHeader(labelKey: string, icon: string) {
    Row({ space: 8 }) {
      TablerIcon(icon, 16, $r('app.color.primary'))
      Text(t(labelKey))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.muted_text'))
    }
    .width('100%')
    .padding({ top: 8, bottom: 4 })
  }

  @Builder
  SectionDivider() {
    Column() {
      Divider().color($r('app.color.border'))
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  ToggleRow(title: string, isOn: boolean, onChange: (on: boolean) => void) {
    Row({ space: 8 }) {
      Text(title)
        .fontSize(14)
        .fontColor($r('app.color.text'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((on: boolean) => {
          onChange(on);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
  }

  @Builder
  SelectRow(title: string, options: SelectOption[], selectedIndex: number, onSelect: (index: number) => void) {
    Row({ space: 8 }) {
      Text(title)
        .fontSize(14)
        .fontColor($r('app.color.text'))
        .layoutWeight(1)
      Select(options)
        .selected(selectedIndex)
        .value(options.length > selectedIndex ? options[selectedIndex].value : '')
        .onSelect((index: number) => {
          onSelect(index);
        })
        .width(120)
        .height(32)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
  }

  @Builder
  ButtonRow(title: string, icon: string, onClick: () => void) {
    Row({ space: 8 }) {
      TablerIcon(icon, 16, $r('app.color.muted_text'))
      Text(title)
        .fontSize(14)
        .fontColor($r('app.color.text'))
        .layoutWeight(1)
      TablerIcon('chevron-right', 14, $r('app.color.muted_text'))
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .onClick(() => {
      onClick();
    })
  }

  // ─── 外观 / 语言（保留原有） ───

  @Builder
  ThemeOption(labelKey: string, mode: ThemeMode) {
    Row({ space: 12 }) {
      TablerIcon('palette', 18, this.selectedTheme === mode ? $r('app.color.primary') : $r('app.color.muted_text'))
      Text(t(labelKey))
        .fontSize(16)
        .fontColor(this.selectedTheme === mode ? $r('app.color.primary') : $r('app.color.text'))
        .layoutWeight(1)
      if (this.selectedTheme === mode) {
        TablerIcon('check', 18, $r('app.color.primary'))
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .borderRadius(8)
    .backgroundColor(this.selectedTheme === mode ? $r('app.color.surface2') : Color.Transparent)
    .onClick(() => {
      this.selectedTheme = mode;
      ThemeManager.setThemeMode(mode);
      AppStorage.setOrCreate('themeMode', mode);
    })
  }

  @Builder
  LanguageOption(label: string, lang: SupportedLanguage) {
    Row({ space: 12 }) {
      TablerIcon('world', 18, this.selectedLanguage === lang ? $r('app.color.primary') : $r('app.color.muted_text'))
      Text(label)
        .fontSize(16)
        .fontColor(this.selectedLanguage === lang ? $r('app.color.primary') : $r('app.color.text'))
        .layoutWeight(1)
      if (this.selectedLanguage === lang) {
        TablerIcon('check', 18, $r('app.color.primary'))
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .borderRadius(8)
    .backgroundColor(this.selectedLanguage === lang ? $r('app.color.surface2') : Color.Transparent)
    .onClick(() => {
      this.selectedLanguage = lang;
      I18n.setLanguage(lang);
      AppStorage.setOrCreate('language', lang);
    })
  }
}
