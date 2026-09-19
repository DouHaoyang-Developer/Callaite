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
  @State hoveredKey: string = '';
  /** 已折叠的命名空间节点（默认全部展开，对齐 Obsidian 文件树） */
  @State collapsedNodes: Map<string, boolean> = new Map<string, boolean>();
  /** 当前打开页（高亮 + 展开刷新），来自全局标签页状态 */
  @StorageLink('callaite_currentPage') @Watch('onStateRebuild') currentPageName: string = '';
  /** 页面/块变更计数（新建页面后刷新树） */
  @StorageLink('callaite_blocksVersion') @Watch('onStateRebuild') blocksVersion: number = 0;

  aboutToAppear(): void {
    this.buildTree();
  }

  /** 当前页或页面集变化时重建树 */
  onStateRebuild(): void {
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
    this.collapsedNodes.forEach((value: boolean, key: string) => {
      newMap.set(key, value);
    });
    if (newMap.has(fullName)) {
      newMap.delete(fullName);
    } else {
      newMap.set(fullName, true);
    }
    this.collapsedNodes = newMap;
  }

  isExpanded(fullName: string): boolean {
    return !this.collapsedNodes.has(fullName);
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

            // 统计行（对齐 Obsidian 移动端文件列表计数）
            Text(this.treeStats())
              .fontSize(10)
              .fontColor($r('app.color.muted_text'))
              .width('100%')
              .padding({ left: 14, top: 12, bottom: 12 })
              .textAlign(TextAlign.Start)
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
          .alignItems(VerticalAlign.Center)
          .width(16)
          .height(16)
          .justifyContent(FlexAlign.Center)
          .onClick(() => { this.toggleExpand(node.fullName); })
        } else {
          Row().width(16).height(16)
        }

        // 图标区分：文件夹 / 文件（对齐 Obsidian 移动端文件列表）
        TablerIcon(
          node.isPage ? 'file' : 'folder',
          14,
          node.isPage ? $r('app.color.muted_text') : $r('app.color.icon_color')
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
      .padding({ left: depth * 14 + 6, right: 8 })
      .borderRadius(6)
      .backgroundColor(
        (node.isPage && this.currentPageName === node.fullName) || this.hoveredKey === node.fullName
          ? $r('app.color.surface2') : Color.Transparent
      )
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onHover((isHover: boolean) => {
        this.hoveredKey = isHover ? node.fullName : (this.hoveredKey === node.fullName ? '' : this.hoveredKey);
      })
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

  /** 递归统计文件与文件夹数量（对齐 Obsidian 文件列表计数行） */
  private countNodes(nodes: NamespaceNode[], files: number[], folders: number[]): void {
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].isPage) {
        files[0] = files[0] + 1;
      } else {
        folders[0] = folders[0] + 1;
        this.countNodes(nodes[i].children, files, folders);
      }
    }
  }

  private treeStats(): string {
    const files: number[] = [0];
    const folders: number[] = [0];
    this.countNodes(this.treeNodes, files, folders);
    return files[0] + ' 个文件，' + folders[0] + ' 个文件夹';
  }
}
