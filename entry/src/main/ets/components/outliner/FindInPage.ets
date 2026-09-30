import { BlockData } from '../../core/models/Block';
import { PageData } from '../../core/models/Page';
import { WorkspaceService } from '../../services/WorkspaceService';
import { TablerIcon } from '../common/Icons';
import { OverlayKeyRouter, OverlayId, OverlayKeyBinding } from '../../utils/OverlayKeyRouter';
import { AppState } from '../../state/AppState';
import { AnchorRegistry, AnchorSource } from '../../services/AnchorRegistry';
import { KeyCode } from '@kit.InputKit';

/**
 * FindInPage — 页内搜索浮动组件。
 *
 * 在当前页面所有 Block 中搜索文本，提供上/下导航，并**跳块 + 块内文本级高亮**。
 * 对应 Logseq 的 find-in-page 功能。
 *
 * 用法与开合：
 *   `FindInPage({ pageId: 'xxx' })` —— 显隐**不由本组件自己的 @State 决定**，
 *   而是与宿主共用 AppStorage 的 `callaite_findInPageOpen`（读写都走 `AppState`）。
 *   入口 = `Ctrl+Shift+F`（`ShortcutService.app.find-in-page`）；
 *   关闭 = Esc / ✕ / `AppState.closeFindInPage()`。
 *
 * 搜索逻辑：
 *   1. 递归遍历当前页所有 Block（getPageBlocks + getChildrenOfBlock）
 *   2. 匹配 content 包含 searchQuery（不区分大小写）
 *   3. 显示 "N/M" 匹配计数
 *   4. 上/下按钮（或 ↵ / Shift+↵）循环导航匹配项
 *
 * ─── U2.4 三件套在本文件的落点（Sprint-02 / W12 前两件 + W13 第三件）───
 *   第 1 件「显隐统一」   W12：删内部 `@State isVisible`，改 `@StorageLink` 共用键 ✓
 *   第 2 件「挂载层/触发源」W12：`Ctrl+Shift+F` 注册；挂载仍在 `BlockList` 顶部 ✓
 *   第 3 件「**跳块 + 文本级高亮**」 **本窗口（W13）完成** ✓
 *     · 跳块：`navigatePrev/Next` → `AnchorRegistry.jump()`（**不自己写滚动/定位**）；
 *     · 文本级高亮：发布「命中块 + 命中词」到 `AppState.setFindInPageHighlight()`，
 *       由 `BlockView` 按 `utils/TextHighlighter.splitHighlight` 切段渲染底色。
 *   ⇒ 原先封存本体的常量 `FIND_IN_PAGE_BODY_READY` 与占位分支**已删除**（占位封存解除）。
 */
@Component
export struct FindInPage {
  @Prop pageId: string = '';
  /**
   * U2.4（W12）：开合态**唯一来源** —— 与宿主 `BlockList` 读的是同一个 AppStorage 键。
   *
   * 迁移前是本组件自己的 `@State isVisible = false`，只有自己的 `show()` 能置 true，
   * 而 `show()` 全仓 0 调用 ⇒ 组件即使被构造出来也永远是关的；
   * 同时宿主还另有一份 `findInPageVisible` ⇒ 两份标志互不相通（U2.4 的「显隐统一」）。
   * 现在两侧共用一个键，`AppState.openFindInPage()/closeFindInPage()` 是唯一写入口。
   */
  @StorageLink('callaite_findInPageOpen') @Watch('onVisibilityChanged') isVisible: boolean = false;
  @State searchQuery: string = '';
  @State matchCount: number = 0;
  @State currentMatch: number = 0;
  @State matchedUuids: string[] = [];
  @StorageLink('callaite_blocksVersion') @Watch('onRefresh') private blocksVersion: number = 0;

