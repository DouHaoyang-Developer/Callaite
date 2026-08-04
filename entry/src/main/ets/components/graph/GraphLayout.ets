import { PageData } from '../../core/models/Page';
import { WorkspaceService } from '../../services/WorkspaceService';

/**
 * GraphNode — 图谱节点。
 */
export interface GraphNode {
  pageUuid: string;
  pageName: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
  radius: number;
  isJournal: boolean;
}

/**
 * GraphEdge — 图谱连线。
 */
export interface GraphEdge {
  source: string;
  target: string;
}

/**
 * GraphLayout — 力导向布局算法。
 * 对应 Logseq extensions/graph/pixi/logic.cljs (1473行)。
 */
export class GraphLayout {
  private nodes: GraphNode[] = [];
  private edges: GraphEdge[] = [];
  private width: number = 800;
  private height: number = 600;

  build(pages: PageData[], width: number, height: number): void {
    this.width = width;
    this.height = height;
    this.nodes = [];
    this.edges = [];

    const ws = WorkspaceService.getInstance();

    // 创建节点
    for (let i = 0; i < pages.length; i++) {
      const node: GraphNode = {
        pageUuid: pages[i].uuid,
        pageName: pages[i].originalName,
        x: Math.random() * width * 0.6 + width * 0.2,
        y: Math.random() * height * 0.6 + height * 0.2,
        vx: 0,
        vy: 0,
        radius: pages[i].tags.length > 3 ? 18 : 14,
        isJournal: pages[i].journalDay !== ''
      };
      this.nodes.push(node);
    }

    // 创建连线（基于引用关系）
    for (let i = 0; i < this.nodes.length; i++) {
      const blocks = ws.getPageBlocks(this.nodes[i].pageUuid);
      for (let bi = 0; bi < blocks.length; bi++) {
        for (let ri = 0; ri < blocks[bi].refs.length; ri++) {
          const targetName = blocks[bi].refs[ri];
          const targetPage = ws.getPageByName(targetName);
          if (targetPage) {
            const edge: GraphEdge = {
              source: this.nodes[i].pageUuid,
              target: targetPage.uuid
            };
            // 去重
            let dup = false;
            for (let ei = 0; ei < this.edges.length; ei++) {
              if ((this.edges[ei].source === edge.source && this.edges[ei].target === edge.target) ||
                  (this.edges[ei].source === edge.target && this.edges[ei].target === edge.source)) {
                dup = true;
                break;
              }
            }
            if (!dup) this.edges.push(edge);
          }
        }
      }
    }
  }

  /**
   * 执行一次力导向迭代。
   */
  step(): void {
    const repulsion = 5000;
    const attraction = 0.005;
    const damping = 0.85;
    const centerForce = 0.01;
    const cx = this.width / 2;
    const cy = this.height / 2;

    // 斥力（节点之间）
    for (let i = 0; i < this.nodes.length; i++) {
      for (let j = i + 1; j < this.nodes.length; j++) {
        const dx = this.nodes[i].x - this.nodes[j].x;
        const dy = this.nodes[i].y - this.nodes[j].y;
        const dist = Math.sqrt(dx * dx + dy * dy) + 1;
        const force = repulsion / (dist * dist);
        const fx = (dx / dist) * force;
        const fy = (dy / dist) * force;
        this.nodes[i].vx += fx;
        this.nodes[i].vy += fy;
        this.nodes[j].vx -= fx;
        this.nodes[j].vy -= fy;
      }
    }

    // 引力（连线之间）
    for (let i = 0; i < this.edges.length; i++) {
      const src = this.findNode(this.edges[i].source);
      const tgt = this.findNode(this.edges[i].target);
      if (src && tgt) {
        const dx = tgt.x - src.x;
        const dy = tgt.y - src.y;
        const dist = Math.sqrt(dx * dx + dy * dy) + 1;
        const force = dist * attraction;
        const fx = (dx / dist) * force;
        const fy = (dy / dist) * force;
        src.vx += fx;
        src.vy += fy;
        tgt.vx -= fx;
        tgt.vy -= fy;
      }
    }

    // 向心力（趋向中心）
    for (let i = 0; i < this.nodes.length; i++) {
      this.nodes[i].vx += (cx - this.nodes[i].x) * centerForce;
      this.nodes[i].vy += (cy - this.nodes[i].y) * centerForce;
    }

    // 应用速度 + 阻尼
    for (let i = 0; i < this.nodes.length; i++) {
      this.nodes[i].vx *= damping;
      this.nodes[i].vy *= damping;
      this.nodes[i].x += this.nodes[i].vx;
      this.nodes[i].y += this.nodes[i].vy;

      // 边界限制
      if (this.nodes[i].x < 20) this.nodes[i].x = 20;
      if (this.nodes[i].x > this.width - 20) this.nodes[i].x = this.width - 20;
      if (this.nodes[i].y < 20) this.nodes[i].y = 20;
      if (this.nodes[i].y > this.height - 20) this.nodes[i].y = this.height - 20;
    }
  }

  /**
   * 执行多步迭代直到稳定。
   */
  simulate(iterations: number): void {
    for (let i = 0; i < iterations; i++) {
      this.step();
    }
  }

  getNodes(): GraphNode[] { return this.nodes; }
  getEdges(): GraphEdge[] { return this.edges; }

  private findNode(uuid: string): GraphNode | undefined {
    for (let i = 0; i < this.nodes.length; i++) {
      if (this.nodes[i].pageUuid === uuid) return this.nodes[i];
    }
    return undefined;
  }
}
