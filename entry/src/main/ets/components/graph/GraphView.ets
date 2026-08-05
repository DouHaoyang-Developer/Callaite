import { WorkspaceService } from '../../services/WorkspaceService';
import { PageData } from '../../core/models/Page';
import { GraphLayout, GraphNode } from './GraphLayout';
import { AppState } from '../../state/AppState';
import { TablerIcon } from '../common/Icons';
import { GraphActions } from './GraphActions';

/**
 * Point — 屏幕坐标点（具名类型，替代内联对象类型以符合 ArkTS 约束）。
 */
interface Point {
  x: number;
  y: number;
}

/**
 * GraphView — 图谱视图。
 * 使用 Canvas 2D 渲染力导向布局的页面关系图。
 * 对应 Logseq extensions/graph/pixi.cljs (2677行)。
 *
 * 扩展能力：
 *  - PinchGesture 缩放（0.2x ~ 3x）
 *  - 节点拖拽（长按节点后拖动）
 *  - 画布平移（单指 Pan）
 *  - 按标签 / 命名空间筛选
 *  - 局部图谱模式（仅显示当前页面关联节点）
 *  - 节点大小按连接数动态计算（GraphLayout.build 内完成）
 *  - 节点颜色按类型（日志页/命名空间页/普通页）
 *  - 右下角缩放控制（+ / - / 重置）
 *  - 长按节点弹出操作菜单（GraphActions）
 */
@Component
export struct GraphView {
  @State private ready: boolean = false;
  @State private nodeCount: number = 0;
  @State private edgeCount: number = 0;
  /** 缩放比例（0.2 ~ 3）。命名 zoomScale，避免与组件 scale() 属性方法冲突 */
  @State private zoomScale: number = 1;
  /** 画布平移 X（屏幕坐标系，已含缩放） */
  @State private offsetX: number = 0;
  /** 画布平移 Y */
  @State private offsetY: number = 0;
  /** 标签筛选（空字符串表示不筛选） */
  @State private filterTag: string = '';
  /** 命名空间筛选（空字符串表示不筛选） */
  @State private filterNamespace: string = '';
  /** 局部图谱模式：仅显示当前页面关联节点 */
  @State private isLocalGraph: boolean = false;
  /** 是否显示节点操作菜单 */
  @State private showActions: boolean = false;
  /** 菜单屏幕 X */
  @State private actionX: number = 0;
  /** 菜单屏幕 Y */
  @State private actionY: number = 0;
  /** 菜单目标页面名 */
  @State private actionPageName: string = '';

  /** 当前页面名（用于局部图谱模式） */
  @Prop currentPageName: string = '';

  private layout: GraphLayout = new GraphLayout();
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D | undefined;
  private canvasWidth: number = 800;
  private canvasHeight: number = 600;

  /** 拖拽模式：'none' | 'node' | 'pan' */
  private dragMode: string = 'none';
  /** 被拖拽节点 uuid */
  private dragNodeUuid: string = '';
  /** 拖拽起点画布偏移 X */
  private panStartOffsetX: number = 0;
  /** 拖拽起点画布偏移 Y */
  private panStartOffsetY: number = 0;
  /** 拖拽起点节点逻辑 X */
  private dragNodeStartX: number = 0;
  /** 拖拽起点节点逻辑 Y */
  private dragNodeStartY: number = 0;

  /** 所有可用标签（筛选用） */
  @State private allTags: string[] = [];
  /** 所有命名空间（筛选用） */
  @State private allNamespaces: string[] = [];

  aboutToAppear(): void {
    this.rebuildLayout();
    const tags = WorkspaceService.getInstance().getAllTags();
    this.allTags = tags;
    this.allNamespaces = this.collectNamespaces();
  }

  /**
   * 收集所有命名空间（去重）。
   */
  private collectNamespaces(): string[] {
    const ws = WorkspaceService.getInstance();
    const pages = ws.getAllPages();
    const seen: Map<string, boolean> = new Map<string, boolean>();
    const result: string[] = [];
    for (let i = 0; i < pages.length; i++) {
      const ns = pages[i].namespace;
      if (ns.length > 0 && !seen.has(ns)) {
        seen.set(ns, true);
        result.push(ns);
      }
    }
    return result;
  }

