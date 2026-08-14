import { AppState } from '../../state/AppState';
import { TablerIcon } from '../common/Icons';
import { WbShape, WbShapeData } from './WbShape';
import { WbConnector, WbConnectorData } from './WbConnector';
import { WbPageRef, WbPageRefData } from './WbPageRef';
import { PenKitService, PenBrushType, StrokePoint, StrokeData, BrushPresetItem } from '../../services/PenKitService';

/**
 * 白板导出数据格式 — .canvas 文件 JSON 结构。
 */
interface WbExportData {
  shapes: WbShapeData[];
  connectors: WbConnectorData[];
  strokes: StrokeData[];
}

/**
 * 工具栏按钮配置。
 */
interface ToolConfig {
  icon: string;
  tool: string;
}

/**
 * Whiteboard — Logseq 风格白板组件。
 *
 * 功能：
 *  - 无限画布（PanGesture 平移 + PinchGesture 缩放）
 *  - 6 种工具：选择/矩形/椭圆/菱形/文本/连线
 *  - 撤销/重做栈（50 层）
 *  - 形状渲染（Stack + ForEach 绝对定位）
 *  - 网格背景（Canvas 2D，随缩放变化）
 *  - .canvas 文件持久化接口（exportCanvas/importCanvas）
 */
@Component
export struct Whiteboard {
  // ─── 画布状态 ───
  @State private scaleValue: number = 1;
  @State private offsetX: number = 0;
  @State private offsetY: number = 0;
  @State private zoomPercent: number = 100;

  // ─── 形状数据 ───
  @State private shapes: WbShapeData[] = [];
  @State private connectors: WbConnectorData[] = [];
  @State private pageRefs: WbPageRefData[] = [];

  // ─── 手写笔触数据 ───
  @State private strokes: StrokeData[] = [];
  @State private showBrushPanel: boolean = false;
  @State private currentBrushType: PenBrushType = PenBrushType.PEN;
  @State private currentBrushColor: number = 0xFF0458A6;
  @State private currentBrushSize: number = 4;

  // ─── 交互状态 ───
  @State private selectedShapeId: string = '';
  @State private editingShapeId: string = '';
  @State private currentTool: string = 'select';
  @State private isDrawing: boolean = false;
  @State private drawStartX: number = 0;
  @State private drawStartY: number = 0;
  @State private drawCurrentX: number = 0;
  @State private drawCurrentY: number = 0;

  // ─── Canvas 2D 上下文 ───
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasWidth: number = 800;
  private canvasHeight: number = 600;

  // ─── 手势辅助 ───
  private lastTouchX: number = 0;
  private lastTouchY: number = 0;
  private panAccumX: number = 0;
  private panAccumY: number = 0;
  private panBaseOffsetX: number = 0;
  private panBaseOffsetY: number = 0;
  private baseScale: number = 1;

  // ─── 拖拽形状 ───
  private isDraggingShape: boolean = false;
  private dragShapeId: string = '';
  private dragStartShapeX: number = 0;
  private dragStartShapeY: number = 0;

  // ─── 双击检测 ───
  private lastTapTime: number = 0;

  // ─── 撤销/重做栈 ───
  private undoStack: WbShapeData[][] = [];
  private redoStack: WbShapeData[][] = [];
  private strokesUndoStack: StrokeData[][] = [];
  private strokesRedoStack: StrokeData[][] = [];
  private shapeCounter: number = 0;

  // ─── 手写笔服务 ───
  private penKit: PenKitService = PenKitService.getInstance();
  private currentStrokePoints: StrokePoint[] = [];
  private currentPressure: number = 1.0;
  private brushPresets: BrushPresetItem[] = [];
  private presetColors: number[] = [];

  // ─── 工具栏配置 ───
  private tools: ToolConfig[] = [
    { icon: 'mouse', tool: 'select' },
    { icon: 'rectangle', tool: 'rect' },
    { icon: 'circle', tool: 'ellipse' },
    { icon: 'diamond', tool: 'diamond' },
    { icon: 'text-caption', tool: 'text' },
    { icon: 'line', tool: 'line' },
    { icon: 'pencil', tool: 'pen' }
  ];

  aboutToAppear(): void {
    // 初始化示例数据
    this.initDemoData();
    // 初始化手写笔服务
    this.brushPresets = this.penKit.getBrushPresets();
    this.presetColors = this.penKit.getPresetColors();
  }

