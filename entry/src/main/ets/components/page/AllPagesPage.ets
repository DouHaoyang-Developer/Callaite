import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { AppState } from '../../state/AppState';
import { WorkspaceService } from '../../services/WorkspaceService';
import { PageData, isJournalPage } from '../../core/models/Page';

/**
 * AllPagesPage — 所有页面列表页。
 *
 * 对应 Logseq 的 All Pages 视图。
 * 功能：搜索 + 排序 + 筛选 + 批量删除 + 长按删除。
 */
@Component
export struct AllPagesPage {
  @State pages: PageData[] = [];
  @State searchQuery: string = '';
  @State sortBy: string = 'updated';
  @State filterType: string = 'all';
  @State selectedUuids: string[] = [];
  @State isMultiSelectMode: boolean = false;

  aboutToAppear(): void {
    this.loadPages();
  }

  loadPages(): void {
    this.pages = WorkspaceService.getInstance().getAllPages();
  }

  /**
   * 根据搜索词、筛选类型、排序方式返回处理后的页面列表。
   */
  getFilteredAndSortedPages(): PageData[] {
    let result: PageData[] = [];

    for (let i = 0; i < this.pages.length; i++) {
      const page = this.pages[i];

      if (this.searchQuery !== '') {
        const query = this.searchQuery.toLowerCase();
        if (page.name.toLowerCase().indexOf(query) === -1 &&
            page.originalName.toLowerCase().indexOf(query) === -1) {
          continue;
        }
      }

      if (this.filterType === 'journal') {
        if (!isJournalPage(page)) {
          continue;
        }
      } else if (this.filterType === 'normal') {
        if (isJournalPage(page)) {
          continue;
        }
      } else if (this.filterType === 'tagged') {
        if (page.tags.length === 0) {
          continue;
        }
      }

      result.push(page);
    }

    if (this.sortBy === 'name') {
      result.sort((a: PageData, b: PageData): number => {
        if (a.originalName < b.originalName) {
          return -1;
        }
        if (a.originalName > b.originalName) {
          return 1;
        }
        return 0;
      });
    } else if (this.sortBy === 'created') {
      result.sort((a: PageData, b: PageData): number => {
        return b.createdAt - a.createdAt;
      });
    } else {
      result.sort((a: PageData, b: PageData): number => {
        return b.updatedAt - a.updatedAt;
      });
    }

    return result;
  }

  isSelected(uuid: string): boolean {
    for (let i = 0; i < this.selectedUuids.length; i++) {
      if (this.selectedUuids[i] === uuid) {
        return true;
      }
    }
    return false;
  }

  toggleSelection(uuid: string): void {
    const newList: string[] = [];
    let removed = false;
    for (let i = 0; i < this.selectedUuids.length; i++) {
      if (this.selectedUuids[i] !== uuid) {
        newList.push(this.selectedUuids[i]);
      } else {
        removed = true;
      }
    }
    if (!removed) {
      newList.push(uuid);
    }
    this.selectedUuids = newList;
  }

  toggleMultiSelectMode(): void {
    this.isMultiSelectMode = !this.isMultiSelectMode;
    if (!this.isMultiSelectMode) {
      this.selectedUuids = [];
    }
  }

  selectAll(): void {
    const filtered = this.getFilteredAndSortedPages();
    const newList: string[] = [];
    for (let i = 0; i < filtered.length; i++) {
      newList.push(filtered[i].uuid);
    }
    this.selectedUuids = newList;
  }

