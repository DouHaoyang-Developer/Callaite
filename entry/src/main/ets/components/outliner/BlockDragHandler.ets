import { BlockData } from '../../core/models/Block';
import { WorkspaceService } from '../../services/WorkspaceService';
import { AppState } from '../../state/AppState';
import { TablerIcon } from '../common/Icons';
import { vibrator } from '@kit.SensorServiceKit';

/**
 * DropPosition — 释放位置类型。
 * above: 放在目标 block 上方（作为其左侧兄弟）
 * below: 放在目标 block 下方（作为其右侧兄弟）
 * child: 作为目标 block 的子节点
 */
type DropPosition = 'above' | 'below' | 'child';

/**
 * DropTarget — 释放目标信息。
 */
interface DropTarget {
  targetUuid: string;
  position: DropPosition;
}

/**
 * DragStateManager — 全局拖拽状态协调器（单例）。
 *
 * 跟踪当前拖拽的 block UUID 和拖拽状态，
 * 供跨组件查询（如 BlockList 判断是否正在拖拽以禁用其他交互）。
 */
class DragStateManager {
  private static instance: DragStateManager | undefined;
  private currentDraggedUuid: string = '';
  private dragging: boolean = false;

  static getInstance(): DragStateManager {
    if (!DragStateManager.instance) {
      DragStateManager.instance = new DragStateManager();
    }
    return DragStateManager.instance;
  }

  setDragging(uuid: string, isDragging: boolean): void {
    this.currentDraggedUuid = uuid;
    this.dragging = isDragging;
  }

  isDragging(): boolean {
    return this.dragging;
  }

  getDraggedUuid(): string {
    return this.currentDraggedUuid;
  }
}

/**
 * BlockDragHandler — Block 拖拽排序处理器组件。
 *
 * 对应 Logseq 中的 block drag-and-drop 重排功能。
 *
 * 职责：
 *  - 长按 500ms 激活拖拽模式（LongPressGesture + SequenceGesture）
 *  - 拖拽时显示半透明预览（PanGesture + Stack position 绝对定位）
 *  - 拖拽时显示蓝色指示线（目标位置预览）
 *  - 释放时计算目标位置（above/below/child）
 *  - 调用 WorkspaceService.executeOp({ type: 'move-block', ... }) 执行移动
 *  - 振动反馈（vibrator.startVibration）
 *
 * 组件接口：
 *   @Prop blockUuid: string  — 要拖拽的 Block UUID
 *   @Prop depth: number      — 缩进深度（用于渲染引导线）
 *   onDragStart: () => void  — 拖拽开始回调
 *   onDragEnd: () => void    — 拖拽结束回调
 *
 * 查询拖拽状态（跨组件）：
 *   DragStateManager.getInstance().isDragging()
 *   DragStateManager.getInstance().getDraggedUuid()
 *
 * 用法：
 *   BlockDragHandler({
 *     blockUuid: 'xxx-xxx',
 *     depth: 0,
 *     onDragStart: () => { console.log('drag started') },
 *     onDragEnd: () => { console.log('drag ended') }
 *   })
 */
@Component
export struct BlockDragHandler {
  /** Block UUID */
  @Prop blockUuid: string = '';
  /** 缩进深度（用于渲染缩进引导线） */
  @Prop depth: number = 0;

  // ─── 拖拽状态（驱动 UI 更新） ───
  /** 是否正在拖拽 */
  @State isDraggingState: boolean = false;
  /** 拖拽预览 X 偏移量 */
  @State previewOffsetX: number = 0;
  /** 拖拽预览 Y 偏移量 */
  @State previewOffsetY: number = 0;
  /** 蓝色指示线是否可见 */
  @State indicatorVisible: boolean = false;
  /** 蓝色指示线 Y 偏移量 */
  @State indicatorOffsetY: number = 0;

  // ─── 回调 ───
  /** 拖拽开始时触发 */
  onDragStart: () => void = () => {};
  /** 拖拽结束时触发（无论是否执行了移动） */
  onDragEnd: () => void = () => {};

