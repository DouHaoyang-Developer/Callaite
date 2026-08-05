import { EditorService } from '../../services/EditorService';
import { WorkspaceService } from '../../services/WorkspaceService';
import { AppState } from '../../state/AppState';

/**
 * MobileToolbarButton — 工具栏按钮配置。
 */
interface MobileToolbarButton {
  id: string;
  label: string;
}

/**
 * 工具栏按钮列表（顺序即显示顺序）。
 *  加粗(B) 斜体(I) 划线(S) 代码(</>) 链接([) TODO(☐)
 *  缩进(→) 反缩进(←) 上移(↑) 下移(↓) 撤销(↶) 重做(↷)
 */
const MOBILE_TOOLBAR_BUTTONS: MobileToolbarButton[] = [
  { id: 'bold', label: 'B' },
  { id: 'italic', label: 'I' },
  { id: 'strike', label: 'S' },
  { id: 'code', label: '</>' },
  { id: 'link', label: '[' },
  { id: 'todo', label: '☐' },
  { id: 'indent', label: '→' },
  { id: 'outdent', label: '←' },
  { id: 'up', label: '↑' },
  { id: 'down', label: '↓' },
  { id: 'undo', label: '↶' },
  { id: 'redo', label: '↷' }
];

/**
 * MobileToolbar — 移动端底部浮动工具栏。
 *
 * 提供常用 Markdown 格式化与 Block 操作按钮，横向可滚动。
 * 按钮为圆形（surface2 背景），浮动于底部（Stack + Bottom 对齐）。
 * 操作后自动调用 AppState.bumpBlocksVersion() 刷新 UI。
 *
 * 用法：父组件持有引用后调用 show()/hide() 控制显隐。
 */
@Component
export struct MobileToolbar {
  @Prop pageId: string = '';
  @State isVisible: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.isVisible) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(MOBILE_TOOLBAR_BUTTONS, (btn: MobileToolbarButton) => {
              Button() {
                Text(btn.label)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text'))
              }
              .width(40)
              .height(40)
              .type(ButtonType.Circle)
              .backgroundColor($r('app.color.surface2'))
              .onClick(() => {
                this.handleAction(btn.id);
                AppState.bumpBlocksVersion();
              })
            }, (btn: MobileToolbarButton) => btn.id)
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .backgroundColor($r('app.color.surface1'))
        .border({ width: 1, color: $r('app.color.border') })
        .shadow({ radius: 8, color: '#00000020' })
      }
    }
    .width('100%')
    .height(this.isVisible ? 56 : 0)
  }

  /**
   * 根据按钮 id 分发操作到对应的 EditorService 方法。
   */
  handleAction(id: string): void {
    if (id === 'bold') {
      this.wrapSelection('**', '**');
    } else if (id === 'italic') {
      this.wrapSelection('*', '*');
    } else if (id === 'strike') {
      this.wrapSelection('~~', '~~');
    } else if (id === 'code') {
      this.wrapSelection('`', '`');
    } else if (id === 'link') {
      this.insertLink();
    } else if (id === 'todo') {
      this.toggleTodo();
    } else if (id === 'indent') {
      this.indent();
    } else if (id === 'outdent') {
      this.outdent();
    } else if (id === 'up') {
      this.moveUp();
    } else if (id === 'down') {
      this.moveDown();
    } else if (id === 'undo') {
      this.undo();
    } else if (id === 'redo') {
      this.redo();
    }
  }

  /**
   * 用前后缀包裹当前焦点 Block 的内容。
   */
  private wrapSelection(prefix: string, suffix: string): void {
    const editor = EditorService.getInstance();
    const uuid = editor.getFocusedBlockUuid();
    if (!uuid) {
      return;
    }
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(uuid);
    if (!block) {
      return;
    }
    const newContent = prefix + block.content + suffix;
    editor.updateBlockContent(uuid, newContent);
  }

  /** 插入链接 [] */
  private insertLink(): void {
    const editor = EditorService.getInstance();
    const uuid = editor.getFocusedBlockUuid();
    if (!uuid) {
      return;
    }
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(uuid);
    if (!block) {
      return;
    }
    editor.updateBlockContent(uuid, block.content + '[]');
  }

  /** TODO 标记循环（无 → TODO → DOING → DONE → 无） */
  private toggleTodo(): void {
    EditorService.getInstance().cycleMarker();
  }

  /** 缩进（Tab 语义） */
  private indent(): void {
    EditorService.getInstance().indentBlock();
  }

  /** 反缩进（Shift+Tab 语义） */
  private outdent(): void {
    EditorService.getInstance().outdentBlock();
  }

  /** 上移当前焦点 Block */
  private moveUp(): void {
    EditorService.getInstance().moveBlockUp();
  }

  /** 下移当前焦点 Block */
  private moveDown(): void {
    EditorService.getInstance().moveBlockDown();
  }

  /** 撤销 */
  private undo(): void {
    EditorService.getInstance().undo();
  }

  /** 重做 */
  private redo(): void {
    EditorService.getInstance().redo();
  }

  /** 显示工具栏 */
  show(): void {
    this.isVisible = true;
  }

  /** 隐藏工具栏 */
  hide(): void {
    this.isVisible = false;
  }
}
