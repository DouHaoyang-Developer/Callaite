import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';

/**
 * HomePage —— 启动首页（复刻 Obsidian 新标签页布局，图 2/5/6 风格）。
 *
 * 结构：居中 Logo + 标题 → 居中搜索框（点击打开快速切换）→ 常用操作快捷入口按钮组。
 * 启动行为调整后，应用每次启动默认进入本页；大纲/日志仍可经
 * 「今日日志」快捷入口、左栏文件树与导航行正常访问。
 */
interface HomeAction {
  icon: string;
  label: string;
  page: string;      // 跳转目标路由；'' 表示走特殊动作（新建对话框）
}

const HOME_ACTIONS: HomeAction[] = [
  { icon: 'file-plus', label: '新建', page: '' },
  { icon: 'search', label: '搜索', page: 'search' },
  { icon: 'command', label: '命令面板', page: 'search' },
  { icon: 'calendar', label: '今日日志', page: 'Journal' },
  { icon: 'layout-grid', label: '白板', page: 'Whiteboards' },
  { icon: 'files', label: '所有页面', page: 'AllPages' }
];

@Component
export struct HomePage {
  @State hoveredAction: string = '';

  private openSearch(): void {
    AppState.setSearchPanelOpen(true);
  }

  private openAction(action: HomeAction): void {
    if (action.page === '') {
      // 新建 → 三选项对话框（Markdown 笔记 / 白板 / 大纲笔记）
      AppStorage.setOrCreate('callaite_newFileDialogOpen', true);
      return;
    }
    if (action.page === 'search') {
      this.openSearch();
      return;
    }
    AppState.setCurrentPage(action.page);
  }

  @Builder
  ActionButton(action: HomeAction) {
    Row({ space: 8 }) {
      TablerIcon(action.icon, 16,
        this.hoveredAction === action.label ? $r('app.color.primary') : $r('app.color.muted_text'))
      Text(action.label)
        .fontSize(13)
        .fontColor(this.hoveredAction === action.label ? $r('app.color.primary') : $r('app.color.text'))
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .height(40)
    .padding({ left: 16, right: 16 })
    .borderRadius(8)
    .backgroundColor($r('app.color.surface1'))
    .border({ width: 1, color: $r('app.color.border') })
    .stateStyles({
      normal: {
        .backgroundColor($r('app.color.surface1'))
      },
      pressed: { .backgroundColor($r('app.color.surface2')) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onHover((isHover: boolean) => {
      this.hoveredAction = isHover ? action.label : '';
    })
    .onClick(() => {
      this.openAction(action);
    })
  }

  build() {
    Column({ space: 0 }) {
      Blank()

      // ─── 居中标题区（Obsidian 新标签页：Logo + 仓库/应用名）───
      Column({ space: 10 }) {
        TablerIcon('bolt', 52, $r('app.color.primary'))
        Text('Callaite')
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text'))
        Text('输入以搜索或创建文件，或选择下方操作')
          .fontSize(12.5)
          .fontColor($r('app.color.muted_text'))
      }
      .alignItems(HorizontalAlign.Center)

      // ─── 居中搜索框（对齐 Obsidian 新标签页「搜索或创建文件」）───
      Row({ space: 10 }) {
        TablerIcon('search', 16, $r('app.color.muted_text'))
        Text('搜索或创建文件...')
          .fontSize(14)
          .fontColor($r('app.color.muted_text'))
          .layoutWeight(1)
      }
      .width('86%')
      .constraintSize({ maxWidth: 480 })
      .height(46)
      .padding({ left: 16, right: 16 })
      .margin({ top: 22 })
      .borderRadius(10)
      .backgroundColor($r('app.color.surface1'))
      .border({ width: 1, color: $r('app.color.border') })
      .onClick(() => {
        this.openSearch();
      })

      // ─── 常用操作快捷入口 ───
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(HOME_ACTIONS, (action: HomeAction) => {
          this.ActionButton(action)
        }, (action: HomeAction) => action.label)
      }
      .width('86%')
      .constraintSize({ maxWidth: 520 })
      .margin({ top: 18 })

      Blank()

      // ─── 底部提示（Obsidian 新标签页底部说明风格）───
      Text('大纲与日志可通过左栏文件树、快捷入口与标签页随时访问')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
        .margin({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
  }
}
