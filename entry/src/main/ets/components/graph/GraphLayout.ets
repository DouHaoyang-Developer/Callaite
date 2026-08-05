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
  /** 命名空间（空字符串表示普通页面） */
  namespace: string;
  /** 连接数（反链 + 出链计数，用于动态计算节点大小） */
  degree: number;
  /** 群集 ID（detectClusters 后填充，-1 表示未分组） */
  clusterId: number;
}

/**
 * GraphEdge — 图谱连线。
 */
export interface GraphEdge {
  source: string;
  target: string;
}

/**
 * LayoutParams — 力导向布局可配置参数。
 * 替代原硬编码的 repulsion/attraction/damping 常量。
 */
export interface LayoutParams {
  /** 引力常数（连线吸引） */
  attraction: number;
  /** 斥力常数（节点排斥） */
  repulsion: number;
  /** 阻尼系数（速度衰减） */
  damping: number;
  /** 迭代次数（simulate 默认步数） */
  iterations: number;
  /** 节点间最小间距（防重叠） */
  minDistance: number;
}

/** 默认参数（与原硬编码值一致，保证向后兼容） */
const DEFAULT_PARAMS: LayoutParams = {
  attraction: 0.005,
  repulsion: 5000,
  damping: 0.85,
  iterations: 100,
  minDistance: 60
};

/** 默认向心力系数 */
const CENTER_FORCE = 0.01;

/**
 * GraphLayout — 力导向布局算法。
 * 对应 Logseq extensions/graph/pixi/logic.cljs (1473行)。
 *
 * 扩展能力：
 *  - 参数可配置（setParameters）
 *  - 群集检测（detectClusters，并查集）
 *  - 防重叠约束（preventOverlap）
 *  - 节点大小按连接数动态计算
 */
export class GraphLayout {
  private nodes: GraphNode[] = [];
  private edges: GraphEdge[] = [];
  private width: number = 800;
  private height: number = 600;
  private params: LayoutParams = DEFAULT_PARAMS;

  /**
   * 更新布局参数（合并式，未提供字段保留原值）。
   */
  setParameters(params: LayoutParams): void {
    this.params = params;
  }

  getParameters(): LayoutParams {
    return this.params;
  }

