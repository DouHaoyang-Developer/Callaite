import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { t } from '../../utils/i18n';
import { WorkspaceService } from '../../services/WorkspaceService';
import { BlockData } from '../../core/models/Block';
import { BacklinkInfo } from '../../core/db/DataStore';

@Component
export struct RightSidebar {
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  @State backlinks: BacklinkInfo[] = [];
  @State backlinksFilter: string = 'all'; // 'all' | 'page' | 'block'
  @State headings: BlockData[] = [];
  @State propEntries: string[][] = [];

  aboutToAppear(): void {
    this.refresh();
  }

  refresh(): void {
    const ws = WorkspaceService.getInstance();
    this.backlinks = ws.getDataStore().getBacklinks(this.currentPage);
    this.headings = this.collectHeadings(ws);
    this.propEntries = this.collectProps(ws);
  }

  collectHeadings(ws: WorkspaceService): BlockData[] {
    const page = ws.getPageByName(this.currentPage);
    if (!page) return [];
    const allBlocks = ws.getPageBlocks(page.uuid);
    const result: BlockData[] = [];
    for (let i = 0; i < allBlocks.length; i++) {
      const b = allBlocks[i];
      if (b.content.startsWith('## ') || b.content.startsWith('# ') ||
          b.content.startsWith('### ')) {
        result.push(b);
      }
    }
    return result;
  }

  collectProps(ws: WorkspaceService): string[][] {
    const page = ws.getPageByName(this.currentPage);
    if (!page) return [];
    const entries: string[][] = [];
    page.properties.forEach((propKey: string, propValue: string) => {
      const pair: string[] = [];
      pair[0] = propKey;
      pair[1] = propValue;
      entries.push(pair);
    });
    return entries;
  }

  build() {
    Column({ space: 16 }) {
      // 标题栏
      Row({ space: 8 }) {
        Text(t('sidebar_right'))
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
          .layoutWeight(1)

        Row() {
          TablerIcon('x', 16, $r('app.color.muted_text'))
        }
        .width(28)
        .height(28)
        .onClick(() => {
          AppState.setRightSidebarOpen(false);
        })
      }
      .width('100%')
      .padding(16)

      Scroll() {
        Column({ space: 20 }) {
          this.BacklinksPanel()
          Row({ space: 6 }) {
            Row() { Text('全部').fontSize(11).fontColor(this.backlinksFilter === 'all' ? $r('app.color.primary') : $r('app.color.muted_text')) }
            .onClick(() => { this.backlinksFilter = 'all'; })
            Row() { Text('页面').fontSize(11).fontColor(this.backlinksFilter === 'page' ? $r('app.color.primary') : $r('app.color.muted_text')) }
            .onClick(() => { this.backlinksFilter = 'page'; })
            Row() { Text('Block').fontSize(11).fontColor(this.backlinksFilter === 'block' ? $r('app.color.primary') : $r('app.color.muted_text')) }
            .onClick(() => { this.backlinksFilter = 'block'; })
          }
          .width('100%')
          .padding({ left: 16 })

          // 2. 页面大纲
          this.OutlinePanel()

          // 3. 属性
          this.PropertiesPanel()
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 8, bottom: 8 })
    .backgroundColor($r('app.color.surface1'))
    .border({ width: { left: 1 }, color: $r('app.color.border') })
  }

  @Builder
  BacklinksPanel() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TablerIcon('world', 18, $r('app.color.text'))
        Text(t('backlinks'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text'))
      }
      .width('100%')

      if (this.getFilteredBacklinks().length === 0) {
        Text('—')
          .fontSize(13)
          .fontColor($r('app.color.muted_text'))
          .width('100%')
      } else {
        ForEach(this.getFilteredBacklinks(), (info: BacklinkInfo) => {
          Row({ space: 8 }) {
            TablerIcon('arrow-right', 14, $r('app.color.muted_text'))
            Column({ space: 2 }) {
              Text(info.sourceContent)
                .fontSize(13)
                .fontColor($r('app.color.text'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(t('from_page') + ': ' + info.sourcePageName)
                .fontSize(11)
                .fontColor($r('app.color.muted_text'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .borderRadius(4)
        }, (info: BacklinkInfo) => info.sourceBlockId)
      }
    }
    .width('100%')
  }

  @Builder
  OutlinePanel() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TablerIcon('list-details', 18, $r('app.color.text'))
        Text(t('outline'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text'))
      }
      .width('100%')

      if (this.headings.length === 0) {
        Text('—')
          .fontSize(13)
          .fontColor($r('app.color.muted_text'))
          .width('100%')
      } else {
        ForEach(this.headings, (block: BlockData) => {
          Row({ space: 8 }) {
            if (block.level > 0) {
              Blank().width(block.level * 12)
            }
            Circle({ width: 5, height: 5 })
              .fill($r('app.color.bullet'))
            Text(block.content)
              .fontSize(13)
              .fontColor($r('app.color.text'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding({ top: 3, bottom: 3 })
        }, (block: BlockData) => block.uuid)
      }
    }
    .width('100%')
  }

  @Builder
  PropertiesPanel() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TablerIcon('adjustments', 18, $r('app.color.text'))
        Text(t('properties'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text'))
      }
      .width('100%')

      if (this.propEntries.length === 0) {
        Text('—')
          .fontSize(13)
          .fontColor($r('app.color.muted_text'))
          .width('100%')
      } else {
        ForEach(this.propEntries, (pair: string[]) => {
          Row({ space: 4 }) {
            Text(pair[0])
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.muted_text'))
            Text(pair[1])
              .fontSize(13)
              .fontColor($r('app.color.text'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Row() {
              TablerIcon('x', 12, $r('app.color.danger'))
            }
            .width(20).height(20)
            .onClick(() => {
              this.deleteProperty(pair[0]);
            })
          }
          .width('100%')
          .padding({ top: 2, bottom: 2 })
        }, (pair: string[]) => pair[0])
      }

      // 添加属性输入
      Row({ space: 4 }) {
        TextInput({ placeholder: 'key:: value' })
          .fontSize(12)
          .layoutWeight(1)
          .height(32)
          .onChange((value: string) => {
            // 检测 :: 分隔符后自动添加
            if (value.indexOf('::') > 0 && value.indexOf('::') < value.length - 2) {
              this.addProperty(value);
            }
          })
      }
      .width('100%')
      .padding({ top: 4 })
    }
    .width('100%')
  }

  getFilteredBacklinks(): BacklinkInfo[] {
    if (this.backlinksFilter === 'page') {
      const result: BacklinkInfo[] = [];
      for (let i = 0; i < this.backlinks.length; i++) {
        if (!this.backlinks[i].isBlockRef) result.push(this.backlinks[i]);
      }
      return result;
    }
    if (this.backlinksFilter === 'block') {
      const result: BacklinkInfo[] = [];
      for (let i = 0; i < this.backlinks.length; i++) {
        if (this.backlinks[i].isBlockRef) result.push(this.backlinks[i]);
      }
      return result;
    }
    return this.backlinks;
  }

  addProperty(input: string): void {
    const sepIdx = input.indexOf('::');
    if (sepIdx <= 0) {
      return;
    }
    const key = input.substring(0, sepIdx).trim();
    const value = input.substring(sepIdx + 2).trim();
    if (!key || !value) {
      return;
    }

    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.currentPage);
    if (page) {
      page.properties.set(key, value);
      ws.savePage(page.uuid);
      this.refresh();
    }
  }

  deleteProperty(key: string): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.currentPage);
    if (page) {
      page.properties.remove(key);
      ws.savePage(page.uuid);
      this.refresh();
    }
  }
}
