import { BlockData } from '../../core/models/Block';
import { PageData } from '../../core/models/Page';
import { WorkspaceService } from '../../services/WorkspaceService';
import { TablerIcon } from '../common/Icons';
import { OverlayKeyRouter, OverlayId, OverlayKeyBinding } from '../../utils/OverlayKeyRouter';
import { AppState } from '../../state/AppState';
import { AnchorRegistry, AnchorSource } from '../../services/AnchorRegistry';
import { ShortcutService } from '../../services/ShortcutService';
import { KeyCode } from '@kit.InputKit';

/**
 * 搜索输入框的稳定 id。
 *
 * 两个用途，必须是同一个字符串：
 *   · `.id(...)` —— 供 `-uiLayout` / `-click <widgetId>` 定位（陷阱 25：2in1 上不要自己换算坐标）；
 *   · `focusControl.requestFocus(...)` —— W13-5 的「按钮点击后焦点回输入框」。
 */
const FIND_IN_PAGE_INPUT_ID: string = 'callaite_findInPageInput';

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
 *   第 2 件「挂载层/触发源」W12：`Ctrl+Shift+F` 注册 ✓；挂载**当时**仍在 `BlockList` 顶部
 *     → **S3-W3 完成第 2 件后半**：挂载点唯一化到 `MainContainer` 顶层 `Stack`
 *       （`ContentArea` 之上、右上角浮动小卡），本组件**不再是 `BlockList` 的子节点**，
 *       也不再占据列表的纵向空间（计划 §U2.4 第 2 条，`PLAN-UI-Alignment.md (v1.md:321`）✓
 *   第 3 件「**跳块 + 文本级高亮**」 W13 完成 ✓
 *     · 跳块：`navigatePrev/Next` → `AnchorRegistry.jump()`（**不自己写滚动/定位**）；
 *     · 文本级高亮：发布「命中块 + 命中词」到 `AppState.setFindInPageHighlight()`，
 *       由 `BlockView` 按 `utils/TextHighlighter.splitHighlight` 切段渲染底色。
 *   ⇒ 原先封存本体的常量 `FIND_IN_PAGE_BODY_READY` 与占位分支**已删除**（占位封存解除）。
 *
 * ─── S3-W3 随「迁 Stack」一并处理的三件事（都是迁移的**直接后果**，不是顺手改）───
 *   ① **Esc 的焦点前提（W13-5）**：见 `navigatePrev/Next` 的 `restoreInputFocus()` 与类尾 §焦点契约。
 *   ② **全局快捷键的投递通路**：迁移前本组件是 `ContentArea` 的**后代**，键入会经
 *      `ContentArea.onKeyPreIme/onKeyEvent` 进 `ShortcutService`；迁到 MainContainer 顶层后
 *      这条通路断了 ⇒ 在根部 `Row` 的 `onKeyEvent` 里按**逐字相同的判据**（仅 ctrl/alt 组合）
 *      补投一次（见 `dispatchShortcut`）。
 *   ③ **关闭时归还焦点**（`restoreFocusId`）：同一次迁移暴露出「关掉本卡片后焦点谁都不在」
 *      ⇒ **所有全局快捷键一起失效**（实测：Esc 关掉搜索条后 `Ctrl+Shift+F` 再也打不开它 ✗）。
 *      与 `SearchPanel.RESTORE_FOCUS_ID` / `CommandPalette.restoreFocusId` **同一约定与同一个 id** ✓。
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
  /**
   * 关闭时把键盘焦点归还给谁（S3-W3）。
   *
   * 默认值 = 主窗格内容区焦点容器的 id（`ContentArea.scrollId()` 在 primary 窗格返回的
   * 就是 `'contentAreaScroll'`）—— 与 `SearchPanel.RESTORE_FOCUS_ID`、
   * `CommandPalette.restoreFocusId` 的默认值**逐字相同**，走的是同一条既有约定。
   *
   * 为什么必须有：`ContentArea` 的全局快捷键（Ctrl+K/F/Shift+F…）挂在
   * **内容区焦点容器**的 `onKeyEvent/onKeyPreIme` 上 ⇒ 焦点不在内容区子树里，
   * 那些键根本到不了 `ShortcutService`。实测（本窗口）：搜索条关闭后不归还焦点，
   * `Ctrl+Shift+F` 再也打不开本卡片 ✗（点一下正文即恢复 ✓）。
   */
  @Prop restoreFocusId: string = 'contentAreaScroll';

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
      // S3-W3：归还焦点（理由见 `restoreFocusId` 字段注释）—— 只做一次 `requestFocus`，
      // 与 `SearchPanel.onVisibilityChanged` 的处理逐字同型：**关掉浮层就把焦点还给内容区**，
      // 否则关掉之后「焦点谁都不在」，所有全局快捷键一起失效 ✗。
      focusControl.requestFocus(this.restoreFocusId);
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
   * W13-5 的一半：**把键盘焦点要回输入框**。
   *
   * ─── 为什么需要（W13 登记的现象，本窗口复现并定位到「焦点去哪了」）───
   * 「点过上/下按钮之后 Esc 不再关闭」✗ —— 计划 §U2.4 的验收写的是「Esc 关闭」，**无前提**。
   * 根因不是按键路由器（`isNavKey` 里明明有 ESC），而是**焦点离开了本子树**：
   * 按钮点完后焦点不再落在搜索输入框上，而本组件根 `Row` 的 `onKeyEvent` 只对
   * **本子树内**的焦点生效 ⇒ 键根本没经过那个兜底落点。
   *
   * 因此修法是两层（详见类尾 §焦点契约）：
   *   ① **本方法**：点完按钮把焦点还给输入框 —— 与用户「先点回输入框」手工动作**完全等价**，
   *      顺带让「点完『下一个』直接按 ↵ 继续走」成立（否则 ↵ 也没有落点）；
   *   ② `MainContainer` 顶层 `Stack` 的宿主兜底 —— 覆盖「焦点谁都不在」的那一态。
   *
   * ⚠️ **对输入法无副作用**（W9 教训：`onKeyPreIme` 返回 true 会截胡输入法）：
   * 本方法只做 `requestFocus`（= 用户点一下输入框），**不碰 preIme、不改按键消费顺序**；
   * 本组件全程只有 post-IME 的 `onKeyEvent`，且回车**刻意不进**路由（走 `onSubmit`）。
   */
  private restoreInputFocus(): void {
    focusControl.requestFocus(FIND_IN_PAGE_INPUT_ID);
  }

  /**
   * 迁移后补回「全局快捷键」的投递通路（迁 Stack 的直接后果，非顺手改）。
   *
   * 迁移前：本组件是 `ContentArea` 的后代 ⇒ 键入冒泡经过 `ContentArea.onKeyPreIme/onKeyEvent`，
   * 那两处把 ctrl/alt 组合转给 `ShortcutService`（`ContentArea.ets:137-142 / 250-260`）。
   * 迁移后：本组件挂在 `MainContainer` 顶层 `Stack`，**不再是 `ContentArea` 的后代** ⇒
   * 这条通路断掉，表现为「搜索框持焦时 Ctrl+K / Ctrl+F 等全部失效」✗。
   *
   * 判据**逐字照抄** `ContentArea.onKeyPreIme` 的两行：仅当有 ctrl 或 alt 修饰键时才转投。
   * 为什么不挂在 `onKeyPreIme`：本组件的落点全部是 post-IME 的 `onKeyEvent`
   * （理由见 `OverlayKeyRouter` 类头 §IME 守卫）；ctrl/alt 组合不参与拼音组词，
   * 放 post-IME 只意味着「输入法先拒绝、它不要的键才轮到快捷键表」，语义不变 ✓。
   *
   * @returns true = 已被全局快捷键消费（调用方应 `stopPropagation`）
   */
  private dispatchShortcut(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) {
      return false;
    }
    const hasCtrl: boolean = event.getModifierKeyState!(['ctrl']);
    const hasAlt: boolean = event.getModifierKeyState!(['alt']);
    if (!hasCtrl && !hasAlt) {
      return false;
    }
    return ShortcutService.getInstance().handleKeyEvent(event);
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
    this.restoreInputFocus();
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
    this.restoreInputFocus();
  }

  build() {
    if (!this.isVisible) {
      // 关：画成 0 高（宿主 MainContainer 只在键为 true 时构造本组件，这里是二重保险）
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
          // S3-W3：同一个字符串也是 `focusControl.requestFocus` 的目标（见 `restoreInputFocus`）。
          .id(FIND_IN_PAGE_INPUT_ID)
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
        // S3-W3（W13-5 的第 ② 层）：按钮自己也是一个按键落点。即便焦点真的停在按钮上
        // （`restoreInputFocus` 的 `requestFocus` 失败、或将来有人给按钮加了别的交互），
        // 这个 id 上的 Esc/↑/↓ 仍然进同一条路由器 ⇒ 不会退回「Esc 不关」✗。
        .onKeyEvent((event: KeyEvent) => {
          if (OverlayKeyRouter.getInstance().handle(event, OverlayId.FIND_IN_PAGE)) {
            event.stopPropagation();
          }
        })
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
        .onKeyEvent((event: KeyEvent) => {
          if (OverlayKeyRouter.getInstance().handle(event, OverlayId.FIND_IN_PAGE)) {
            event.stopPropagation();
          }
        })
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
        .onKeyEvent((event: KeyEvent) => {
          if (OverlayKeyRouter.getInstance().handle(event, OverlayId.FIND_IN_PAGE)) {
            event.stopPropagation();
          }
        })
        .onClick(() => {
          this.hide();
        })
      }
      // ─── S3-W3：从「列表内联的整宽横条」改为「顶部 Stack 层的浮动小卡」 ───
      // 计划 §U2.4 第 2 条要的就是这个观感（Obsidian 布局位）。三个量是同一件事的三面：
      //   · `width(380)`：不再 `100%` —— 不再占满内容列，这是「迁 Stack 成功」的可观测判据之一
      //     （`Ctrl+Shift+F` 的像素差分应从「整条内容列」缩到右上角一小块）；
      //   · `borderRadius` + `shadow`：浮动小卡（迁移前是贴边的横条，只画了底边框）；
      //   · 定位在宿主：`MainContainer` 的 Stack 里 `.align(Alignment.TopEnd)` + 边距。
      .width(380)
      .height(44)
      .padding({ left: 12, right: 8 })
      .backgroundColor($r('app.color.surface1'))
      .borderRadius(10)
      .border({ width: 1, color: $r('app.color.glass_border') })
      .shadow({ radius: 16, color: 'rgba(0,0,0,0.18)', offsetY: 4 })
      // 兜底落点：焦点落在本卡片内但不在输入框（或按钮）时，仍能接管 ↑/↓/Esc
      // （与输入框、按钮同走路由器一份去重标记）。W13-5 的第 ③ 层是宿主的兜底，见 MainContainer。
      .onKeyEvent((event: KeyEvent) => {
        if (OverlayKeyRouter.getInstance().handle(event, OverlayId.FIND_IN_PAGE)) {
          event.stopPropagation();
          return;
        }
        // 迁 Stack 后补回的全局快捷键通路（理由见 `dispatchShortcut` 方法头）
        if (this.dispatchShortcut(event)) {
          event.stopPropagation();
        }
      })
    }
  }
}

