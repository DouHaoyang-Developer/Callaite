import { display } from '@kit.ArkUI';
import { LeftSidebar } from '../sidebar/LeftSidebar';
import { RightSidebar } from '../sidebar/RightSidebar';
import { ContentArea } from '../page/ContentArea';
import { AppState } from '../../state/AppState';

const SIDEBAR_DEFAULT = 260;
const RIGHT_SIDEBAR_DEFAULT = 280;
const SIDEBAR_MIN = 180;
const SIDEBAR_MAX = 480;
const RESIZER_WIDTH = 4;

/**
 * MainContainer — 三栏布局 + 可拖拽 resizer 分隔条
 *
 * 结构：
 *   ┌─────────┬─┬────────────────────┬─┬──────────┐
 *   │ Left    │R│  Main Content      │R│ Right    │
 *   │ Sidebar │e│                    │e│ Sidebar  │
 *   │         │s│                    │s│          │
 *   │         │i│                    │i│          │
 *   │         │z│                    │z│          │
 *   │         │e│                    │e│          │
 *   │         │r│                    │r│          │
 *   └─────────┴─┴────────────────────┴─┴──────────┘
 *
 *  - 拖拽 resizer 调整左右侧栏宽度
 *  - 宽度持久化到 AppStorage（callaite_leftSidebarWidth / callaite_rightSidebarWidth）
 *  - 窄屏（<768）自动改用 bindSheet 抽屉模式
 */
@Component
export struct MainContainer {
  @StorageLink('callaite_leftSidebarOpen') leftSidebarOpen: boolean = true;
  @StorageLink('callaite_rightSidebarOpen') rightSidebarOpen: boolean = false;
  @State windowWidth: number = 800;
  @State leftWidth: number = SIDEBAR_DEFAULT;
  @State rightWidth: number = RIGHT_SIDEBAR_DEFAULT;
  // 拖拽中临时宽度，避免 @StorageLink 反复写盘
  @State draggingLeft: boolean = false;
  @State draggingRight: boolean = false;
  // 手势起点宽度（event.offsetX 是累计偏移，需以起点宽度为基准计算）
  private dragStartLeftWidth: number = SIDEBAR_DEFAULT;
  private dragStartRightWidth: number = RIGHT_SIDEBAR_DEFAULT;

  aboutToAppear(): void {
    try {
      const displayInstance = display.getDefaultDisplaySync();
      this.windowWidth = displayInstance.width / displayInstance.densityPixels;
    } catch (e) {
      console.warn('[MainContainer] Failed to get display info', e);
    }
    // 恢复持久化宽度
    const savedLeft = AppStorage.get<number>('callaite_leftSidebarWidth');
    if (savedLeft && savedLeft >= SIDEBAR_MIN && savedLeft <= SIDEBAR_MAX) {
      this.leftWidth = savedLeft;
    }
    const savedRight = AppStorage.get<number>('callaite_rightSidebarWidth');
    if (savedRight && savedRight >= SIDEBAR_MIN && savedRight <= SIDEBAR_MAX) {
      this.rightWidth = savedRight;
    }
  }

  // 注意：必须是普通方法 —— struct 上的 getter 会被 ArkTS 编译器静默丢弃，
  // 导致 isCompact 恒为 undefined（内联侧栏永远显示、抽屉永远打不开）。
  getIsCompact(): boolean {
    return this.windowWidth < 768;
  }

  build() {
    Row() {
      // ─── 左侧栏 ───
      if (!this.getIsCompact() && this.leftSidebarOpen) {
        LeftSidebar()
          .width(this.leftWidth)
          .height('100%')

        // 左 resizer
        Row() {
          Column()
            .width(2)
            .height(40)
            .backgroundColor(this.draggingLeft
              ? $r('app.color.primary')
              : $r('app.color.border'))
        }
        .width(RESIZER_WIDTH)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .gesture(
          PanGesture()
            .onActionStart(() => {
              this.draggingLeft = true;
              this.dragStartLeftWidth = this.leftWidth;
            })
            .onActionUpdate((event: GestureEvent) => {
              const newWidth = this.dragStartLeftWidth + event.offsetX;
              if (newWidth >= SIDEBAR_MIN && newWidth <= SIDEBAR_MAX) {
                this.leftWidth = newWidth;
              }
            })
            .onActionEnd(() => {
              this.draggingLeft = false;
              AppStorage.setOrCreate('callaite_leftSidebarWidth', this.leftWidth);
            })
        )
      }

      // ─── 主内容区 ───
      // 右抽屉 bindSheet 绑定在 ContentArea 上：同一组件上链式多次 bindSheet
      // 会互相覆盖（左侧抽屉生命周期被右侧覆盖导致打开即关闭），必须分开绑定。
      ContentArea()
        .layoutWeight(1)
        .height('100%')
        .bindSheet(this.getIsCompact() && this.rightSidebarOpen, this.RightDrawerBuilder(), {
          height: SheetSize.LARGE,
          dragBar: false,
          showClose: false,
          onDisappear: () => {
            AppState.setRightSidebarOpen(false);
          }
        })

      // ─── 右侧栏 + resizer ───
      if (!this.getIsCompact() && this.rightSidebarOpen) {
        // 右 resizer
        Row() {
          Column()
            .width(2)
            .height(40)
            .backgroundColor(this.draggingRight
              ? $r('app.color.primary')
              : $r('app.color.border'))
        }
        .width(RESIZER_WIDTH)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .gesture(
          PanGesture()
            .onActionStart(() => {
              this.draggingRight = true;
              this.dragStartRightWidth = this.rightWidth;
            })
            .onActionUpdate((event: GestureEvent) => {
              const newWidth = this.dragStartRightWidth - event.offsetX;
              if (newWidth >= SIDEBAR_MIN && newWidth <= SIDEBAR_MAX) {
                this.rightWidth = newWidth;
              }
            })
            .onActionEnd(() => {
              this.draggingRight = false;
              AppStorage.setOrCreate('callaite_rightSidebarWidth', this.rightWidth);
            })
        )

        RightSidebar()
          .width(this.rightWidth)
          .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface0'))
    .bindSheet(this.getIsCompact() && this.leftSidebarOpen, this.LeftDrawerBuilder(), {
      height: SheetSize.LARGE,
      dragBar: false,
      showClose: false,
      onDisappear: () => {
        AppState.setLeftSidebarOpen(false);
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