  aboutToAppear(): void {
    // U2.2/W11：登记进按键路由器。开合态以**共用的 `callaite_findInPageOpen` 为准** ——
    // 不按「已挂载」登记为打开，否则会出现「浮层没显示却在吞按键」的静默失效。
    //
    // ─── 可达性：W12（U2.4 前两件）已修，此处保留核对记录 ───
    // 迁移前的缺口是**两条叠加**：
    //   ① 宿主 `BlockList.findInPageVisible` 决定是否构造本组件，但**全仓 0 调用**
    //      （`toggleFindInPage` / `showFindInPage` / `hideFindInPage` 三个方法也无调用点）
    //      ⇒ 组件从未被构造；
    //   ② 即便构造出来，本组件自己的 `isVisible` 初始 false 且只有 `show()` 能置 true，
    //      而 `show()` 同样 0 调用 ⇒ 仍是关的。
    //   ⇒ 两条合起来 = 「**当前没有任何路径能让它显示**」（EXEC-PLAN §17.6-2 原文）。
    //
    // W12 的修法（= U2.4 的第 1、2 件）：
    //   · 显隐统一：删掉本组件的 `@State isVisible`，与宿主共用
    //     `AppStorage['callaite_findInPageOpen']`（写入口只有 `AppState.open/closeFindInPage`）；
    //   · 可达入口：`ShortcutService` 注册 `Ctrl+Shift+F`（计划 §U2.3 目标键位表）。
    // 第 3 件（跳块走 `AnchorRegistry` + 文本级高亮）**W13 已完成**，见类头。
    const router = OverlayKeyRouter.getInstance();
    router.registerOverlay(OverlayId.FIND_IN_PAGE, new OverlayKeyBinding((keyCode: number, event: KeyEvent) => {
      return this.applyNavKey(keyCode, event);
    }));
    router.setOverlayOpen(OverlayId.FIND_IN_PAGE, this.isVisible);
  }

  aboutToDisappear(): void {
    OverlayKeyRouter.getInstance().unregisterOverlay(OverlayId.FIND_IN_PAGE);
  }

  /**
   * 开合态变化 ⇒ 同步按键路由器的「已打开」标记。
   *
   * 路由器的开合态必须与视觉状态同步，否则会出现
   * 「搜索栏已经关掉、enter/esc 仍被它吞掉」的分叉（SlashMenu 上一轮修过的同型缺陷）。
   */
  onVisibilityChanged(): void {
    const open: boolean = this.isVisible;
    OverlayKeyRouter.getInstance().setOverlayOpen(OverlayId.FIND_IN_PAGE, open);
    if (!open) {
      this.clearSearchState();
    }
  }

  /**
   * 按键 → 动作（U2.2/W11 新增；迁移前本组件**没有任何键盘处理**）。
   * 语义按 U2.4 的目标定义：Enter=下一个 / Shift+Enter=上一个 / Esc=关闭
   * （区别于命令面板类的 ↑↓ 选择 —— 本组件没有列表，只有「当前是第 M 个匹配」）。
   */
  private applyNavKey(keyCode: number, event: KeyEvent): boolean {
    if (keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.hide();
      return true;
    }
    if (keyCode === KeyCode.KEYCODE_ENTER || keyCode === KeyCode.KEYCODE_NUMPAD_ENTER) {
      // 修饰键判据与 ShortcutService.matchShortcut 同一写法（KeyEvent 无 ctrlKey/shiftKey 属性，
      // 走 getModifierKeyState，SDK common.d.ts:11143）。
      const shift: boolean = event.getModifierKeyState!(['shift']);
      if (shift) {
        this.navigatePrev();
      } else {
        this.navigateNext();
      }
      return true;
    }
    return false;
  }

  /**
   * blocksVersion 变化时重新执行搜索（如果可见且查询非空）。
   * 由 Block 编辑/移动/删除等操作触发，保持搜索结果新鲜。
   */
  onRefresh(): void {
    if (this.isVisible && this.searchQuery.length > 0) {
      this.performSearch();
    }
  }

