import { window } from '@kit.ArkUI';

/**
 * SystemBarHelper —— 系统栏（状态栏/导航条）样式的统一管理。
 *
 * 职责：
 *   1. 持有主窗口引用（由 EntryAbility 在窗口就绪时注入）
 *   2. 提供系统栏背景/内容色的统一设置入口
 *   3. 主题切换时由 ThemeManager 调用 refresh() 实时更新内容色
 *
 * 背景**必须显式置为全透明**：SystemBarProperties 的 statusBarColor /
 * navigationBarColor 默认值是 '#66000000'（40% 黑色半透明），
 * 沉浸式布局下会让应用背景透过黑膜形成灰色条，与顶栏/底栏颜色不一致。
 */
export class SystemBarHelper {
  private static mainWindow: window.Window | undefined = undefined;
  private static lastIsDark: boolean = false;

  /** EntryAbility 在窗口就绪后注入主窗口 */
  static setWindow(win: window.Window): void {
    SystemBarHelper.mainWindow = win;
  }

  /**
   * 应用系统栏样式：背景全透明 + 内容色随主题。
   * @param isDark 当前是否深色主题
   */
  static apply(isDark: boolean): void {
    SystemBarHelper.lastIsDark = isDark;
    const win = SystemBarHelper.mainWindow;
    if (win === undefined) {
      return;
    }
    const contentColor: string = isDark ? '#FFFFFF' : '#1F2328';
    try {
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: contentColor,
        navigationBarContentColor: contentColor
      }).catch(() => {
        // 个别设备不支持时忽略
      });
    } catch (e) {
      // 忽略：不影响主流程
    }
  }

  /** 主题切换后调用：按当前主题更新系统栏内容色 */
  static refresh(): void {
    const win = SystemBarHelper.mainWindow;
    if (win === undefined) {
      return;
    }
    const isDark: boolean = SystemBarHelper.lastIsDark;
    SystemBarHelper.apply(isDark);
  }
}