  /**
   * 初始化演示数据 — 2 个形状 + 1 条连线 + 1 个页面引用。
   */
  private initDemoData(): void {
    const s1: WbShapeData = {
      id: 'shape_demo_1', type: 'rect', x: 100, y: 80,
      width: 160, height: 80, text: '欢迎使用白板',
      fillColor: '#F3F3F4', borderColor: '#0458A6', rotation: 0
    };
    const s2: WbShapeData = {
      id: 'shape_demo_2', type: 'ellipse', x: 320, y: 200,
      width: 120, height: 120, text: '拖拽捏合\n探索画布',
      fillColor: '#EAEAEB', borderColor: '#0458A6', rotation: 0
    };
    const c1: WbConnectorData = {
      id: 'conn_demo_1', fromShapeId: 'shape_demo_1', toShapeId: 'shape_demo_2',
      fromPoint: { x: 260, y: 120 }, toPoint: { x: 320, y: 260 },
      type: 'curved', color: '#787B80'
    };
    const pr1: WbPageRefData = {
      id: 'pageref_demo_1', pageName: 'Journal',
      x: 120, y: 260, width: 160, height: 80, blockCount: 12
    };
    this.shapes = [s1, s2];
    this.connectors = [c1];
    this.pageRefs = [pr1];
  }

  // ═══════════════════════════════════════════
  //  形状操作方法
  // ═══════════════════════════════════════════

  /**
   * 生成唯一形状 ID。
   */
  private generateShapeId(): string {
    this.shapeCounter++;
    return 'shape_' + Date.now() + '_' + this.shapeCounter;
  }

  /**
   * 添加新形状到画布。
   */
  addShape(type: string, x: number, y: number, w: number, h: number): void {
    this.pushHistory();
    const id = this.generateShapeId();
    const shape: WbShapeData = {
      id: id,
      type: type,
      x: x,
      y: y,
      width: w,
      height: h,
      text: '',
      fillColor: '#F3F3F4',
      borderColor: '#0458A6',
      rotation: 0
    };
    if (type === 'text') {
      shape.text = '双击编辑';
    }
    if (type === 'line') {
      shape.fillColor = 'transparent';
    }
    const newShapes: WbShapeData[] = [];
    for (let i = 0; i < this.shapes.length; i++) {
      newShapes.push(this.shapes[i]);
    }
    newShapes.push(shape);
    this.shapes = newShapes;
    this.selectedShapeId = id;
  }

  /**
   * 选中形状。
   */
  selectShape(id: string): void {
    this.selectedShapeId = id;
    this.editingShapeId = '';
  }

  /**
   * 移动形状（相对偏移）。
   */
  moveShape(id: string, dx: number, dy: number): void {
    const newShapes: WbShapeData[] = [];
    for (let i = 0; i < this.shapes.length; i++) {
      const s = this.shapes[i];
      if (s.id === id) {
        newShapes.push({
          id: s.id, type: s.type, x: s.x + dx, y: s.y + dy,
          width: s.width, height: s.height, text: s.text,
          fillColor: s.fillColor, borderColor: s.borderColor, rotation: s.rotation
        });
      } else {
        newShapes.push(s);
      }
    }
    this.shapes = newShapes;
  }

  /**
   * 设置形状绝对位置（拖拽时使用）。
   */
  private setShapePosition(id: string, x: number, y: number): void {
    const newShapes: WbShapeData[] = [];
    for (let i = 0; i < this.shapes.length; i++) {
      const s = this.shapes[i];
      if (s.id === id) {
        newShapes.push({
          id: s.id, type: s.type, x: x, y: y,
          width: s.width, height: s.height, text: s.text,
          fillColor: s.fillColor, borderColor: s.borderColor, rotation: s.rotation
        });
      } else {
        newShapes.push(s);
      }
    }
    this.shapes = newShapes;
  }

  /**
   * 删除形状。
   */
  deleteShape(id: string): void {
    this.pushHistory();
    const newShapes: WbShapeData[] = [];
    for (let i = 0; i < this.shapes.length; i++) {
      if (this.shapes[i].id !== id) {
        newShapes.push(this.shapes[i]);
      }
    }
    this.shapes = newShapes;
    if (this.selectedShapeId === id) {
      this.selectedShapeId = '';
    }
    if (this.editingShapeId === id) {
      this.editingShapeId = '';
    }
  }

  /**
   * 更新形状文本。
   */
  private updateShapeText(id: string, text: string): void {
    const newShapes: WbShapeData[] = [];
    for (let i = 0; i < this.shapes.length; i++) {
      const s = this.shapes[i];
      if (s.id === id) {
        newShapes.push({
          id: s.id, type: s.type, x: s.x, y: s.y,
          width: s.width, height: s.height, text: text,
          fillColor: s.fillColor, borderColor: s.borderColor, rotation: s.rotation
        });
      } else {
        newShapes.push(s);
      }
    }
    this.shapes = newShapes;
  }

