import { Header } from '../layout/Header';
import { PageView } from './PageView';
import { CommandPalette } from '../commandpalette/CommandPalette';
import { ExportDialog } from '../common/ExportDialog';
import { ImportDialog } from '../common/ImportDialog';
import { Toolbar } from '../outliner/Toolbar';
import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';
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
        .onKeyEvent((event: KeyEvent) => {
          const editor = EditorService.getInstance();
          const ws = WorkspaceService.getInstance();
          const page = ws.getPageByName(ContentArea.resolvePageName(this.currentPage));
          if (!page) return;

          // 修复：使用 HarmonyOS 标准键码
          // KEYCODE_ENTER = 2049, KEYCODE_DEL = 2048 (Backspace), KEYCODE_TAB = 2050
          // KEYCODE_DPAD_UP = 2017, KEYCODE_DPAD_DOWN = 2018

          // Enter (2049) — 创建新 Block
          if (event.type === KeyType.Down && event.keyCode === 2049) {
            editor.createBlockBelow(page.uuid);
          }

          // Backspace (2048) on empty — 删除空 Block
          if (event.type === KeyType.Down && event.keyCode === 2048) {
            editor.deleteEmptyBlock();
          }

          // Tab (2050) — 缩进
          if (event.type === KeyType.Down && event.keyCode === 2050) {
            editor.indentBlock();
          }

          // Alt+↑ (2017) — 上移
          if (event.type === KeyType.Down && event.keyCode === 2017 &&
              event.getModifierKeyState!(['alt'])) {
            editor.moveBlockUp();
          }

          // Alt+↓ (2018) — 下移
          if (event.type === KeyType.Down && event.keyCode === 2018 &&
              event.getModifierKeyState!(['alt'])) {
            editor.moveBlockDown();
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
