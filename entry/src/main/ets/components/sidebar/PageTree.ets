import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { WorkspaceService } from '../../services/WorkspaceService';
import { NamespaceUtils, NamespaceNode } from '../../utils/NamespaceUtils';
import { PageContextMenu } from './PageContextMenu';

/**
 * PageTree — 按命名空间层级展示页面树。
 *
 * 对应 Logseq sidebar 中的命名空间页面树。
 * 命名空间使用 "/" 分隔，构建为树形结构后递归渲染。
 *
 * U1.1：树行接入 `PageContextMenu`（右键 / 长按 → bindContextMenuWithResponse）。
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

  // ─── U1.1 上下文菜单状态 ───
  /**
   * 右键 / 长按命中的行（fullName）。
   *
   * 为什么用 @State 而不是只当作 Builder 形参：`bindContextMenuWithResponse` 绑定的是
   * **一个** Builder（整棵树只有一份实例），Builder 里拿不到「是哪一行被点了」。
   * 因此在 onWillAppear（菜单弹出前）把命中行写进 @State，Builder 与菜单动作都从它取值。
   * 关闭时立即清空，保证下一次打开时反链计数从 0 起算。
   */
  @State ctxMenuKey: string = '';
  @State ctxMenuOpen: boolean = false;

  // ─── U1.1 行内重命名（对齐 LeftSidebar.PageLink 的交互） ───
  @State renamingKey: string = '';
  @State renameText: string = '';

  /**
   * 刚被按下的行尾「…」按钮所属行。
   *
   * 用途：`bindMenu` 的弹出发生在 onClick 之前（onTouch.Down），行自身的 onClick
   * 需要一个标记来判断「这次点击落在菜单按钮上」并提前返回，否则点菜单会顺带打开页面。
   *
   * ⚠️ **刻意不用 @State**：该标记只参与「同一次事件分发内」的判断，不参与渲染。
   *    写成 @State 时实测失效 —— @State 的可见性更新被推迟到下一帧，
   *    onTouch.Down 写入后，同一帧到达行 onClick 的读值仍是旧值（''），
   *    于是点「…」既弹菜单、又顺带打开了页面（实测两端都发生了）。
   *    普通字段赋值立即生效，正好满足这里的时序要求。
   */
  private spanKey: string = '';

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

  /** 只展开、不折叠（上下文菜单「展开」项用：菜单项语义是单向的展开，而非切换） */
  expandNode(fullName: string): void {
    if (!this.collapsedNodes.has(fullName)) {
      return;
    }
    const newMap = new Map<string, boolean>();
    this.collapsedNodes.forEach((value: boolean, key: string) => {
      newMap.set(key, value);
    });
    newMap.delete(fullName);
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

        // 名称 / 行内重命名输入框
        if (this.renamingKey === node.fullName) {
          TextInput({ text: this.renameText })
            .fontSize(13)
            .layoutWeight(1)
            .height(26)
            .onChange((value: string) => { this.renameText = value; })
            .onSubmit(() => { this.commitTreeRename(); })
        } else {
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

        // ─── U1.1 可点击等价入口：行尾「…」 ───
        // 触屏/模拟器上右键与长按难以用输入注入稳定触发（本会话实测：uitest uiInput longClick
        // 落在树行上无任何反应；且触屏不产生 hover 事件）。因此这里**常显**一个「…」按钮，
        // 保证右键/长按之外有一条确定可达的入口。
        //
        // ⚠️ 为什么不是 hover 才显：`onHover` 在触屏上永不触发（实测确认），
        //    曾一度写成 hover 才显 ⇒ 平板上这个入口根本点不到，等于没有。
        // ⚠️ 时序：`bindMenu` 的 Builder 形参就是本行的 node（闭包捕获），
        //    不读 @State —— 因此不存在「状态还没生效就读到上一行」的问题。
        // ⚠️ 行点击抑制靠 `onTouch`（Down 即写 spanKey，早于 onClick 触发）。
        Row() {
          TablerIcon('dots-vertical', 14, $r('app.color.muted_text'))
        }
        .width(18)
        .height(18)
        .borderRadius(4)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.spanKey = node.fullName;
            // 同时钉住右键/长按路径的菜单目标，避免「上一次点的是哪一行」残留
            this.ctxMenuKey = node.fullName;
          }
        })
        .bindMenu(this.CtxMenuForRow(node))
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
      // U1.1：右键/长按弹出的是**同一个** Builder（整棵树一份实例），Builder 里拿不到
      // 「哪一行被点了」，所以必须在手势发生前把该行钉成菜单目标。
      //
      // 触屏长按不会产生 hover 事件（实测：只靠 onHover 时菜单标题为空 ✗），
      // 故这里用 onTouch.Down 钉目标 —— 它一定早于长按手势判定与菜单弹出。
      // 鼠标右键路径则由 onHover 覆盖（见上）。
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.ctxMenuKey = node.fullName;
        }
      })
      .onClick(() => {
        // 「…」按钮刚被按下：抑制行点击（否则点菜单按钮会顺带打开页面）
        if (this.spanKey === node.fullName) {
          this.spanKey = '';
          return;
        }
        // 普通点选后清掉菜单目标：否则「先点 A 行、再在空白处右键」会弹出指向 A 的菜单
        this.ctxMenuKey = '';
        if (node.isPage) {
          this.currentPageName = node.fullName;
          AppState.setCurrentPage(node.fullName);
        } else {
          this.toggleExpand(node.fullName);
        }
      })
      // ─── U1.1：右键 / 长按 → 上下文菜单（主路径） ───
      // bindContextMenuWithResponse（API 23+）一次绑定同时承接 RightClick 与 LongPress，
      // 菜单内容由带参 @Builder（CustomBuilderT<ResponseType>）提供。
      // 菜单目标由上面的 onTouch.Down / onHover 提前钉进 ctxMenuKey；
      // onDisappear 负责清空它，保证下次打开时反链计数从 0 起算。
      .bindContextMenuWithResponse(this.TreeContextMenu, {
        onWillAppear: () => {
          this.ctxMenuOpen = true;
        },
        onDisappear: () => {
          this.closeTreeContextMenu();
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

  /**
   * ★ U1.1 菜单内容 Builder（主路径 · 右键 / 长按）—— 形参必须是 ResponseType：
   * `CustomBuilderT<ResponseType> = (t: ResponseType) => void`（common.d.ts:22841）。
   *
   * ⚠️ 这里刻意**不使用** trigger 形参做任何分流：右键与长按给同一份菜单。
   * 形参保留只为满足类型约束；真正的「菜单目标」从 @State 的 ctxMenuKey 取 ——
   * 该值已在手势发生前被钉住（见 RenderNode 的 onTouch.Down / onHover）。
   */
  /**
   * ★ U1.1 菜单内容 Builder（主路径 · 右键 / 长按）—— 形参必须是 ResponseType：
   * `CustomBuilderT<ResponseType> = (t: ResponseType) => void`（common.d.ts:22841）。
   *
   * ⚠️ 这里刻意**不使用** trigger 形参做任何分流：右键与长按给同一份菜单。
   * 形参保留只为满足类型约束；「菜单目标」由 @State ctxMenuKey 承载 ——
   * 它在指针/手指进入某一行时（onHover）就被钉住，因为整棵树共用这一个 Builder 实例，
   * Builder 内部无从得知是哪一行触发了菜单。
   */
  @Builder
  TreeContextMenu(trigger: ResponseType) {
    PageContextMenu({
      pageName: this.ctxMenuKey,
      isFolder: this.isFolderKey(this.ctxMenuKey),
      noOverlay: true,
      isVisible: true,
      onClose: (): void => { this.closeTreeContextMenu(); },
      onDeleted: (): void => {
        this.closeTreeContextMenu();
        this.buildTree();
      }
    })
  }

  /**
   * 「…」按钮的菜单面板（bindMenu 路径 · 可点击等价入口）。
   *
   * ⚠️ 不复用 TreeContextMenu：那个 Builder 的属性从 @State 读，而「…」点击与
   *    状态写入在同一帧、@State 尚未生效，会读到上一行的目标。这里把**当前行**
   *    作为 Builder 形参显式传入 —— 闭包捕获，零时序依赖。
   */
  @Builder
  CtxMenuForRow(node: NamespaceNode) {
    PageContextMenu({
      pageName: node.fullName,
      isFolder: !node.isPage,
      noOverlay: true,
      isVisible: true,
      onClose: (): void => {},
      onDeleted: (): void => { this.spanKey = ''; this.buildTree(); }
    })
  }

  /** 关闭右键菜单：清空命中行，保证下一次打开时反链计数从 0 起算（不会误报预警） */
  private closeTreeContextMenu(): void {
    this.ctxMenuOpen = false;
    this.ctxMenuKey = '';
  }

  /**
   * 判定某个 fullName 是否为「中间目录节点」（isPage = false）。
   *
   * 递归查树而不是向 WorkspaceService 问 —— 目录节点在页面表里并不存在，
   * 用 getPageByName() 判定会把「目录」与「已被别处删掉的页面」混为一谈。
   */
  private isFolderKey(fullName: string): boolean {
    if (fullName === '') {
      return false;
    }
    const found: NamespaceNode | undefined = this.findNode(this.treeNodes, fullName);
    if (found === undefined) {
      return false;
    }
    return !found.isPage;
  }

  /** 在树里按 fullName 查节点（未命中返回 undefined） */
  private findNode(nodes: NamespaceNode[], fullName: string): NamespaceNode | undefined {
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].fullName === fullName) {
        return nodes[i];
      }
      if (nodes[i].children.length > 0) {
        const hit: NamespaceNode | undefined = this.findNode(nodes[i].children, fullName);
        if (hit !== undefined) {
          return hit;
        }
      }
    }
    return undefined;
  }

  // ─── U1.1 行内重命名 ───
  private startTreeRename(fullName: string): void {
    this.renamingKey = fullName;
    this.renameText = fullName;
  }

  private commitTreeRename(): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.renamingKey);
    if (page && this.renameText !== '' && this.renameText !== this.renamingKey) {
      ws.getDataStore().renamePage(page.uuid, this.renameText);
    }
    this.renamingKey = '';
    this.renameText = '';
    this.buildTree();
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
