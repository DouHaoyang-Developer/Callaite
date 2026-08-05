import { PageData } from '../core/models/Page';

/**
 * NamespaceNode — 命名空间树节点。
 *
 * 表示页面命名空间层级中的一个节点：
 *  - 非页面节点（如 "project" in "project/sub/page"）是中间目录节点
 *  - 页面节点（如 "project/sub/page"）是实际存在的页面
 */
export interface NamespaceNode {
  /** 短名（不含路径前缀） */
  name: string;
  /** 完整路径名（含前缀，如 "project/sub/page"） */
  fullName: string;
  /** 子节点列表 */
  children: NamespaceNode[];
  /** 是否为实际存在的页面（true = 页面，false = 中间目录） */
  isPage: boolean;
}

/**
 * NamespaceUtils — 命名空间工具类（静态方法）。
 *
 * 对应 Logseq common/namespaces.cljs。
 *
 * 页面命名空间使用 "/" 分隔，例如：
 *   "project/sub/page" → 命名空间层级 [project, sub, page]
 *   "project" → 顶级页面，无命名空间
 *
 * 与 core/models/Page.ets 中的 extractNamespace 不同：
 *  - extractNamespace 返回第一级命名空间（"project"）
 *  - getNamespace 返回父命名空间（"project/sub"）
 */
export class NamespaceUtils {

  /**
   * 按 "/" 拆分页面名为多级命名空间。
   *
   * @param pageName 页面名
   * @returns 命名空间层级数组
   *
   * @example
   *   splitNamespace("project/sub/page") → ["project", "sub", "page"]
   *   splitNamespace("project") → ["project"]
   */
  static splitNamespace(pageName: string): string[] {
    if (pageName === '') {
      return [];
    }
    const parts: string[] = pageName.split('/');
    const result: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i].trim();
      if (part !== '') {
        result.push(part);
      }
    }
    return result;
  }

  /**
   * 获取父命名空间（去掉最后一级）。
   *
   * @param pageName 页面名
   * @returns 父命名空间；无父级时返回空字符串
   *
   * @example
   *   getNamespace("project/sub/page") → "project/sub"
   *   getNamespace("project") → ""
   */
  static getNamespace(pageName: string): string {
    const lastSlash = pageName.lastIndexOf('/');
    if (lastSlash <= 0) {
      return '';
    }
    return pageName.substring(0, lastSlash);
  }

  /**
   * 获取顶级命名空间（第一级）。
   *
   * @param pageName 页面名
   * @returns 顶级命名空间；无命名空间时返回空字符串
   *
   * @example
   *   getTopLevel("project/sub/page") → "project"
   *   getTopLevel("project") → ""
   */
  static getTopLevel(pageName: string): string {
    const firstSlash = pageName.indexOf('/');
    if (firstSlash <= 0) {
      return '';
    }
    return pageName.substring(0, firstSlash);
  }

  /**
   * 判断页面名是否包含命名空间（是否含有 "/"）。
   *
   * @param pageName 页面名
   * @returns 含有 "/" 且非首尾字符时返回 true
   *
   * @example
   *   isNamespaced("project/sub/page") → true
   *   isNamespaced("project") → false
   */
  static isNamespaced(pageName: string): boolean {
    const slashIdx = pageName.indexOf('/');
    return slashIdx > 0 && slashIdx < pageName.length - 1;
  }

  /**
   * 从页面列表构建命名空间树。
   *
   * 将所有页面按 "/" 拆分，构建树形结构。
   * 中间目录节点（未对应实际页面的）的 isPage = false。
   *
   * @param pages 页面列表
   * @returns 顶级节点列表
   */
  static buildTree(pages: PageData[]): NamespaceNode[] {
    const rootChildren: NamespaceNode[] = [];

    for (let i = 0; i < pages.length; i++) {
      const page = pages[i];
      const parts: string[] = NamespaceUtils.splitNamespace(page.name);
      if (parts.length === 0) {
        continue;
      }

      // 从根开始逐级查找或创建节点
      let currentLevel: NamespaceNode[] = rootChildren;
      let currentPath: string = '';

      for (let j = 0; j < parts.length; j++) {
        const part = parts[j];
        if (currentPath === '') {
          currentPath = part;
        } else {
          currentPath = currentPath + '/' + part;
        }

        // 查找是否已存在该节点
        let foundNode: NamespaceNode | undefined;
        for (let k = 0; k < currentLevel.length; k++) {
          if (currentLevel[k].name === part) {
            foundNode = currentLevel[k];
            break;
          }
        }

        if (foundNode) {
          // 已存在：若这是最后一级，标记为页面
          if (j === parts.length - 1) {
            foundNode.isPage = true;
          }
          currentLevel = foundNode.children;
        } else {
          // 不存在：创建新节点
          const newNode: NamespaceNode = {
            name: part,
            fullName: currentPath,
            children: [],
            isPage: j === parts.length - 1
          };
          currentLevel.push(newNode);
          currentLevel = newNode.children;
        }
      }
    }

    // 对每层节点按名称排序
    NamespaceUtils.sortTree(rootChildren);
    return rootChildren;
  }

  /**
   * 递归对树节点按名称排序。
   */
  private static sortTree(nodes: NamespaceNode[]): void {
    nodes.sort((a: NamespaceNode, b: NamespaceNode): number => {
      if (a.name < b.name) {
        return -1;
      }
      if (a.name > b.name) {
        return 1;
      }
      return 0;
    });
    for (let i = 0; i < nodes.length; i++) {
      NamespaceUtils.sortTree(nodes[i].children);
    }
  }

  /**
   * 将命名空间树展平为页面名列表。
   *
   * 只返回 isPage = true 的节点（实际页面），
   * 按深度优先顺序输出 fullName。
   *
   * @param nodes 顶级节点列表
   * @returns 页面全名列表
   */
  static flattenTree(nodes: NamespaceNode[]): string[] {
    const result: string[] = [];
    NamespaceUtils.flattenRecursive(nodes, result);
    return result;
  }

  /**
   * 递归展平辅助方法。
   */
  private static flattenRecursive(nodes: NamespaceNode[], result: string[]): void {
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      if (node.isPage) {
        result.push(node.fullName);
      }
      if (node.children.length > 0) {
        NamespaceUtils.flattenRecursive(node.children, result);
      }
    }
  }
}
