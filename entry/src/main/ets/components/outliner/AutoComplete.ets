import { WorkspaceService } from '../../services/WorkspaceService';
import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';

/**
 * AutoComplete — 自动补全建议面板。
 *
 * 当用户在 TextArea 中输入 [[、((、# 时触发。
 * 显示匹配的页面名 / Block UUID / 标签，点击后替换触发词。
 */
@Component
export struct AutoComplete {
  @Prop triggerType: string = '';  // 'page' | 'block' | 'tag'
  @Prop filterText: string = '';
  @Prop blockUuid: string = '';
  onSelect: (value: string) => void = (_v: string) => {};
  onDismiss: () => void = () => {};
  @State suggestions: string[] = [];

  aboutToAppear(): void {
    this.loadSuggestions();
  }

  loadSuggestions(): void {
    const ws = WorkspaceService.getInstance();

    if (this.triggerType === 'page') {
      const pages = ws.searchPages(this.filterText);
      const names: string[] = [];
      for (let i = 0; i < pages.length; i++) {
        names.push(pages[i].originalName);
      }
      this.suggestions = names.slice(0, 8);
    } else if (this.triggerType === 'block') {
      // 搜索当前页面的 Block UUID
      const page = ws.getPageByName(AppState.getCurrentPage());
      if (page) {
        const blocks = ws.getPageBlocks(page.uuid);
        const uuids: string[] = [];
        for (let i = 0; i < blocks.length; i++) {
          if (blocks[i].uuid.startsWith(this.filterText) || this.filterText === '') {
            uuids.push(blocks[i].uuid + ' | ' + blocks[i].content.substring(0, 40));
          }
        }
        this.suggestions = uuids.slice(0, 8);
      }
    } else if (this.triggerType === 'tag') {
      const allTags = ws.getAllTags();
      const filtered: string[] = [];
      for (let i = 0; i < allTags.length; i++) {
        if (allTags[i].toLowerCase().indexOf(this.filterText.toLowerCase()) !== -1 ||
            this.filterText === '') {
          filtered.push(allTags[i]);
        }
      }
      this.suggestions = filtered.slice(0, 8);
    }
  }

  build() {
    if (this.suggestions.length === 0 && this.filterText !== '') {
      Column()
        .width(0)
        .height(0)
    } else {
      Column({ space: 0 }) {
        ForEach(this.suggestions, (item: string) => {
          Row({ space: 8 }) {
            if (this.triggerType === 'page') {
              TablerIcon('file', 14, $r('app.color.link'))
            } else if (this.triggerType === 'block') {
              TablerIcon('arrow-right', 14, $r('app.color.primary'))
            } else {
              TablerIcon('hash', 14, $r('app.color.success'))
            }
            Text(item)
              .fontSize(13)
              .fontColor($r('app.color.text'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .height(36)
          .padding({ left: 10, right: 10 })
          .borderRadius(4)
          .onClick(() => {
            if (this.triggerType === 'block') {
              const uuid = item.substring(0, 36);
              this.onSelect(uuid);
            } else {
              this.onSelect(item);
            }
          })
        }, (item: string) => item)

        if (this.filterText !== '' && this.suggestions.length === 0) {
          Row({ space: 8 }) {
            TablerIcon('plus', 14, $r('app.color.primary'))
            Text('创建: ' + this.filterText)
              .fontSize(13)
              .fontColor($r('app.color.primary'))
          }
          .width('100%')
          .height(36)
          .padding({ left: 10, right: 10 })
          .borderRadius(4)
          .onClick(() => {
            this.onSelect(this.filterText);
          })
        }
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      .backgroundColor($r('app.color.surface1'))
      .borderRadius(6)
      .border({ width: 1, color: $r('app.color.border') })
    }
  }
}