  // ═══════════════════════════════════════════
  //  撤销/重做
  // ═══════════════════════════════════════════

  /**
   * 深拷贝形状数组（替代 spread）。
   */
  private deepCopyShapes(shapes: WbShapeData[]): WbShapeData[] {
    const copy: WbShapeData[] = [];
    for (let i = 0; i < shapes.length; i++) {
      const s = shapes[i];
      copy.push({
        id: s.id, type: s.type, x: s.x, y: s.y,
        width: s.width, height: s.height, text: s.text,
        fillColor: s.fillColor, borderColor: s.borderColor, rotation: s.rotation
      });
    }
    return copy;
  }

  /**
   * 深拷贝笔触数组（替代 spread）。
   */
  private deepCopyStrokes(strokes: StrokeData[]): StrokeData[] {
    const copy: StrokeData[] = [];
    for (let i = 0; i < strokes.length; i++) {
      const stk = strokes[i];
      const pts: StrokePoint[] = [];
      for (let j = 0; j < stk.points.length; j++) {
        const p = stk.points[j];
        pts.push({ x: p.x, y: p.y, pressure: p.pressure, timestamp: p.timestamp });
      }
      copy.push({
        id: stk.id, brushType: stk.brushType, color: stk.color,
        baseSize: stk.baseSize, opacity: stk.opacity, points: pts
      });
    }
    return copy;
  }

  /**
   * 推入撤销栈（保存当前状态快照，含形状和笔触）。
   */
  private pushHistory(): void {
    const snapshot: WbShapeData[] = this.deepCopyShapes(this.shapes);
    this.undoStack.push(snapshot);
    if (this.undoStack.length > 50) {
      this.undoStack.shift();
    }
    this.redoStack = [];

    const strokeSnapshot: StrokeData[] = this.deepCopyStrokes(this.strokes);
    this.strokesUndoStack.push(strokeSnapshot);
    if (this.strokesUndoStack.length > 50) {
      this.strokesUndoStack.shift();
    }
    this.strokesRedoStack = [];
  }

  /**
   * 撤销。
   */
  undo(): void {
    if (this.undoStack.length === 0) return;
    const current: WbShapeData[] = this.deepCopyShapes(this.shapes);
    this.redoStack.push(current);
    const prev = this.undoStack.pop();
    if (prev) {
      this.shapes = prev;
      this.selectedShapeId = '';
      this.editingShapeId = '';
    }
    // 笔触撤销
    if (this.strokesUndoStack.length > 0) {
      const curStrokes: StrokeData[] = this.deepCopyStrokes(this.strokes);
      this.strokesRedoStack.push(curStrokes);
      const prevStrokes = this.strokesUndoStack.pop();
      if (prevStrokes) {
        this.strokes = prevStrokes;
      }
    }
    this.drawGrid();
  }

  /**
   * 重做。
   */
  redo(): void {
    if (this.redoStack.length === 0) return;
    const current: WbShapeData[] = this.deepCopyShapes(this.shapes);
    this.undoStack.push(current);
    const next = this.redoStack.pop();
    if (next) {
      this.shapes = next;
      this.selectedShapeId = '';
      this.editingShapeId = '';
    }
    // 笔触重做
    if (this.strokesRedoStack.length > 0) {
      const curStrokes: StrokeData[] = this.deepCopyStrokes(this.strokes);
      this.strokesUndoStack.push(curStrokes);
      const nextStrokes = this.strokesRedoStack.pop();
      if (nextStrokes) {
        this.strokes = nextStrokes;
      }
    }
    this.drawGrid();
  }

  // ═══════════════════════════════════════════
  //  导入/导出
  // ═══════════════════════════════════════════

  /**
   * 导出画布为 JSON 字符串（.canvas 文件格式）。
   * 实际持久化由 WhiteboardFileService 处理（预留接口）。
   */
  exportCanvas(): string {
    const data: WbExportData = {
      shapes: this.shapes,
      connectors: this.connectors,
      strokes: this.strokes
    };
    return JSON.stringify(data);
  }

  /**
   * 从 JSON 字符串导入画布。
   */
  importCanvas(json: string): void {
    try {
      const data = JSON.parse(json) as WbExportData;
      this.pushHistory();
      this.shapes = data.shapes;
      this.connectors = data.connectors;
      if (data.strokes) {
        this.strokes = data.strokes;
      } else {
        this.strokes = [];
      }
      this.selectedShapeId = '';
      this.editingShapeId = '';
      this.drawGrid();
    } catch (e) {
      console.error('[Whiteboard] 导入失败', e);
    }
  }

  // ═══════════════════════════════════════════
  //  命中测试 & 点击处理
  // ═══════════════════════════════════════════

