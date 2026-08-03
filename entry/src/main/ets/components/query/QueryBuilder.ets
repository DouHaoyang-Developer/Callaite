import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { WorkspaceService } from '../../services/WorkspaceService';
import { BlockData } from '../../core/models/Block';
import { QueryEngine, QueryOptions } from '../../core/db/QueryEngine';
import { AppState } from '../../state/AppState';

/**
 * QueryBuilder — 查询构建器 UI。
 * 支持按任务状态、优先级、日期范围、标签筛选 Block。
 */
@Component
export struct QueryBuilder {
  @State selectedMarker: string = '';
  @State selectedPriority: string = '';
  @State dateFrom: string = '';
  @State dateTo: string = '';
  @State tagFilter: string = '';
  @State results: BlockData[] = [];
  @State showResults: boolean = false;

  build() {
    Column({ space: 12 }) {
      // 标题
      Row({ space: 8 }) {
        TablerIcon('search', 18, $r('app.color.primary'))
        Text('查询构建器')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
      }
      .width('100%')

      // 筛选条件
      Column({ space: 8 }) {
        // 任务状态
        Row({ space: 8 }) {
          Text('状态:').fontSize(13).fontColor($r('app.color.muted_text')).width(50)
          Row({ space: 4 }) {
            this.FilterChip('全部', '', this.selectedMarker === '')
            this.FilterChip('TODO', 'TODO', this.selectedMarker === 'TODO')
            this.FilterChip('DOING', 'DOING', this.selectedMarker === 'DOING')
            this.FilterChip('DONE', 'DONE', this.selectedMarker === 'DONE')
          }
        }
        .width('100%')

        // 优先级
        Row({ space: 8 }) {
          Text('优先级:').fontSize(13).fontColor($r('app.color.muted_text')).width(50)
          Row({ space: 4 }) {
            this.FilterChip('全部', '', this.selectedPriority === '')
            this.FilterChip('A', 'A', this.selectedPriority === 'A')
            this.FilterChip('B', 'B', this.selectedPriority === 'B')
            this.FilterChip('C', 'C', this.selectedPriority === 'C')
          }
        }
        .width('100%')

        // 日期范围
        Row({ space: 8 }) {
          Text('日期:').fontSize(13).fontColor($r('app.color.muted_text')).width(50)
          TextInput({ text: this.dateFrom, placeholder: '从 yyyy-MM-dd' })
            .fontSize(12).layoutWeight(1).height(32)
            .onChange((value: string) => { this.dateFrom = value; })
          Text('—').fontSize(12).fontColor($r('app.color.muted_text'))
          TextInput({ text: this.dateTo, placeholder: '到 yyyy-MM-dd' })
            .fontSize(12).layoutWeight(1).height(32)
            .onChange((value: string) => { this.dateTo = value; })
        }
        .width('100%')

        // 标签
        Row({ space: 8 }) {
          Text('标签:').fontSize(13).fontColor($r('app.color.muted_text')).width(50)
          TextInput({ text: this.tagFilter, placeholder: '#tag' })
            .fontSize(12).layoutWeight(1).height(32)
            .onChange((value: string) => { this.tagFilter = value; })
        }
        .width('100%')

        // 执行按钮
        Row() {
          Button('查询')
            .fontSize(14)
            .type(ButtonType.Capsule)
            .backgroundColor($r('app.color.primary'))
            .onClick(() => { this.executeQuery(); })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 8 })
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.surface1'))
      .borderRadius(8)

      // 查询结果
      if (this.showResults) {
        Column({ space: 4 }) {
          Row() {
            Text('结果 (' + this.results.length + ')')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text'))
              .layoutWeight(1)
            Row() {
              TablerIcon('x', 14, $r('app.color.muted_text'))
            }
            .width(24).height(24)
            .onClick(() => { this.showResults = false; })
          }
          .width('100%')

          if (this.results.length === 0) {
            Text('— 无匹配结果')
              .fontSize(13)
              .fontColor($r('app.color.muted_text'))
              .padding({ top: 16 })
          } else {
            ForEach(this.results.slice(0, 20), (block: BlockData) => {
              Row({ space: 8 }) {
                if (block.marker !== '') {
                  Text(block.marker)
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(block.marker === 'DONE' ? $r('app.color.success') : $r('app.color.primary'))
                }
                Text(block.content.substring(0, 80))
                  .fontSize(13)
                  .fontColor($r('app.color.text'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .height(32)
              .padding({ left: 8, right: 8 })
              .borderRadius(4)
              .onClick(() => {
                const ws = WorkspaceService.getInstance();
                const pageId = ws.getPageUuidForBlock(block.uuid);
                if (pageId) {
                  const page = ws.getDataStore().getIndexStore().getPage(pageId);
                  if (page) { AppState.setCurrentPage(page.originalName); }
                }
              })
            }, (block: BlockData) => block.uuid)
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.surface1'))
        .borderRadius(8)
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8 })
  }

  @Builder
  FilterChip(label: string, value: string, isActive: boolean) {
    Text(label)
      .fontSize(12)
      .fontColor(isActive ? '#FFFFFF' : $r('app.color.text'))
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(12)
      .backgroundColor(isActive ? $r('app.color.primary') : $r('app.color.surface2'))
      .onClick(() => {
        if (value === '') {
          if (isActive) {
            if (label === '全部') {
              this.selectedMarker = '';
            }
          }
        } else {
          if (label === 'A' || label === 'B' || label === 'C') {
            this.selectedPriority = isActive ? '' : value;
          } else {
            this.selectedMarker = isActive ? '' : value;
          }
        }
      })
  }

  executeQuery(): void {
    const ws = WorkspaceService.getInstance();
    const options: QueryOptions = { limit: 20 };

    if (this.selectedMarker !== '') {
      options.marker = this.selectedMarker;
    }
    if (this.selectedPriority !== '') {
      options.priority = this.selectedPriority;
    }
    if (this.dateFrom !== '') {
      options.scheduledAfter = this.dateFrom;
    }
    if (this.dateTo !== '') {
      options.scheduledBefore = this.dateTo;
    }
    if (this.tagFilter !== '') {
      const tag: string = this.tagFilter.startsWith('#') ?
        this.tagFilter.substring(1) : this.tagFilter;
      const tags: string[] = [];
      tags.push(tag);
      options.tags = tags;
    }

    this.results = QueryEngine.query(ws.getDataStore(), options);
    this.showResults = true;
  }
}
