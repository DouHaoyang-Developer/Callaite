import { PageView } from './PageView';
import { CommandPalette } from '../commandpalette/CommandPalette';
import { ExportDialog } from '../common/ExportDialog';
import { ImportDialog } from '../common/ImportDialog';
import { Toolbar } from '../outliner/Toolbar';
import { ShortcutService } from '../../services/ShortcutService';
import { AppState } from '../../state/AppState';
import { Breakpoints } from '../../state/Breakpoints';

/**
 * ContentArea — 内容区（TabBar 之下、StatusBar 之上）。
 *
 * 桌面：工具栏 + 编辑区；命令面板为 Obsidian 风格顶部居中玻璃卡片。
 * 手机：为悬浮玻璃顶栏/底部胶囊栏预留安全边距。
 */
@Component
export struct ContentArea {
  @StorageLink('callaite_searchPanelOpen') searchPanelOpen: boolean = false;
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  @StorageLink('callaite_exportDialogOpen') exportDialogOpen: boolean = false;
  @StorageLink('callaite_importDialogOpen') importDialogOpen: boolean = false;
  /** 系统栏安全区（沉浸式下由 EntryAbility 发布，单位 vp） */
  @StorageLink('callaite_safeTop') safeTop: number = 0;
  @StorageLink('callaite_safeBottom') safeBottom: number = 0;

  aboutToAppear(): void {
    // 主动夺取焦点，否则 Scroll 未持焦时 onKeyEvent 不触发（快捷键整体失效）
    focusControl.requestFocus('contentAreaScroll');
  }

  /**
   * 顶部预留 = 状态栏安全区 + 悬浮顶栏高度(56) + 间距(8)。
   * 沉浸式后状态栏不再占用布局空间，必须由内容区自行避让，
   * 否则首行内容会被悬浮顶栏与状态栏叠压。
   */
  private mobileTopInset(): number {
    return Breakpoints.isCompact() ? this.safeTop + 64 : 0;
  }

  /**
   * 底部预留 = 导航条安全区 + 胶囊栏高度(56) + 间距(12) + 呼吸间距(8)。
   */
  private mobileBottomInset(): number {
    return Breakpoints.isCompact() ? this.safeBottom + 76 : 0;
  }

  build() {
    Stack() {
      Column() {
        Toolbar()

        Scroll() {
          PageView()
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .align(Alignment.TopStart)
        .focusable(true)
        .defaultFocus(true)
        .id('contentAreaScroll')
        .onKeyEvent((event: KeyEvent) => {
          // 统一路由到 ShortcutService（含 Ctrl+K/Ctrl+Z/Tab/Alt+↑↓ 等全部快捷键）
          if (event.type === KeyType.Down) {
            ShortcutService.getInstance().handleKeyEvent(event);
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.surface0'))
      .padding({ top: this.mobileTopInset(), bottom: this.mobileBottomInset() })

      // ─── 快速切换 / 命令面板：Obsidian 风格居中玻璃卡片 ───
      if (this.searchPanelOpen) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)
            .backgroundColor('rgba(0,0,0,0.35)')
            .onClick(() => {
              AppState.setSearchPanelOpen(false);
            })

          Row() {
            CommandPalette()
          }
          .width('92%')
          .constraintSize({ maxWidth: 560 })
          .height(420)
          .borderRadius(12)
          .clip(true)
          .shadow({ radius: 24, color: 'rgba(0,0,0,0.22)', offsetY: 8 })
          .border({ width: 0.6, color: $r('app.color.glass_border') })

          Column()
            .width('100%')
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              AppState.setSearchPanelOpen(false);
            })
        }
        .width('100%')
        .height('100%')
      }

      if (this.exportDialogOpen) {
        Column() {
          ExportDialog({
            pageName: ContentArea.resolvePageName(this.currentPage),
            onClose: () => { AppState.setExportDialogOpen(false); }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      if (this.importDialogOpen) {
        Column() {
          ImportDialog({
            pageName: ContentArea.resolvePageName(this.currentPage),
            onClose: () => { AppState.setImportDialogOpen(false); }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    // 修饰键组合（Ctrl+K/Ctrl+Z/Alt+↑↓ 等）在 IME/子组件处理前拦截，
    // 保证 WebEditor 持焦时全局快捷键依然可用；无修饰键的按键放行给编辑器。
    .onKeyPreIme((event: KeyEvent) => {
      if (event.type !== KeyType.Down) {
        return false;
      }
      const hasCtrl = event.getModifierKeyState!(['ctrl']);
      const hasAlt = event.getModifierKeyState!(['alt']);
      if (!hasCtrl && !hasAlt) {
        return false;
      }
      return ShortcutService.getInstance().handleKeyEvent(event);
    })
  }

  static resolvePageName(pageName: string): string {
    if (pageName === 'Journal') {
      const now = new Date();
      const y = now.getFullYear().toString();
      const m = (now.getMonth() + 1).toString().padStart(2, '0');
      const d = now.getDate().toString().padStart(2, '0');
      return y + '-' + m + '-' + d;
    }
    return pageName;
  }
}
