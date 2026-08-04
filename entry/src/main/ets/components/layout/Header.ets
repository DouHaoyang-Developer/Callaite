import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { JournalService } from '../../services/JournalService';

@Component
export struct Header {
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  @StorageLink('callaite_leftSidebarOpen') leftSidebarOpen: boolean = true;
  @StorageLink('callaite_rightSidebarOpen') rightSidebarOpen: boolean = false;

  get displayTitle(): string {
    if (this.currentPage === 'Journal') {
      return JournalService.getTodayDateString();
    }
    return this.currentPage;
  }

  build() {
    Row() {
      Row({ space: 4 }) {
        Row() {
          TablerIcon('menu-2', 18, $r('app.color.text'))
        }
        .width(32).height(32).borderRadius(4)
        .onClick(() => { AppState.toggleLeftSidebar(); })

        Row() {
          TablerIcon('arrow-left', 16, '#9CA3AF')
        }
        .width(28).height(28)
        .onClick(() => {
          if (this.currentPage === 'Journal') {
            AppState.setCurrentPage(JournalService.getYesterdayDateString());
          }
        })

        Row() {
          TablerIcon('arrow-right', 16, '#9CA3AF')
        }
        .width(28).height(28)
        .onClick(() => {
          if (this.currentPage === 'Journal') {
            AppState.setCurrentPage(JournalService.getTomorrowDateString());
          }
        })
      }

      Blank()

      Row({ space: 2 }) {
        Row() {
          TablerIcon('search', 18, $r('app.color.text'))
        }
        .width(32).height(32).borderRadius(4)
        .onClick(() => { AppState.setSearchPanelOpen(true); })

        Row() {
          TablerIcon('layout-sidebar-right', 18,
            this.rightSidebarOpen ? $r('app.color.primary') : $r('app.color.text'))
        }
        .width(32).height(32).borderRadius(4)
        .onClick(() => { AppState.toggleRightSidebar(); })

        Row() {
          TablerIcon('settings', 18, $r('app.color.text'))
        }
        .width(32).height(32).borderRadius(4)
        .onClick(() => { AppState.setCurrentPage('Settings'); })
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('app.color.surface0'))
    .border({ width: { bottom: 1 }, color: '#E5E7EB' })
  }
}
