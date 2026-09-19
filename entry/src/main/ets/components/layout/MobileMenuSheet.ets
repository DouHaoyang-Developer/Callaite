import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { t } from '../../utils/i18n';
import { JournalService } from '../../services/JournalService';
import { TabState } from '../../state/TabState';

interface MenuRow {
  icon: string;
  label: string;
  action: string;
}

interface MenuGroup {
  title: string;
  rows: MenuRow[];
}

/**
 * MobileMenuSheet — Obsidian iOS "更多"菜单（Obsidian_iphone (3).jpg 复刻）。
 *
 * 结构优化：原先 9 个条目平铺 + 8 条分割线，视觉噪声大且难以扫读；
 * 现按「内容 / 视图 / 数据与系统」三组归类，组间用分割线分隔，减少认知负担。
 */
@Component
export struct MobileMenuSheet {
  @State hoveredAction: string = '';

  /**
   * 按意图分组 —— 创建/浏览内容、切换视图、数据与系统设置。
   */
  private groups(): MenuGroup[] {
    const g: MenuGroup[] = [];

    const content: MenuRow[] = [];
    content[0] = { icon: 'search', label: t('quick_switch'), action: 'switcher' };
    content[1] = { icon: 'file-plus', label: t('new_page'), action: 'newPage' };
    content[2] = { icon: 'calendar-plus', label: t('open_today_journal'), action: 'today' };
    content[3] = { icon: 'list', label: t('nav_all_pages'), action: 'allPages' };
    g[0] = { title: t('menu_group_content'), rows: content };

    const view: MenuRow[] = [];
    view[0] = { icon: 'hierarchy', label: t('view_graph'), action: 'graph' };
    view[1] = { icon: 'layout-grid', label: t('new_whiteboard'), action: 'whiteboard' };
    view[2] = { icon: 'layout-sidebar-right', label: t('sidebar_right'), action: 'rightSidebar' };
    g[1] = { title: t('menu_group_view'), rows: view };

    const sys: MenuRow[] = [];
    sys[0] = { icon: 'upload', label: t('import'), action: 'import' };
    sys[1] = { icon: 'settings', label: t('settings'), action: 'settings' };
    g[2] = { title: t('menu_group_system'), rows: sys };

    return g;
  }

  private close(): void {
    AppStorage.setOrCreate('callaite_mobileMenuOpen', false);
  }

  private handle(row: MenuRow): void {
    this.close();
    if (row.action === 'switcher' || row.action === 'newPage') {
      AppState.setSearchPanelOpen(true);
    } else if (row.action === 'graph') {
      TabState.newTab('Graph');
    } else if (row.action === 'whiteboard') {
      TabState.newTab('Whiteboards');
    } else if (row.action === 'today') {
      JournalService.ensureTodayJournal();
      AppState.setCurrentPage('Journal');
    } else if (row.action === 'allPages') {
      TabState.newTab('AllPages');
    } else if (row.action === 'rightSidebar') {
      AppState.toggleRightSidebar();
    } else if (row.action === 'import') {
      AppState.setImportDialogOpen(true);
    } else if (row.action === 'settings') {
      AppState.setCurrentPage('Settings');
    }
  }

  @Builder
  GroupHeader(title: string) {
    Text(title)
      .fontSize(11)
      .fontColor($r('app.color.muted_text'))
      .letterSpacing(0.6)
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 4 })
  }

  @Builder
  MenuRowItem(row: MenuRow) {
    Row({ space: 14 }) {
      TablerIcon(row.icon, 22, $r('app.color.text'))
      Text(row.label)
        .fontSize(16)
        .fontColor($r('app.color.text'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(52)
    .padding({ left: 20, right: 20 })
    .stateStyles({
      normal: {
        .backgroundColor(this.hoveredAction === row.action ? $r('app.color.surface2') : Color.Transparent)
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onHover((isHover: boolean) => {
      this.hoveredAction = isHover ? row.action : '';
    })
    .onClick(() => {
      this.handle(row);
    })
  }

  build() {
    Column() {
      // 顶部拖动指示条
      Column()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor($r('app.color.border'))
        .margin({ top: 8, bottom: 6 })

      ForEach(this.groups(), (group: MenuGroup, gi: number) => {
        if (gi > 0) {
          Divider()
            .color($r('app.color.border'))
            .width('90%')
            .margin({ top: 6 })
        }
        this.GroupHeader(group.title)
        ForEach(group.rows, (row: MenuRow) => {
          this.MenuRowItem(row)
        }, (row: MenuRow) => group.title + '_' + row.action)
      }, (group: MenuGroup) => group.title)

      Blank().height(12)
    }
    .width('100%')
    .padding({ bottom: 24 })
    .backgroundColor($r('app.color.surface1'))
    .borderRadius({ topLeft: 24, topRight: 24 })
    .border({ width: { top: 0.5 }, color: $r('app.color.glass_border') })
  }
}
