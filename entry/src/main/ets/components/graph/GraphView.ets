import { WorkspaceService } from '../../services/WorkspaceService';
import { PageData } from '../../core/models/Page';
import { GraphLayout, GraphNode, GraphEdge } from './GraphLayout';
import { AppState } from '../../state/AppState';
import { TablerIcon } from '../common/Icons';

/**
 * GraphView — 图谱视图。
 * 使用 Canvas 2D 渲染力导向布局的页面关系图。
 * 对应 Logseq extensions/graph/pixi.cljs (2677行)。
 */
@Component
export struct GraphView {
  @State private ready: boolean = false;
  @State private nodeCount: number = 0;
  @State private edgeCount: number = 0;
  private layout: GraphLayout = new GraphLayout();
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D | undefined;
  private offsetX: number = 0;
  private offsetY: number = 0;
  private zoomLevel: number = 1;
  private canvasWidth: number = 800;
  private canvasHeight: number = 600;

  aboutToAppear(): void {
    const ws = WorkspaceService.getInstance();
    const pages = ws.getAllPages();
    this.layout.build(pages, this.canvasWidth, this.canvasHeight);
    this.layout.simulate(100);
    this.nodeCount = this.layout.getNodes().length;
    this.edgeCount = this.layout.getEdges().length;
    this.ready = true;
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

      // Canvas 画布
      Canvas(this.ctx)
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.surface1'))
        .onReady(() => {
          this.drawGraph();
        })
        .gesture(
          PanGesture({ fingers: 1 })
            .onActionUpdate((event: GestureEvent) => {
              this.offsetX += event.offsetX;
              this.offsetY += event.offsetY;
              this.drawGraph();
            })
        )
        .onClick((event: ClickEvent) => {
          this.handleTap(event);
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface0'))
  }

  drawGraph(): void {
    if (!this.ctx) return;
    const ctx = this.ctx;
    const w = this.canvasWidth;
    const h = this.canvasHeight;

    // 清空
    ctx.clearRect(0, 0, w, h);

    // 绘制连线
    const edges = this.layout.getEdges();
    ctx.strokeStyle = '#D1D5DB';
    ctx.lineWidth = 1;
    for (let i = 0; i < edges.length; i++) {
      const src = this.findNode(edges[i].source);
      const tgt = this.findNode(edges[i].target);
      if (src && tgt) {
        ctx.beginPath();
        ctx.moveTo(src.x + this.offsetX, src.y + this.offsetY);
        ctx.lineTo(tgt.x + this.offsetX, tgt.y + this.offsetY);
        ctx.stroke();
      }
    }

    // 绘制节点
    const nodes = this.layout.getNodes();
    for (let i = 0; i < nodes.length; i++) {
      const nx = nodes[i].x + this.offsetX;
      const ny = nodes[i].y + this.offsetY;

      // 圆
      ctx.beginPath();
      ctx.arc(nx, ny, nodes[i].radius, 0, Math.PI * 2);
      ctx.fillStyle = nodes[i].isJournal ? '#10B981' : '#0078D4';
      ctx.fill();
      ctx.strokeStyle = '#FFFFFF';
      ctx.lineWidth = 2;
      ctx.stroke();

      // 标签
      ctx.font = '11px sans-serif';
      ctx.fillStyle = '#1A1A1A';
      ctx.textAlign = 'center';
      ctx.fillText(nodes[i].pageName.substring(0, 12), nx, ny + nodes[i].radius + 14);
    }
  }

  handleTap(event: ClickEvent): void {
    const nodes = this.layout.getNodes();
    const localX = event.x - this.offsetX;
    const localY = event.y - this.offsetY;
    for (let i = 0; i < nodes.length; i++) {
      const dx = localX - nodes[i].x;
      const dy = localY - nodes[i].y;
      if (Math.sqrt(dx * dx + dy * dy) < nodes[i].radius + 8) {
        AppState.setCurrentPage(nodes[i].pageName);
        return;
      }
    }
  }

  findNode(uuid: string): GraphNode | undefined {
    const nodes = this.layout.getNodes();
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].pageUuid === uuid) return nodes[i];
    }
    return undefined;
  }
}
