import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { t } from '../../utils/i18n';
import { WorkspaceService } from '../../services/WorkspaceService';
import { PageData } from '../../core/models/Page';

@Component
export struct LeftSidebar {
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  @StorageLink('callaite_favorites') favoritesRaw: string = '[]';
  @StorageLink('callaite_recentPages') recentRaw: string = '[]';
  @State allPages: PageData[] = [];
  @State favorites: string[] = [];
  @State recent: string[] = [];
  @State renamingPage: string = '';
  @State renameText: string = '';

  aboutToAppear(): void {
    const ws = WorkspaceService.getInstance();
    this.allPages = ws.getAllPages();
    this.refreshSidebarData();
  }

  refreshSidebarData(): void {
    if (this.favoritesRaw) {
      try { const p = JSON.parse(this.favoritesRaw) as string[]; this.favorites = p ?? []; } catch (e) { this.favorites = []; }
    }
    if (this.recentRaw) {
      try { const p = JSON.parse(this.recentRaw) as string[]; this.recent = p ?? []; } catch (e) { this.recent = []; }
    }
  }

  build() {
    Column({ space: 0 }) {
      // Header
      Row({ space: 10 }) {
        TablerIcon('command', 22, $r('app.color.primary'))
        Text(t('app_name'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })

      Divider().color($r('app.color.border')).width('100%')

      Scroll() {
        Column({ space: 0 }) {
          // ── 收藏夹 ──
          this.SectionHeader(t('favorites'), 'pin')
          if (this.favorites.length === 0) {
            Text('  点击页面旁的 ★ 收藏')
              .fontSize(12).fontColor($r('app.color.muted_text'))
              .padding({ left: 20, right: 16, top: 4, bottom: 4 })
          } else {
            ForEach(this.favorites, (name: string) => { this.PageLink(name); }, (name: string) => name)
          }

          Blank().height(4)
          Divider().color($r('app.color.border')).width('100%').margin({ left: 16, right: 16 })

          // ── 最近页面 ──
          this.SectionHeader(t('recent'), 'refresh')
          if (this.recent.length === 0) {
            Text('  暂无最近页面')
              .fontSize(12).fontColor($r('app.color.muted_text'))
              .padding({ left: 20, right: 16, top: 4, bottom: 4 })
          } else {
            ForEach(this.recent.slice(0, 10), (name: string) => { this.PageLink(name); }, (name: string) => name)
          }

          Blank().height(4)
          Divider().color($r('app.color.border')).width('100%').margin({ left: 16, right: 16 })

          // ── 所有页面（命名空间树） ──
          this.SectionHeader(t('all_pages'), 'file')
          if (this.allPages.length === 0) {
            Text('  暂无页面')
              .fontSize(12).fontColor($r('app.color.muted_text'))
              .padding({ left: 20, right: 16, top: 4, bottom: 4 })
          } else {
            ForEach(this.getNamespaceGroups(), (ns: string) => {
              if (ns !== '') {
                Row({ space: 6 }) {
                  TablerIcon('folder', 13, $r('app.color.muted_text'))
                  Text(ns).fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted_text'))
                }
                .width('100%')
                .padding({ left: 20, top: 8, bottom: 4 })
              }
              ForEach(this.getPagesByNamespace(ns), (page: PageData) => {
                this.PageLink(page.originalName);
              }, (page: PageData) => page.uuid)
            }, (ns: string) => ns)
          }
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // Footer
      Divider().color($r('app.color.border')).width('100%')
      Row({ space: 8 }) {
        TablerIcon('settings', 16, $r('app.color.muted_text'))
        Text(t('settings')).fontSize(13).fontColor($r('app.color.muted_text'))
      }
      .width('100%')
      .height(40)
      .padding({ left: 16, right: 16 })
      .onClick(() => { AppState.setCurrentPage('Settings'); })
    }
    .width('100%')
    .height('100%')
    .padding({ top: 4, bottom: 4 })
    .backgroundColor('#F7F7F7')
    .border({ width: { right: 1 }, color: '#E5E7EB' })
  }

  @Builder
  SectionHeader(title: string, iconName: string) {
    Row({ space: 6 }) {
      TablerIcon(iconName, 14, $r('app.color.muted_text'))
      Text(title).fontSize(11).fontWeight(FontWeight.Bold).fontColor($r('app.color.muted_text'))
    }
    .width('100%')
    .padding({ left: 20, right: 16, top: 10, bottom: 6 })
  }

  @Builder
  PageLink(name: string) {
    Row({ space: 10 }) {
      if (this.renamingPage === name) {
        TextInput({ text: this.renameText })
          .fontSize(13).layoutWeight(1).height(28)
          .onChange((value: string) => { this.renameText = value; })
          .onSubmit(() => { this.commitRename(); })
      } else {
        Text(name)
          .fontSize(13)
          .fontColor(this.currentPage === name ? $r('app.color.primary') : $r('app.color.text'))
          .fontWeight(this.currentPage === name ? FontWeight.Medium : FontWeight.Normal)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => { AppState.setCurrentPage(name); })
      }

      Row() {
        TablerIcon('edit', 11, $r('app.color.muted_text'))
      }.width(18).height(18).opacity(0.5)
      .onClick(() => { this.startRename(name); })

      Row() {
        TablerIcon('trash', 11, '#EF4444')
      }.width(18).height(18).opacity(0.5)
      .onClick(() => { this.deletePage(name); })
    }
    .width('100%')
    .height(32)
    .padding({ left: 20, right: 16 })
    .borderRadius(4)
    .backgroundColor(this.currentPage === name ? '#0078D410' : Color.Transparent)
  }

  startRename(oldName: string): void {
    this.renamingPage = oldName;
    this.renameText = oldName;
  }

  commitRename(): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.renamingPage);
    if (page && this.renameText !== '' && this.renameText !== this.renamingPage) {
      ws.getDataStore().renamePage(page.uuid, this.renameText);
    }
    this.renamingPage = '';
    this.renameText = '';
    const ws2 = WorkspaceService.getInstance();
    this.allPages = ws2.getAllPages();
  }

  deletePage(pageName: string): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(pageName);
    if (page) {
      ws.getDataStore().deletePage(page.uuid);
      this.allPages = ws.getAllPages();
    }
  }

  getNamespaceGroups(): string[] {
    const ns: string[] = [''];
    for (let i = 0; i < this.allPages.length; i++) {
      const pageNs = this.allPages[i].namespace;
      if (pageNs !== '' && ns.indexOf(pageNs) === -1) ns.push(pageNs);
    }
    return ns;
  }

  getPagesByNamespace(ns: string): PageData[] {
    const result: PageData[] = [];
    for (let i = 0; i < this.allPages.length; i++) {
      if (this.allPages[i].namespace === ns) result.push(this.allPages[i]);
    }
    return result;
  }
}
