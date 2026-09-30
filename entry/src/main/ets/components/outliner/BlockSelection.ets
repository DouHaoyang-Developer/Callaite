import { EditorService } from '../../services/EditorService';
import { WorkspaceService } from '../../services/WorkspaceService';
import { AppState } from '../../state/AppState';
import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { pasteboard } from '@kit.BasicServicesKit';

/**
 * BlockSelection — Block 多选入口 + 批量操作浮动栏组件。
 *
 * 对应 Logseq 中选中多个 block 后底部出现的批量操作工具栏。
 *
 * 职责：
 *  - **提供多选的可点击入口**（U1.4 接线增补）：未进入多选模式时渲染一枚常显的
 *    「选择」按钮（id=callaite_selectionEntry），点击即开启多选模式。
 *  - 显示当前选中的 block 数量
 *  - 提供批量操作按钮：缩进(→)、反缩进(←)、删除(×)、复制、全选、完成
 *  - 通过 @StorageLink('callaite_blocksVersion') 监听全局数据刷新、
 *    通过 @StorageLink('callaite_selectionVersion') 监听**选中集合**变化
 *  - 选中数量为 0 且未进入多选模式时不显示工具栏（只显示入口按钮）
 *
 * 组件接口：
 *   @Prop pageId: string — 当前页面 UUID（用于全选操作）
 *
 * 用法：
 *   BlockSelection({ pageId: 'xxx-page-uuid' })
 *
 * 操作流程：
 *   1. 用户点底部「选择」进入多选模式（或桌面 Ctrl+点击某块）→ 行内出现选择圈
 *   2. 点行内选择圈 → EditorService.toggleSelection(uuid) → 选中集合更新
 *   3. AppState.bumpSelectionVersion() 触发本组件与各行 BlockView 刷新
 *   4. 浮动工具栏显示「N 块」，点击按钮调用 EditorService 批量操作
 *   5. 操作后 AppState.bumpBlocksVersion()（数据变了）+ bumpSelectionVersion()（选中态变了）
 *   6. 点「完成」退出多选模式并清空选择
 *
 * ⚠️ 接线历史（U1.4，避免后来者重走弯路）：
 *   本组件与 `EditorService` 的多选后端（toggleSelection / getSelectedUuids /
 *   deleteSelected / indentSelected / outdentSelected / selectAll / clearSelection）
 *   在此窗口之前**都已存在**，缺的只是「谁能把选中集合变成非空」这一环：
 *   `EditorService.toggleSelection` 全仓 0 调用 ⇒ 选中数恒为 0 ⇒ 工具栏恒不出现；
 *   而工具栏里的「全选」按钮又只在工具栏出现时才可点 —— 形成死锁。
 *   因此本次改动的核心是**入口**，不是重写批量操作。
 */
@Component
export struct BlockSelection {
  /** 当前页面 UUID（用于全选操作） */
  @Prop pageId: string = '';

  /** 当前选中的 block 数量 */
  @State selectedCount: number = 0;

  /** 监听全局 blocksVersion 变化，触发选中数量刷新 */
  @StorageLink('callaite_blocksVersion') @Watch('onBlocksVersionChanged') private blocksVersion: number = 0;

  /**
   * 监听**选中集合**版本号。
   *
   * 为什么不能只靠 blocksVersion：选中/取消选中不改动任何块数据，
   * 不会 bump blocksVersion（也不应该 —— 那会导致 BlockList 整表重建）。
   * 故选中集合的变化由这条独立通道通知（见 AppState.bumpSelectionVersion）。
   */
  @StorageLink('callaite_selectionVersion') @Watch('onSelectionVersionChanged') private selectionVersion: number = 0;

  /** 多选模式开关（与 BlockView 读同一把键，保证「圈出现」与「工具栏出现」同步） */
  @StorageLink('callaite_selectionMode') private selectionMode: boolean = false;

  aboutToAppear(): void {
    this.refreshSelectedCount();
  }

  /**
   * blocksVersion 变化时刷新选中数量。
   *
   * 由以下操作触发：
   *  - BlockView 中的折叠/缩进/移动/删除
   *  - 本组件的批量操作（缩进/反缩进/删除/全选）
   *  - 其他调用 AppState.bumpBlocksVersion() 的地方
   */
  onBlocksVersionChanged(): void {
    this.refreshSelectedCount();
  }

