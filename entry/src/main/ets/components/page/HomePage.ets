import { AppState } from '../../state/AppState';
import { Breakpoints } from '../../state/Breakpoints';
import { TabState } from '../../state/TabState';

/**
 * HomePage —— 新标签页（忠实复刻 Obsidian 新标签页：图 Laptop 1 桌面 / 图 iphone 1 移动）。
 *
 * 桌面：垂直居中的三条文字链接 —— 创建新文件 (Ctrl + N) / 打开文件 (Ctrl + O) / 关闭当前页。
 * 移动：垂直居中的两个 pill 按钮 —— 创建新文件 / 关闭标签页。
 * 无 Logo / 搜索框 / 按钮组（按截图效果处理，与此前版本冲突处以截图为准）。
 * 大纲与日志经左栏文件树、导航行、「今日日志」快捷入口与标签页正常访问。
 */
@Component
export struct HomePage {
  @State hoveredLink: string = '';

  private openCreateDialog(): void {
    // 新建 → 三选项对话框（Markdown 笔记 / 白板 / 大纲笔记）
    AppStorage.setOrCreate('callaite_newFileDialogOpen', true);
  }

  private openSearch(): void {
    // 打开文件（Ctrl + O）→ 快速切换 / 搜索面板
    AppState.setSearchPanelOpen(true);
  }

  private closeCurrentTab(): void {
    // 关闭当前标签页；仅剩一个标签时不关闭（保持工作区可用）
    if (TabState.getTabs().length > 1) {
      TabState.closeTab(TabState.getActiveTabId());
    }
  }

  /** 桌面：居中文字链接（Obsidian 新标签页样式，主题紫） */
  @Builder
  TextLink(label: string, onTap: () => void) {
    Text(label)
      .fontSize(14)
      .fontColor($r('app.color.primary'))
      .padding({ top: 5, bottom: 5, left: 10, right: 10 })
      .opacity(this.hoveredLink === label ? 0.7 : 1)
      .animation({ duration: 140, curve: Curve.EaseOut })
      .onHover((isHover: boolean) => {
        this.hoveredLink = isHover ? label : '';
      })
      .onClick(() => {
        onTap();
      })
  }

  /** 移动端：pill 按钮（浅紫底 + 主题紫文字，对齐 iphone 截图） */
  @Builder
  PillButton(label: string, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.primary'))
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .height(38)
    .padding({ left: 26, right: 26 })
    .borderRadius(10)
    .backgroundColor($r('app.color.accent_soft'))
    .onClick(() => {
      onTap();
    })
  }

  build() {
    Column({ space: 0 }) {
      Blank()

      if (Breakpoints.isCompact()) {
        // ─── 移动端（Obsidian iphone 新标签页）：两个竖排 pill 按钮 ───
        Column({ space: 14 }) {
          this.PillButton('创建新文件', (): void => {
            this.openCreateDialog();
          })
          this.PillButton('关闭标签页', (): void => {
            this.closeCurrentTab();
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      } else {
        // ─── 桌面（Obsidian 桌面新标签页）：三条居中文字链接 ───
        Column({ space: 6 }) {
          this.TextLink('创建新文件 (Ctrl + N)', (): void => {
            this.openCreateDialog();
          })
          this.TextLink('打开文件 (Ctrl + O)', (): void => {
            this.openSearch();
          })
          this.TextLink('关闭当前页', (): void => {
            this.closeCurrentTab();
          })
        }
        .alignItems(HorizontalAlign.Center)
      }

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
  }
}
