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
    if (this.favoritesRaw) { try { this.favorites = JSON.parse(this.favoritesRaw) as string[] ?? []; } catch (e) { this.favorites = []; } }
    if (this.recentRaw) { try { this.recent = JSON.parse(this.recentRaw) as string[] ?? []; } catch (e) { this.recent = []; } }
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 10 }) {
        Text(t('app_name')).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#1A1A1A')
      }
      .width('100%').height(48).padding({ left: 18, right: 16 })

      Divider().color('#E8E9EA').width('100%')

      Scroll() {
        Column({ space: 0 }) {
          this.SectionHeader(t('favorites'), 'pin')
          ForEach(this.favorites, (name: string) => { this.PageLink(name); }, (name: string) => name)
          if (this.favorites.length === 0) this.EmptyHint('点击 ··· 收藏页面')
          this.SectionSpacer()

          this.SectionHeader(t('recent'), 'refresh')
          ForEach(this.recent.slice(0, 8), (name: string) => { this.PageLink(name); }, (name: string) => name)
          if (this.recent.length === 0) this.EmptyHint('最近访问的页面')
          this.SectionSpacer()

          this.SectionHeader(t('all_pages'), 'file')
          ForEach(this.getNamespaceGroups(), (ns: string) => {
            if (ns !== '') {
              Row({ space: 6 }) {
                TablerIcon('folder', 12, '#A0A3A8')
                Text(ns).fontSize(11).fontWeight(FontWeight.Medium).fontColor('#787B80')
              }.width('100%').padding({ left: 20, top: 10, bottom: 4 })
            }
            ForEach(this.getPagesByNamespace(ns), (page: PageData) => {
              this.PageLink(page.originalName);
            }, (page: PageData) => page.uuid)
          }, (ns: string) => ns)
          if (this.allPages.length === 0) this.EmptyHint('创建新页面')
        }.width('100%')
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)

      Divider().color('#E8E9EA').width('100%')
      Row({ space: 8 }) {
        TablerIcon('settings', 15, '#787B80')
        Text(t('settings')).fontSize(13).fontColor('#787B80')
      }
      .width('100%').height(40).padding({ left: 18, right: 16 })
      .onClick(() => { AppState.setCurrentPage('Settings'); })
    }
    .width('100%').height('100%').padding({ top: 4, bottom: 4 })
    .backgroundColor('#F3F3F4')
    .border({ width: { right: 1 }, color: '#E8E9EA' })
  }

  @Builder SectionHeader(title: string, iconName: string) {
    Row({ space: 6 }) {
      TablerIcon(iconName, 13, '#A0A3A8')
      Text(title).fontSize(11).fontWeight(FontWeight.Bold).fontColor('#787B80')
    }.width('100%').padding({ left: 20, right: 16, top: 14, bottom: 6 })
  }

  @Builder SectionSpacer() {
    Divider().color('#E8E9EA').width('100%').margin({ left: 16, right: 16, top: 2, bottom: 2 })
  }

  @Builder EmptyHint(text: string) {
    Text(text).fontSize(12).fontColor('#B0B3B8')
      .padding({ left: 20, right: 16, top: 4, bottom: 4 })
  }

  @Builder PageLink(name: string) {
    Row({ space: 10 }) {
      if (this.renamingPage === name) {
        TextInput({ text: this.renameText }).fontSize(13).layoutWeight(1).height(26)
          .onChange((value: string) => { this.renameText = value; })
          .onSubmit(() => { this.commitRename(); })
      } else {
        Text(name)
          .fontSize(13).fontColor(this.currentPage === name ? '#0458A6' : '#3A3A3A')
          .fontWeight(this.currentPage === name ? FontWeight.Medium : FontWeight.Normal)
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => { AppState.setCurrentPage(name); })
      }
      Row() { TablerIcon('edit', 12, '#B0B3B8') }.width(16).height(16).opacity(0.4)
        .onClick(() => { this.startRename(name); })
      Row() { TablerIcon('trash', 12, '#DC2626') }.width(16).height(16).opacity(0.4)
        .onClick(() => { this.deletePage(name); })
    }
    .width('100%').height(30).padding({ left: 20, right: 14 }).borderRadius(4)
    .backgroundColor(this.currentPage === name ? '#0458A612' : Color.Transparent)
  }

  startRename(oldName: string): void { this.renamingPage = oldName; this.renameText = oldName; }

  commitRename(): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.renamingPage);
    if (page && this.renameText !== '' && this.renameText !== this.renamingPage) {
      ws.getDataStore().renamePage(page.uuid, this.renameText);
    }
    this.renamingPage = ''; this.renameText = '';
    this.allPages = WorkspaceService.getInstance().getAllPages();
  }

  deletePage(pageName: string): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(pageName);
    if (page) { ws.getDataStore().deletePage(page.uuid); this.allPages = ws.getAllPages(); }
  }

  getNamespaceGroups(): string[] { const ns: string[] = ['']; for (let i=0;i<this.allPages.length;i++){ const n=this.allPages[i].namespace; if(n&&ns.indexOf(n)===-1)ns.push(n); } return ns; }
  getPagesByNamespace(ns: string): PageData[] { const r:PageData[]=[]; for(let i=0;i<this.allPages.length;i++){ if(this.allPages[i].namespace===ns)r.push(this.allPages[i]); } return r; }
}
