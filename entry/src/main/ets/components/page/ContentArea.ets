import { Header } from '../layout/Header';
import { PageView } from './PageView';
import { CommandPalette } from '../commandpalette/CommandPalette';
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

        Scroll() {
          PageView()
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .backgroundColor($r('app.color.surface0'))
        .focusable(true)
        .onKeyEvent((event: KeyEvent) => {
          this.handleKeyEvent(event);
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

  handleKeyEvent(event: KeyEvent): void {
    const editor = EditorService.getInstance();
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.currentPage);
    if (!page) return;

    // Enter (keyCode 2054) — 创建新 Block
    if (event.type === KeyType.Down && event.keyCode === 2054) {
      editor.createBlockBelow(page.uuid);
      return;
    }

    // Tab (keyCode 2055) — 缩进
    if (event.type === KeyType.Down && event.keyCode === 2055) {
      editor.indentBlock();
      return;
    }

    // Backspace (keyCode 2053) on empty — 删除空 Block
    if (event.type === KeyType.Down && event.keyCode === 2053) {
      editor.deleteEmptyBlock();
      return;
    }

    // Alt+↑ (keyCode 2019) — 上移
    if (event.type === KeyType.Down && event.keyCode === 2019) {
      editor.moveBlockUp();
      return;
    }

    // Alt+↓ (keyCode 2020) — 下移
    if (event.type === KeyType.Down && event.keyCode === 2020) {
      editor.moveBlockDown();
      return;
    }
  }
}
