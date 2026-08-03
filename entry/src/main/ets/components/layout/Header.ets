import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';

@Component
export struct Header {
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  @StorageLink('callaite_leftSidebarOpen') leftSidebarOpen: boolean = true;
  @StorageLink('callaite_rightSidebarOpen') rightSidebarOpen: boolean = false;

  build() {
    Row() {
      // 左侧: 汉堡菜单 + 导航
      Row({ space: 4 }) {
        Row() {
          TablerIcon('menu-2', 18, $r('app.color.text'))
        }
        .width(32).height(32).borderRadius(4)
        .onClick(() => { AppState.toggleLeftSidebar(); })

        Row() {
          TablerIcon('arrow-left', 16, '#D1D5DB')
        }
        .width(28).height(28)

        Row() {
          TablerIcon('arrow-right', 16, '#D1D5DB')
        }
        .width(28).height(28)
      }

      Blank()

      // 右侧: 搜索 + 右侧栏 + 设置
      Row({ space: 2 }) {
        Row() {
          TablerIcon('search', 18, $r('app.color.text'))
        }
        .width(32).height(32).borderRadius(4)
        .onClick(() => { AppState.setSearchPanelOpen(true); })

        Row() {
          TablerIcon(this.rightSidebarOpen ? 'layout-sidebar-right' : 'layout-sidebar-right', 18,
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
