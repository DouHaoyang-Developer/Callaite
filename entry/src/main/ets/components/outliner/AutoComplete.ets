import { WorkspaceService } from '../../services/WorkspaceService';
import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';

/**
 * AutoCompleteItem — 自动补全条目。
 *
 * type 取值：
 *  - 'page'  页面名补全（[[pageName]]）
 *  - 'block' Block 引用补全（((uuid))）
 *  - 'tag'   标签补全（#tagName）
 */
export interface AutoCompleteItem {
  /** 主文本：页面名 / Block UUID / 标签名 */
  text: string;
  /** 副标题：类型说明或内容预览 */
  subtitle: string;
  /** 条目类型 */
  type: 'page' | 'block' | 'tag';
}

/**
 * 根据补全条目类型返回应插入的文本。
 *  page → [[text]]，block → ((text))，tag → #text
 */
export function formatAutoCompleteInsertion(item: AutoCompleteItem): string {
  if (item.type === 'page') {
    return '[[' + item.text + ']]';
  }
  if (item.type === 'block') {
    return '((' + item.text + '))';
  }
  return '#' + item.text;
}

/**
 * AutoComplete — 自动补全建议面板。
 *
 * 当用户在 TextArea 中输入 [[、((、# 时触发。
 * 显示匹配的页面名 / Block UUID / 标签，点击或 Enter 后替换触发词。
 *
 * 触发映射：
 *  - '[[[' → 页面名补全（搜索 WorkspaceService.getAllPages()）
 *  - '(('  → Block 引用补全（当前页所有 Block）
 *  - '#'   → 标签补全（搜索 WorkspaceService.getAllTags()）
 *
 * 特性：
 *  - 模糊匹配输入文字（大小写不敏感子串匹配）
 *  - 浮动下拉框（Stack 叠加样式，阴影 + 圆角边框）
 *  - 每项：图标 + 文本 + 类型标签
 *  - 上下键导航 + Enter 确认 + Esc 取消（由父组件调用下方导航方法）
 *  - 最多显示 8 项
 */
@Component
export struct AutoComplete {
  /** 当前 Block UUID（用于 (( 块引用时排除自身） */
  @Prop blockUuid: string = '';
  /** 触发字符：'[[', '((', '#' */
  @Prop @Watch('onTriggerChange') trigger: string = '';
  /** 搜索词 */
  @Prop @Watch('onTriggerChange') query: string = '';
  /** 选中回调，返回补全条目 */
  onSelect: (item: AutoCompleteItem) => void = (_i: AutoCompleteItem) => {};
  /** 取消回调（Esc / 失焦） */
  onDismiss: () => void = () => {};

  /** 补全条目列表 */
  @State items: AutoCompleteItem[] = [];
  /** 当前选中索引 */
  @State selectedIndex: number = 0;

  aboutToAppear(): void {
    this.loadItems();
  }

  /**
   * trigger / query 变化时重新加载建议并重置选中项。
   */
  onTriggerChange(): void {
    this.loadItems();
  }

  /**
   * 根据 trigger 与 query 加载补全条目，最多 8 项。
   */
  loadItems(): void {
    const triggerType: string = this.triggerToType(this.trigger);
    const newItems: AutoCompleteItem[] = [];
    if (triggerType === 'page') {
      this.loadPageItems(this.query, newItems);
    } else if (triggerType === 'block') {
      this.loadBlockItems(this.query, newItems);
    } else if (triggerType === 'tag') {
      this.loadTagItems(this.query, newItems);
    }
    this.items = newItems;
    if (this.selectedIndex >= this.items.length) {
      this.selectedIndex = 0;
    }
  }

  /**
   * '[[[' → 'page', '((' → 'block', '#' → 'tag'，其余返回 ''。
   */
  private triggerToType(t: string): string {
    if (t === '[[') {
      return 'page';
    }
    if (t === '((') {
      return 'block';
    }
    if (t === '#') {
      return 'tag';
    }
    return '';
  }

  /**
   * 加载页面名补全条目（模糊匹配 originalName）。
   */
  private loadPageItems(query: string, out: AutoCompleteItem[]): void {
    const ws = WorkspaceService.getInstance();
    const pages = ws.getAllPages();
    const lower = query.toLowerCase();
    for (let i = 0; i < pages.length; i++) {
      if (out.length >= 8) {
        break;
      }
      const name = pages[i].originalName;
      if (lower === '' || name.toLowerCase().indexOf(lower) !== -1) {
        out.push({ text: name, subtitle: '页面', type: 'page' });
      }
    }
  }