/**
 * ─── §焦点契约（S3-W3 / W13-5 修复记录，**验收判据就写在这里**）───
 *
 * 计划 §U2.4 的验收原文是「**Esc 关闭**」，**没有任何焦点前提**。W13 实测到的边界是：
 *
 *   | 按键前的状态              | 迁移前 Esc | 现在 Esc |
 *   |---------------------------|-----------|---------|
 *   | ① 输入框持焦（刚打开）     | 关闭 ✓    | 关闭 ✓  |
 *   | ② 按钮持焦（点过上/下）    | **不关** ✗ | 关闭 ✓  |
 *   | ③ 焦点谁都不在（点过正文） | 关闭 ✓    | 关闭 ✓  |
 *
 * 三层落点，任一层命中即关闭（共用 `OverlayKeyRouter` 一份去重标记 ⇒ 一次按压只走一步）：
 *   ① `TextInput.onKeyEvent` → 路由器                       （态 ①）
 *   ② 上/下/关三个按钮各自的 `onKeyEvent` → 路由器           （态 ②，随迁 Stack 补）
 *   ③ 本卡片根 `Row.onKeyEvent` → 路由器                     （卡片内其它位置）
 *   ④ `MainContainer` 顶层 `Stack.onKeyEvent` → `handleFromHost`（态 ③，**迁 Stack 的必备件**：
 *      迁移后本组件不再是 `ContentArea` 的后代，而 `ContentArea.ets:243` 的宿主兜底只覆盖
 *      「焦点在自己的子树里」的情形）
 *
 * **为什么不是「只把 Esc 处理上浮」就够**：④ 单独就能让三态都关，
 * 但**焦点仍然丢着** ⇒ 点完「下一个」之后按 ↵（`onSubmit`）或继续打字都没有落点，
 * 循环跳转会变成「必须每次用鼠标点按钮」。因此两层都做：
 * ④ 保证「不依赖焦点也能关」，`restoreInputFocus()` 保证「焦点回到该在的地方」。
 *
 * **为什么不给按钮加 `.focusable(false)`**（W13 报告里的备选）：那会让键盘用户
 * （Tab 遍历）永远够不到上/下/关三个按钮 —— 用一个可达性缺陷换另一个，不取。
 *
 * **为什么不碰 `onKeyPreIme`**（W9 教训，必须逐条对照）：
 * `BlockEditor` 的 Enter 走 `onKeyPreIme` 且返回 true ⇒ 会「截胡输入法」
 * （SDK 顺序 `preIme → keyboardShortcut → input method events → onKeyEventDispatch → onKeyEvent`，
 *  `common.d.ts:18672-18687`）。本次改动**一处 preIme 都没有新增**：
 *   · 三个新加的 `onKeyEvent` 与既有的两处落点一样，全是 **post-IME** ⇒ 输入法先拒绝，
 *     它不要的键才轮到本组件（这正是 `OverlayKeyRouter` 类头 §IME 守卫的定论）；
 *   · 路由器只认 ↑/↓/Esc（`isNavKey`），**回车刻意不在其中** —— 回车走 `TextInput.onSubmit`，
 *     由输入法在合成结束后发出（组词中的回车被输入法吃掉，不触发 onSubmit）；
 *   · `restoreInputFocus()` 只做 `focusControl.requestFocus`（= 用户点一下输入框），
 *     不改变任何按键的消费顺序；
 *   · `dispatchShortcut()` 只转 ctrl/alt 组合键 —— 它们不参与拼音组词。
 * ⇒ 本浮层与块编辑器的区别正在这里：它是**非模态浮层**，全部按键处理都在 post-IME 一侧，
 *   不存在「抢在输入法之前把回车吃掉」的通路 ✓。
 */
