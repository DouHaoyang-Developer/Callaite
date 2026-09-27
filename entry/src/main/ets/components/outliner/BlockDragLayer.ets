import { BlockData } from '../../core/models/Block';
import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';
import { AppState } from '../../state/AppState';
import { TablerIcon } from '../common/Icons';
import { hilog } from '@kit.PerformanceAnalysisKit';

// ─────────────────────────────────────────────────────────────────────────────
// S1-H：块拖拽重排 —— 接线层
//
// 背景（为什么新建本文件而不是挂上 BlockDragHandler.ets）：
//   1. BlockDragHandler 自带 UI（极简单行文本），没有内容插槽 → 直接替换 BlockView
//      会丢掉富内容渲染（编辑态/折叠/表格/内联查询/embed/日期/marker/优先级等）；
//   2. 它的 computeDropTarget 三个前提全部不成立：offsetY 是手势相对位移而非屏幕坐标、
//      硬编码行高 36、getPageBlocks 只返回顶层块（嵌套子块永不可能是落点）；
//   3. 它在每行内挂 GestureGroup(Sequence, LongPress 500ms, Pan distance:1)，
//      与 S1-B 引入的 List 纵向滚动正面竞争。
//   该文件因此保持为「未接线死代码」不动，其命中算法与落库逻辑（executeMove）一律不复用。
//
// 本文件的职责边界：
//   · 只做「手势 → (目标 uuid, 三态)」的判定；
//   · 落库**一律**交给 EditorService.moveBlockToTarget(uuid, target, position)，
//     绝不自己拼 move-block op（单一数据路径，避免第二份拷贝再次漂移）。
// ─────────────────────────────────────────────────────────────────────────────

const DRAG_LOG_DOMAIN = 0x0001;
const DRAG_LOG_TAG = 'BlockDragLayer';

/** 命中判定：行矩形上 30% → above */
const BAND_ABOVE_RATIO = 0.3;
/** 命中判定：行矩形下 30% → below，中间 40% → child */
const BAND_BELOW_RATIO = 0.7;
/** 边缘自动滚动触发带宽度（vp，列表上下各一条） */
const EDGE_BAND_VP = 48;
/** 边缘自动滚动单帧位移（vp）与周期（ms） */
const EDGE_SCROLL_STEP_VP = 12;
const EDGE_SCROLL_INTERVAL_MS = 16;
/** 自动滚动累计上限，防止越界后仍无限累加（实际越界由 List 自身回弹） */
const EDGE_SCROLL_LIMIT_VP = 200000;
/** 长按激活拖拽的时长（与 Logseq 手感对齐） */
const DRAG_LONG_PRESS_MS = 500;

// ─────────────────────────────────────────────────────────────────────────────
// 行矩形注册表（模块级单例，普通对象，不参与 ArkTS 状态观察）
//
// 为什么用模块级单例而不是 @Provide/@Consume 或 AppStorage：
//   BlockView 是 BlockChildren 递归渲染出来的深层子组件，且需要「每个可见行一条记录」；
//   状态观察对这个高频写入的纯几何表毫无价值（写入发生在布局回调里），
//   用普通模块变量可避免任何 @State/@Link 的刷新风暴与 AppStorage 序列化开销。
// ─────────────────────────────────────────────────────────────────────────────

/**
 * 行矩形记录。
 *
 * 坐标系说明（两套坐标系在此显式区分，避免混用）：
 *   · top / height：**窗口坐标系** vp。与 `onAreaChange` 的 `globalPosition`、
 *     以及 `GestureEvent.fingerList[i].globalX/globalY`、`TouchObject.windowY`
 *     同源（SDK：FingerInfo.globalY = "relative to the upper left corner of the
 *     application window, in vp"；Area.globalPosition = "current window coordinate
 *     system"，单位 vp）。
 *   · 不含「列表内容坐标系」：内容坐标系随滚动变化，把滚动偏移算进去会让回收/复用时
 *     的旧值变成幽灵行，故一律使用**随布局更新的窗口坐标**。
 */
interface BlockRowRect {
  /** 行所属 block uuid */
  uuid: string;
  /** 行顶边 Y（窗口坐标，vp） */
  top: number;
  /** 行高（vp）；<= 0 视为未完成布局 → 命中时忽略 */
  height: number;
  /** 行的缩进层级（用于命中时「最深的可见行优先」） */
  level: number;
  /** 注册序号（同层级并列时取最新登记的一条） */
  seq: number;
}

/** 行矩形注册表 */
const blockRowRects: BlockRowRect[] = [];
let blockRowSeq: number = 0;

/**
 * 登记/更新一个可见行的矩形（幂等 upsert）。
 *
 * 复用防护：LazyForEach 复用组件实例时 uuid 会变，旧 uuid 的记录若残留即为幽灵行。
 * 因此这里按 uuid upsert，并由 BlockView.aboutToAppear（复用/新建时都会触发）
 * 先调用 invalidateBlockRow 把旧记录置为 height=0 —— 未完成布局的记录不参与命中。
 */
