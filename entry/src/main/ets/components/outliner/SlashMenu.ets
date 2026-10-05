import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';
import { TemplateService, TemplateInfo } from '../../services/TemplateService';
import { AppState } from '../../state/AppState';
import { TablerIcon } from '../common/Icons';
import { OverlayKeyRouter, OverlayId, OverlayKeyBinding } from '../../utils/OverlayKeyRouter';
import { KeyCode } from '@kit.InputKit';
import { promptAction } from '@kit.ArkUI';

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
  // U2.3：`Ctrl+P = 循环优先级` 让位给「快速切换」后，循环动作落到这里（计划 §U2.3：
  // 「移入 SlashMenu 命令『切换优先级 A/B/C』——块级操作归块上下文」）。
  // 放在 A/B/C 之后（而不是之前）：三个绝对设置项是「一屏内直接点」的主路径，
  // 循环是「连按多次」的次路径；且在过滤「优先级」时它同样可见、可达。
  { id: 'priority-cycle', name: '切换优先级', icon: 'refresh', description: '循环切换（A → B → C → 无）', category: 'priority', keywords: 'priority 优先级 cycle 循环 切换 toggle' },

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
  @State showTemplateList: boolean = false;
  @State templates: TemplateInfo[] = [];
  /**
   * 扁平命令序列（`filteredGroups` 展开，**只含命令行、不含分类标题行**）。
   * 键盘导航的下标空间就是它 —— 分类标题不可选中，故不进下标空间；
   * 跨分类移动即「分类间跳转」（分类边界由命令顺序自然决定）。
   */
  @State flatCommands: SlashCommand[] = [];
  /** 当前高亮的命令在 `flatCommands` 中的下标（clamp 之后，任何时刻指向真实存在的行） */
  @State selectedIndex: number = 0;
  /** 命令列表滚动控制器（把高亮行滚入视口） */
  private listScroller: Scroller = new Scroller();
  /**
   * 行 id → 该行相对**滚动内容顶部**的 y（由各行的 onAreaChange 回填，单位 vp）。
   *
   * 为什么需要它：宿主是 `Scroll`，而 `Scroller.scrollToIndex` 的 NOTE 只对
   * ArcList/Grid/List/WaterFlow 生效、**不含 Scroll**（SDK scroll.d.ts:488）⇒
   * 「高亮行滚入视口」只能自己按行 y 调 `scrollTo({yOffset})`。
   * 行 y 取自布局实测（onAreaChange 的 area.position.y，相对父容器 = 滚动内容），
   * 不靠「行高 × 下标」估算 —— 分类标题行高度与命令行(48vp)不同，估算必然偏。
   */
  private rowTops: Map<string, number> = new Map<string, number>();

  /** 菜单卡片宽度（vp）。见 build() 里为什么必须自持宽度。 */
  private static readonly MENU_WIDTH: number = 320;

  aboutToAppear(): void {
    // U2.2/W11：登记进按键路由器并声明「已打开」。
    // U2.3：触发源已接线（BlockView 行内入口 + BlockList 页面级入口）—— 本组件只在这些
    //       入口把 `AppState.openSlashMenu(uuid)` 的**开合态**置 true 时才被宿主构造。
    // 开合态登记必须与「组件是否在树上」一致：宿主在关闭时就会卸载本组件，
    // 故 `aboutToDisappear` 里注销即等价于「菜单已关」。
    const router = OverlayKeyRouter.getInstance();
    router.registerOverlay(OverlayId.SLASH_MENU, new OverlayKeyBinding((keyCode: number, event: KeyEvent) => {
      return this.applyNavKey(keyCode);
    }));
    router.setOverlayOpen(OverlayId.SLASH_MENU, true);
    this.filterCommands('');
  }

  aboutToDisappear(): void {
    OverlayKeyRouter.getInstance().unregisterOverlay(OverlayId.SLASH_MENU);
  }

  /**
   * 关闭菜单。
   *
   * U2.3 修法（此前是「关不干净」）：**开合态写回 AppStorage**，由宿主 BlockList
   * 卸载本组件。旧实现只置内部 `dismissed = true` 把组件画成 0×0 —— 组件仍挂在树上，
   * 于是「视觉已关」与「按键路由仍认为开着」可以分叉（本组件自己那次
   * `setOverlayOpen(false)` 是唯一补救，任何一条绕过它的路径都会留下吞键的幽灵浮层）。
   * 现在只有一份状态：组件在树上 ⇔ 菜单开着。
   */
  private dismissMenu(): void {
    AppState.closeSlashMenu();
  }

  /**
   * 按键 → 动作（U2.2/W11 新增；迁移前本组件**没有任何键盘处理**）。
   * 语义与 CommandPalette/SearchPanel 对齐：↑↓ 移动 / ↵ 执行 / esc 关闭。
   * 模板子视图只接 esc（返回命令列表）—— 子视图内的列表导航留给触发源接线那一轮。
   */
  private applyNavKey(keyCode: number): boolean {
    if (this.showTemplateList) {
      if (keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.showTemplateList = false;
        return true;
      }
      return false;
    }
    if (keyCode === KeyCode.KEYCODE_DPAD_UP) {
      this.moveSelection(-1);
      return true;
    }
    if (keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      this.moveSelection(1);
      return true;
    }
    if (keyCode === KeyCode.KEYCODE_ENTER || keyCode === KeyCode.KEYCODE_NUMPAD_ENTER) {
      this.executeSelected();
      return true;
    }
    if (keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.dismissMenu();
      return true;
    }
    return false;
  }

  /** 移动高亮。到底/到顶后停在边界（不做环绕，避免误触回到底部）。 */
  private moveSelection(delta: number): void {
    const count: number = this.flatCommands.length;
    if (count === 0) {
      return;
    }
    let next: number = this.selectedIndex + delta;
    if (next < 0) {
      next = 0;
    }
    if (next > count - 1) {
      next = count - 1;
    }
    if (next === this.selectedIndex) {
      return;
    }
    this.selectedIndex = next;
    this.scrollSelectionIntoView();
  }

  /** 执行当前高亮的命令（越界时无动作 —— 空结果只有「无匹配命令」提示行，不可选）。 */
  private executeSelected(): void {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.flatCommands.length) {
      return;
    }
    this.executeCommand(this.flatCommands[this.selectedIndex]);
  }

  /**
   * 把高亮行滚入视口（含 48vp 余量，让选中项不贴边）。
   * 行 y 由 onAreaChange 实测回填；未实测到（尚未布局）时不动 —— 不猜。
   */
  private scrollSelectionIntoView(): void {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.flatCommands.length) {
      return;
    }
    const top = this.rowTops.get(this.flatCommands[this.selectedIndex].id);
    if (top === undefined) {
      return;
    }
    let yOffset: number = top - 48;
    if (yOffset < 0) {
      yOffset = 0;
    }
    // ScrollOptions 的 xOffset 是必填项（SDK scroll.d.ts:648-689），横向不动传 0。
    this.listScroller.scrollTo({ xOffset: 0, yOffset: yOffset });
  }

  /** 命令行的扁平下标（用于高亮判定）；不在当前过滤结果中时返回 -1。 */
  private flatIndexOf(cmd: SlashCommand): number {
    return this.flatCommands.indexOf(cmd);
  }

  /** 命令行的背景色：键盘选中 > 透明（本组件无 hover 态，触屏不产生 onHover）。 */
  private commandRowBackground(cmd: SlashCommand): ResourceColor {
    if (this.flatIndexOf(cmd) === this.selectedIndex) {
      return $r('app.color.accent_soft');
    }
    return Color.Transparent;
  }

  build() {
    // ⚠️ U2.3：菜单本体必须自持宽度 —— 旧实现用 `.width('100%')`，
    // 而它的宿主是整页 Stack ⇒ 菜单会撑满整页宽（1440vp 的横条），
    // 既不像弹层，也让「滚动/行 y 回填」这些回调满屏铺开。
    // 320vp 与 CommandPalette / SearchPanel 的卡片宽度同一量级。
    Stack() {
      if (this.showTemplateList) {
        this.TemplateListView()
      } else {
        this.CommandListView()
      }
    }
    .width(SlashMenu.MENU_WIDTH)
  }

  @Builder
  TemplateListView() {
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
      .shadow({ radius: 8, color: '#20000000' })
  }

  @Builder
  CommandListView() {
      // ─── 命令列表主视图 ───
      Column() {
        TextInput({ placeholder: '搜索命令...', text: this.filterText })
          .fontSize(14)
          .width('100%')
          .height(40)
          .padding({ left: 12, right: 12 })
          // U2.3：菜单一打开就把焦点交给过滤框（与 CommandPalette「打开时主动 requestFocus」
          // 同一取舍）。不给焦点时焦点留在内容区容器上：↑↓ 仍能被本组件的兜底落点接住
          // （高亮照常移动 ✓），但**回车的归属会错** —— 真实键盘上回车该由持焦输入框的
          // `onSubmit`（输入法处理完之后发出，见 OverlayKeyRouter 类头 §IME 守卫）交付；
          // 焦点在容器上时它既进不了 onSubmit，也不再被全局快捷键抢（那条已由
          // ShortcutService.isOverlayBlockedKey 堵住）⇒ 表现为「按回车没反应」。
          .defaultFocus(true)
          .onChange((value: string, previewText?: PreviewText) => {
            this.filterText = value;
            // U2.2/W11：上报 IME 预览文本 —— 组词态下的回车属于输入法，不得被路由抢走
            // （依据：text_common.d.ts:481 / 625-646，见 OverlayKeyRouter 类头 §SDK 依据）。
            OverlayKeyRouter.getInstance().reportImePreviewText(OverlayId.SLASH_MENU, previewText);
            this.filterCommands(value);
          })
          // ↵ 执行当前高亮命令 —— 走 onSubmit（输入法处理完合成之后才发出），
          // 组词态的回车归输入法上屏（理由与实测见 OverlayKeyRouter 类头 §IME 守卫）。
          .onSubmit(() => {
            this.executeSelected();
          })
          // ⚠️ W11 实测后**不用 `onKeyPreIme`**（理由见 OverlayKeyRouter 类头 §IME 守卫）：
          //    preIme 早于输入法会抢走拼音组词的回车，而组词期间应用收不到合成态信号。
          //    改用 post-IME 的 `onKeyEvent`：输入法先拒绝，它不要的键才轮到本菜单。
          .onKeyEvent((event: KeyEvent) => {
            if (OverlayKeyRouter.getInstance().handle(event, OverlayId.SLASH_MENU)) {
              event.stopPropagation();
            }
          })

        Divider()
          .color($r('app.color.border'))

        Scroll(this.listScroller) {
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
              // 分类标题行：不可选中（不进 flatCommands 下标空间），但它的 y 要登记 ——
              // 「高亮行滚入视口」用的是行 y 实测值，标题行高度与 48vp 命令行不同。
              Text(group.label)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.muted_text'))
                .width('100%')
                .padding({ left: 12, top: 8, bottom: 4 })
                .onAreaChange((_oldArea: Area, newArea: Area) => {
                  this.rowTops.set('header_' + group.category, SlashMenu.areaVp(newArea.position.y));
                })

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
                // 键盘选中行：与 CommandPalette/SearchPanel 同一视觉语言
                // （accent_soft = 选中；本组件无 hover 态 —— 触屏不产生 onHover）。
                .backgroundColor(this.commandRowBackground(cmd))
                .onAreaChange((_oldArea: Area, newArea: Area) => {
                  this.rowTops.set(cmd.id, SlashMenu.areaVp(newArea.position.y));
                })
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
      .shadow({ radius: 8, color: '#20000000' })
      // 兜底落点：焦点不在过滤输入框（如落在列表上）时仍能接管 ↑↓ / ↵ / esc。
      // 与输入框上的回调同走路由器一份去重标记，不会一次按键走两格。
      .onKeyEvent((event: KeyEvent) => {
        if (OverlayKeyRouter.getInstance().handle(event, OverlayId.SLASH_MENU)) {
          event.stopPropagation();
        }
      })
  }

  /**
   * 把 Area 的 Length（string | number | Resource）取成 vp 数值。
   * onAreaChange 在布局回调中给出的 position/height 为 number（vp），
   * 但类型上仍是 Length 联合体，ArkTS 禁用 any，故必须显式收窄
   * （与 BlockDragLayer.toVpNumber / BlockView.areaVp 同一处理）。
   */
  private static areaVp(value: Length | undefined): number {
    if (value === undefined) {
      return 0;
    }
    if (typeof value === 'number') {
      return value;
    }
    return 0;
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
    // 扁平序列 = 键盘导航的下标空间（只含命令行；顺序与渲染顺序一致 ⇒
    // 「分类间跳转」天然成立：跨过分类边界只是下标 +1）。
    // 过滤后高亮必须归零：否则旧下标可能越界或指向另一条命令
    // （与 CommandPalette.doSearch「输入后回车打开了意料之外的页面」同一处理）。
    this.flatCommands = commands;
    this.selectedIndex = 0;
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
      this.dismissMenu();
      return;
    }

    // ─── 优先级 ───
    if (cmd.id === 'priority-a') {
      ws.executeOp({ type: 'set-priority', uuid: this.blockUuid, priority: 'A' });
      this.dismissMenu();
      return;
    }
    if (cmd.id === 'priority-b') {
      ws.executeOp({ type: 'set-priority', uuid: this.blockUuid, priority: 'B' });
      this.dismissMenu();
      return;
    }
    if (cmd.id === 'priority-c') {
      ws.executeOp({ type: 'set-priority', uuid: this.blockUuid, priority: 'C' });
      this.dismissMenu();
      return;
    }
    // U2.3：循环优先级（原 Ctrl+P 动作，迁到块级命令）。
    // 必须按**本菜单持有的 blockUuid** 算下一步 —— 不能转调
    // `EditorService.cyclePriority()`（它只认 focusedBlockUuid，而菜单的
    // blockUuid 来自更可靠的「哪一行的入口被点」（见 BlockList.requestSlashMenu）；
    // 焦点块可能不是本行，转调会改错块）。
    if (cmd.id === 'priority-cycle') {
      this.cyclePriorityForBlock();
      this.dismissMenu();
      return;
    }

    // ─── 日期 ───
    if (cmd.id === 'scheduled') {
      const today = this.getTodayString();
      ws.executeOp({ type: 'set-scheduled', uuid: this.blockUuid, date: today });
      this.dismissMenu();
      return;
    }
    if (cmd.id === 'deadline') {
      const today = this.getTodayString();
      ws.executeOp({ type: 'set-deadline', uuid: this.blockUuid, date: today });
      this.dismissMenu();
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
      this.dismissMenu();
      return;
    }
    if (cmd.id === 'block-ref') {
      this.insertText('((');
      this.dismissMenu();
      return;
    }

    // ─── 媒体 ───
    if (cmd.id === 'image') {
      this.insertText('![]()');
      this.dismissMenu();
      return;
    }
    if (cmd.id === 'code-block') {
      this.insertText('\n```\n```\n');
      this.dismissMenu();
      return;
    }
    if (cmd.id === 'embed') {
      this.insertText('{{embed ');
      this.dismissMenu();
      return;
    }

    // ─── 查询 ───
    if (cmd.id === 'query') {
      this.insertText('{{query: }}');
      this.dismissMenu();
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
      this.dismissMenu();
      return;
    }

    // ─── 新建页面 ───
    if (cmd.id === 'new-page') {
      const pageName = '新页面 ' + this.getTodayString();
      // S4-W27（H2）：原先**丢弃** OpResult ⇒ 名字碰撞被拒时仍会把当前页切到
      // 一个并不存在的页面上。现在必须判成败：失败则不动当前页、给出可见反馈。
      // 提示机制沿用本仓既有的 promptAction.openToast（全仓 30 处在用）。
      const r = ws.executeOp({
        type: 'new-page',
        name: pageName,
        originalName: pageName
      });
      if (!r.success) {
        promptAction.openToast({
          message: '已存在同名文件，未创建：「' + pageName + '」'
        }).catch(() => {});
        this.dismissMenu();
        return;
      }
      AppState.setCurrentPage(pageName);
      this.dismissMenu();
      return;
    }

    this.dismissMenu();
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
    this.dismissMenu();
  }

  /**
   * 循环切换本块的优先级：无 → A → B → C → 无。
   *
   * 判据与 `EditorService.cyclePriority()` **逐条一致**（同样的四段递进与兜底），
   * 唯一差别是「作用在哪一块」：这里按本菜单的 `blockUuid` 取块，
   * 而 EditorService 那个按 `focusedBlockUuid` 取。菜单必须用前者 ——
   * 入口来自「哪一行的命令按钮被点」，与编辑器焦点无关。
   */
  cyclePriorityForBlock(): void {
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(this.blockUuid);
    if (!block) {
      return;
    }

    let nextPriority = '';
    if (block.priority === '') {
      nextPriority = 'A';
    } else if (block.priority === 'A') {
      nextPriority = 'B';
    } else if (block.priority === 'B') {
      nextPriority = 'C';
    } else if (block.priority === 'C') {
      nextPriority = '';
    } else {
      nextPriority = 'A';
    }

    ws.executeOp({ type: 'set-priority', uuid: block.uuid, priority: nextPriority });
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
