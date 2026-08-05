import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { WorkspaceService } from '../../services/WorkspaceService';
import { NamespaceUtils, NamespaceNode } from '../../utils/NamespaceUtils';

/**
 * PageTree — 按命名空间层级展示页面树。
 *
 * 对应 Logseq sidebar 中的命名空间页面树。
 * 命名空间使用 "/" 分隔，构建为树形结构后递归渲染。
 */
@Component
export struct PageTree {
  @State treeNodes: NamespaceNode[] = [];
  @State expandedNodes: Map<string, boolean> = new Map<string, boolean>();
  @State currentPageName: string = '';

  aboutToAppear(): void {
    this.buildTree();
  }

  buildTree(): void {
    const ws = WorkspaceService.getInstance();
    this.treeNodes = NamespaceUtils.buildTree(ws.getAllPages());
  }

  /**
   * 切换命名空间节点的展开/折叠状态。
   * 创建新 Map 以触发 @State 重渲染。
   */
  toggleExpand(fullName: string): void {
    const newMap = new Map<string, boolean>();
    this.expandedNodes.forEach((value: boolean, key: string) => {
      newMap.set(key, value);
    });
    if (newMap.has(fullName)) {
      newMap.delete(fullName);
    } else {
      newMap.set(fullName, true);
    }
    this.expandedNodes = newMap;
  }

  isExpanded(fullName: string): boolean {
    return this.expandedNodes.has(fullName);
  }

  hasChildren(node: NamespaceNode): boolean {
    return node.children.length > 0;
  }

  build() {
    Column({ space: 0 }) {
      if (this.treeNodes.length === 0) {
        Column({ space: 8 }) {
          TablerIcon('folder-off', 28, $r('app.color.muted_text'))
          Text('暂无页面')
            .fontSize(12)
            .fontColor($r('app.color.muted_text'))
        }
        .width('100%')
        .padding({ top: 30, bottom: 30 })
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 0 }) {
            ForEach(this.treeNodes, (node: NamespaceNode) => {
              this.RenderNode(node, 0)
            }, (node: NamespaceNode) => node.fullName)
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 递归渲染树节点。
   *
   * @param node 当前节点
   * @param depth 缩进深度（0 = 顶级）
   */
  @Builder
  RenderNode(node: NamespaceNode, depth: number) {
    Column({ space: 0 }) {
      // ─── 当前节点行 ───
      Row({ space: 6 }) {
        // 展开/折叠箭头
        if (this.hasChildren(node)) {
          Row() {
            TablerIcon(
              this.isExpanded(node.fullName) ? 'chevron-down' : 'chevron-right',
              12,
              $r('app.color.muted_text')
            )
          }
          .width(16)
          .height(16)
          .justifyContent(FlexAlign.Center)
          .onClick(() => { this.toggleExpand(node.fullName); })
        } else {
          Row().width(16).height(16)
        }

        // 图标
        TablerIcon(
          node.isPage ? 'file' : 'folder',
          14,
          node.isPage ? $r('app.color.muted_text') : $r('app.color.primary')
        )

        // 名称
        Text(node.name)
          .fontSize(13)
          .fontColor(
            this.currentPageName === node.fullName
              ? $r('app.color.primary')
              : $r('app.color.text')
          )
          .fontWeight(
            this.currentPageName === node.fullName
              ? FontWeight.Medium
              : FontWeight.Normal
          )
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(28)
      .padding({ left: depth * 14 + 4, right: 8 })
      .borderRadius(4)
      .onClick(() => {
        if (node.isPage) {
          this.currentPageName = node.fullName;
          AppState.setCurrentPage(node.fullName);
        } else {
          this.toggleExpand(node.fullName);
        }
      })

      // ─── 子节点（递归） ───
      if (this.isExpanded(node.fullName) && this.hasChildren(node)) {
        ForEach(node.children, (child: NamespaceNode) => {
          this.RenderNode(child, depth + 1)
        }, (child: NamespaceNode) => child.fullName)
      }
    }
    .width('100%')
  }
}