  /** 选中集合版本号变化时刷新选中数量（含本组件按钮操作与行内选择圈操作两条来源）。 */
  onSelectionVersionChanged(): void {
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
    if (this.selectedCount === 0 && !this.selectionMode) {
      // ─── 多选入口（常显） ───
      // 这是 U1.4 唯一不依赖按键、不依赖长按的进入方式：
      //   · 触屏不产生 onHover（AGENTS §7 陷阱 11）→ 本按钮无条件常显；
      //   · 块级长按已被 S1-H 的拖拽抓取占用 → 入口不走长按；
      //   · uitest 的按键注入不达 ArkUI 按键管线 → 入口不走 Ctrl+点击。
      this.SelectionEntry()
    } else {
      // 浮动底部工具栏（Stack 叠加实现 position: absolute 效果）
      Stack({ alignContent: Alignment.Bottom }) {
        Row({ space: 8 }) {
          // ─── 选中数量显示 ───
          Row({ space: 4 }) {
            TablerIcon('checkbox', 18, $r('app.color.primary'))
            Text(this.selectedCount.toString() + ' ' + t('status_blocks'))
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
          .id('callaite_selectionIndent')
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
          .id('callaite_selectionOutdent')
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
          .id('callaite_selectionDelete')
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
          .id('callaite_selectionCopy')
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
          .id('callaite_selectionSelectAll')
          .onClick(() => {
            this.handleSelectAll();
          })

          // ─── 完成按钮：清空选择并退出多选模式 ───
          // 与旧的「清除选择(x)」合并为一颗：退出多选后行内选择圈一并消失，
          // 若只清空不退出，用户会停在一个「没有圈、也没有入口」的中间态。
          Button() {
            TablerIcon('check', 18, $r('app.color.success'))
          }
          .width(32).height(32)
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.surface2'))
          .id('callaite_selectionDone')
          .onClick(() => {
            this.handleExitSelectionMode();
          })
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .margin({ bottom: 8 })
        .backgroundColor($r('app.color.surface1'))
        .borderRadius(12)
        .shadow({ radius: 12, color: '#20000000', offsetX: 0, offsetY: -2 })
        .border({ width: 1, color: $r('app.color.border') })
        .id('callaite_selectionToolbar')
      }
      .width('100%')
      .height(72)
      .padding({ left: 16, right: 16 })
    }
  }

  /**
   * 多选入口按钮。
   *
   * 为什么放在这里（而不是 ContentArea 顶栏）：本组件已挂在 BlockList 的 Stack 底部，
   * 与工具栏同一个宿主 ⇒ 「入口」与「工具栏」的显隐是同一份状态的两个分支，
   * 不会出现「入口在某页显示、工具栏在另一处被裁掉」的错位。
   */
  @Builder
  SelectionEntry() {
    Row({ space: 6 }) {
      TablerIcon('checkbox', 16, $r('app.color.primary'))
      Text(t('hint_select'))
        .fontSize(13)
        .fontColor($r('app.color.primary'))
        .fontWeight(FontWeight.Medium)
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.surface1'))
    .borderRadius(18)
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({ radius: 10, color: '#20000000', offsetX: 0, offsetY: 2 })
    .id('callaite_selectionEntry')
    .onClick(() => {
      this.handleEnterSelectionMode();
    })
  }

  // ─── 多选模式开关 ───

  /**
   * 进入多选模式。
   * 不做任何数据操作 —— 选中集合仍为空，用户随后点各行选择圈。
   */
  handleEnterSelectionMode(): void {
    AppState.setSelectionMode(true);
    this.refreshSelectedCount();
  }

  /**
   * 退出多选模式：清空选中集合 + 关模式。
   * 顺序：先清集合再关模式，避免「模式已关但集合非空」的中间帧把工具栏重新画出来。
   */
  handleExitSelectionMode(): void {
    EditorService.getInstance().clearSelection();
    AppState.setSelectionMode(false);
    this.refreshSelectedCount();
  }

  // ─── 批量操作处理 ───

  /**
   * 缩进选中的 block。
   * 调用 EditorService.indentSelected()，然后触发全局刷新。
   *
   * ⚠️ 两个版本号都要 bump：blocksVersion（结构变了 → BlockList 重算可见行）
   * 与 selectionVersion（选中集合本身未变，但各行的 isSelected 需要重算/重绘）。
   */
  handleIndent(): void {
    const editor = EditorService.getInstance();
    editor.indentSelected();
    AppState.bumpBlocksVersion();
    AppState.bumpSelectionVersion();
  }

  /**
   * 反缩进选中的 block。
   * 调用 EditorService.outdentSelected()，然后触发全局刷新。
   */
  handleOutdent(): void {
    const editor = EditorService.getInstance();
    editor.outdentSelected();
    AppState.bumpBlocksVersion();
    AppState.bumpSelectionVersion();
  }

  /**
   * 删除选中的 block。
   * 调用 EditorService.deleteSelected()，然后触发全局刷新。
   * 删除后选中列表会被清空（EditorService.deleteSelected 内 `selectedUuids = []`），
   * 因此这里必须 bump selectionVersion 让各行的选中描边一并消失。
   */
  handleDelete(): void {
    const editor = EditorService.getInstance();
    editor.deleteSelected();
    AppState.bumpBlocksVersion();
    AppState.bumpSelectionVersion();
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

    // 复制不改动数据、也不改动选中集合，故只做一次轻量重算
    this.refreshSelectedCount();
  }

  /**
   * 全选当前页面的 block。
   * 调用 EditorService.selectAll(pageId)，然后触发全局刷新。
   *
   * ⚠️ pageId 必须由宿主传入真实页面 uuid：`EditorService.selectAll` 内部走
   * `WorkspaceService.getPageBlocks(pageId)` → `DataStore.getTopLevelBlocks`，
   * 传空串会得到空列表 ⇒ 表现为「点了全选没反应」（本窗口修复：BlockList 此前
   * 构造 BlockSelection 时未传 pageId，@Prop 一直取默认值 ''）。
   * 另注：getPageBlocks 只返回**顶层**块，因此全选 = 选中本页所有顶层块。
   */
  handleSelectAll(): void {
    const editor = EditorService.getInstance();
    editor.selectAll(this.pageId);
    AppState.bumpSelectionVersion();
  }
}
