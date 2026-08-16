import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';
import { TemplateService, TemplateInfo } from '../../services/TemplateService';
import { AppState } from '../../state/AppState';
import { TablerIcon } from '../common/Icons';

/**
 * SlashCommand — 斜杠菜单命令定义。
 */
interface SlashCommand {
  id: string;
  name: string;
  icon: string;
  description: string;
  category: string;
  keywords: string;
}

/**
 * CommandGroup — 命令分组（按 category 聚合）。
 */
interface CommandGroup {
  category: string;
  label: string;
  commands: SlashCommand[];
}

/**
 * 全部斜杠命令列表（按分类顺序排列）。
 */
const ALL_COMMANDS: SlashCommand[] = [
  // ─── 基础标记 ───
  { id: 'todo', name: 'TODO', icon: 'circle-minus', description: '添加待办事项', category: 'marker', keywords: 'todo task 待办' },
  { id: 'doing', name: 'DOING', icon: 'player-play', description: '添加进行中', category: 'marker', keywords: 'doing progress 进行' },
  { id: 'done', name: 'DONE', icon: 'check', description: '添加已完成', category: 'marker', keywords: 'done complete 完成' },
  { id: 'cancelled', name: 'CANCELLED', icon: 'x', description: '添加已取消', category: 'marker', keywords: 'cancelled cancel 取消' },
  { id: 'later', name: 'LATER', icon: 'calendar', description: '稍后处理', category: 'marker', keywords: 'later 稍后' },
  { id: 'now', name: 'NOW', icon: 'bolt', description: '现在处理', category: 'marker', keywords: 'now 当前' },

  // ─── 优先级 ───
  { id: 'priority-a', name: 'Priority A', icon: 'bolt', description: '设置优先级 A（高）', category: 'priority', keywords: 'priority 优先级 a high 高' },
  { id: 'priority-b', name: 'Priority B', icon: 'hash', description: '设置优先级 B（中）', category: 'priority', keywords: 'priority 优先级 b medium 中' },
  { id: 'priority-c', name: 'Priority C', icon: 'circle-minus', description: '设置优先级 C（低）', category: 'priority', keywords: 'priority 优先级 c low 低' },

  // ─── 日期 ───
  { id: 'scheduled', name: 'SCHEDULED', icon: 'calendar-plus', description: '设置计划日期', category: 'date', keywords: 'scheduled date 计划 日期' },
  { id: 'deadline', name: 'DEADLINE', icon: 'alert-triangle', description: '设置截止日期', category: 'date', keywords: 'deadline 截止 日期' },

  // ─── 模板 ───
  { id: 'template', name: 'Template', icon: 'file-code', description: '插入模板', category: 'template', keywords: 'template 模板' },

  // ─── 引用 ───
  { id: 'page-ref', name: 'Page Reference', icon: 'external-link', description: '插入页面引用 [[', category: 'reference', keywords: 'page reference link 页面 引用 链接' },
  { id: 'block-ref', name: 'Block Reference', icon: 'file-symlink', description: '插入 Block 引用 ((', category: 'reference', keywords: 'block reference 引用' },

  // ─── 媒体 ───
  { id: 'image', name: 'Image', icon: 'file-upload', description: '插入图片', category: 'media', keywords: 'image picture 图片 照片' },
  { id: 'code-block', name: 'Code Block', icon: 'source-code', description: '插入代码块', category: 'media', keywords: 'code 代码 block 块' },
  { id: 'embed', name: 'Embed', icon: 'file-symlink', description: '嵌入内容', category: 'media', keywords: 'embed 嵌入' },

  // ─── 查询 ───
  { id: 'query', name: 'Query', icon: 'search', description: '插入查询', category: 'query', keywords: 'query search 查询 搜索' },

  // ─── 属性 ───
  { id: 'add-property', name: 'Add Property', icon: 'list-details', description: '添加属性', category: 'property', keywords: 'property attribute 属性' },

  // ─── 页面 ───
  { id: 'new-page', name: 'New Page', icon: 'plus', description: '新建页面', category: 'page', keywords: 'new page 新建 页面' }
];

/**
 * 获取分类的中文标签。
 */
function getCategoryLabel(category: string): string {
  if (category === 'marker') {
    return '基础标记';
  }
  if (category === 'priority') {
    return '优先级';
  }
  if (category === 'date') {
    return '日期';
  }
  if (category === 'template') {
    return '模板';
  }
  if (category === 'reference') {
    return '引用';
  }
  if (category === 'media') {
    return '媒体';
  }
  if (category === 'query') {
    return '查询';
  }
  if (category === 'property') {
    return '属性';
  }
  if (category === 'page') {
    return '页面';
  }
  return category;
}

