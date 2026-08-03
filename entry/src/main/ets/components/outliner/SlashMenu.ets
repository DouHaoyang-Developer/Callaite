import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';
import { TemplateService, TemplateInfo } from '../../services/TemplateService';
import { TablerIcon } from '../common/Icons';

interface SlashCommand {
  name: string;
  icon: string;
  description: string;
}

const SLASH_COMMANDS: SlashCommand[] = [
  { name: 'TODO', icon: 'circle-minus', description: '添加待办事项' },
  { name: 'DOING', icon: 'player-play', description: '添加进行中' },
  { name: 'DONE', icon: 'check', description: '添加已完成' },
  { name: 'LATER', icon: 'calendar', description: '稍后处理' },
  { name: 'NOW', icon: 'bolt', description: '现在处理' },
  { name: 'Template', icon: 'file-code', description: '插入模板' },
  { name: 'Link', icon: 'external-link', description: '插入链接' },
  { name: 'Embed', icon: 'file-symlink', description: '嵌入内容' },
  { name: 'Date Picker', icon: 'calendar-plus', description: '选择日期' },
  { name: 'Query', icon: 'search', description: '插入查询' }
];

@Component
export struct SlashMenu {
  @Prop blockUuid: string = '';
  @State filterText: string = '';
  @State filteredCommands: SlashCommand[] = SLASH_COMMANDS;
  @State dismissed: boolean = false;
  @State showTemplates: boolean = false;

  build() {
    if (this.dismissed) {
      Column().width(0).height(0)
    } else {
      Column() {
        // 搜索过滤
        TextInput({ placeholder: '搜索命令...', text: this.filterText })
          .fontSize(14)
          .width('100%')
          .height(40)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.filterText = value;
            this.filterCommands(value);
          })

        Divider()
          .color($r('app.color.border'))

        // 命令列表
        Scroll() {
          Column({ space: 0 }) {
            ForEach(this.filteredCommands.slice(0, 8), (cmd: SlashCommand) => {
              Row({ space: 10 }) {
                TablerIcon(cmd.icon, 18, $r('app.color.text'))
                Column({ space: 2 }) {
                  Text(cmd.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text'))
                  Text(cmd.description)
                    .fontSize(12)
                    .fontColor($r('app.color.muted_text'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .height(48)
              .padding({ left: 12, right: 12 })
              .borderRadius(6)
              .onClick(() => {
                this.executeCommand(cmd);
              })
            }, (cmd: SlashCommand) => cmd.name)
          }
          .width('100%')
        }
        .width('100%')
        .height(200)
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })
      .backgroundColor($r('app.color.surface1'))
      .borderRadius(8)
      .shadow({ radius: 8, color: '#00000020' })
    }
  }

  filterCommands(filter: string): void {
    if (filter === '') {
      this.filteredCommands = SLASH_COMMANDS;
      return;
    }
    const lower = filter.toLowerCase();
    const result: SlashCommand[] = [];
    for (let i = 0; i < SLASH_COMMANDS.length; i++) {
      const cmd = SLASH_COMMANDS[i];
      if (cmd.name.toLowerCase().indexOf(lower) !== -1 ||
          cmd.description.indexOf(filter) !== -1) {
        result.push(cmd);
      }
    }
    this.filteredCommands = result;
  }

  executeCommand(cmd: SlashCommand): void {
    const editor = EditorService.getInstance();
    const ws = WorkspaceService.getInstance();

    if (cmd.name === 'TODO' || cmd.name === 'DOING' || cmd.name === 'DONE' ||
        cmd.name === 'LATER' || cmd.name === 'NOW') {
      ws.executeOp({ type: 'set-marker', uuid: this.blockUuid, marker: cmd.name });
    }

    if (cmd.name === 'Date Picker') {
      const today = new Date().toISOString().substring(0, 10);
      ws.executeOp({ type: 'set-scheduled', uuid: this.blockUuid, date: today });
    }

    if (cmd.name === 'Template') {
      const templates = TemplateService.getBuiltinTemplates();
      if (templates.length > 0) {
        const block = ws.getBlock(this.blockUuid);
        const pageId = ws.getPageUuidForBlock(this.blockUuid);
        let pageTitle = '';
        if (pageId) {
          const page = ws.getDataStore().getIndexStore().getPage(pageId);
          if (page) {
            pageTitle = page.originalName;
          }
        }
        const expanded = TemplateService.expand(templates[0].content, pageTitle);
        if (block) {
          editor.updateBlockContent(this.blockUuid, block.content + '\n' + expanded);
        }
      }
      this.dismissed = true;
      return;
    }

    this.dismissed = true;
  }
}