  /**
   * 根据当前筛选条件重建布局。
   */
  rebuildLayout(): void {
    const ws = WorkspaceService.getInstance();
    let pages: PageData[] = ws.getAllPages();

    // 局部图谱模式：仅保留当前页面及其直接关联节点
    if (this.isLocalGraph && this.currentPageName.length > 0) {
      pages = this.filterLocalPages(pages, this.currentPageName);
    } else {
      // 标签筛选
      if (this.filterTag.length > 0) {
        pages = ws.getPagesByTag(this.filterTag);
      }
      // 命名空间筛选
      if (this.filterNamespace.length > 0) {
        const filtered: PageData[] = [];
        for (let i = 0; i < pages.length; i++) {
          if (pages[i].namespace === this.filterNamespace) {
            filtered.push(pages[i]);
          }
        }
        pages = filtered;
      }
    }

    this.layout.build(pages, this.canvasWidth, this.canvasHeight);
    this.layout.simulate(100);
    this.layout.detectClusters();
    this.nodeCount = this.layout.getNodes().length;
    this.edgeCount = this.layout.getEdges().length;
    this.ready = true;
    this.drawGraph();
  }

  /**
   * 局部图谱：返回当前页面 + 与之有边相连的所有页面。
   */
  private filterLocalPages(allPages: PageData[], centerName: string): PageData[] {
    const ws = WorkspaceService.getInstance();
    const center = ws.getPageByName(centerName);
    if (!center) {
      return allPages;
    }
    const keep: Map<string, boolean> = new Map<string, boolean>();
    keep.set(center.uuid, true);
    // 出链：center 引用的页面
    const blocks = ws.getPageBlocks(center.uuid);
    for (let bi = 0; bi < blocks.length; bi++) {
      for (let ri = 0; ri < blocks[bi].refs.length; ri++) {
        const refPage = ws.getPageByName(blocks[bi].refs[ri]);
        if (refPage) {
          keep.set(refPage.uuid, true);
        }
      }
    }
    // 入链：引用 center 的页面（反链）
    const backlinks = ws.getDataStore().getBacklinks(center.name);
    for (let bi = 0; bi < backlinks.length; bi++) {
      const srcPageUuid = ws.getDataStore().getIndexStore().getPageUuidForBlock(backlinks[bi].sourceBlockId);
      if (srcPageUuid) {
        keep.set(srcPageUuid, true);
      }
    }
    const result: PageData[] = [];
    for (let i = 0; i < allPages.length; i++) {
      if (keep.has(allPages[i].uuid)) {
        result.push(allPages[i]);
      }
    }
    return result;
  }