/**
 * SlashMenu — 斜杠命令菜单组件。
 *
 * 在 Block 编辑器中输入 "/" 时触发，提供快捷命令选择。
 * 支持搜索过滤、分类分组显示、模板选择子视图。
 *
 * 命令分类：
 *   基础标记（TODO/DOING/DONE/CANCELLED/LATER/NOW）
 *   优先级（A/B/C）
 *   日期（SCHEDULED/DEADLINE）
 *   模板（插入预置模板）
 *   引用（页面引用 [[ / Block 引用 ((）
 *   媒体（图片 / 代码块 / 嵌入）
 *   查询（插入 {{query:}}）
 *   属性（添加 key:: value）
 *   页面（新建页面）
 */
@Component
export struct SlashMenu {
  @Prop blockUuid: string = '';
  @State filterText: string = '';
  @State filteredGroups: CommandGroup[] = [];
  @State dismissed: boolean = false;
  @State showTemplateList: boolean = false;
  @State templates: TemplateInfo[] = [];

  aboutToAppear(): void {
    this.filterCommands('');
  }

  build() {
    if (this.dismissed) {
      Column().width(0).height(0)
    } else if (this.showTemplateList) {
      // ─── 模板选择子视图 ───
      Column() {
        Row({ space: 8 }) {
          TablerIcon('chevron-left', 16, $r('app.color.text'))
          Text('选择模板')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text'))
        }
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          this.showTemplateList = false;
        })

        Divider()
          .color($r('app.color.border'))

        Scroll() {
          Column({ space: 0 }) {
            ForEach(this.templates, (tpl: TemplateInfo) => {
              Row({ space: 10 }) {
                TablerIcon(tpl.icon, 18, $r('app.color.text'))
                Column({ space: 2 }) {
                  Text(tpl.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text'))
                  Text(tpl.content.substring(0, 40))
                    .fontSize(11)
                    .fontColor($r('app.color.muted_text'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .height(52)
              .padding({ left: 12, right: 12 })
              .borderRadius(6)
              .onClick(() => {
                this.insertTemplate(tpl);
              })
            }, (tpl: TemplateInfo) => tpl.name)
          }
          .width('100%')
        }
        .width('100%')
        .height(240)
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })
      .backgroundColor($r('app.color.surface1'))
      .borderRadius(8)
      .shadow({ radius: 8, color: '#00000020' })
    } else {
      // ─── 命令列表主视图 ───
      Column() {
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

        Scroll() {
          Column({ space: 0 }) {
            if (this.filteredGroups.length === 0) {
              Text('无匹配命令')
                .fontSize(13)
                .fontColor($r('app.color.muted_text'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 24, bottom: 24 })
            }
            ForEach(this.filteredGroups, (group: CommandGroup) => {
              Text(group.label)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.muted_text'))
                .width('100%')
                .padding({ left: 12, top: 8, bottom: 4 })

              ForEach(group.commands, (cmd: SlashCommand) => {
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
              }, (cmd: SlashCommand) => cmd.id)
            }, (group: CommandGroup) => group.category)
          }
          .width('100%')
        }
        .width('100%')
        .height(300)
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })
      .backgroundColor($r('app.color.surface1'))
      .borderRadius(8)
      .shadow({ radius: 8, color: '#00000020' })
    }
  }

  /**
   * 根据搜索文本过滤命令，并按分类分组。
   */
  filterCommands(filter: string): void {
    let commands: SlashCommand[] = ALL_COMMANDS;

    if (filter !== '') {
      const lower = filter.toLowerCase();
      commands = [];
      for (let i = 0; i < ALL_COMMANDS.length; i++) {
        const cmd = ALL_COMMANDS[i];
        if (cmd.name.toLowerCase().indexOf(lower) !== -1 ||
            cmd.description.indexOf(filter) !== -1 ||
            cmd.keywords.toLowerCase().indexOf(lower) !== -1) {
          commands.push(cmd);
        }
      }
    }

    // 按 category 分组
    const groups: CommandGroup[] = [];
    for (let i = 0; i < commands.length; i++) {
      const cmd = commands[i];
      let groupIndex = -1;
      for (let j = 0; j < groups.length; j++) {
        if (groups[j].category === cmd.category) {
          groupIndex = j;
          break;
        }
      }
      if (groupIndex >= 0) {
        groups[groupIndex].commands.push(cmd);
      } else {
        const newGroup: CommandGroup = {
          category: cmd.category,
          label: getCategoryLabel(cmd.category),
          commands: []
        };
        newGroup.commands.push(cmd);
        groups.push(newGroup);
      }
    }

    this.filteredGroups = groups;
  }

  /**
   * 执行选中的命令。
   */
  executeCommand(cmd: SlashCommand): void {
    const ws = WorkspaceService.getInstance();

    // ─── 基础标记 ───
    if (cmd.id === 'todo' || cmd.id === 'doing' || cmd.id === 'done' ||
        cmd.id === 'cancelled' || cmd.id === 'later' || cmd.id === 'now') {
      ws.executeOp({ type: 'set-marker', uuid: this.blockUuid, marker: cmd.name });
      this.dismissed = true;
      return;
    }

    // ─── 优先级 ───
    if (cmd.id === 'priority-a') {
      ws.executeOp({ type: 'set-priority', uuid: this.blockUuid, priority: 'A' });
      this.dismissed = true;
      return;
    }
    if (cmd.id === 'priority-b') {
      ws.executeOp({ type: 'set-priority', uuid: this.blockUuid, priority: 'B' });
      this.dismissed = true;
      return;
    }
    if (cmd.id === 'priority-c') {
      ws.executeOp({ type: 'set-priority', uuid: this.blockUuid, priority: 'C' });
      this.dismissed = true;
      return;
    }

    // ─── 日期 ───
    if (cmd.id === 'scheduled') {
      const today = this.getTodayString();
      ws.executeOp({ type: 'set-scheduled', uuid: this.blockUuid, date: today });
      this.dismissed = true;
      return;
    }
    if (cmd.id === 'deadline') {
      const today = this.getTodayString();
      ws.executeOp({ type: 'set-deadline', uuid: this.blockUuid, date: today });
      this.dismissed = true;
      return;
    }

    // ─── 模板（切换到模板选择子视图） ───
    if (cmd.id === 'template') {
      this.templates = TemplateService.getBuiltinTemplates();
      this.showTemplateList = true;
      return;
    }

    // ─── 引用 ───
    if (cmd.id === 'page-ref') {
      this.insertText('[[');
      this.dismissed = true;
      return;
    }
    if (cmd.id === 'block-ref') {
      this.insertText('((');
      this.dismissed = true;
      return;
    }

    // ─── 媒体 ───
    if (cmd.id === 'image') {
      this.insertText('![]()');
      this.dismissed = true;
      return;
    }
    if (cmd.id === 'code-block') {
      this.insertText('\n```\n```\n');
      this.dismissed = true;
      return;
    }
    if (cmd.id === 'embed') {
      this.insertText('{{embed ');
      this.dismissed = true;
      return;
    }

    // ─── 查询 ───
    if (cmd.id === 'query') {
      this.insertText('{{query: }}');
      this.dismissed = true;
      return;
    }

    // ─── 属性 ───
    if (cmd.id === 'add-property') {
      ws.executeOp({
        type: 'add-property',
        blockUuid: this.blockUuid,
        name: 'key',
        value: 'value'
      });
      this.dismissed = true;
      return;
    }

    // ─── 新建页面 ───
    if (cmd.id === 'new-page') {
      const pageName = '新页面 ' + this.getTodayString();
      ws.executeOp({
        type: 'new-page',
        name: pageName,
        originalName: pageName
      });
      AppState.setCurrentPage(pageName);
      this.dismissed = true;
      return;
    }

    this.dismissed = true;
  }

  /**
   * 插入选中的模板到当前 Block。
   * 展开模板变量后追加到 Block 内容末尾。
   */
  insertTemplate(tpl: TemplateInfo): void {
    const ws = WorkspaceService.getInstance();
    const editor = EditorService.getInstance();
    const block = ws.getBlock(this.blockUuid);
    const pageId = ws.getPageUuidForBlock(this.blockUuid);

    let pageTitle = '';
    if (pageId) {
      const page = ws.getDataStore().getIndexStore().getPage(pageId);
      if (page) {
        pageTitle = page.originalName;
      }
    }

    const expanded = TemplateService.expand(tpl.content, pageTitle);
    if (block) {
      editor.updateBlockContent(this.blockUuid, block.content + '\n' + expanded);
    }
    this.dismissed = true;
  }

  /**
   * 在当前 Block 内容末尾插入文本。
   * 如果内容不为空且不以空格结尾，自动添加一个空格分隔。
   */
  insertText(text: string): void {
    if (!this.blockUuid) {
      return;
    }
    const ws = WorkspaceService.getInstance();
    const editor = EditorService.getInstance();
    const block = ws.getBlock(this.blockUuid);
    if (!block) {
      return;
    }

    let newContent = block.content;
    if (newContent.length > 0) {
      const lastChar = newContent.charAt(newContent.length - 1);
      if (lastChar !== ' ' && lastChar !== '\n') {
        newContent = newContent + ' ';
      }
    }
    newContent = newContent + text;
    editor.updateBlockContent(this.blockUuid, newContent);
  }

  /**
   * 获取今天的日期字符串（yyyy-MM-dd，本地时区）。
   */
  getTodayString(): string {
    const now = new Date();
    const y = now.getFullYear().toString();
    const m = (now.getMonth() + 1).toString().padStart(2, '0');
    const d = now.getDate().toString().padStart(2, '0');
    return y + '-' + m + '-' + d;
  }
}
