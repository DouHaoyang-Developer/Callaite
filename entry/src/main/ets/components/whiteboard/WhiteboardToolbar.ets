import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';

/**
 * ToolConfig —— 白板工具定义。
 */
export interface ToolConfig {
  icon: string;
  tool: string;
}

/**
 * WhiteboardToolbar —— 白板顶部工具栏。
 *
 * 对齐华为示例（Penkit.txt / HandWritingComponent）的组件划分方式：
 *   · 薄展示组件：业务状态由父组件（Whiteboard）持有，交互经回调上抛
 *   · 样式统一：40vp 触控热区（官方 7.1.1.3.3）、6vp 圆角、stateStyles 三态、
 *     悬停态、色彩走 app.color token
 */
@Component
export struct WhiteboardToolbar {
  @Link currentTool: string;
  @Prop canUndo: boolean = false;
  @Prop canRedo: boolean = false;
  @Prop hasSelection: boolean = false;
  onBack: () => void = () => {};
  onToolTap: (tool: string) => void = (_tool: string) => {};
  onUndo: () => void = () => {};
  onRedo: () => void = () => {};
  onDelete: () => void = () => {};
  onSave: () => void = () => {};
  @State private hoveredKey: string = '';

  private tools: ToolConfig[] = [
    { icon: 'mouse', tool: 'select' },
    { icon: 'rectangle', tool: 'rect' },
    { icon: 'circle', tool: 'ellipse' },
    { icon: 'diamond', tool: 'diamond' },
    { icon: 'text-caption', tool: 'text' },
    { icon: 'line', tool: 'line' },
    { icon: 'pencil', tool: 'pen' }
  ];

  @Builder IconBtn(key: string, icon: string, iconSize: number, iconColor: ResourceColor,
    enabled: boolean, onTap: () => void) {
    Row() {
      TablerIcon(icon, iconSize, iconColor)
    }
    .width(40)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(6)
    .opacity(enabled ? 1 : 0.4)
    .stateStyles({
      normal: {
        .backgroundColor(this.hoveredKey === key ? $r('app.color.surface2') : Color.Transparent)
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onHover((isHover: boolean) => {
      this.hoveredKey = isHover ? key : '';
    })
    .onClick(() => {
      if (enabled) {
        onTap();
      }
    })
  }

  build() {
    Row({ space: 4 }) {
      // 返回按钮
      this.IconBtn('back', 'arrow-left', 20, $r('app.color.text'), true, (): void => {
        this.onBack();
      })

      // 分隔线
      Divider()
        .vertical(true)
        .height(20)
        .color($r('app.color.border'))
        .strokeWidth(1)
        .margin({ left: 2, right: 2 })

      // 工具按钮组（横向可滚动，窄屏不溢出裁切）
      Scroll() {
        Row({ space: 4 }) {
          ForEach(this.tools, (tc: ToolConfig) => {
            Row() {
              TablerIcon(tc.icon, 18,
                this.currentTool === tc.tool ? $r('app.color.primary') : $r('app.color.muted_text'))
            }
            .width(40)
            .height(40)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .borderRadius(6)
            .stateStyles({
              normal: {
                .backgroundColor(this.currentTool === tc.tool || this.hoveredKey === 'tool_' + tc.tool
                  ? $r('app.color.surface2') : Color.Transparent)
              },
              pressed: { .backgroundColor($r('app.color.surface3')) }
            })
            .animation({ duration: 140, curve: Curve.EaseOut })
            .onHover((isHover: boolean) => {
              this.hoveredKey = isHover ? 'tool_' + tc.tool : '';
            })
            .onClick(() => {
              this.onToolTap(tc.tool);
            })
          }, (tc: ToolConfig) => tc.tool)
        }
      }
      .layoutWeight(1)
      .height(40)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)

      // 分隔线
      Divider()
        .vertical(true)
        .height(20)
        .color($r('app.color.border'))
        .strokeWidth(1)
        .margin({ left: 2, right: 2 })

      // 撤销 / 重做
      this.IconBtn('undo', 'arrow-back-up', 18,
        this.canUndo ? $r('app.color.text') : $r('app.color.muted_text'),
        this.canUndo, (): void => {
          this.onUndo();
        })
      this.IconBtn('redo', 'arrow-forward-up', 18,
        this.canRedo ? $r('app.color.text') : $r('app.color.muted_text'),
        this.canRedo, (): void => {
          this.onRedo();
        })

      // 删除（选中时显示）
      if (this.hasSelection) {
        this.IconBtn('delete', 'trash', 16, $r('app.color.danger'), true, (): void => {
          this.onDelete();
        })
      }

      // 保存
      this.IconBtn('save', 'download', 18, $r('app.color.muted_text'), true, (): void => {
        this.onSave();
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.surface0'))
  }
}
