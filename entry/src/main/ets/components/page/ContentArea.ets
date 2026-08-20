import { Header } from '../layout/Header';
import { PageView } from './PageView';
import { CommandPalette } from '../commandpalette/CommandPalette';
import { ExportDialog } from '../common/ExportDialog';
import { ImportDialog } from '../common/ImportDialog';
import { Toolbar } from '../outliner/Toolbar';
import { ShortcutService } from '../../services/ShortcutService';
import { AppState } from '../../state/AppState';

@Component
export struct ContentArea {
  @StorageLink('callaite_searchPanelOpen') searchPanelOpen: boolean = false;
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  @StorageLink('callaite_exportDialogOpen') exportDialogOpen: boolean = false;
  @StorageLink('callaite_importDialogOpen') importDialogOpen: boolean = false;

  build() {
    Stack() {
      Column() {
        Header()

        Toolbar()

        Scroll() {
          PageView()
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .backgroundColor($r('app.color.surface0'))
        .focusable(true)
        .defaultFocus(true)
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

      if (this.searchPanelOpen) {
        Column() {
          CommandPalette()
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.surface0'))
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
