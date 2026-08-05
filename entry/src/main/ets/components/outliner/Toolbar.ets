import { TablerIcon } from '../common/Icons';
import { EditorService } from '../../services/EditorService';

/**
 * Toolbar — 编辑器浮动工具栏。
 * 提供撤销/重做按钮。
 */
@Component
export struct Toolbar {
  @State canUndo: boolean = false;
  @State canRedo: boolean = false;

  aboutToAppear(): void {
    this.refreshState();
  }

  /**
   * 页面显示时刷新撤销/重做状态。
   * 修复：此前未调用 refreshState()，canUndo/canRedo 始终为 false，工具栏永远不显示。
   */
  onPageShow(): void {
    this.refreshState();
  }

  build() {
    if (!this.canUndo && !this.canRedo) {
      Row().width(0).height(0)
    } else {
      Row({ space: 4 }) {
        Button() {
          Row({ space: 4 }) {
            TablerIcon('arrow-left', 13, this.canUndo ? $r('app.color.text') : '#D1D5DB')
          }
        }
        .width(28).height(28).type(ButtonType.Circle).backgroundColor('#F3F4F6')
        .enabled(this.canUndo)
        .onClick(() => {
          const editor = EditorService.getInstance();
          editor.undo();
          this.refreshState();
        })

        Button() {
          Row({ space: 4 }) {
            TablerIcon('arrow-right', 13, this.canRedo ? $r('app.color.text') : '#D1D5DB')
          }
        }
        .width(28).height(28).type(ButtonType.Circle).backgroundColor('#F3F4F6')
        .enabled(this.canRedo)
        .onClick(() => {
          const editor = EditorService.getInstance();
          editor.redo();
          this.refreshState();
        })
      }
      .padding({ left: 4, right: 4, top: 2, bottom: 2 })
      .borderRadius(6)
      .backgroundColor($r('app.color.surface0'))
      .shadow({ radius: 4, color: '#00000010' })
    }
  }

  refreshState(): void {
    const editor = EditorService.getInstance();
    this.canUndo = editor.canUndo();
    this.canRedo = editor.canRedo();
  }
}
