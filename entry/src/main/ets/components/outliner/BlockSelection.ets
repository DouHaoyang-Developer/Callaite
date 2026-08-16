import { EditorService } from '../../services/EditorService';
import { WorkspaceService } from '../../services/WorkspaceService';
import { AppState } from '../../state/AppState';
import { TablerIcon } from '../common/Icons';
import { pasteboard } from '@kit.BasicServicesKit';

/**
 * BlockSelection — Block 多选 + 批量操作浮动栏组件。
 *
 * 对应 Logseq 中选中多个 block 后底部出现的批量操作工具栏。
 *
 * 职责：
 *  - 显示当前选中的 block 数量
 *  - 提供批量操作按钮：缩进(→)、反缩进(←)、删除(×)、复制、全选
 *  - 通过 @StorageLink('callaite_blocksVersion') 监听全局刷新
 *  - 选中数量为 0 时不显示工具栏
 *
 * 组件接口：
 *   @Prop pageId: string — 当前页面 UUID（用于全选操作）
 *
 * 用法：
 *   BlockSelection({ pageId: 'xxx-page-uuid' })
 *
 * 操作流程：
 *   1. 用户在其他组件（如 BlockView）中长按或 Ctrl+点击选中多个 block
 *   2. EditorService.selectedUuids 更新
 *   3. AppState.bumpBlocksVersion() 触发本组件刷新 selectedCount
 *   4. selectedCount > 0 时显示浮动工具栏
 *   5. 点击按钮调用 EditorService 批量操作
 *   6. 操作后再次调用 AppState.bumpBlocksVersion() 刷新 UI
 */
@Component
export struct BlockSelection {
  /** 当前页面 UUID（用于全选操作） */
  @Prop pageId: string = '';

  /** 当前选中的 block 数量 */
  @State selectedCount: number = 0;

  /** 监听全局 blocksVersion 变化，触发选中数量刷新 */
  @StorageLink('callaite_blocksVersion') @Watch('onBlocksVersionChanged') private blocksVersion: number = 0;

  aboutToAppear(): void {
    this.refreshSelectedCount();
  }

  /**
   * blocksVersion 变化时刷新选中数量。
   *
   * 由以下操作触发：
   *  - BlockView 中的折叠/缩进/移动/删除
   *  - 本组件的批量操作（缩进/反缩进/删除/全选/清除）
   *  - 其他调用 AppState.bumpBlocksVersion() 的地方
   */
  onBlocksVersionChanged(): void {
    this.refreshSelectedCount();
  }

  /**
   * 从 EditorService 获取最新选中数量。
   */
  refreshSelectedCount(): void {
    const editor = EditorService.getInstance();
    const uuids = editor.getSelectedUuids();
    this.selectedCount = uuids.length;
  }