  batchDelete(): void {
    const count = this.selectedUuids.length;
    AlertDialog.show({
      title: t('delete'),
      message: `确认删除选中的 ${count} 个页面？`,
      primaryButton: {
        value: t('cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: t('delete'),
        fontColor: $r('app.color.danger'),
        action: (): void => {
          const ws = WorkspaceService.getInstance();
          for (let i = 0; i < this.selectedUuids.length; i++) {
            ws.getDataStore().deletePage(this.selectedUuids[i]);
          }
          this.selectedUuids = [];
          this.isMultiSelectMode = false;
          this.loadPages();
        }
      }
    });
  }

  deleteSinglePage(page: PageData): void {
    AlertDialog.show({
      title: t('delete'),
      message: `确认删除页面 "${page.originalName}"？`,
      primaryButton: {
        value: t('cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: t('delete'),
        fontColor: $r('app.color.danger'),
        action: (): void => {
          WorkspaceService.getInstance().getDataStore().deletePage(page.uuid);
          this.loadPages();
        }
      }
    });
  }

  formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const y = date.getFullYear();
    const m = date.getMonth() + 1;
    const d = date.getDate();
    const monthStr = m < 10 ? '0' + m : '' + m;
    const dayStr = d < 10 ? '0' + d : '' + d;
    return y + '-' + monthStr + '-' + dayStr;
  }

  build() {
    Column({ space: 0 }) {
      // ─── 标题栏 ───
      Row({ space: 12 }) {
        Text(t('all_pages'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
          .layoutWeight(1)

        if (this.isMultiSelectMode) {
          Text(this.selectedUuids.length.toString())
            .fontSize(13)
            .fontColor($r('app.color.primary'))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(4)
            .backgroundColor($r('app.color.surface2'))

          Row({ space: 4 }) {
            TablerIcon('check', 14, $r('app.color.muted_text'))
            Text('全选')
              .fontSize(12)
              .fontColor($r('app.color.muted_text'))
          }
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .borderRadius(4)
          .backgroundColor($r('app.color.surface2'))
          .onClick(() => { this.selectAll(); })

          if (this.selectedUuids.length > 0) {
            Row({ space: 4 }) {
              TablerIcon('trash', 14, $r('app.color.danger'))
              Text(t('delete'))
                .fontSize(12)
                .fontColor($r('app.color.danger'))
            }
            .padding({ left: 8, right: 8, top: 5, bottom: 5 })
            .borderRadius(4)
            .backgroundColor($r('app.color.surface2'))
            .onClick(() => { this.batchDelete(); })
          }
        }

        Row({ space: 4 }) {
          TablerIcon(this.isMultiSelectMode ? 'x' : 'checklist', 14,
            this.isMultiSelectMode ? $r('app.color.primary') : $r('app.color.muted_text'))
          Text(this.isMultiSelectMode ? t('close') : '多选')
            .fontSize(12)
            .fontColor(this.isMultiSelectMode ? $r('app.color.primary') : $r('app.color.muted_text'))
        }
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .borderRadius(4)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => { this.toggleMultiSelectMode(); })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      // ─── 搜索 + 筛选 ───
      Row({ space: 8 }) {
        Row({ space: 6 }) {
          TablerIcon('search', 14, $r('app.color.muted_text'))
          TextInput({ text: this.searchQuery, placeholder: t('search') })
            .fontSize(13)
            .layoutWeight(1)
            .height(34)
            .backgroundColor(Color.Transparent)
            .onChange((value: string) => {
              this.searchQuery = value;
            })
        }
        .layoutWeight(1)
        .height(34)
        .padding({ left: 10, right: 10 })
        .borderRadius(6)
        .backgroundColor($r('app.color.surface2'))

        Select([
          { value: '更新时间' },
          { value: '名称' },
          { value: '创建时间' }
        ])
          .selected(this.sortBy === 'updated' ? 0 : this.sortBy === 'name' ? 1 : 2)
          .value('排序')
          .fontSize(12)
          .height(34)
          .backgroundColor($r('app.color.surface2'))
          .borderRadius(6)
          .onSelect((index: number) => {
            if (index === 0) {
              this.sortBy = 'updated';
            } else if (index === 1) {
              this.sortBy = 'name';
            } else {
              this.sortBy = 'created';
            }
          })

        Select([
          { value: '全部' },
          { value: '日志' },
          { value: '普通' },
          { value: '带标签' }
        ])
          .selected(
            this.filterType === 'all' ? 0 :
            this.filterType === 'journal' ? 1 :
            this.filterType === 'normal' ? 2 : 3
          )
          .value('筛选')
          .fontSize(12)
          .height(34)
          .backgroundColor($r('app.color.surface2'))
          .borderRadius(6)
          .onSelect((index: number) => {
            if (index === 0) {
              this.filterType = 'all';
            } else if (index === 1) {
              this.filterType = 'journal';
            } else if (index === 2) {
              this.filterType = 'normal';
            } else {
              this.filterType = 'tagged';
            }
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 12 })

      Divider().color($r('app.color.border')).width('100%')

      // ─── 页面列表 ───
      if (this.getFilteredAndSortedPages().length === 0) {
        Column({ space: 10 }) {
          TablerIcon('file-off', 40, $r('app.color.muted_text'))
          Text(this.pages.length === 0 ? '暂无页面' : '无匹配结果')
            .fontSize(14)
            .fontColor($r('app.color.muted_text'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 0 }) {
            ForEach(this.getFilteredAndSortedPages(), (page: PageData) => {
              this.PageItem(page)
            }, (page: PageData) => page.uuid)
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface1'))
  }

  @Builder
  PageItem(page: PageData) {
    Row({ space: 10 }) {
      if (this.isMultiSelectMode) {
        Row() {
          if (this.isSelected(page.uuid)) {
            TablerIcon('check', 14, $r('app.color.primary'))
          }
        }
        .width(20)
        .height(20)
        .borderRadius(4)
        .border({ width: 1, color: this.isSelected(page.uuid) ? $r('app.color.primary') : $r('app.color.border') })
        .backgroundColor(this.isSelected(page.uuid) ? $r('app.color.surface2') : Color.Transparent)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.toggleSelection(page.uuid); })
      }

      TablerIcon(
        isJournalPage(page) ? 'calendar' : 'file',
        16,
        isJournalPage(page) ? $r('app.color.primary') : $r('app.color.muted_text')
      )

      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(page.originalName)
            .fontSize(14)
            .fontColor($r('app.color.text'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (page.namespace !== '') {
            Text(page.namespace)
              .fontSize(10)
              .fontColor($r('app.color.muted_text'))
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(3)
              .backgroundColor($r('app.color.surface2'))
          }
        }
        .width('100%')

        Row({ space: 8 }) {
          Text(this.formatTime(page.updatedAt))
            .fontSize(11)
            .fontColor($r('app.color.muted_text'))

          if (page.tags.length > 0) {
            ForEach(page.tags.slice(0, 3), (tag: string) => {
              Text('#' + tag)
                .fontSize(10)
                .fontColor($r('app.color.link'))
            }, (tag: string) => tag)
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 10, bottom: 10 })
    .backgroundColor(this.isSelected(page.uuid) && this.isMultiSelectMode
      ? $r('app.color.surface2')
      : Color.Transparent)
    .onClick(() => {
      if (this.isMultiSelectMode) {
        this.toggleSelection(page.uuid);
      } else {
        AppState.setCurrentPage(page.originalName);
      }
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          this.deleteSinglePage(page);
        })
    )
  }
}