  build(pages: PageData[], width: number, height: number): void {
    this.width = width;
    this.height = height;
    this.nodes = [];
    this.edges = [];

    const ws = WorkspaceService.getInstance();

    // 创建节点（degree 初始为 0，后续构建边时累加）
    for (let i = 0; i < pages.length; i++) {
      const node: GraphNode = {
        pageUuid: pages[i].uuid,
        pageName: pages[i].originalName,
        x: Math.random() * width * 0.6 + width * 0.2,
        y: Math.random() * height * 0.6 + height * 0.2,
        vx: 0,
        vy: 0,
        radius: pages[i].tags.length > 3 ? 18 : 14,
        isJournal: pages[i].journalDay !== '',
        namespace: pages[i].namespace,
        degree: 0,
        clusterId: -1
      };
      this.nodes.push(node);
    }

    // 创建连线（基于引用关系），同时累加 degree
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
            if (!dup) {
              this.edges.push(edge);
              this.nodes[i].degree += 1;
              const tgtNode = this.findNode(targetPage.uuid);
              if (tgtNode) {
                tgtNode.degree += 1;
              }
            }
          }
        }
      }
    }

    // 按 degree 动态调整节点半径（连接数越多越大，范围 10~26）
    for (let i = 0; i < this.nodes.length; i++) {
      const d = this.nodes[i].degree;
      let r = 12;
      if (d === 0) {
        r = 10;
      } else if (d <= 2) {
        r = 14;
      } else if (d <= 5) {
        r = 18;
      } else if (d <= 10) {
        r = 22;
      } else {
        r = 26;
      }
      this.nodes[i].radius = r;
    }
  }

  /**
   * 执行一次力导向迭代。
   * 参数取自 this.params（可通过 setParameters 配置）。
   */
  step(): void {
    const repulsion = this.params.repulsion;
    const attraction = this.params.attraction;
    const damping = this.params.damping;
    const centerForce = CENTER_FORCE;
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

    // 应用速度 + 阻尼 + 边界
    for (let i = 0; i < this.nodes.length; i++) {
      this.nodes[i].vx *= damping;
      this.nodes[i].vy *= damping;
      this.nodes[i].x += this.nodes[i].vx;
      this.nodes[i].y += this.nodes[i].vy;

      if (this.nodes[i].x < 20) this.nodes[i].x = 20;
      if (this.nodes[i].x > this.width - 20) this.nodes[i].x = this.width - 20;
      if (this.nodes[i].y < 20) this.nodes[i].y = 20;
      if (this.nodes[i].y > this.height - 20) this.nodes[i].y = this.height - 20;
    }

    // 防重叠约束
    this.preventOverlap(this.nodes);
  }

  /**
   * 执行多步迭代直到稳定。
   * @param iterations 指定步数；若 <= 0 则使用 params.iterations
   */
  simulate(iterations: number): void {
    const steps = iterations > 0 ? iterations : this.params.iterations;
    for (let i = 0; i < steps; i++) {
      this.step();
    }
  }

  /**
   * 防重叠：保证任意两节点中心距 >= minDistance - (r1+r2)。
   * 通过沿连线方向推开重叠节点实现，迭代 3 轮以收敛。
   */
  preventOverlap(nodes: GraphNode[]): void {
    const minDist = this.params.minDistance;
    for (let round = 0; round < 3; round++) {
      for (let i = 0; i < nodes.length; i++) {
        for (let j = i + 1; j < nodes.length; j++) {
          const dx = nodes[j].x - nodes[i].x;
          const dy = nodes[j].y - nodes[i].y;
          const dist = Math.sqrt(dx * dx + dy * dy) + 0.01;
          const required = minDist + nodes[i].radius + nodes[j].radius;
          if (dist < required) {
            const overlap = (required - dist) / 2;
            const ux = dx / dist;
            const uy = dy / dist;
            nodes[i].x -= ux * overlap;
            nodes[i].y -= uy * overlap;
            nodes[j].x += ux * overlap;
            nodes[j].y += uy * overlap;
          }
        }
      }
    }
  }

  /**
   * 群集检测：基于边的连通性，使用并查集将节点分组。
   * 连通的节点属于同一群集，孤立节点自成一群。
   *
   * @returns 节点 pageUuid → 群集 ID 映射。同时会写入 node.clusterId。
   */
  detectClusters(): Map<string, number> {
    const result: Map<string, number> = new Map<string, number>();
    // 并查集 parent：pageUuid → parent pageUuid
    const parent: Map<string, string> = new Map<string, string>();
    for (let i = 0; i < this.nodes.length; i++) {
      parent.set(this.nodes[i].pageUuid, this.nodes[i].pageUuid);
    }
    // find
    const find = (u: string): string => {
      let cur = u;
      while (parent.get(cur) !== cur) {
        cur = parent.get(cur) as string;
      }
      // 路径压缩
      let p = u;
      while (parent.get(p) !== cur) {
        const next = parent.get(p) as string;
        parent.set(p, cur);
        p = next;
      }
      return cur;
    };
    // union
    const union = (a: string, b: string): void => {
      const ra = find(a);
      const rb = find(b);
      if (ra !== rb) {
        parent.set(ra, rb);
      }
    };
    for (let i = 0; i < this.edges.length; i++) {
      union(this.edges[i].source, this.edges[i].target);
    }
    // 收集根 → 群集 ID
    const rootToId: Map<string, number> = new Map<string, number>();
    let nextId = 0;
    for (let i = 0; i < this.nodes.length; i++) {
      const root = find(this.nodes[i].pageUuid);
      let id = rootToId.get(root);
      if (id === undefined) {
        id = nextId;
        rootToId.set(root, nextId);
        nextId += 1;
      }
      this.nodes[i].clusterId = id;
      result.set(this.nodes[i].pageUuid, id);
    }
    return result;
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
