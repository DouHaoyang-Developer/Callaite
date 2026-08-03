import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { AppState } from '../../state/AppState';
import { ThemeManager, ThemeMode } from '../common/ThemeManager';
import { I18n, SupportedLanguage } from '../../utils/i18n';

@Component
export struct SettingsPage {
  @State selectedTheme: string = '';
  @State selectedLanguage: string = '';

  aboutToAppear(): void {
    this.selectedTheme = ThemeManager.getThemeMode();
    this.selectedLanguage = I18n.getLanguage();
  }

  build() {
    Column({ space: 24 }) {
      // 标题
      Row({ space: 12 }) {
        Row() {
          TablerIcon('arrow-left', 20, $r('app.color.text'))
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
      .padding({ top: 24, bottom: 12 })

      // 外观
      this.SectionHeader('theme')

      this.ThemeOption('theme_light', ThemeMode.LIGHT)
      this.ThemeOption('theme_dark', ThemeMode.DARK)
      this.ThemeOption('theme_system', ThemeMode.SYSTEM)

      Divider().color($r('app.color.border'))
      Blank().height(12)

      // 语言
      this.SectionHeader('language')

      this.LanguageOption('中文 (zh-CN)', 'zh-CN')
      this.LanguageOption('English (en-US)', 'en-US')

      Divider().color($r('app.color.border'))
      Blank().height(12)

      // 关于
      this.SectionHeader('about')

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

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SectionHeader(labelKey: string) {
    Text(t(labelKey))
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.muted_text'))
      .width('100%')
      .padding({ top: 4, bottom: 4 })
  }

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
