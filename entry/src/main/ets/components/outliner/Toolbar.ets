import { TablerIcon } from '../common/Icons';
import { EditorService } from '../../services/EditorService';
import { AppState } from '../../state/AppState';

/**
 * Toolbar — 编辑器浮动工具栏。
 * 提供撤销/重做按钮。
 */
@Component
export struct Toolbar {
  @State canUndo: boolean = false;
  @State canRedo: boolean = false;

  /**
   * 数据版本号 —— 撤销/重做按钮**可用性的刷新源**（W10 修复）。
   *
   * 本组件是长驻的（挂在 `ContentArea` 的 `build()` 里，`Index` 页只创建一次），
   * 因此 `aboutToAppear` 只跑一次、`onPageShow` 只在**路由级**页面切换时触发。
   * 而撤销栈的变化完全发生在同一路由内部（删一个块就使 canUndo 由 false 变 true）
   * ⇒ 两个入口都不会再跑 ⇒ `canUndo` 恒为启动时的值（false）
   * ⇒ `build()` 一直走 `Row().width(0).height(0)` 分支 ⇒ **撤销/重做按钮永远不出现**
   * ⇒ `OutlinerEngine.undo()` 在触屏上没有任何可达入口（只剩 Ctrl+Z，而注入的按键
   *    不达 ArkUI 按键管线，AGENTS §7 陷阱 13/§3）。
   *
   * 选 `callaite_blocksVersion` 而不是新开一个版本号的理由：`execute()` / `undo()` /
   * `redo()` 都会让块数据变化，其调用方本就 bump 该键（BlockView 的删除/缩进/移动、
   * BlockSelection 的批量操作、BlockDragLayer 的落位…）。复用同一条通道可保证
   * 「按钮可用性」与「块数据已变」永远同步，不会出现两条版本号各自漂移。
   */
  @StorageLink('callaite_blocksVersion') @Watch('onBlocksVersionChanged') private blocksVersion: number = 0;

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

  /** 块数据变化 → 撤销/重做栈可能已变，刷新按钮可用性。 */
  onBlocksVersionChanged(): void {
    this.refreshState();
  }

  build() {
    if (!this.canUndo && !this.canRedo) {
      Row().width(0).height(0)
    } else {
      Row({ space: 4 }) {
        Button() {
          Row({ space: 4 }) {
            TablerIcon('arrow-left', 18, this.canUndo ? $r('app.color.icon_color') : $r('app.color.muted_text'))
          }
        }
        .width(36).height(36).type(ButtonType.Circle).backgroundColor($r('app.color.surface2'))
        .enabled(this.canUndo)
        // `id` 供 uitest dumpLayout 精确定位（与 BlockSelection / SelectionToggle 同一约定）；
        // 本按钮无文字，dump 里只能靠 id 或坐标命中。
        .id('callaite_undoBtn')
        .onClick(() => {
          const editor = EditorService.getInstance();
          editor.undo();
          // ⚠️ W8 修复（E14 / W7-2）：`undo()` 只回滚**数据 + 磁盘**，
          //    而撤销一次缩进会把 `level` 改回去（uuid 不变）⇒ `LazyForEach` 键未变
          //    ⇒ 行不重算 ⇒ **磁盘对、画面陈旧**（要离开页面再回来才对）✗。
          //    `OutlinerEngine` 刻意不 bump（全仓仅 UI 层 bump，AGENTS §7 陷阱 22）
          //    ⇒ 工具栏这条入口必须自己补。`refreshState()` 只刷新「按钮可用性」，
          //    **不会**让任何一行重算 ✗。
          AppState.bumpBlocksVersion();
          this.refreshState();
        })

        Button() {
          Row({ space: 4 }) {
            TablerIcon('arrow-right', 18, this.canRedo ? $r('app.color.icon_color') : $r('app.color.muted_text'))
          }
        }
        .width(36).height(36).type(ButtonType.Circle).backgroundColor($r('app.color.surface2'))
        .enabled(this.canRedo)
        .id('callaite_redoBtn')
        .onClick(() => {
          const editor = EditorService.getInstance();
          editor.redo();
          // 同 `callaite_undoBtn`：重做同样会改 `level`/`parentId`，必须 bump 才能让行重算。
          AppState.bumpBlocksVersion();
          this.refreshState();
        })
      }
      .padding({ left: 4, right: 4, top: 2, bottom: 2 })
      .borderRadius(6)
      .backgroundColor($r('app.color.surface0'))
      .shadow({ radius: 4, color: '#10000000' })
    }
  }

  refreshState(): void {
    const editor = EditorService.getInstance();
    this.canUndo = editor.canUndo();
    this.canRedo = editor.canRedo();
  }
}