  /**
   * 显示搜索框。
   *
   * U2.4（W12）：**不再直接写自己的状态**，而是走 `AppState` 这个唯一写入口 ——
   * 这样宿主 `BlockList` 的 `@StorageLink` 会同步收到，两侧不可能再分叉。
   */
  show(): void {
    AppState.openFindInPage();
  }

  /**
   * 隐藏并清空搜索状态。
   *
   * 同样走 `AppState`（闭环见 `onVisibilityChanged`：它会在关闭时清搜索状态并
   * 同步按键路由器，故这里不再重复一遍清理）。
   */
  hide(): void {
    AppState.closeFindInPage();
  }

  /**
   * 清空搜索态（关闭时调用；也供将来「重开时从零开始」复用）。
   *
   * U2.4 第 3 件（W13）：一并清掉**块内文本级高亮**的发布量 ——
   * 否则关掉搜索条后，上一次命中的那一行会留着一片底色（`AppState.closeFindInPage`
   * 也会清一次，两条关闭路径都覆盖）。
   */
  private clearSearchState(): void {
    this.searchQuery = '';
    this.matchCount = 0;
    this.currentMatch = 0;
    this.matchedUuids = [];
    AppState.clearFindInPageHighlight();
  }

  /**
   * 递归收集页面所有 Block UUID（深度优先，保持文档顺序）。
   * isPage 为 true 时 nodeId 是 pageId，否则是 block uuid。
   */
  collectAllBlocks(nodeId: string, isPage: boolean, out: string[]): void {
    const ws = WorkspaceService.getInstance();
    let blocks: BlockData[] = [];
    if (isPage) {
      blocks = ws.getPageBlocks(nodeId);
    } else {
      blocks = ws.getChildrenOfBlock(nodeId);
    }
    for (let i = 0; i < blocks.length; i++) {
      const b: BlockData = blocks[i];
      out.push(b.uuid);
      this.collectAllBlocks(b.uuid, false, out);
    }
  }

  /**
   * 执行搜索，刷新匹配列表。
   * 不区分大小写，匹配 content 包含 searchQuery 的 Block。
   */
  performSearch(): void {
    const query: string = this.searchQuery;
    if (query.length === 0) {
      this.matchCount = 0;
      this.currentMatch = 0;
      this.matchedUuids = [];
      return;
    }

    const allUuids: string[] = [];
    this.collectAllBlocks(this.pageId, true, allUuids);

    const ws = WorkspaceService.getInstance();
    const matched: string[] = [];
    const lowerQuery: string = query.toLowerCase();
    for (let i = 0; i < allUuids.length; i++) {
      const block: BlockData | undefined = ws.getBlock(allUuids[i]);
      if (block && block.content.toLowerCase().indexOf(lowerQuery) >= 0) {
        matched.push(block.uuid);
      }
    }

    this.matchedUuids = matched;
    this.matchCount = matched.length;
    if (matched.length > 0) {
      this.currentMatch = 1;
    } else {
      this.currentMatch = 0;
    }
    // U2.4 第 3 件（W13）：查询变化后，把**文本级高亮**立即落到当前命中块上
    // （只发布高亮，不滚动 —— 滚动由 ↵/「下一个」触发，与计划验收「输入 → Enter 循环跳转」一致）。
    AppState.setFindInPageHighlight(this.currentMatchUuid(), this.searchQuery);
  }

  /**
   * 当前命中项（`currentMatch` 是 1-based；无命中返回空串）。
   */
  private currentMatchUuid(): string {
    if (this.matchedUuids.length === 0 || this.currentMatch <= 0) {
      return '';
    }
    const idx: number = this.currentMatch - 1;
    if (idx >= this.matchedUuids.length) {
      return '';
    }
    return this.matchedUuids[idx];
  }

  /**
   * 本页的页名（供 `AnchorRegistry` 在索引缺失时兜底）。
   * 取法与 `BlockAnchorService.revealBlockByUuid` 同源（IndexStore.getPage(pageId).originalName）。
   */
  private resolvePageName(): string {
    const ws = WorkspaceService.getInstance();
    const page: PageData | undefined = ws.getDataStore().getIndexStore().getPage(this.pageId);
    return page ? page.originalName : '';
  }

