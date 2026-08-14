import { WorkspaceService } from '../../services/WorkspaceService';
import { BlockData } from '../../core/models/Block';
import { DataStore } from '../../core/db/DataStore';
import { QueryEngine, QueryOptions } from '../../core/db/QueryEngine';
import { DatalogEngine } from '../../core/db/DatalogEngine';
import { AppState } from '../../state/AppState';

/**
 * 属性等值条件（用于 {{query}} 简单语法中的 property:key:value）。
 */
interface PropertyEq {
  key: string;
  value: string;
}

/**
 * InlineQueryBlock — 内联查询渲染组件。
 *
 * 支持：
 *  - `#+BEGIN_QUERY ... #+END_QUERY`（Datalog 语法，走 DatalogEngine）
 *  - `{{query ...}}`（简单标记/tag/property 语法，走 QueryEngine）
 *
 * 结果以列表形式嵌入 Block 下方，点击结果跳转到对应页面。
 */
@Component
export struct InlineQueryBlock {
  @Prop queryText: string = '';
  @State results: BlockData[] = [];

  aboutToAppear(): void {
    this.execute();
  }

  private execute(): void {
    const ws = WorkspaceService.getInstance();
    const store = ws.getDataStore();
    const trimmed = this.queryText.trim();
    if (trimmed === '') {
      this.results = [];
      return;
    }
    if (trimmed.startsWith('(')) {
      this.results = DatalogEngine.execute(trimmed, store);
    } else {
      this.results = InlineQueryBlock.executeSimple(trimmed, store);
    }
  }

  private static executeSimple(raw: string, store: DataStore): BlockData[] {
    const markers: string[] = [];
    const tags: string[] = [];
    const propEqs: PropertyEq[] = [];
    let hasProperty = '';

    const parts = raw.split(' ');
    for (let i = 0; i < parts.length; i++) {
      const token = parts[i].trim();
      if (token === '' || token === 'all') {
        continue;
      }
      const upper = token.toUpperCase();
      if (upper === 'TODO' || upper === 'DOING' || upper === 'DONE' ||
        upper === 'LATER' || upper === 'NOW' || upper === 'CANCELLED') {
        markers.push(upper);
      } else if (token.startsWith('tag:')) {
        const tag = token.substring('tag:'.length).trim();
        if (tag !== '') {
          tags.push(tag);
        }
      } else if (token.startsWith('property:')) {
        const rest = token.substring('property:'.length);
        const colonIdx = rest.indexOf(':');
        if (colonIdx > 0 && colonIdx < rest.length - 1) {
          const eq: PropertyEq = { key: rest.substring(0, colonIdx).trim(), value: rest.substring(colonIdx + 1).trim() };
          propEqs.push(eq);
        } else if (rest.length > 0) {
          hasProperty = rest.trim();
        }
      }
    }

    const options: QueryOptions = { limit: 100 };
    if (markers.length > 0) {
      options.markers = markers;
    }
    if (tags.length > 0) {
      options.tags = tags;
    }
    if (hasProperty !== '') {
      options.hasProperty = hasProperty;
    }

    let result = QueryEngine.query(store, options);
    if (propEqs.length > 0) {
      const filtered: BlockData[] = [];
      for (let i = 0; i < result.length; i++) {
        let ok = true;
        for (let j = 0; j < propEqs.length; j++) {
          if (!result[i].properties.has(propEqs[j].key) ||
            result[i].properties.get(propEqs[j].key) !== propEqs[j].value) {
            ok = false;
            break;
          }
        }
        if (ok) {
          filtered.push(result[i]);
        }
      }
      result = filtered;
    }
    return result;
  }

  private findPageName(pageId: string): string {
    const pages = WorkspaceService.getInstance().getAllPages();
    for (let i = 0; i < pages.length; i++) {
      if (pages[i].uuid === pageId) {
        return pages[i].originalName;
      }
    }
    return pageId;
  }

  private summary(content: string, max: number): string {
    if (content.length <= max) {
      return content;
    }
    return content.substring(0, max) + '…';
  }

  build() {
    Column({ space: 4 }) {
      Text('查询结果 (' + this.results.length.toString() + ')')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.muted_text'))
        .width('100%')

      if (this.results.length === 0) {
        Text('无匹配结果')
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
          .fontStyle(FontStyle.Italic)
          .width('100%')
      } else {
        ForEach(this.results, (b: BlockData) => {
          Row({ space: 8 }) {
            Column()
              .width(5)
              .height(5)
              .borderRadius(2.5)
              .backgroundColor(b.marker !== '' ? $r('app.color.marker_todo') : $r('app.color.bullet'))
            Text(this.summary(b.content, 100))
              .fontSize(13)
              .fontColor($r('app.color.text'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(this.findPageName(b.pageId))
              .fontSize(10)
              .fontColor($r('app.color.muted_text'))
              .maxLines(1)
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .borderRadius(4)
          .backgroundColor($r('app.color.surface1'))
          .onClick(() => {
            AppState.setCurrentPage(this.findPageName(b.pageId));
          })
        }, (b: BlockData) => b.uuid)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 8, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.surface2'))
    .borderRadius(4)
    .border({ width: { left: 2 }, color: $r('app.color.primary') })
  }
}