  /**
   * 命中测试：返回指定画布坐标下的形状 ID。
   */
  private hitTestShape(canvasX: number, canvasY: number): string {
    for (let i = this.shapes.length - 1; i >= 0; i--) {
      const s = this.shapes[i];
      if (canvasX >= s.x && canvasX <= s.x + s.width &&
        canvasY >= s.y && canvasY <= s.y + s.height) {
        return s.id;
      }
    }
    return '';
  }

  /**
   * 判断点是否在指定形状内。
   */
  private isPointInShape(canvasX: number, canvasY: number, shapeId: string): boolean {
    for (let i = 0; i < this.shapes.length; i++) {
      const s = this.shapes[i];
      if (s.id === shapeId) {
        return canvasX >= s.x && canvasX <= s.x + s.width &&
          canvasY >= s.y && canvasY <= s.y + s.height;
      }
    }
    return false;
  }

  /**
   * 查找形状 by ID。
   */
  private findShape(id: string): WbShapeData | undefined {
    for (let i = 0; i < this.shapes.length; i++) {
      if (this.shapes[i].id === id) {
        return this.shapes[i];
      }
    }
    return undefined;
  }

  /**
   * 处理形状点击（含双击检测进入文本编辑）。
   */
  private handleShapeTap(id: string): void {
    const now = Date.now();
    const shape = this.findShape(id);
    if (shape && shape.type === 'text' &&
      id === this.selectedShapeId &&
      now - this.lastTapTime < 350) {
      this.editingShapeId = id;
      return;
    }
    this.lastTapTime = now;
    this.selectedShapeId = id;
    this.editingShapeId = '';
  }

  // ═══════════════════════════════════════════
  //  绘制预览
  // ═══════════════════════════════════════════

  /**
   * 获取绘制预览形状数据。
   */
  private getPreviewShape(): WbShapeData {
    const w = Math.abs(this.drawCurrentX - this.drawStartX);
    const h = Math.abs(this.drawCurrentY - this.drawStartY);
    const x = Math.min(this.drawStartX, this.drawCurrentX);
    const y = Math.min(this.drawStartY, this.drawCurrentY);
    return {
      id: 'preview',
      type: this.currentTool,
      x: x,
      y: y,
      width: w,
      height: h,
      text: '',
      fillColor: 'rgba(4, 88, 166, 0.1)',
      borderColor: '#0458A6',
      rotation: 0
    };
  }

  /**
   * 预览形状屏幕 X 坐标。
   */
  private getPreviewScreenX(): number {
    return Math.min(this.drawStartX, this.drawCurrentX) * this.scaleValue + this.offsetX;
  }

  /**
   * 预览形状屏幕 Y 坐标。
   */
  private getPreviewScreenY(): number {
    return Math.min(this.drawStartY, this.drawCurrentY) * this.scaleValue + this.offsetY;
  }

  /**
   * 完成绘制：创建最终形状。
   */
  private finalizeShape(): void {
    const dx = this.drawCurrentX - this.drawStartX;
    const dy = this.drawCurrentY - this.drawStartY;
    const w = Math.abs(dx);
    const h = Math.abs(dy);
    if (w < 10 && h < 10) return;
    const x = Math.min(this.drawStartX, this.drawCurrentX);
    const y = Math.min(this.drawStartY, this.drawCurrentY);
    this.addShape(this.currentTool, x, y, w, h);
  }

  // ═══════════════════════════════════════════
  //  网格 & 笔触绘制
  // ═══════════════════════════════════════════

  /**
   * 绘制网格背景（随缩放变化间距）+ 笔触。
   */
  drawGrid(): void {
    const ctx = this.ctx;
    const w = this.canvasWidth;
    const h = this.canvasHeight;
    ctx.clearRect(0, 0, w, h);
    // 网格
    const baseGridSize = 40;
    const gridSize = baseGridSize * this.scaleValue;
    if (gridSize >= 8) {
      const startX = ((this.offsetX % gridSize) + gridSize) % gridSize;
      const startY = ((this.offsetY % gridSize) + gridSize) % gridSize;
      ctx.strokeStyle = '#E8E9EA';
      ctx.lineWidth = 0.5;
      ctx.beginPath();
      for (let x = startX; x < w; x += gridSize) {
        ctx.moveTo(x, 0);
        ctx.lineTo(x, h);
      }
      for (let y = startY; y < h; y += gridSize) {
        ctx.moveTo(0, y);
        ctx.lineTo(w, y);
      }
      ctx.stroke();
    }
    // 笔触
    this.drawStrokes();
  }