  /**
   * 把「当前命中块」推到屏幕上 —— **跳块 + 文本级高亮**（U2.4 第 3 件 / W13）。
   *
   * 两件事分开做，各有唯一入口：
   *   ① **文本级高亮**：`AppState.setFindInPageHighlight(uuid, query)` ⇒ BlockView 切段渲染底色；
   *   ② **跳块**：`AnchorRegistry.jump()` ⇒ 入口层（选窗格/对齐路由/跨页等一帧）⇒
   *      算法层 `BlockAnchorService.revealBlock`（下标计算 + `scrollToIndex` + 块闪烁 + 统一降级）。
   *
   * ─── 为什么不自己写滚动/定位（本条的硬约束）───
   * 本仓 Sprint-01 已建立 `AnchorRegistry`（入口层）+ `BlockAnchorService`（算法层）这条**单一通路**，
   * 里面已经沉淀了三个只有踩过才知道的坑，自己再写一套必然重踩：
   *   · 陷阱 19：`AppStorage` 里那个 `Scroller` **不是 `List` 绑定的那一个**，
   *     对它 `scrollToIndex` 不抛错也**不滚动** ⇒ 必须用 `BlockList` 自报的直接引用；
   *   · 陷阱 20：`scrollToIndex` **异步**生效，且**切页后首帧会被静默忽略**
   *     ⇒ `revealBlockDeferred` 的幂等重试（80ms/+240ms）正是为此而建；
   *   · 折叠祖先必须先展开再算下标（顺序反了会误报「不在大纲中」）。
   * 另：`jump()` **不传 `onDismiss`** —— 本搜索条不是带遮罩的模态（挂在内容区顶部），
   * 跳转后保持打开，用户才能连按 ↵ 逐个走（与右侧栏大纲/反链同一取舍）。
   */
  private revealCurrentMatch(): void {
    const uuid: string = this.currentMatchUuid();
    if (uuid === '') {
      return;
    }
    // ① 文本级高亮（唯一写入口在 AppState）
    AppState.setFindInPageHighlight(uuid, this.searchQuery);
    // ② 跳块（唯一入口在 AnchorRegistry）
    AnchorRegistry.getInstance().jump({
      blockUuid: uuid,
      source: AnchorSource.FIND_IN_PAGE,
      pageNameHint: this.resolvePageName()
    });
  }

  /**
   * 跳转到上一个匹配项（循环导航）。
   */
  navigatePrev(): void {
    if (this.matchedUuids.length === 0) {
      return;
    }
    if (this.currentMatch <= 1) {
      this.currentMatch = this.matchedUuids.length;
    } else {
      this.currentMatch = this.currentMatch - 1;
    }
    this.revealCurrentMatch();
  }

  /**
   * 跳转到下一个匹配项（循环导航）。
   */
  navigateNext(): void {
    if (this.matchedUuids.length === 0) {
      return;
    }
    if (this.currentMatch >= this.matchedUuids.length) {
      this.currentMatch = 1;
    } else {
      this.currentMatch = this.currentMatch + 1;
    }
    this.revealCurrentMatch();
  }

