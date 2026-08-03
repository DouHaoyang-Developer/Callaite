import { display } from '@kit.ArkUI';
import { LeftSidebar } from '../sidebar/LeftSidebar';
import { RightSidebar } from '../sidebar/RightSidebar';
import { ContentArea } from '../page/ContentArea';
import { AppState } from '../../state/AppState';

const SIDEBAR_WIDTH = 260;
const RIGHT_SIDEBAR_WIDTH = 280;

@Component
export struct MainContainer {
  @StorageLink('callaite_leftSidebarOpen') leftSidebarOpen: boolean = true;
  @StorageLink('callaite_rightSidebarOpen') rightSidebarOpen: boolean = false;
  @State windowWidth: number = 800;

  aboutToAppear(): void {
    try {
      const displayInstance = display.getDefaultDisplaySync();
      this.windowWidth = displayInstance.width / displayInstance.densityPixels;
    } catch (e) {
      console.warn('[MainContainer] Failed to get display info', e);
    }
  }

  get isCompact(): boolean {
    return this.windowWidth < 768;
  }

  build() {
    Row() {
      // 左侧栏
      if (!this.isCompact && this.leftSidebarOpen) {
        LeftSidebar()
          .width(SIDEBAR_WIDTH)
          .height('100%')
      }

      // 主内容区
      ContentArea()
        .layoutWeight(1)
        .height('100%')

      // 右侧栏
      if (!this.isCompact && this.rightSidebarOpen) {
        RightSidebar()
          .width(RIGHT_SIDEBAR_WIDTH)
          .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface0'))
    .bindSheet(this.isCompact && this.leftSidebarOpen, this.LeftDrawerBuilder(), {
      height: SheetSize.LARGE,
      dragBar: false,
      showClose: false,
      onDisappear: () => {
        AppState.setLeftSidebarOpen(false);
      }
    })
    .bindSheet(this.isCompact && this.rightSidebarOpen, this.RightDrawerBuilder(), {
      height: SheetSize.LARGE,
      dragBar: false,
      showClose: false,
      onDisappear: () => {
        AppState.setRightSidebarOpen(false);
      }
    })
  }

  @Builder
  LeftDrawerBuilder() {
    LeftSidebar()
      .width('80%')
      .height('100%')
  }

  @Builder
  RightDrawerBuilder() {
    RightSidebar()
      .width('80%')
      .height('100%')
  }
}