export function registerBlockRow(uuid: string, top: number, height: number, level: number): void {
  if (uuid === '') {
    return;
  }
  blockRowSeq = blockRowSeq + 1;
  for (let i = 0; i < blockRowRects.length; i++) {
    if (blockRowRects[i].uuid === uuid) {
      blockRowRects[i].top = top;
      blockRowRects[i].height = height;
      blockRowRects[i].level = level;
      blockRowRects[i].seq = blockRowSeq;
      return;
    }
  }
  const record: BlockRowRect = {
    uuid: uuid,
    top: top,
    height: height,
    level: level,
    seq: blockRowSeq
  };
  blockRowRects.push(record);
}

/**
 * 使某行的几何失效（height=0），但不删除记录。
 * 用于 BlockView.aboutToAppear：此刻组件已被复用到新 uuid 或尚未完成布局，
 * 旧几何必须立即作废，否则会被误判为落点。
 */
export function invalidateBlockRow(uuid: string): void {
  if (uuid === '') {
    return;
  }
  for (let i = 0; i < blockRowRects.length; i++) {
    if (blockRowRects[i].uuid === uuid) {
      blockRowRects[i].height = 0;
      return;
    }
  }
}

/**
 * 反注册（彻底删除记录）。由 BlockView.aboutToDisappear 调用 ——
 * LazyForEach 回收行组件时触发，是「幽灵行」的第一道防线。
 */
export function unregisterBlockRow(uuid: string): void {
  if (uuid === '') {
    return;
  }
  for (let i = 0; i < blockRowRects.length; i++) {
    if (blockRowRects[i].uuid === uuid) {
      blockRowRects.splice(i, 1);
      return;
    }
  }
}

/**
 * 查询某行的窗口矩形（仅返回已布局完成的记录）。
 * @returns 长度为 2 的数组 [top, height]；未登记/未布局时返回 null
 */
function findBlockRowRect(uuid: string): number[] | null {
  if (uuid === '') {
    return null;
  }
  for (let i = 0; i < blockRowRects.length; i++) {
    if (blockRowRects[i].uuid === uuid) {
      if (blockRowRects[i].height <= 0) {
        return null;
      }
      return [blockRowRects[i].top, blockRowRects[i].height];
    }
  }
  return null;
}

/**
 * 把 Area 的 Length（string | number | Resource）取成 vp 数值。
 * onAreaChange 在布局回调中给出的 position/height 为 number（vp），
 * 但类型上仍是 Length 联合体，ArkTS 禁用 any，故必须显式收窄。
 */
