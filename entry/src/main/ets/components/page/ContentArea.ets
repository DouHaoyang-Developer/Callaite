import { Header } from '../layout/Header';
import { PageView } from './PageView';
import { CommandPalette } from '../commandpalette/CommandPalette';
import { Toolbar } from '../outliner/Toolbar';
import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';

@Component
export struct ContentArea {
  @StorageLink('callaite_searchPanelOpen') searchPanelOpen: boolean = false;
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';

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

          // Enter (2054) — 创建新 Block
          if (event.type === KeyType.Down && event.keyCode === 2054) {
            editor.createBlockBelow(page.uuid);
          }

          // Backspace (2053) on empty — 删除空 Block
          if (event.type === KeyType.Down && event.keyCode === 2053) {
            editor.deleteEmptyBlock();
          }

          // Tab (2055) — 缩进
          if (event.type === KeyType.Down && event.keyCode === 2055) {
            editor.indentBlock();
          }

          // Alt+↑ (2019) — 上移
          if (event.type === KeyType.Down && event.keyCode === 2019) {
            editor.moveBlockUp();
          }

          // Alt+↓ (2020) — 下移
          if (event.type === KeyType.Down && event.keyCode === 2020) {
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