  // ─── 私有数据 ───
  private blockData: BlockData | undefined;
  private dragStateManager: DragStateManager = DragStateManager.getInstance();

  aboutToAppear(): void {
    this.refreshBlock();
  }

  /**
   * 刷新 Block 数据。
   * 在拖拽结束后调用以获取最新内容。
   */
  refreshBlock(): void {
    const ws = WorkspaceService.getInstance();
    this.blockData = ws.getBlock(this.blockUuid);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ─── 内容区域 + 拖拽手势 ───
      // 使用 GestureGroup(Sequence) 组合 LongPress + Pan
      // 长按 500ms 识别后，PanGesture 接管手指移动
      Column() {
        this.BlockContent()
      }
      .width('100%')
      .gesture(
        GestureGroup(GestureMode.Sequence,
          LongPressGesture({ repeat: false, duration: 500 })
            .onAction((event: GestureEvent) => {
              this.startDrag();
            }),
          PanGesture({ fingers: 1, distance: 1 })
            .onActionStart((event: GestureEvent) => {
              this.previewOffsetX = 0;
              this.previewOffsetY = 0;
            })
            .onActionUpdate((event: GestureEvent) => {
              this.updateDrag(event.offsetX, event.offsetY);
            })
            .onActionEnd((event: GestureEvent) => {
              this.endDrag(event.offsetX, event.offsetY);
            })
            .onActionCancel(() => {
              this.cancelDrag();
            })
        )
      )

      // ─── 拖拽预览（半透明，跟随手指） ───
      if (this.isDraggingState) {
        this.DragPreview()
      }

      // ─── 蓝色指示线（目标位置预览） ───
      if (this.indicatorVisible) {
        this.DropIndicator()
      }
    }
    .width('100%')
    .clip(false)
  }

  // ─── Block 内容渲染 ───

  @Builder
  BlockContent() {
    Row() {
      // 缩进引导线（与 BlockView 风格一致）
      if (this.depth > 0) {
        ForEach(this.buildGuideArray(), (idx: number) => {
          Row() {
            Column().width(1).height('100%').backgroundColor($r('app.color.border')).margin({ left: 8 })
            Blank().width(15)
          }.width(24).height('100%')
        }, (idx: number) => idx.toString())
      }

      Row({ space: 8 }) {
        // Bullet 圆点
        Circle({ width: 6, height: 6 })
          .fill($r('app.color.muted_text'))
          .margin({ top: 5 })

        // Block 内容文本（单行预览）
        if (this.blockData) {
          Text(this.blockData.content)
            .fontSize(15)
            .fontColor($r('app.color.text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        } else {
          Text('')
            .fontSize(15)
            .layoutWeight(1)
        }

        // 拖拽手柄图标（悬停时可见的感觉）
        TablerIcon('grip-vertical', 14, $r('app.color.muted_text'))
      }.layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    .opacity(this.isDraggingState ? 0.3 : 1.0)
  }

  // ─── 拖拽预览（半透明，跟随手指位置） ───

  @Builder
  DragPreview() {
    Column() {
      if (this.blockData) {
        Row({ space: 8 }) {
          Circle({ width: 6, height: 6 })
            .fill($r('app.color.primary'))
            .margin({ top: 5 })
          Text(this.blockData.content)
            .fontSize(15)
            .fontColor($r('app.color.text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('80%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.surface2'))
        .borderRadius(6)
        .shadow({ radius: 8, color: '#40000000', offsetX: 0, offsetY: 4 })
        .opacity(0.85)
      }
    }
    .width('100%')
    .position({ x: this.previewOffsetX, y: this.previewOffsetY })
  }

  // ─── 蓝色指示线（目标位置预览） ───

  @Builder
  DropIndicator() {
    Row() {
      Row()
        .width('100%')
        .height(2)
        .backgroundColor($r('app.color.primary'))
        .borderRadius(1)
    }
    .width('100%')
    .position({ x: 0, y: this.indicatorOffsetY })
  }

  // ─── 拖拽生命周期 ───

  /**
   * 开始拖拽 — 由 LongPressGesture.onAction 触发。
   */
  startDrag(): void {
    this.isDraggingState = true;
    this.dragStateManager.setDragging(this.blockUuid, true);
    this.onDragStart();
    this.triggerVibration();
  }

  /**
   * 更新拖拽位置 — 由 PanGesture.onActionUpdate 触发。
   * 更新预览位置，并计算目标位置以显示蓝色指示线。
   */
  updateDrag(offsetX: number, offsetY: number): void {
    if (!this.isDraggingState) return;

    this.previewOffsetX = offsetX;
    this.previewOffsetY = offsetY;

    // 计算目标位置并显示指示线
    const target = this.computeDropTarget(offsetY);
    if (target.targetUuid !== '' && target.targetUuid !== this.blockUuid) {
      this.indicatorVisible = true;
      this.indicatorOffsetY = offsetY;
    } else {
      this.indicatorVisible = false;
    }
  }

  /**
   * 结束拖拽 — 由 PanGesture.onActionEnd 触发。
   * 计算最终目标位置并执行 move-block 操作。
   */
  endDrag(offsetX: number, offsetY: number): void {
    if (!this.isDraggingState) return;

    const target = this.computeDropTarget(offsetY);
    this.executeMove(target);

    this.cleanupDrag();
    this.triggerVibration();
    AppState.bumpBlocksVersion();
  }

  /**
   * 取消拖拽 — 由 PanGesture.onActionCancel 触发。
   * 清理拖拽状态但不执行移动操作。
   */
  cancelDrag(): void {
    this.cleanupDrag();
  }

  /**
   * 清理拖拽状态。
   */
  cleanupDrag(): void {
    this.isDraggingState = false;
    this.indicatorVisible = false;
    this.previewOffsetX = 0;
    this.previewOffsetY = 0;
    this.dragStateManager.setDragging('', false);
    this.onDragEnd();
  }

  // ─── 目标位置计算 ───

  /**
   * 根据拖拽 Y 偏移量计算释放目标。
   *
   * 算法：
   *  1. 获取当前页面的顶层 block 列表
   *  2. 基于 Y 偏移量估算目标 block 索引（每个 block 约 36px 高度）
   *  3. 根据偏移量在目标 block 内的相对位置确定 above/below/child
   *
   * @param offsetY 拖拽 Y 偏移量（相对于拖拽起点）
   * @returns DropTarget 包含目标 UUID 和位置
   */
  computeDropTarget(offsetY: number): DropTarget {
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(this.blockUuid);
    if (!block) {
      return { targetUuid: '', position: 'below' };
    }

    const pageUuid = ws.getPageUuidForBlock(this.blockUuid);
    if (!pageUuid) {
      return { targetUuid: '', position: 'below' };
    }

    const topBlocks = ws.getPageBlocks(pageUuid);
    if (topBlocks.length === 0) {
      return { targetUuid: '', position: 'below' };
    }

    // 基于 Y 偏移量估算目标 block
    const blockHeight = 36;
    const absOffset = offsetY < 0 ? -offsetY : offsetY;
    let targetIndex = Math.floor(absOffset / blockHeight);

    if (targetIndex < 0) {
      targetIndex = 0;
    }
    if (targetIndex >= topBlocks.length) {
      targetIndex = topBlocks.length - 1;
    }

    const targetBlock = topBlocks[targetIndex];
    if (!targetBlock) {
      return { targetUuid: '', position: 'below' };
    }
    if (targetBlock.uuid === this.blockUuid) {
      return { targetUuid: '', position: 'below' };
    }

    // 计算位置：above / below / child
    const relativeY = absOffset - targetIndex * blockHeight;
    let position: DropPosition;

    if (relativeY < blockHeight * 0.3) {
      position = 'above';
    } else if (relativeY > blockHeight * 0.7) {
      position = 'below';
    } else {
      // 中间区域 → 作为子节点
      position = 'child';
    }

    return { targetUuid: targetBlock.uuid, position: position };
  }

  // ─── 执行移动操作 ───

  /**
   * 执行 move-block 操作。
   *
   * 根据目标位置计算 newParentId / newLeftId / newLevel，
   * 然后调用 WorkspaceService.executeOp。
   *
   * @param target 释放目标信息
   */
  executeMove(target: DropTarget): void {
    if (target.targetUuid === '' || target.targetUuid === this.blockUuid) {
      return;
    }

    const ws = WorkspaceService.getInstance();
    const dragged = ws.getBlock(this.blockUuid);
    const targetBlock = ws.getBlock(target.targetUuid);

    if (!dragged || !targetBlock) {
      return;
    }

    // 防止循环：不能将 block 移动到自己的子树中
    if (this.isDescendant(target.targetUuid, this.blockUuid)) {
      return;
    }

    let newParentId: string;
    let newLeftId: string;
    let newLevel: number;

    if (target.position === 'above') {
      // 放在目标上方 → 作为目标的左兄弟的右兄弟
      const leftSibling = ws.getDataStore().getBlockTree().getLeftSibling(target.targetUuid);
      newParentId = targetBlock.parentId;
      newLeftId = leftSibling ? leftSibling.uuid : '';
      newLevel = targetBlock.level;
    } else if (target.position === 'below') {
      // 放在目标下方 → 作为目标的右兄弟
      newParentId = targetBlock.parentId;
      newLeftId = targetBlock.uuid;
      newLevel = targetBlock.level;
    } else {
      // 作为目标的子节点（最后一个子节点之后）
      const children = ws.getChildrenOfBlock(target.targetUuid);
      const lastChildId = children.length > 0 ? children[children.length - 1].uuid : '';
      newParentId = target.targetUuid;
      newLeftId = lastChildId;
      newLevel = targetBlock.level + 1;
    }

    ws.executeOp({
      type: 'move-block',
      uuid: this.blockUuid,
      newParentId: newParentId,
      newLeftId: newLeftId,
      newLevel: newLevel
    });
  }

  /**
   * 检查 candidateUuid 是否是 ancestorUuid 的后代（防止循环移动）。
   *
   * @param candidateUuid 待检查的 block UUID
   * @param ancestorUuid 祖先 block UUID
   * @returns 如果 candidateUuid 是 ancestorUuid 的后代则返回 true
   */
  isDescendant(candidateUuid: string, ancestorUuid: string): boolean {
    const ws = WorkspaceService.getInstance();
    let current = ws.getBlock(candidateUuid);
    const visited: string[] = [];

    while (current) {
      // 防止循环引用导致无限遍历
      let alreadyVisited = false;
      for (let i = 0; i < visited.length; i++) {
        if (visited[i] === current.uuid) {
          alreadyVisited = true;
          break;
        }
      }
      if (alreadyVisited) {
        break;
      }
      visited.push(current.uuid);

      if (current.parentId === ancestorUuid) {
        return true;
      }
      // 到达顶层（parentId 为空或等于 pageId）则停止
      if (current.parentId === '' || current.parentId === current.pageId) {
        break;
      }
      current = ws.getBlock(current.parentId);
    }
    return false;
  }

  // ─── 振动反馈 ───

  /**
   * 触发短振动（50ms），用于拖拽开始和结束的触觉反馈。
   */
  triggerVibration(): void {
    try {
      vibrator.startVibration({ type: 'time', duration: 50 });
    } catch (e) {
      // 忽略振动失败（模拟器或无权限时）
    }
  }

  // ─── 辅助方法 ───

  /**
   * 构建缩进引导线数组（与 BlockView 一致）。
   */
  buildGuideArray(): number[] {
    const a: number[] = [];
    for (let i = 0; i < this.depth; i++) {
      a.push(i);
    }
    return a;
  }

  // ─── 暴露的方法 ───

  /**
   * 当前组件是否正在拖拽。
   * @returns 拖拽状态
   */
  isDragging(): boolean {
    return this.isDraggingState;
  }

  /**
   * 获取全局当前被拖拽的 block UUID。
   * 通过 DragStateManager 单例实现跨组件查询。
   * @returns 被拖拽的 block UUID，无拖拽时返回空字符串
   */
  getDraggedUuid(): string {
    return this.dragStateManager.getDraggedUuid();
  }
}
