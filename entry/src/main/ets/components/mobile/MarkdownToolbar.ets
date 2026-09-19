import { TablerIcon } from '../common/Icons';
import { EditorService } from '../../services/EditorService';
import { GlassSurface } from '../common/GlassSurface';
import { GlassMode } from '../common/GlassSurface';
import { MaterialRole } from '../../theme/MaterialTokens';

/**
 * MarkdownToolbar —— 键盘上方的 Markdown 格式化工具条。
 *
 * 复刻 Obsidian iOS 编辑器工具行（参考图 Obsidian_iphone (7).jpg），原图 9 个按钮：
 *   ↶ 撤销 | ↷ 重做 | [[]] 页面双链 | 📄 插入文件 | # 标签 | 🔗 链接 | H 标题 | B 加粗 | ⌨˅ 收起键盘
 *
 * 说明：参考图中「H」「B」本身就是**字母字形**而非图标，因此此处用 Text 渲染，
 *      比套用近义图标更贴近原设计。
 *
 * 所有按钮均绑定**真实动作**（作用于 EditorService 的焦点 block），无空壳按钮：
 *   · 撤销/重做 → EditorService.undo() / redo()
 *   · 其余插入类 → 改写焦点 block 内容并提交
 */
@Component
export struct MarkdownToolbar {
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  @State canUndo: boolean = false;
  @State canRedo: boolean = false;
  @State hoveredKey: string = '';
  /** 命令序号：保证连续点击同一按钮也能触发对端 @Watch */
  @State cmdSeq: number = 0;

  aboutToAppear(): void {
    this.refreshState();
  }

  private refreshState(): void {
    const editor = EditorService.getInstance();
    this.canUndo = editor.canUndo();
    this.canRedo = editor.canRedo();
  }

  /**
   * 通过 AppStorage 命令通道把格式化指令发给**当前获焦的 WebEditor**。
   *
   * 为什么不能直接改 store：块编辑态由 WebEditor（contenteditable）承载，
   * 它只在创建时读取 initialContent，直接写 store 不会反映到正在编辑的编辑器上。
   * 因此格式化必须经 `runJavaScript` 在编辑器内部以 execCommand 执行。
   *
   * 命令格式 `cmd|seq`：seq 递增，保证连续点击同一按钮也能触发对方的 @Watch。
   */
  private sendCommand(cmd: string): void {
    if (EditorService.getInstance().getFocusedBlockUuid() === '') {
      return;   // 无焦点块时不发命令，避免误改
    }
    this.cmdSeq = this.cmdSeq + 1;
    AppStorage.setOrCreate('callaite_editorCommand', cmd + '|' + this.cmdSeq.toString());
  }

  /** 收起软键盘：清空焦点即让编辑器退出编辑态 */
  private dismissKeyboard(): void {
    EditorService.getInstance().clearFocus();
  }

  /**
   * 工具按钮：三态齐全，禁用态降透明度且不响应点击。
   */
  @Builder
  ToolItem(key: string, enabled: boolean, onTap: () => void) {
    Row() {
      if (key === 'heading') {
        Text('H')
          .fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(enabled ? $r('app.color.text') : $r('app.color.muted_text'))
      } else if (key === 'bold') {
        Text('B')
          .fontSize(17).fontWeight(FontWeight.Bold)
          .fontColor(enabled ? $r('app.color.text') : $r('app.color.muted_text'))
      } else {
        TablerIcon(this.iconOf(key), 19, enabled ? $r('app.color.text') : $r('app.color.muted_text'))
      }
    }
    .width(38)
    .height(38)
    .borderRadius(10)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: {
        .backgroundColor(this.hoveredKey === key && enabled
          ? $r('app.color.surface2')
          : Color.Transparent)
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .opacity(enabled ? 1 : 0.35)
    .onHover((isHover: boolean) => {
      this.hoveredKey = isHover ? key : '';
    })
    .onClick(() => {
      if (enabled) {
        onTap();
      }
    })
  }

  /** 按钮 key → Tabler 图标名（H/B 两个字母字形按钮不走图标） */
  private iconOf(key: string): string {
    if (key === 'undo') {
      return 'arrow-back-up';
    }
    if (key === 'redo') {
      return 'arrow-forward-up';
    }
    if (key === 'pageLink') {
      return 'book';
    }
    if (key === 'file') {
      return 'file-description';
    }
    if (key === 'tag') {
      return 'hash';
    }
    if (key === 'link') {
      return 'link';
    }
    return 'keyboard';
  }

  build() {
    Row() {
      GlassSurface({
        radius: 22,
        fill: $r('app.color.glass_fill'),
        mode: GlassMode.EFFECT,
        // 位于底部悬浮层之上，按官方规范取 THIN 档
        materialRole: MaterialRole.BOTTOM_FLOATING
      }) {
        Row({ space: 2 }) {
          this.ToolItem('undo', this.canUndo, () => {
            this.sendCommand('undo');
          })
          this.ToolItem('redo', this.canRedo, () => {
            this.sendCommand('redo');
          })
          this.ToolItem('pageLink', true, () => {
            this.sendCommand('[[]]');
          })
          this.ToolItem('file', true, () => {
            this.sendCommand('[](/.md)');
          })
          this.ToolItem('tag', true, () => {
            this.sendCommand('#');
          })
          this.ToolItem('link', true, () => {
            this.sendCommand('[](url)');
          })
          this.ToolItem('heading', true, () => {
            this.sendCommand('heading');
          })
          this.ToolItem('bold', true, () => {
            this.sendCommand('bold');
          })
          this.ToolItem('keyboard', true, () => {
            this.dismissKeyboard();
          })
        }
        .width('100%')
        .height(52)
        .padding({ left: 8, right: 8 })
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('96%')
    .constraintSize({ maxWidth: 420 })
    .height(52)
  }
}