  /**
   * 绘制所有笔触（已完成 + 正在绘制的预览）。
   * 使用 PenKitService 的压感映射计算每段线宽。
   */
  private drawStrokes(): void {
    const ctx = this.ctx;
    // 已完成的笔触
    for (let i = 0; i < this.strokes.length; i++) {
      this.drawSingleStroke(ctx, this.strokes[i]);
    }
    // 正在绘制的笔触预览
    if (this.isDrawing && this.currentTool === 'pen' && this.currentStrokePoints.length > 1) {
      const brush = this.penKit.getBrush();
      const previewStroke: StrokeData = {
        id: 'preview_stroke',
        brushType: brush.type,
        color: brush.color,
        baseSize: brush.size,
        opacity: brush.opacity,
        points: this.currentStrokePoints
      };
      this.drawSingleStroke(ctx, previewStroke);
    }
  }

  /**
   * 绘制单条笔触（分段渲染，每段宽度由压感映射决定）。
   * 橡皮擦轨迹本身不渲染（仅用于擦除逻辑）。
   */
  private drawSingleStroke(ctx: CanvasRenderingContext2D, stroke: StrokeData): void {
    if (stroke.points.length < 2) {
      return;
    }
    // 橡皮擦轨迹不渲染
    if (stroke.brushType === PenBrushType.ERASER) {
      return;
    }
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    const colorStr = PenKitService.colorToRgba(stroke.color, stroke.opacity);
    ctx.strokeStyle = colorStr;

    for (let j = 1; j < stroke.points.length; j++) {
      const p0 = stroke.points[j - 1];
      const p1 = stroke.points[j];
      const avgPressure = (p0.pressure + p1.pressure) / 2;
      // 使用笔触存储时的 baseSize 渲染，而非当前笔刷设置
      const lineWidth = this.penKit.mapPressureWithBase(avgPressure, stroke.brushType, stroke.baseSize) * this.scaleValue;
      ctx.lineWidth = lineWidth;
      ctx.beginPath();
      ctx.moveTo(p0.x * this.scaleValue + this.offsetX, p0.y * this.scaleValue + this.offsetY);
      ctx.lineTo(p1.x * this.scaleValue + this.offsetX, p1.y * this.scaleValue + this.offsetY);
      ctx.stroke();
    }
  }

  // ═══════════════════════════════════════════
  //  手写笔绘制
  // ═══════════════════════════════════════════

  /**
   * 完成笔触绘制：创建 StrokeData 并添加到 strokes 数组。
   * 橡皮擦模式则执行擦除逻辑。
   */
  private finalizeStroke(): void {
    if (this.currentStrokePoints.length < 2) {
      this.currentStrokePoints = [];
      return;
    }
    this.pushHistory();

    if (this.currentBrushType === PenBrushType.ERASER) {
      // 橡皮擦：移除与擦除路径相交的笔触
      this.applyEraser(this.currentStrokePoints);
    } else {
      // 普通笔刷：创建并存储笔触
      const stroke = this.penKit.createStroke(this.currentStrokePoints);
      const newStrokes: StrokeData[] = [];
      for (let i = 0; i < this.strokes.length; i++) {
        newStrokes.push(this.strokes[i]);
      }
      newStrokes.push(stroke);
      this.strokes = newStrokes;
    }

    this.currentStrokePoints = [];
    this.drawGrid();
  }

  /**
   * 橡皮擦：移除与擦除路径相近的笔触。
   * @param eraserPoints 擦除路径点序列
   */
  private applyEraser(eraserPoints: StrokePoint[]): void {
    const eraserRadius = this.penKit.getBrush().size * 1.5;
    const radiusSq = eraserRadius * eraserRadius;
    const newStrokes: StrokeData[] = [];
    for (let i = 0; i < this.strokes.length; i++) {
      const stroke = this.strokes[i];
      let shouldKeep = true;
      for (let j = 0; j < stroke.points.length && shouldKeep; j++) {
        const sp = stroke.points[j];
        for (let k = 0; k < eraserPoints.length; k++) {
          const ep = eraserPoints[k];
          const dx = sp.x - ep.x;
          const dy = sp.y - ep.y;
          if (dx * dx + dy * dy < radiusSq) {
            shouldKeep = false;
            break;
          }
        }
      }
      if (shouldKeep) {
        newStrokes.push(stroke);
      }
    }
    this.strokes = newStrokes;
  }

  // ═══════════════════════════════════════════
  //  UI 构建
  // ═══════════════════════════════════════════