  /**
   * 加载 Block 引用补全条目（当前页所有 Block，排除自身）。
   */
  private loadBlockItems(query: string, out: AutoCompleteItem[]): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(AppState.getCurrentPage());
    if (!page) {
      return;
    }
    const blocks = ws.getPageBlocks(page.uuid);
    const lower = query.toLowerCase();
    for (let i = 0; i < blocks.length; i++) {
      if (out.length >= 8) {
        break;
      }
      const b = blocks[i];
      if (b.uuid === this.blockUuid) {
        continue;
      }
      const content = b.content;
      if (lower === '' ||
          content.toLowerCase().indexOf(lower) !== -1 ||
          b.uuid.toLowerCase().indexOf(lower) !== -1) {
        const preview = content.length > 40 ? content.substring(0, 40) + '…' : content;
        out.push({ text: b.uuid, subtitle: preview, type: 'block' });
      }
    }
  }

  /**
   * 加载标签补全条目（模糊匹配标签名）。
   */
  private loadTagItems(query: string, out: AutoCompleteItem[]): void {
    const ws = WorkspaceService.getInstance();
    const tags = ws.getAllTags();
    const lower = query.toLowerCase();
    for (let i = 0; i < tags.length; i++) {
      if (out.length >= 8) {
        break;
      }
      const tag = tags[i];
      if (lower === '' || tag.toLowerCase().indexOf(lower) !== -1) {
        out.push({ text: tag, subtitle: '标签', type: 'tag' });
      }
    }
  }

  // ─── 键盘导航方法（由父组件调用） ───

  /** 上移选中（循环） */
  moveUp(): void {
    if (this.items.length === 0) {
      return;
    }
    this.selectedIndex = this.selectedIndex <= 0
      ? this.items.length - 1
      : this.selectedIndex - 1;
  }

  /** 下移选中（循环） */
  moveDown(): void {
    if (this.items.length === 0) {
      return;
    }
    this.selectedIndex = this.selectedIndex >= this.items.length - 1
      ? 0
      : this.selectedIndex + 1;
  }

  /** Enter 确认当前选中条目 */
  confirmSelection(): void {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.items.length) {
      return;
    }
    this.onSelect(this.items[this.selectedIndex]);
  }

  /** Esc 取消 */
  dismiss(): void {
    this.onDismiss();
  }

  /**
   * 类型显示标签。
   */
  private typeLabel(type: string): string {
    if (type === 'page') {
      return 'PAGE';
    }
    if (type === 'block') {
      return 'BLOCK';
    }
    if (type === 'tag') {
      return 'TAG';
    }
    return '';
  }

  build() {
    // 空查询且无建议时不渲染任何内容
    if (this.items.length === 0 && this.query === '') {
      Column()
        .width(0)
        .height(0)
    } else {
      Column({ space: 0 }) {
        ForEach(this.items, (item: AutoCompleteItem, index: number) => {
          Row({ space: 8 }) {
            // 图标（按类型区分）
            if (item.type === 'page') {
              TablerIcon('file', 14, $r('app.color.link'))
            } else if (item.type === 'block') {
              TablerIcon('arrow-right', 14, $r('app.color.primary'))
            } else {
              TablerIcon('hash', 14, $r('app.color.success'))
            }

            // 主文本
            Text(item.text)
              .fontSize(13)
              .fontColor($r('app.color.text'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            // 类型标签
            Text(this.typeLabel(item.type))
              .fontSize(10)
              .fontColor($r('app.color.muted_text'))
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(3)
              .backgroundColor($r('app.color.surface2'))
          }
          .width('100%')
          .height(36)
          .padding({ left: 10, right: 10 })
          .borderRadius(4)
          .backgroundColor(index === this.selectedIndex
            ? $r('app.color.surface2')
            : $r('app.color.surface1'))
          .onClick(() => {
            this.selectedIndex = index;
            this.onSelect(item);
          })
        }, (item: AutoCompleteItem) => item.type + ':' + item.text)

        // 空状态：创建新条目
        if (this.query !== '' && this.items.length === 0) {
          Row({ space: 8 }) {
            TablerIcon('plus', 14, $r('app.color.primary'))
            Text('创建: ' + this.query)
              .fontSize(13)
              .fontColor($r('app.color.primary'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.typeLabel(this.triggerToType(this.trigger)))
              .fontSize(10)
              .fontColor($r('app.color.muted_text'))
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(3)
              .backgroundColor($r('app.color.surface2'))
          }
          .width('100%')
          .height(36)
          .padding({ left: 10, right: 10 })
          .borderRadius(4)
          .backgroundColor($r('app.color.surface2'))
          .onClick(() => {
            const triggerType = this.triggerToType(this.trigger);
            let itemType: 'page' | 'block' | 'tag' = 'page';
            if (triggerType === 'block') {
              itemType = 'block';
            } else if (triggerType === 'tag') {
              itemType = 'tag';
            }
            const newItem: AutoCompleteItem = {
              text: this.query,
              subtitle: '',
              type: itemType
            };
            this.onSelect(newItem);
          })
        }
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      .backgroundColor($r('app.color.surface1'))
      .borderRadius(6)
      .border({ width: 1, color: $r('app.color.border') })
      .shadow({ radius: 8, color: '#00000020' })
    }
  }
}