  build() {
    // 选中数量为 0 时不显示工具栏
    if (this.selectedCount === 0) {
      Row().width(0).height(0)
    } else {
      // 浮动底部工具栏（Stack 叠加实现 position: absolute 效果）
      Stack({ alignContent: Alignment.Bottom }) {
        Row({ space: 8 }) {
          // ─── 选中数量显示 ───
          Row({ space: 4 }) {
            TablerIcon('checkbox', 18, $r('app.color.primary'))
            Text(this.selectedCount.toString())
              .fontSize(13)
              .fontColor($r('app.color.primary'))
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor($r('app.color.surface1'))
          .borderRadius(4)

          // ─── 缩进按钮（→） ───
          Button() {
            TablerIcon('indent-increase', 18, $r('app.color.text'))
          }
          .width(32).height(32)
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.surface2'))
          .onClick(() => {
            this.handleIndent();
          })

          // ─── 反缩进按钮（←） ───
          Button() {
            TablerIcon('indent-decrease', 18, $r('app.color.text'))
          }
          .width(32).height(32)
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.surface2'))
          .onClick(() => {
            this.handleOutdent();
          })

          // ─── 删除按钮（×） ───
          Button() {
            TablerIcon('trash', 18, $r('app.color.error'))
          }
          .width(32).height(32)
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.surface2'))
          .onClick(() => {
            this.handleDelete();
          })

          // ─── 复制按钮 ───
          Button() {
            TablerIcon('copy', 18, $r('app.color.text'))
          }
          .width(32).height(32)
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.surface2'))
          .onClick(() => {
            this.handleCopy();
          })

          // ─── 全选按钮 ───
          Button() {
            TablerIcon('square-check', 18, $r('app.color.text'))
          }
          .width(32).height(32)
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.surface2'))
          .onClick(() => {
            this.handleSelectAll();
          })

          // ─── 清除选择按钮 ───
          Button() {
            TablerIcon('x', 18, $r('app.color.muted_text'))
          }
          .width(32).height(32)
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.surface2'))
          .onClick(() => {
            this.handleClearSelection();
          })
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.surface1'))
        .borderRadius(12)
        .shadow({ radius: 12, color: '#20000000', offsetX: 0, offsetY: -2 })
        .border({ width: 1, color: $r('app.color.border') })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
    }
  }

  // ─── 批量操作处理 ───

  /**
   * 缩进选中的 block。
   * 调用 EditorService.indentSelected()，然后触发全局刷新。
   */
  handleIndent(): void {
    const editor = EditorService.getInstance();
    editor.indentSelected();
    AppState.bumpBlocksVersion();
  }

  /**
   * 反缩进选中的 block。
   * 调用 EditorService.outdentSelected()，然后触发全局刷新。
   */
  handleOutdent(): void {
    const editor = EditorService.getInstance();
    editor.outdentSelected();
    AppState.bumpBlocksVersion();
  }

  /**
   * 删除选中的 block。
   * 调用 EditorService.deleteSelected()，然后触发全局刷新。
   * 删除后选中列表会被清空，工具栏自动隐藏。
   */
  handleDelete(): void {
    const editor = EditorService.getInstance();
    editor.deleteSelected();
    AppState.bumpBlocksVersion();
  }

  /**
   * 复制选中的 block 内容到系统剪贴板。
   *
   * 流程：
   *  1. 通过 EditorService.getSelectedUuids() 获取选中的 UUID 列表
   *  2. 通过 WorkspaceService.getBlock(uuid) 获取每个 block 的内容
   *  3. 拼接为 Markdown 格式文本（每行一个 block，缩进用制表符）
   *  4. 写入系统剪贴板
   */
  handleCopy(): void {
    const editor = EditorService.getInstance();
    const uuids = editor.getSelectedUuids();
    if (uuids.length === 0) {
      return;
    }

    const ws = WorkspaceService.getInstance();
    const lines: string[] = [];

    for (let i = 0; i < uuids.length; i++) {
      const block = ws.getBlock(uuids[i]);
      if (block) {
        // 根据缩进层级生成制表符前缀
        let indent = '';
        for (let j = 0; j < block.level; j++) {
          indent += '\t';
        }
        // 拼接 marker（如有）和内容
        let line = indent;
        if (block.marker !== '') {
          line += block.marker + ' ';
        }
        line += block.content;
        lines.push(line);
      }
    }

    const text = lines.join('\n');

    // 写入系统剪贴板
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteData).then(() => {
        // 复制成功
      });
    } catch (e) {
      // 忽略剪贴板写入失败
    }

    AppState.bumpBlocksVersion();
  }

  /**
   * 全选当前页面的所有 block。
   * 调用 EditorService.selectAll(pageId)，然后触发全局刷新。
   */
  handleSelectAll(): void {
    const editor = EditorService.getInstance();
    editor.selectAll(this.pageId);
    AppState.bumpBlocksVersion();
  }

  /**
   * 清除当前选择。
   * 调用 EditorService.clearSelection()，然后触发全局刷新。
   * 清除后选中数量为 0，工具栏自动隐藏。
   */
  handleClearSelection(): void {
    const editor = EditorService.getInstance();
    editor.clearSelection();
    AppState.bumpBlocksVersion();
  }
}