  /**
   * 工具栏按钮。
   * pen 工具点击时切换笔刷面板。
   */
  @Builder ToolButton(icon: string, tool: string) {
    Row() {
      TablerIcon(icon, 18,
        this.currentTool === tool ? $r('app.color.primary') : $r('app.color.muted_text'))
    }
    .width(36)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(6)
    .backgroundColor(this.currentTool === tool ? $r('app.color.surface2') : Color.Transparent)
    .onClick(() => {
      if (tool === 'pen' && this.currentTool === 'pen') {
        // 已选中手写笔时切换面板显隐
        this.showBrushPanel = !this.showBrushPanel;
      } else {
        this.currentTool = tool;
        this.showBrushPanel = (tool === 'pen');
      }
      this.selectedShapeId = '';
      this.editingShapeId = '';
    })
  }

  private brushIcon(type: PenBrushType): string {
    if (type === PenBrushType.PEN) {
      return 'ballpen';
    }
    if (type === PenBrushType.PENCIL) {
      return 'pencil';
    }
    if (type === PenBrushType.MARKER) {
      return 'highlight';
    }
    return 'eraser';
  }

  /**
   * 笔刷选择面板（4 种笔刷 + 颜色 + 粗细）。
   */
  @Builder BrushPanel() {
    Column({ space: 10 }) {
      // 笔刷类型按钮
      Row({ space: 8 }) {
        ForEach(this.brushPresets, (preset: BrushPresetItem) => {
          Column({ space: 2 }) {
            TablerIcon(this.brushIcon(preset.type), 16,
              this.currentBrushType === preset.type ? $r('app.color.primary') : $r('app.color.text'))
            Text(preset.label)
              .fontSize(9)
              .fontColor(this.currentBrushType === preset.type ? $r('app.color.primary') : $r('app.color.muted_text'))
          }
          .width(48)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .borderRadius(6)
          .backgroundColor(this.currentBrushType === preset.type ? $r('app.color.surface2') : Color.Transparent)
          .onClick(() => {
            this.penKit.setBrushType(preset.type);
            this.currentBrushType = preset.type;
          })
        }, (preset: BrushPresetItem) => preset.type)
      }

      // 颜色选择
      Row({ space: 8 }) {
        ForEach(this.presetColors, (color: number, index: number) => {
          Row()
            .width(24)
            .height(24)
            .borderRadius(12)
            .backgroundColor(PenKitService.colorToHex(color))
            .border({
              width: this.currentBrushColor === color ? 2 : 1,
              color: this.currentBrushColor === color ? $r('app.color.primary') : $r('app.color.border')
            })
            .onClick(() => {
              this.penKit.setBrushColor(color);
              this.currentBrushColor = color;
            })
        }, (color: number, index: number) => index.toString())
      }

      // 粗细滑块
      Row({ space: 8 }) {
        Text('细')
          .fontSize(10)
          .fontColor($r('app.color.muted_text'))
        Slider({ value: this.currentBrushSize, min: 1, max: 20, step: 1 })
          .layoutWeight(1)
          .onChange((value: number) => {
            const rounded = Math.round(value);
            this.penKit.setBrushSize(rounded);
            this.currentBrushSize = rounded;
          })
        Text('粗')
          .fontSize(10)
          .fontColor($r('app.color.muted_text'))
        Text(this.currentBrushSize.toString())
          .fontSize(11)
          .fontColor($r('app.color.text'))
          .width(24)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.surface0'))
  }

  /**
   * 操作按钮（撤销/重做）。
   */
  @Builder UndoButton() {
    Text('↶')
      .fontSize(16)
      .fontColor(this.undoStack.length > 0 ? $r('app.color.text') : $r('app.color.muted_text'))
      .width(32)
      .height(32)
      .textAlign(TextAlign.Center)
      .borderRadius(6)
      .opacity(this.undoStack.length > 0 ? 1 : 0.4)
      .onClick(() => {
        this.undo();
      })
  }

  @Builder RedoButton() {
    Text('↷')
      .fontSize(16)
      .fontColor(this.redoStack.length > 0 ? $r('app.color.text') : $r('app.color.muted_text'))
      .width(32)
      .height(32)
      .textAlign(TextAlign.Center)
      .borderRadius(6)
      .opacity(this.redoStack.length > 0 ? 1 : 0.4)
      .onClick(() => {
        this.redo();
      })
  }

  build() {
    Column({ space: 0 }) {
      // ─── 顶部工具栏 ───
      Row({ space: 4 }) {
        // 返回按钮
        Row() {
          TablerIcon('arrow-left', 18, $r('app.color.text'))
        }
        .width(32)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          AppState.setCurrentPage('Journal');
        })

        // 分隔线
        Divider()
          .vertical(true)
          .height(20)
          .color($r('app.color.border'))
          .strokeWidth(1)
          .margin({ left: 4, right: 4 })

        // 工具按钮组
          ForEach(this.tools, (tc: ToolConfig) => {
            this.ToolButton(tc.icon, tc.tool)
          }, (tc: ToolConfig) => tc.tool)

        // 分隔线
        Divider()
          .vertical(true)
          .height(20)
          .color($r('app.color.border'))
          .strokeWidth(1)
          .margin({ left: 4, right: 4 })

        // 撤销/重做
        this.UndoButton()
        this.RedoButton()

        // 弹性间距
        Blank()

        // 缩放百分比
        Text(this.zoomPercent + '%')
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
          .margin({ right: 8 })

        // 删除按钮（选中时显示）
        if (this.selectedShapeId !== '') {
          Row() {
            TablerIcon('trash', 16, $r('app.color.danger'))
          }
          .width(32)
          .height(32)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .borderRadius(6)
          .onClick(() => {
            this.deleteShape(this.selectedShapeId);
          })
        }

        // 导出按钮
        Row() {
          TablerIcon('download', 16, $r('app.color.muted_text'))
        }
        .width(32)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .borderRadius(6)
        .onClick(() => {
          const json = this.exportCanvas();
          console.info('[Whiteboard] 导出: ' + json.substring(0, 200));
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.surface0'))

      // ─── 画布区域 ───
      Stack() {
        // 网格背景（Canvas 2D）
        Canvas(this.ctx)
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.surface1'))
          .hitTestBehavior(HitTestMode.None)
          .onReady(() => {
            this.drawGrid();
          })
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            const w = newValue.width;
            const h = newValue.height;
            if (typeof w === 'number' && typeof h === 'number') {
              this.canvasWidth = w;
              this.canvasHeight = h;
              this.drawGrid();
            }
          })

        // 连线
        ForEach(this.connectors, (c: WbConnectorData) => {
          WbConnector({
            connector: c,
            zoomScale: this.scaleValue,
            isSelected: false
          })
            .hitTestBehavior(HitTestMode.None)
        }, (c: WbConnectorData) => c.id)

        // 形状
        ForEach(this.shapes, (s: WbShapeData) => {
          WbShape({
            shape: s,
            isSelected: s.id === this.selectedShapeId,
            zoomScale: this.scaleValue,
            isEditing: s.id === this.editingShapeId,
            onTextChange: (id: string, text: string) => {
              this.updateShapeText(id, text);
            }
          })
            .position({
              x: s.x * this.scaleValue + this.offsetX,
              y: s.y * this.scaleValue + this.offsetY
            })
            .hitTestBehavior(s.id === this.editingShapeId ? HitTestMode.Default : HitTestMode.None)
        }, (s: WbShapeData) => s.id)

        // 页面引用
        ForEach(this.pageRefs, (pr: WbPageRefData) => {
          WbPageRef({
            pageRef: pr,
            zoomScale: this.scaleValue,
            isSelected: false,
            onNavigate: (pageName: string) => {
              AppState.setCurrentPage(pageName);
            }
          })
            .position({
              x: pr.x * this.scaleValue + this.offsetX,
              y: pr.y * this.scaleValue + this.offsetY
            })
        }, (pr: WbPageRefData) => pr.id)

        // 绘制预览（手写笔模式不显示形状预览，笔触在 Canvas 上实时渲染）
        if (this.isDrawing && this.currentTool !== 'pen') {
          WbShape({
            shape: this.getPreviewShape(),
            isSelected: false,
            zoomScale: this.scaleValue,
            isEditing: false
          })
            .position({
              x: this.getPreviewScreenX(),
              y: this.getPreviewScreenY()
            })
            .opacity(0.5)
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.surface1'))
      .onTouch((event: TouchEvent) => {
        if (event.touches.length > 0) {
          const touch = event.touches[0];
          this.lastTouchX = touch.x;
          this.lastTouchY = touch.y;
          // 提取压感（HarmonyOS TouchObject.pressure 字段，0-1，可选属性）
          // 模拟器下 pressure 通常为 0，PenKitService 会降级为默认压感 1.0
          const pressure: number = touch.pressure !== undefined ? touch.pressure : 0;
          this.currentPressure = pressure;
          if (pressure > 0) {
            this.penKit.notifyTouchPressure(pressure);
          }
        }
      })
      .gesture(
        PanGesture({ fingers: 1 })
          .onActionStart(() => {
            this.panAccumX = 0;
            this.panAccumY = 0;
            if (this.currentTool === 'select') {
              const canvasX = (this.lastTouchX - this.offsetX) / this.scaleValue;
              const canvasY = (this.lastTouchY - this.offsetY) / this.scaleValue;
              if (this.selectedShapeId !== '' && this.isPointInShape(canvasX, canvasY, this.selectedShapeId)) {
                this.isDraggingShape = true;
                this.dragShapeId = this.selectedShapeId;
                const shape = this.findShape(this.selectedShapeId);
                if (shape) {
                  this.dragStartShapeX = shape.x;
                  this.dragStartShapeY = shape.y;
                }
                this.pushHistory();
              } else {
                this.panBaseOffsetX = this.offsetX;
                this.panBaseOffsetY = this.offsetY;
              }
            } else {
              this.isDrawing = true;
              this.drawStartX = (this.lastTouchX - this.offsetX) / this.scaleValue;
              this.drawStartY = (this.lastTouchY - this.offsetY) / this.scaleValue;
              this.drawCurrentX = this.drawStartX;
              this.drawCurrentY = this.drawStartY;
              // 手写笔模式：初始化笔触点序列
              if (this.currentTool === 'pen') {
                this.currentStrokePoints = [];
                const firstPoint: StrokePoint = {
                  x: this.drawStartX,
                  y: this.drawStartY,
                  pressure: this.currentPressure,
                  timestamp: Date.now()
                };
                this.currentStrokePoints.push(firstPoint);
              }
            }
          })
          .onActionUpdate((event: GestureEvent) => {
            this.panAccumX += event.offsetX;
            this.panAccumY += event.offsetY;
            if (this.isDraggingShape) {
              const totalDx = this.panAccumX / this.scaleValue;
              const totalDy = this.panAccumY / this.scaleValue;
              this.setShapePosition(this.dragShapeId, this.dragStartShapeX + totalDx, this.dragStartShapeY + totalDy);
            } else if (this.isDrawing && this.currentTool === 'pen') {
              // 手写笔模式：收集笔触点并实时重绘
              this.drawCurrentX = this.drawStartX + this.panAccumX / this.scaleValue;
              this.drawCurrentY = this.drawStartY + this.panAccumY / this.scaleValue;
              const point: StrokePoint = {
                x: this.drawCurrentX,
                y: this.drawCurrentY,
                pressure: this.currentPressure,
                timestamp: Date.now()
              };
              this.currentStrokePoints.push(point);
              this.drawGrid();
            } else if (this.isDrawing) {
              this.drawCurrentX = this.drawStartX + this.panAccumX / this.scaleValue;
              this.drawCurrentY = this.drawStartY + this.panAccumY / this.scaleValue;
            } else {
              this.offsetX = this.panBaseOffsetX + this.panAccumX;
              this.offsetY = this.panBaseOffsetY + this.panAccumY;
              this.drawGrid();
            }
          })
          .onActionEnd(() => {
            if (this.isDraggingShape) {
              this.isDraggingShape = false;
            }
            if (this.isDrawing) {
              if (this.currentTool === 'pen') {
                // 手写笔模式：完成笔触（保持工具激活以便连续绘制）
                this.finalizeStroke();
                this.isDrawing = false;
              } else {
                this.finalizeShape();
                this.isDrawing = false;
                this.currentTool = 'select';
              }
            }
          })
      )
      .parallelGesture(
        PinchGesture({ fingers: 2 })
          .onActionStart(() => {
            this.baseScale = this.scaleValue;
          })
          .onActionUpdate((event: GestureEvent) => {
            const newScale = Math.max(0.2, Math.min(3, this.baseScale * event.scale));
            this.scaleValue = newScale;
            this.zoomPercent = Math.round(newScale * 100);
            this.drawGrid();
          })
      )
      .onClick((event: ClickEvent) => {
        if (this.currentTool === 'select' && !this.isDrawing) {
          const canvasX = (event.x - this.offsetX) / this.scaleValue;
          const canvasY = (event.y - this.offsetY) / this.scaleValue;
          const hitId = this.hitTestShape(canvasX, canvasY);
          if (hitId !== '') {
            this.handleShapeTap(hitId);
          } else {
            this.selectedShapeId = '';
            this.editingShapeId = '';
          }
        }
      })

      // ─── 笔刷选择面板（手写笔模式时显示） ───
      if (this.showBrushPanel) {
        this.BrushPanel()
      }

      // ─── 底部状态栏 ───
      Row({ space: 12 }) {
        Text('工具: ' + this.currentTool)
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
        Text('·')
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
        Text(this.shapes.length + ' 形状')
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
        Text('·')
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
        Text(this.connectors.length + ' 连线')
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
        Text('·')
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
        Text(this.strokes.length + ' 笔触')
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
        Blank()
        if (this.selectedShapeId !== '') {
          Text('已选中')
            .fontSize(11)
            .fontColor($r('app.color.primary'))
        }
        if (this.currentTool === 'pen') {
          Text(this.penKit.isPenAvailable() ? '手写笔' : '触摸模式')
            .fontSize(11)
            .fontColor($r('app.color.muted_text'))
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .backgroundColor($r('app.color.surface0'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface0'))
  }
}