function toVpNumber(value: Length | undefined): number {
  if (value === undefined) {
    return 0;
  }
  if (typeof value === 'number') {
    return value;
  }
  return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// 拖拽层实例注册表（模块级）
//
// 为什么需要它：ArkTS 不允许把 `BlockDragLayer({...})` 这样的 UI 组件实例化语句
// 写成赋值表达式（编译器报 "does not meet UI component syntax"），因此父组件
// （BlockList）无法用一个成员变量持有子组件实例来转发行长按回调。
// 解决办法：拖拽层自己在 aboutToAppear 注册、aboutToDisappear 反注册，
// 父组件按自己生成的 layerId 查表转发 —— 同一份「整页只 1 个实例」的语义不变
// （layerId 由所在整页 BlockList 生成，分屏时两个窗格各自持有一个 key，
// 互不覆盖，也不存在跨窗格误转发）。
// ─────────────────────────────────────────────────────────────────────────────

interface DragLayerBinding {
  layerId: string;
  layer: BlockDragLayer;
}

const dragLayerBindings: DragLayerBinding[] = [];

/** 由拖拽层自身在挂载/卸载时调用（父组件不直接调用）。 */
export function bindDragLayer(layerId: string, layer: BlockDragLayer): void {
  if (layerId === '') {
    return;
  }
  for (let i = 0; i < dragLayerBindings.length; i++) {
    if (dragLayerBindings[i].layerId === layerId) {
      dragLayerBindings[i].layer = layer;
      return;
    }
  }
  const binding: DragLayerBinding = { layerId: layerId, layer: layer };
  dragLayerBindings.push(binding);
}

/** 由拖拽层自身在卸载时调用。 */
export function unbindDragLayer(layerId: string, layer: BlockDragLayer): void {
  for (let i = 0; i < dragLayerBindings.length; i++) {
    if (dragLayerBindings[i].layerId === layerId && dragLayerBindings[i].layer === layer) {
      dragLayerBindings.splice(i, 1);
      return;
    }
  }
}

/**
 * 把行长按上报转发给该整页唯一的拖拽层。
 * 查不到实例（未挂载/已卸载）时静默忽略 —— 与「缺省不拖拽」等价。
 */
export function forwardRowGrab(layerId: string, uuid: string, globalX: number, globalY: number): void {
  if (layerId === '') {
    return;
  }
  for (let i = 0; i < dragLayerBindings.length; i++) {
    if (dragLayerBindings[i].layerId === layerId) {
      dragLayerBindings[i].layer.onRowGrab(uuid, globalX, globalY);
      return;
    }
  }
}

/**
 * 触感反馈（拖拽起止各一次）。
 * 与 BlockDragHandler 不同，这里不引入振动：本机模拟器无马达，且 VIBRATE 权限链
 * 属于装饰性路径，S1-H 阶段不扩大改动面。缺失项已在交付说明中标注。
 */

/**
 * BlockDragLayer — 整页大纲的拖拽重排覆盖层。
 *
 * 挂载方式（关键）：**整页分支的 Stack 内、List 之外，全局只挂 1 个实例**。
 * 每行不再挂任何拖拽手势容器 —— 行内只保留一个 LongPressGesture（复用 BlockView 既有
 * 行容器），用于「报出被长按的 block uuid + 按下点窗口坐标」，其余全部由本层统一处理。
 *
 * 手势与数据流：
 *   按下 → 本层 onTouch(TouchType.Down) 记录触点
 *   ↓ 500ms 不动
 *   BlockView 行内 LongPressGesture → onRowGrab(uuid, globalX, globalY)
 *   ↓ 手指移动
 *   本层 onTouch(TouchType.Move) → 命中测试 → 三态判定 → 指示线
 *   ↓ 抬手
 *   本层 onTouch(TouchType.Up) → EditorService.moveBlockToTarget(uuid, target, position)
 *
 * 为什么「移动」用 onTouch 而不是本层的 PanGesture：
 *   长按激活后手势竞技场已判定，此时再引入新的 Pan 识别器无法接管同一次触摸；
 *   而原始触摸事件在任何一方获胜后都会继续投递给命中节点（onTouch），
 *   因此本层用 onTouch 跟踪位移是可靠路径，同时 List 的滚动在长按获胜后已被判负，
 *   不会出现「拖拽中列表还在自己滚」的情况。
 */
@Component
export struct BlockDragLayer {
  /** 供命中测试与预览定位使用的本层根容器 id（getRectangleById 用） */
  private static readonly LAYER_ID: string = 'callaite_blockDragLayer';
  /**
   * 本实例的注册键（由所在整页 BlockList 生成，整页唯一）。
   * 用于把「整页所有行的长按上报」路由到本实例。
   */
  @Prop layerId: string = '';
  /**
   * 当前页 uuid（由 BlockList 注入）。
   * 用途：命中表里若残留别的页面的行记录（跨页复用/换页后的幽灵行），据此排除。
   */
  @Prop pageUuid: string = '';
  /** 与 BlockList 同一个 Scroller 实例（边缘自动滚动） */
  scroller?: Scroller;

  // ─── 拖拽状态（驱动覆盖层 UI） ───
  @State private dragging: boolean = false;
  @State private previewText: string = '';
  /** 预览卡位置（本层局部坐标，vp） */
  @State private previewLeft: number = 0;
  @State private previewTop: number = 0;
  /** 指示线是否可见 */
  @State private indicatorVisible: boolean = false;
  /** 落点行局部坐标（vp）与行高 */
  @State private dropTop: number = 0;
  @State private dropHeight: number = 0;
  /** child 态左侧内缩（用缩进层级表达「将成为谁的子块」） */
  @State private dropInset: number = 0;
  /** child 态为 true（画嵌套框），否则画水平线 */
  @State private dropIsChild: boolean = false;

  // ─── 拖拽内部状态（不参与 UI 刷新） ───
  /** 被拖拽 block uuid */
  private draggedUuid: string = '';
  /** 当前命中目标 uuid 与三态 */
  private targetUuid: string = '';
  private targetPosition: string = '';
  /** 本次移动是否会成为空操作（已在目标位置）→ 抬手时不落库 */
  private targetIsNoop: boolean = false;
  /** 手指最新窗口坐标（vp） */
  private fingerWindowX: number = 0;
  private fingerWindowY: number = 0;
  /** 本层根容器的窗口顶边（vp）—— 由 getRectangleById 结果换算，使局部坐标 = 窗口坐标 - 该值 */
  private layerWindowTop: number = 0;
  /** 本层高度（vp），用于边缘带判定 */
  private layerHeight: number = 0;
  /** 本层宽度（vp），用于预览卡右侧收边 */
  private layerWidth: number = 0;
  /** 正在自动滚动的方向：-1 上 / 0 无 / 1 下 */
  private edgeDir: number = 0;
  /** 自动滚动累计位移（vp），用于越界保护 */
  private edgeScrolled: number = 0;
  /** 自动滚动定时器 id */
  private edgeTimer: number = -1;
  /** 布局尚未就绪时的兜底：getRectangleById 失败后置 true，用 onAreaChange 的值 */
  private layerRectFromArea: boolean = false;
  /** onAreaChange 记录的窗口顶边（vp），作为 layerWindowTop 的兜底来源 */
  private layerAreaTop: number = 0;

  aboutToAppear(): void {
    this.syncLayerRect();
    // 自行注册到模块级实例表：父组件据此把行长按上报路由到本实例
    bindDragLayer(this.layerId, this);
  }

  aboutToDisappear(): void {
    this.stopEdgeScroll();
    unbindDragLayer(this.layerId, this);
  }

  // ─── 根容器：覆盖整个列表区域，命中模式 Transparent ───

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Stack 必须有内容才能测到尺寸；以下均为 0 尺寸占位（不可见、不可命中）
      Column()
        .width(0)
        .height(0)
        .hitTestBehavior(HitTestMode.None)

      // ─── 落点指示（覆盖层，1 个实例） ───
      if (this.indicatorVisible) {
        this.DropIndicator()
      }

      // ─── 拖拽预览（跟随手指） ───
      if (this.dragging) {
        this.DragPreview()
      }
    }
    .width('100%')
    .height('100%')
    // 命中模式 Transparent：本层自己（及其子节点）响应命中，同时**不阻塞兄弟节点**
    // （List）的命中 → List 的滚动、行内点击/长按均不受影响；
    // 本层的手势因此与 List 的滚动同处一个手势竞技场，谁先满足条件谁获胜。
    .hitTestBehavior(HitTestMode.Transparent)
    .id(BlockDragLayer.LAYER_ID)
    // 长按 500ms 未移动 → 本层赢得竞技场（此时 List 的滚动已判负）→ 进入拖拽态。
    // 之后手指移动只会触发这里；抬手/取消即收尾。
    .gesture(
      LongPressGesture({ fingers: 1, repeat: false, duration: DRAG_LONG_PRESS_MS })
        .onAction((event: GestureEvent) => {
          this.onLayerLongPress(event);
        })
        .onActionEnd(() => {
          this.finishDrag();
        })
        .onActionCancel(() => {
          this.cancelDrag();
        })
    )
    .onTouch((event: TouchEvent) => {
      this.onLayerTouch(event);
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const h = toVpNumber(newValue.height);
      const w = toVpNumber(newValue.width);
      if (h > 0) {
        this.layerHeight = h;
      }
      if (w > 0) {
        this.layerWidth = w;
      }
      this.layerAreaTop = toVpNumber(newValue.globalPosition.y);
      if (this.layerRectFromArea) {
        this.layerWindowTop = this.layerAreaTop;
      }
    })
  }

  // ─── 覆盖层视觉 ───

  /**
   * 落点指示线。与 BlockDragHandler.DropIndicator 的差异：
   *   · above/below 是**真实行矩形**的上下边（不是手势位移）；
   *   · child 额外画一个带缩进的嵌套框，明确「将成为该块的子块」。
   */
  @Builder
  DropIndicator() {
    if (this.dropIsChild) {
      Row() {
        Column()
          .width(2)
          .height('100%')
          .backgroundColor($r('app.color.primary'))
      }
      .width(BlockDragLayer.childBoxWidth(this.layerWidth, this.dropInset))
      .height(this.dropHeight)
      .margin({ left: this.dropInset + 2 })
      .borderRadius(3)
      .border({ width: 1, color: $r('app.color.primary') })
      .backgroundColor($r('app.color.surface2'))
      .opacity(0.55)
      .position({ x: 0, y: this.dropTop })
      // 指示层自身不可命中：拖拽期间手指仍必须落在本层根容器上
      .hitTestBehavior(HitTestMode.None)
    } else {
      Row()
        .width('100%')
        .height(2)
        .backgroundColor($r('app.color.primary'))
        .borderRadius(1)
        .position({ x: 0, y: this.dropTop })
        .hitTestBehavior(HitTestMode.None)
    }
  }

  /** 拖拽预览：被拖块的文本 + 图标，半透明跟随手指。 */
  @Builder
  DragPreview() {
    Row({ space: 6 }) {
      TablerIcon('grip-vertical', 14, $r('app.color.muted_text'))
      Text(this.previewText)
        .fontSize(14)
        .fontColor($r('app.color.text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width(200)
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.surface2'))
    .borderRadius(6)
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({ radius: 8, color: '#40000000', offsetX: 0, offsetY: 4 })
    .opacity(0.9)
    .position({ x: this.previewLeft, y: this.previewTop })
    .hitTestBehavior(HitTestMode.None)
  }

  // ─── 手势 / 触摸 ───

  /**
   * 本层长按（覆盖层自身的长按路径）。
   *
   * 与 BlockView 行内长按的关系：两者时长相同、同时起跑，行内长按会先（或同时）触发
   * onRowGrab 完成「按到哪一行」的绑定；本层长按作为兜底，在 onRowGrab 因故未到达时
   * 用按下点自行命中一次。二者都只做同一件事：enterDrag(uuid)。
   */
  private onLayerLongPress(event: GestureEvent): void {
    if (this.dragging) {
      return;
    }
    const x = BlockDragLayer.fingerX(event);
    const y = BlockDragLayer.fingerY(event);
    if (x >= 0 && y >= 0) {
      this.fingerWindowX = x;
      this.fingerWindowY = y;
    }
    const found = this.hitTestRow(this.fingerWindowY);
    if (found !== '') {
      this.enterDrag(found);
    }
  }

  /**
   * 行内长按回调（由 BlockView 通过 BlockList 转发）。
   *
   * @param uuid 被长按的 block uuid
   * @param globalX 按下点窗口 X（vp）
   * @param globalY 按下点窗口 Y（vp）
   */
  onRowGrab(uuid: string, globalX: number, globalY: number): void {
    if (uuid === '' || this.dragging) {
      return;
    }
    const rect = findBlockRowRect(uuid);
    if (rect === null) {
      // 该行尚未完成布局登记 → 保守放弃，不做任何猜测
      return;
    }
    if (globalX < 0 || globalY < 0) {
      // 手指信息不可用（键鼠/无触点）→ 不进入拖拽
      return;
    }
    // 一致性自检：上报点必须落在该行矩形内（容忍 12vp 的行间误差）。
    // 不满足说明手势来源与命中表不同步（例如复用瞬间）→ 保守放弃。
    const tolerance = 12;
    if (globalY < rect[0] - tolerance || globalY > rect[0] + rect[1] + tolerance) {
      this.logWarn('onRowGrab ignored: reported point is outside the row rect');
      return;
    }
    this.fingerWindowX = globalX;
    this.fingerWindowY = globalY;
    this.enterDrag(uuid);
  }

  private onLayerTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      if (!this.dragging) {
        // 上一次拖拽若因异常路径残留，按下即清干净
        this.resetDragState();
      }
      return;
    }
    if (event.type === TouchType.Move) {
      if (!this.dragging) {
        return;
      }
      const touch = BlockDragLayer.firstTouch(event);
      if (touch === null) {
        return;
      }
      this.fingerWindowX = touch.windowX;
      this.fingerWindowY = touch.windowY;
      this.applyFinger();
      this.syncEdgeScroll();
      return;
    }
    if (event.type === TouchType.Up) {
      if (this.dragging) {
        this.finishDrag();
      }
      return;
    }
    if (event.type === TouchType.Cancel) {
      if (this.dragging) {
        this.cancelDrag();
      }
      return;
    }
  }

  // ─── 拖拽生命周期 ───

  private enterDrag(uuid: string): void {
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(uuid);
    // 只在拖拽开始时取一次本层窗口偏移：拖拽过程中本层自身不移动
    // （滚动发生在 List 内部，行矩形由 onAreaChange 持续回填），
    // 因此无需在每个 Move 事件里再做一次 getRectangleById。
    this.syncLayerRect();
    this.draggedUuid = uuid;
    this.dragging = true;
    this.previewText = block ? block.content : uuid.substring(0, 8);
    this.targetUuid = '';
    this.targetPosition = '';
    this.targetIsNoop = false;
    this.indicatorVisible = false;
    this.edgeScrolled = 0;
    this.applyFinger();
    this.syncEdgeScroll();
  }

  /** 依据当前手指位置刷新命中、指示线与预览位置。 */
  private applyFinger(): void {
    if (!this.dragging) {
      return;
    }
    const top = this.fingerWindowY - this.layerWindowTop;
    const left = this.fingerWindowX;
    // 预览卡跟随手指，右/下边收在层内
    const previewW = 200;
    let px = left - 24;
    if (px + previewW > this.layerWidth && this.layerWidth > previewW) {
      px = this.layerWidth - previewW;
    }
    if (px < 0) {
      px = 0;
    }
    this.previewLeft = px;
    this.previewTop = top - 18 < 0 ? 0 : top - 18;

    const hit = this.hitTestRow(this.fingerWindowY);
    if (hit === '') {
      this.targetUuid = '';
      this.targetPosition = '';
      this.targetIsNoop = false;
      this.indicatorVisible = false;
      return;
    }
    this.targetUuid = hit;
    this.applyDropPosition(hit, this.decidePosition(hit, this.fingerWindowY));
  }

  /**
   * 三态判定：按**真实行矩形**（onAreaChange 登记的 height）而非硬编码行高。
   *   上 30% → above；下 30% → below；中间 40% → child。
   *
   * 两个保守降级：
   *   · 目标行本身不可作为 child 容器（空块 / 折叠块 / 自身 / 自己的后代）→ 降级为 below；
   *   · 自身即目标 → 不产生落点。
   */
  private decidePosition(targetUuid: string, windowY: number): string {
    if (targetUuid === this.draggedUuid) {
      return '';
    }
    const rect = findBlockRowRect(targetUuid);
    if (rect === null) {
      return '';
    }
    const top = rect[0];
    const height = rect[1];
    const ratio = (windowY - top) / height;
    if (ratio < BAND_ABOVE_RATIO) {
      return 'above';
    }
    if (ratio > BAND_BELOW_RATIO) {
      return 'below';
    }
    // 中间 40%：仅当目标确实能容纳子块时才允许 child
    if (!this.canAcceptChild(targetUuid)) {
      return 'below';
    }
    return 'child';
  }

  /**
   * 目标行是否可容纳子块。
   *
   * 数据安全：折叠块的子块在 UI 上完全不可见（BlockChildren 仅在 !collapsed 时渲染，
   * BlockList.ets:206-215），落到不可见的子位置等于「块凭空消失」→ 折叠目标降级为 below。
   * 自身与自身后代排除以防成环（moveBlock 会把源挂到自己的后代下，形成环 / 子树丢失）。
   */
  private canAcceptChild(targetUuid: string): boolean {
    const ws = WorkspaceService.getInstance();
    const target = ws.getBlock(targetUuid);
    if (!target) {
      return false;
    }
    if (target.collapsed) {
      return false;
    }
    if (targetUuid === this.draggedUuid) {
      return false;
    }
    if (this.isDescendantOf(targetUuid, this.draggedUuid)) {
      return false;
    }
    return true;
  }

  /** 记录落点并刷新指示线几何（全部换算到本层局部坐标）。 */
  private applyDropPosition(targetUuid: string, position: string): void {
    if (position === '') {
      this.targetUuid = '';
      this.targetPosition = '';
      this.indicatorVisible = false;
      return;
    }
    const rect = findBlockRowRect(targetUuid);
    if (rect === null) {
      this.targetUuid = '';
      this.targetPosition = '';
      this.indicatorVisible = false;
      return;
    }
    const rowTop = rect[0] - this.layerWindowTop;
    const rowHeight = rect[1];
    this.targetUuid = targetUuid;
    this.targetPosition = position;
    this.targetIsNoop = this.isNoopMove(targetUuid, position);
    this.dropHeight = rowHeight;
    this.dropIsChild = (position === 'child');
    if (position === 'above') {
      this.dropTop = rowTop;
      this.dropInset = 0;
    } else if (position === 'below') {
      this.dropTop = rowTop + rowHeight - 2;
      this.dropInset = 0;
    } else {
      this.dropTop = rowTop;
      this.dropInset = this.dropInsetFor(targetUuid);
    }
    this.indicatorVisible = !this.targetIsNoop;
  }

  /** child 态缩进：可表达「成为该块子块」的视觉预期。 */
  private dropInsetFor(candidateUuid: string): number {
    const ws = WorkspaceService.getInstance();
    const candidate = ws.getBlock(candidateUuid);
    if (!candidate) {
      return 0;
    }
    return 16 + (candidate.level + 1) * 24;
  }

  /**
   * 目标位置是否与当前父子/兄弟关系完全一致（移动将是无操作）。
   * 无操作仍会走一遍 op（并写盘），因此直接不落库、只收起 UI。
   */
  private isNoopMove(targetUuid: string, position: string): boolean {
    const ws = WorkspaceService.getInstance();
    const dragged = ws.getBlock(this.draggedUuid);
    const target = ws.getBlock(targetUuid);
    if (!dragged || !target) {
      return true;
    }
    if (position === 'child') {
      return dragged.parentId === targetUuid;
    }
    if (dragged.parentId !== target.parentId) {
      return false;
    }
    const siblings = ws.getChildrenOfBlock(target.parentId);
    for (let i = 0; i < siblings.length; i++) {
      if (siblings[i].uuid !== this.draggedUuid) {
        continue;
      }
      if (position === 'above') {
        // 已是目标的紧邻左兄弟 → 无操作
        return i + 1 < siblings.length && siblings[i + 1].uuid === targetUuid;
      }
      return i - 1 >= 0 && siblings[i - 1].uuid === targetUuid;
    }
    return false;
  }

  /** 抬手：唯一落库路径。 */
  private finishDrag(): void {
    const dragged = this.draggedUuid;
    const target = this.targetUuid;
    const position = this.targetPosition;
    const isNoop = this.targetIsNoop;
    this.resetDragState();

    if (dragged === '' || target === '' || position === '') {
      return;
    }
    if (isNoop) {
      return;
    }
    this.commitMove(dragged, target, position);
  }

  /** 取消：只收 UI，不落库。 */
  private cancelDrag(): void {
    this.resetDragState();
  }

  private resetDragState(): void {
    this.stopEdgeScroll();
    this.dragging = false;
    this.indicatorVisible = false;
    this.draggedUuid = '';
    this.targetUuid = '';
    this.targetPosition = '';
    this.targetIsNoop = false;
    this.dropIsChild = false;
    this.dropTop = 0;
    this.dropHeight = 0;
    this.dropInset = 0;
    this.edgeScrolled = 0;
  }

  /**
   * 落库 —— **唯一**数据出口。
   *
   * 三重守卫（宁可不动，不可动错）：
   *   1. 存在性：源/目标都必须还在树里；
   *   2. 自落：目标 == 源 → 丢弃；
   *   3. 成环：目标位于源的子树内 → 丢弃（此时 moveBlock 会把源挂到自己的后代下，
   *      产生环 / 子树丢失）。
   *
   * 通过守卫后只调用 EditorService.moveBlockToTarget —— 绝不在此拼 move-block op。
   * EditorService 内部走 executeOp → OutlinerEngine.doMoveBlock → BlockTree.moveBlock
   * → persistForOp → savePage，与其它所有移动操作同一条数据路径。
   */
  private commitMove(draggedUuid: string, targetUuid: string, position: string): void {
    const ws = WorkspaceService.getInstance();
    if (!ws.getBlock(draggedUuid) || !ws.getBlock(targetUuid)) {
      this.logWarn('commitMove skipped: source or target block not found');
      return;
    }
    if (this.isDescendantOf(targetUuid, draggedUuid)) {
      this.logWarn('commitMove skipped: target is inside dragged subtree (would create a cycle)');
      return;
    }
    this.logInfo('commitMove via EditorService.moveBlockToTarget position=' + position);
    EditorService.getInstance().moveBlockToTarget(draggedUuid, targetUuid, position);
    AppState.bumpBlocksVersion();
  }

  // ─── 命中测试 ───

  /**
   * 命中测试：把手指窗口 Y 换算成**列表局部坐标**后定位所在行。
   *
   * 这里刻意保留两级判定顺序：
   *   ① 先用 getRectangleById 把本层（= 列表可视区）的窗口左上角换成 vp，
   *      得到「局部坐标 = 窗口坐标 - 本层窗口顶」的换算基准；
   *   ② 行矩形来自 onAreaChange 登记的窗口坐标 vp，二者同源，直接相减即局部坐标。
   *
   * @returns 命中的 block uuid；无命中返回空串
   */
  private hitTestRow(windowY: number): string {
    let bestUuid = '';
    let bestLevel = -1;
    let bestSeq = -1;
    for (let i = 0; i < blockRowRects.length; i++) {
      const record = blockRowRects[i];
      if (record.height <= 0) {
        continue;
      }
      if (windowY < record.top || windowY > record.top + record.height) {
        continue;
      }
      // 幽灵行第二道防线：该 uuid 必须仍然存在于块树中；
      // 第三道：仍在同一页面内（跨页残留记录不得成为落点）
      if (!this.isLiveRow(record.uuid)) {
        continue;
      }
      // 父子行矩形天然重叠（父行包住整个子树）→ 层级最深者优先
      if (record.level > bestLevel || (record.level === bestLevel && record.seq > bestSeq)) {
        bestLevel = record.level;
        bestSeq = record.seq;
        bestUuid = record.uuid;
      }
    }
    return bestUuid;
  }

  /** 行是否仍然「活着」：块存在且属于当前页。 */
  private isLiveRow(uuid: string): boolean {
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(uuid);
    if (!block) {
      return false;
    }
    const pageUuid = ws.getPageUuidForBlock(uuid);
    if (pageUuid === undefined || pageUuid === '') {
      return false;
    }
    if (this.pageUuid === '') {
      return true;
    }
    return pageUuid === this.pageUuid;
  }

  /**
   * 用 UIContext 版 ComponentUtils 取本层矩形的窗口偏移。
   *
   * 为什么不用 `componentUtils.getRectangleById`：@ohos.arkui.componentUtils 的全局同名
   * 函数在本机 SDK（API 26）已 `@deprecated since 18`，官方 @useinstead 指向
   * UIContext.ComponentUtils#getRectangleById（@ohos.arkui.UIContext.d.ts:2509-2529）。
   *
   * 单位注意：ComponentInfo.windowOffset 的单位是 **px**（componentUtils.d.ts:59-69 / 165-190），
   * 而 Area / FingerInfo 全是 vp，故必须经 UIContext.px2vp 换算后再混用。
   */
  private syncLayerRect(): void {
    try {
      const ui = this.getUIContext();
      const info = ui.getComponentUtils().getRectangleById(BlockDragLayer.LAYER_ID);
      const h = ui.px2vp(info.size.height);
      if (h <= 0) {
        // 尚未完成布局：此时 windowOffset 无意义，转用 onAreaChange 的窗口坐标
        this.layerRectFromArea = true;
        this.layerWindowTop = this.layerAreaTop;
        return;
      }
      this.layerWindowTop = ui.px2vp(info.windowOffset.y);
      this.layerHeight = h;
      this.layerWidth = ui.px2vp(info.size.width);
      this.layerRectFromArea = false;
    } catch (e) {
      // 布局尚未完成 / 组件未挂载：回退到 onAreaChange 记录的窗口坐标
      this.layerRectFromArea = true;
      this.layerWindowTop = this.layerAreaTop;
    }
  }

  // ─── 边缘自动滚动 ───

  /** 依据手指是否落在上下 48vp 带内启停自动滚动。 */
  private syncEdgeScroll(): void {
    if (!this.dragging || this.layerHeight <= 0) {
      this.stopEdgeScroll();
      return;
    }
    const localY = this.fingerWindowY - this.layerWindowTop;
    let dir = 0;
    if (localY < EDGE_BAND_VP) {
      dir = -1;
    } else if (localY > this.layerHeight - EDGE_BAND_VP) {
      dir = 1;
    }
    if (dir === 0) {
      this.stopEdgeScroll();
      return;
    }
    if (this.edgeTimer !== -1 && this.edgeDir === dir) {
      return;
    }
    this.stopEdgeScroll();
    this.edgeDir = dir;
    this.edgeTimer = setInterval(() => {
      this.edgeTick();
    }, EDGE_SCROLL_INTERVAL_MS);
  }

  /**
   * 自动滚动一帧。
   *
   * 为什么用 Scroller.scrollBy(dx, dy)（scroll.d.ts:550，Length 参数）而不是 scrollToIndex：
   * 逐帧小幅滚动才有连续手感，且不依赖索引与像素的映射关系。
   * 滚动后**立即重算命中**：行矩形由 onAreaChange 在布局完成后回填，
   * 因此本帧末尾的命中用的是最新几何（下一帧的 onAreaChange 会继续修正）。
   */
  private edgeTick(): void {
    if (!this.dragging) {
      this.stopEdgeScroll();
      return;
    }
    const scroller = this.scroller;
    if (scroller === undefined) {
      this.stopEdgeScroll();
      return;
    }
    if (this.edgeScrolled > EDGE_SCROLL_LIMIT_VP) {
      this.stopEdgeScroll();
      return;
    }
    const dy = this.edgeDir * EDGE_SCROLL_STEP_VP;
    scroller.scrollBy(0, dy);
    this.edgeScrolled = this.edgeScrolled + (dy < 0 ? -dy : dy);
    // 滚动后重算命中（几何回填 + 命中重算，避免指示线停在滚动前的行上）
    this.applyFinger();
  }

  private stopEdgeScroll(): void {
    if (this.edgeTimer !== -1) {
      clearInterval(this.edgeTimer);
      this.edgeTimer = -1;
    }
    this.edgeDir = 0;
  }

  // ─── 循环防护 ───

  /**
   * candidateUuid 是否位于 ancestorUuid 的子树内（含自身）。
   * 带 visited 集合防脏数据成环导致死循环。
   */
  private isDescendantOf(candidateUuid: string, ancestorUuid: string): boolean {
    if (candidateUuid === '' || ancestorUuid === '') {
      return false;
    }
    if (candidateUuid === ancestorUuid) {
      return true;
    }
    const visited: string[] = [];
    let cursor = candidateUuid;
    while (cursor !== '') {
      let seen = false;
      for (let i = 0; i < visited.length; i++) {
        if (visited[i] === cursor) {
          seen = true;
          break;
        }
      }
      if (seen) {
        return true;
      }
      visited.push(cursor);
      const parent = this.parentOf(cursor);
      if (parent === '') {
        return false;
      }
      if (parent === ancestorUuid) {
        return true;
      }
      cursor = parent;
    }
    return false;
  }

  /** 取父 uuid；等于 pageId 或空串表示到顶。 */
  private parentOf(uuid: string): string {
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(uuid);
    if (!block) {
      return '';
    }
    if (block.parentId === uuid || block.parentId === block.pageId) {
      return '';
    }
    return block.parentId;
  }

  // ─── 静态工具 ───

  /** 取 TouchEvent 第一个触点（无触点返回 null）。 */
  private static firstTouch(event: TouchEvent): TouchObject | null {
    const list = event.touches;
    if (list === undefined || list.length === 0) {
      return null;
    }
    return list[0];
  }

  /** 取手势事件第一根手指的窗口 X（vp）；不可用返回 -1。 */
  private static fingerX(event: GestureEvent): number {
    const list = event.fingerList;
    if (list === undefined || list.length === 0) {
      return -1;
    }
    return list[0].globalX;
  }

  /** 取手势事件第一根手指的窗口 Y（vp）；不可用返回 -1。 */
  private static fingerY(event: GestureEvent): number {
    const list = event.fingerList;
    if (list === undefined || list.length === 0) {
      return -1;
    }
    return list[0].globalY;
  }

  /**
   * child 态嵌套框宽度：层宽 - 缩进 - 右侧留白，且**不小于 32vp**。
   * 极窄屏 + 深层嵌套时若算出非正宽度，绘制会退化（不可见或异常），故在此夹紧。
   */
  private static childBoxWidth(layerWidth: number, inset: number): number {
    const minWidth = 32;
    const width = layerWidth - inset - 4;
    if (width < minWidth) {
      return minWidth;
    }
    return width;
  }

  private logInfo(message: string): void {
    hilog.info(DRAG_LOG_DOMAIN, DRAG_LOG_TAG, '%{public}s', message);
  }

  private logWarn(message: string): void {
    hilog.warn(DRAG_LOG_DOMAIN, DRAG_LOG_TAG, '%{public}s', message);
  }
}