  build() {
    if (!this.isVisible) {
      // 关：画成 0 高（宿主 BlockList 只在键为 true 时构造本组件，这里是二重保险）
      Row().width('100%').height(0)
    } else {
      // ─── U2.4 第 3 件（W13）已完成 ⇒ 原先「FIND_IN_PAGE_BODY_READY=false 占位分支」已删除 ───
      // 封存解除的依据：本形态下每个命中项都会
      //   ① 经 `AnchorRegistry.jump()` 真滚动到目标块（含跨页延迟 + 幂等重试），
      //   ② 由 `AppState.setFindInPageHighlight` 让目标块内命中词显示 `search_highlight` 底色。
      // 即计划 §U2.4 验收要求的「滚动 + 块高亮 + 块内文本高亮」三样都到位，不再是「点了没反应」的半成品。
      Row({ space: 8 }) {
        TablerIcon('search', 16, $r('app.color.muted_text'))

        TextInput({ placeholder: '页内搜索...', text: this.searchQuery })
          .fontSize(14)
          .layoutWeight(1)
          .height(32)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          // W13：稳定 id —— 供 `-uiLayout` / `-click <widgetId>` 精确定位（陷阱 25：
          // 侧栏/浮层坐标会陈旧，2in1 上必须走 widgetId 通道，不要自己换算坐标）。
          .id('callaite_findInPageInput')
          .onChange((value: string, previewText?: PreviewText) => {
            this.searchQuery = value;
            // U2.2/W11：上报 IME 预览文本 —— 组词态下的回车归输入法（见 OverlayKeyRouter 类头 §SDK 依据）
            OverlayKeyRouter.getInstance().reportImePreviewText(OverlayId.FIND_IN_PAGE, previewText);
            this.performSearch();
          })
          // ↵ 跳到下一个匹配 —— 走 onSubmit（输入法处理完合成之后才发出）；
          // 组词态的回车归输入法上屏（理由与实测见 OverlayKeyRouter 类头 §IME 守卫）。
          // 注：Shift+Enter=上一个 无法在 onSubmit 里判修饰键（其形参只有 EnterKeyType）；
          // 该键位由 `applyNavKey`（onKeyEvent → OverlayKeyRouter）承担 —— 输入框持焦时
          // 注入/物理 Shift+↵ 会先经 IME，未被 IME 吃掉的那一次才落到路由器（陷阱 21 ④⑤）。
          .onSubmit(() => {
            this.navigateNext();
          })
          // 键盘导航落点（U2.2/W11）：与 CommandPalette/SearchPanel 同样挂在持焦输入框上，
          // 但**不用 `onKeyPreIme`**（理由与实测证据见 OverlayKeyRouter 类头 §IME 守卫）：
          // preIme 会抢走拼音组词的回车；post-IME 的 onKeyEvent 让输入法先拒绝。
          .onKeyEvent((event: KeyEvent) => {
            if (OverlayKeyRouter.getInstance().handle(event, OverlayId.FIND_IN_PAGE)) {
              event.stopPropagation();
            }
          })

        // 匹配计数 — 有匹配时使用 search_highlight 高亮色
        Text(this.currentMatch.toString() + '/' + this.matchCount.toString())
          .fontSize(12)
          .fontColor(this.matchCount > 0 ? $r('app.color.search_highlight') : $r('app.color.muted_text'))
          .margin({ left: 4, right: 4 })

        // 上一个匹配
        Row() {
          TablerIcon('chevron-up', 16, $r('app.color.text'))
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .width(28)
        .height(28)
        .borderRadius(4)
        .id('callaite_findInPagePrev')
        .onClick(() => {
          this.navigatePrev();
        })

        // 下一个匹配
        Row() {
          TablerIcon('chevron-down', 16, $r('app.color.text'))
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .width(28)
        .height(28)
        .borderRadius(4)
        .id('callaite_findInPageNext')
        .onClick(() => {
          this.navigateNext();
        })

        // 关闭按钮
        Row() {
          TablerIcon('x', 16, $r('app.color.muted_text'))
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .width(28)
        .height(28)
        .borderRadius(4)
        .id('callaite_findInPageClose')
        .onClick(() => {
          this.hide();
        })
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 8 })
      .backgroundColor($r('app.color.surface1'))
      .border({ width: { bottom: 1 }, color: $r('app.color.border') })
      // 兜底落点：焦点不在搜索输入框时仍能接管 enter/esc（与输入框同走路由器一份去重标记）
      .onKeyEvent((event: KeyEvent) => {
        if (OverlayKeyRouter.getInstance().handle(event, OverlayId.FIND_IN_PAGE)) {
          event.stopPropagation();
        }
      })
    }
  }
}