  build() {
    Column({ space: 8 }) {
      // 顶部工具栏
      Row({ space: 12 }) {
        Row({ space: 4 }) {
          TablerIcon('arrow-left', 18, $r('app.color.text'))
        }
        .width(32).height(32)
        .onClick(() => { AppState.setCurrentPage('Journal'); })

        Text('图谱关系')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
          .layoutWeight(1)

        Text(this.nodeCount + ' 节点 · ' + this.edgeCount + ' 连线')
          .fontSize(12).fontColor($r('app.color.muted_text'))
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      // 筛选栏
      Row({ space: 8 }) {
        // 局部图谱开关
        Row({ space: 4 }) {
          TablerIcon(this.isLocalGraph ? 'focus-2' : 'focus', 14,
            this.isLocalGraph ? $r('app.color.primary') : $r('app.color.muted_text'))
          Text('局部')
            .fontSize(11)
            .fontColor(this.isLocalGraph ? $r('app.color.primary') : $r('app.color.muted_text'))
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(4)
        .backgroundColor(this.isLocalGraph ? $r('app.color.surface2') : $r('app.color.surface1'))
        .onClick(() => {
          this.isLocalGraph = !this.isLocalGraph;
          this.rebuildLayout();
        })

        // 标签筛选下拉
        Select(this.getTagOptions())
          .value(this.filterTag.length > 0 ? this.filterTag : '标签')
          .selected(this.getTagSelectedIndex())
          .font({ size: 11 })
          .height(28)
          .backgroundColor($r('app.color.surface1'))
          .onSelect((index: number) => {
            this.filterTag = index === 0 ? '' : this.allTags[index - 1];
            this.rebuildLayout();
          })

        // 命名空间筛选下拉
        Select(this.getNamespaceOptions())
          .value(this.filterNamespace.length > 0 ? this.filterNamespace : '命名空间')
          .selected(this.getNamespaceSelectedIndex())
          .font({ size: 11 })
          .height(28)
          .backgroundColor($r('app.color.surface1'))
          .onSelect((index: number) => {
            this.filterNamespace = index === 0 ? '' : this.allNamespaces[index - 1];
            this.rebuildLayout();
          })

        // 重置筛选
        if (this.filterTag.length > 0 || this.filterNamespace.length > 0 || this.isLocalGraph) {
          Row({ space: 4 }) {
            TablerIcon('x', 14, $r('app.color.danger'))
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(4)
          .backgroundColor($r('app.color.surface1'))
          .onClick(() => {
            this.filterTag = '';
            this.filterNamespace = '';
            this.isLocalGraph = false;
            this.rebuildLayout();
          })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 4 })

      // Canvas 画布 + 浮动控件
      Stack({ alignContent: Alignment.BottomEnd }) {
        Canvas(this.ctx)
          .width('100%')
          .layoutWeight(1)
          .backgroundColor($r('app.color.surface1'))
          .onReady(() => {
            this.drawGraph();
          })
          .gesture(
            // 缩放（双指）
            PinchGesture({ fingers: 2 })
              .onActionUpdate((event: GestureEvent) => {
                const next = this.zoomScale * event.scale;
                this.zoomScale = Math.max(0.2, Math.min(3, next));
                this.drawGraph();
              })
              .onActionEnd(() => {
                this.drawGraph();
              })
          )
          .parallelGesture(
            // 长按节点 → 弹出操作菜单
            LongPressGesture({ duration: 500 })
              .onAction((event: GestureEvent) => {
                this.handleLongPress(event);
              })
          )
          .gesture(
            // 单指拖动：平移画布或拖拽节点
            PanGesture({ fingers: 1 })
              .onActionStart((event: GestureEvent) => {
                this.handlePanStart(event);
              })
              .onActionUpdate((event: GestureEvent) => {
                this.handlePanUpdate(event);
              })
              .onActionEnd(() => {
                this.dragMode = 'none';
                this.dragNodeUuid = '';
              })
          )
          .onClick((event: ClickEvent) => {
            this.handleTap(event);
          })

        // 右下角缩放控制
        Column({ space: 6 }) {
          Row() {
            TablerIcon('plus', 16, $r('app.color.text'))
          }
          .width(32).height(32)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .borderRadius(16)
          .backgroundColor($r('app.color.surface2'))
          .onClick(() => { this.zoomIn(); })

          Row() {
            TablerIcon('minus', 16, $r('app.color.text'))
          }
          .width(32).height(32)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .borderRadius(16)
          .backgroundColor($r('app.color.surface2'))
          .onClick(() => { this.zoomOut(); })

          Row() {
            Text(Math.round(this.zoomScale * 100) + '%')
              .fontSize(10).fontColor($r('app.color.muted_text'))
          }
          .width(32).height(20)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .borderRadius(10)
          .backgroundColor($r('app.color.surface2'))

          Row() {
            TablerIcon('refresh', 14, $r('app.color.text'))
          }
          .width(32).height(32)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .borderRadius(16)
          .backgroundColor($r('app.color.surface2'))
          .onClick(() => { this.resetView(); })
        }
        .padding({ right: 12, bottom: 12 })

        // 节点操作浮动菜单
        if (this.showActions) {
          GraphActions({
            pageName: this.actionPageName,
            isVisible: this.showActions,
            positionX: this.actionX,
            positionY: this.actionY,
            onClose: () => {
              this.showActions = false;
            }
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface0'))
  }

  /**
   * 构建标签下拉选项。
   */
  getTagOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    options.push({ value: '全部标签' });
    for (let i = 0; i < this.allTags.length; i++) {
      options.push({ value: this.allTags[i] });
    }
    return options;
  }

  getTagSelectedIndex(): number {
    if (this.filterTag.length === 0) return 0;
    for (let i = 0; i < this.allTags.length; i++) {
      if (this.allTags[i] === this.filterTag) return i + 1;
    }
    return 0;
  }

  getNamespaceOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    options.push({ value: '全部命名空间' });
    for (let i = 0; i < this.allNamespaces.length; i++) {
      options.push({ value: this.allNamespaces[i] });
    }
    return options;
  }

  getNamespaceSelectedIndex(): number {
    if (this.filterNamespace.length === 0) return 0;
    for (let i = 0; i < this.allNamespaces.length; i++) {
      if (this.allNamespaces[i] === this.filterNamespace) return i + 1;
    }
    return 0;
  }

  /**
   * 绘制图谱：应用 scale + offset 变换。
   */
  drawGraph(): void {
    if (!this.ctx) return;
    const ctx = this.ctx;
    const w = this.canvasWidth;
    const h = this.canvasHeight;
    const s = this.zoomScale;

    ctx.clearRect(0, 0, w, h);

    // 绘制连线
    const edges = this.layout.getEdges();
    ctx.strokeStyle = '#D1D5DB';
    ctx.lineWidth = 1;
    for (let i = 0; i < edges.length; i++) {
      const src = this.findNode(edges[i].source);
      const tgt = this.findNode(edges[i].target);
      if (src && tgt) {
        const sx = src.x * s + this.offsetX;
        const sy = src.y * s + this.offsetY;
        const tx = tgt.x * s + this.offsetX;
        const ty = tgt.y * s + this.offsetY;
        ctx.beginPath();
        ctx.moveTo(sx, sy);
        ctx.lineTo(tx, ty);
        ctx.stroke();
      }
    }

    // 绘制节点
    const nodes = this.layout.getNodes();
    for (let i = 0; i < nodes.length; i++) {
      const nx = nodes[i].x * s + this.offsetX;
      const ny = nodes[i].y * s + this.offsetY;
      const r = nodes[i].radius * s;

      // 颜色按类型
      ctx.beginPath();
      ctx.arc(nx, ny, r, 0, Math.PI * 2);
      ctx.fillStyle = this.nodeColor(nodes[i]);
      ctx.fill();
      ctx.strokeStyle = '#FFFFFF';
      ctx.lineWidth = 2;
      ctx.stroke();

      // 标签（仅当缩放足够大时显示）
      if (s > 0.5) {
        ctx.font = '11px sans-serif';
        ctx.fillStyle = '#1A1A1A';
        ctx.textAlign = 'center';
        const label = nodes[i].pageName.length > 12
          ? nodes[i].pageName.substring(0, 12)
          : nodes[i].pageName;
        ctx.fillText(label, nx, ny + r + 14);
      }
    }
  }

  /**
   * 节点颜色：日志页绿 / 命名空间页蓝 / 普通页紫。
   */
  private nodeColor(node: GraphNode): string {
    if (node.isJournal) {
      return '#10B981';
    }
    if (node.namespace.length > 0) {
      return '#0078D4';
    }
    return '#8B5CF6';
  }

  /**
   * 屏幕坐标 → 逻辑坐标。
   */
  private toLocal(screenX: number, screenY: number): Point {
    const lx = (screenX - this.offsetX) / this.zoomScale;
    const ly = (screenY - this.offsetY) / this.zoomScale;
    const p: Point = { x: lx, y: ly };
    return p;
  }

  /**
   * 命中检测：返回点击位置下的节点，未命中返回 undefined。
   */
  private hitTest(screenX: number, screenY: number): GraphNode | undefined {
    const local = this.toLocal(screenX, screenY);
    const nodes = this.layout.getNodes();
    for (let i = nodes.length - 1; i >= 0; i--) {
      const dx = local.x - nodes[i].x;
      const dy = local.y - nodes[i].y;
      const hitR = nodes[i].radius + 6;
      if (Math.sqrt(dx * dx + dy * dy) < hitR) {
        return nodes[i];
      }
    }
    return undefined;
  }

  handleTap(event: ClickEvent): void {
    const node = this.hitTest(event.x, event.y);
    if (node) {
      AppState.setCurrentPage(node.pageName);
    }
  }

  handleLongPress(event: GestureEvent): void {
    // GestureEvent 无 x/y 属性，从 fingerList 取触摸点局部坐标
    const finger: FingerInfo | undefined = event.fingerList[0];
    if (finger === undefined) {
      return;
    }
    const node = this.hitTest(finger.localX, finger.localY);
    if (node) {
      this.actionPageName = node.pageName;
      this.actionX = finger.localX;
      this.actionY = finger.localY;
      this.showActions = true;
    }
  }

  handlePanStart(event: GestureEvent): void {
    // GestureEvent 无 x/y 属性，从 fingerList 取触摸点局部坐标
    const finger: FingerInfo | undefined = event.fingerList[0];
    if (finger === undefined) {
      return;
    }
    const node = this.hitTest(finger.localX, finger.localY);
    if (node) {
      this.dragMode = 'node';
      this.dragNodeUuid = node.pageUuid;
      this.dragNodeStartX = node.x;
      this.dragNodeStartY = node.y;
    } else {
      this.dragMode = 'pan';
      this.panStartOffsetX = this.offsetX;
      this.panStartOffsetY = this.offsetY;
    }
  }

  handlePanUpdate(event: GestureEvent): void {
    if (this.dragMode === 'node' && this.dragNodeUuid.length > 0) {
      const node = this.findNode(this.dragNodeUuid);
      if (node) {
        node.x = this.dragNodeStartX + event.offsetX / this.zoomScale;
        node.y = this.dragNodeStartY + event.offsetY / this.zoomScale;
        this.drawGraph();
      }
    } else if (this.dragMode === 'pan') {
      this.offsetX = this.panStartOffsetX + event.offsetX;
      this.offsetY = this.panStartOffsetY + event.offsetY;
      this.drawGraph();
    }
  }

  zoomIn(): void {
    this.zoomScale = Math.min(3, this.zoomScale * 1.2);
    this.drawGraph();
  }

  zoomOut(): void {
    this.zoomScale = Math.max(0.2, this.zoomScale / 1.2);
    this.drawGraph();
  }

  resetView(): void {
    this.zoomScale = 1;
    this.offsetX = 0;
    this.offsetY = 0;
    this.drawGraph();
  }

  findNode(uuid: string): GraphNode | undefined {
    const nodes = this.layout.getNodes();
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].pageUuid === uuid) return nodes[i];
    }
    return undefined;
  }
}
