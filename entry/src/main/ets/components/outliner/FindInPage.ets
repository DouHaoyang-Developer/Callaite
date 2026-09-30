import { BlockData } from '../../core/models/Block';
import { WorkspaceService } from '../../services/WorkspaceService';
import { TablerIcon } from '../common/Icons';
import { OverlayKeyRouter, OverlayId, OverlayKeyBinding } from '../../utils/OverlayKeyRouter';
import { AppState } from '../../state/AppState';
import { KeyCode } from '@kit.InputKit';

/**
 * 页内搜索**本体**是否已就绪。
 *
 * U2.4 的排程裁决（计划 §U2.4 原文）：
 *   「键位 Ctrl+Shift+F **先注册（打开即占位提示「编辑器重铸后可用」）**，
 *     组件本体随编辑器节奏走。」
 * ⇒ 本窗口（W12）只做**前两件**：显隐统一 + 可达入口；**本体保持占位**。
 *
 * 为什么用常量而不是删掉下面那段实现：
 *   · 计划 §U2.4 第 3 件（跳块走 `AnchorRegistry` + 文本级高亮）**尚未做**，
 *     现在就把它打开 = 交付一个「能打开、搜得到计数、但既不滚动也不高亮」的半成品，
 *     用户看到的「跳块」是假的 —— 比占位更糟（可点但无用的 UI）。
 *   · 保留实现、只由这一个常量切换 ⇒ 第 3 件做完时**改一行**即可，
 *     不会出现「现在删、下轮再写一遍」的两轮 churn（这正是计划延后它的理由）。
 */
const FIND_IN_PAGE_BODY_READY: boolean = false;

/**
 * FindInPage — 页内搜索浮动组件。
 *
 * 在当前页面所有 Block 中搜索文本，提供上/下导航。
 * 对应 Logseq 的 find-in-page 功能。
 *
 * 用法与开合：
 *   `FindInPage({ pageId: 'xxx' })` —— 显隐**不再由本组件自己的 @State 决定**，
 *   而是与宿主共用 AppStorage 的 `callaite_findInPageOpen`（读写都走 `AppState`）。
 *   入口 = `Ctrl+Shift+F`（`ShortcutService.app.find-in-page`）；
 *   关闭 = Esc / ✕ / `AppState.closeFindInPage()`。
 *
 * 搜索逻辑：
 *   1. 递归遍历当前页所有 Block（getPageBlocks + getChildrenOfBlock）
 *   2. 匹配 content 包含 searchQuery（不区分大小写）
 *   3. 显示 "N/M" 匹配计数
 *   4. 上/下按钮循环导航匹配项
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
    // 仍未做的第 3 件（**跳块走 `AnchorRegistry` + 文本级高亮**）见文件头
    // `FIND_IN_PAGE_BODY_READY` 的说明；本组件当前以占位形态呈现。
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
   */
  private clearSearchState(): void {
    this.searchQuery = '';
    this.matchCount = 0;
    this.currentMatch = 0;
    this.matchedUuids = [];
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
  }

  build() {
    if (!this.isVisible) {
      Row().width('100%').height(0)
    } else if (!FIND_IN_PAGE_BODY_READY) {
      // ─── U2.4 占位形态（计划原文：「键位 Ctrl+Shift+F 先注册，打开即占位提示
      //     『编辑器重铸后可用』，组件本体随编辑器节奏走」）───
      //
      // 为什么不直接把下面那份实现打开：第 3 件（跳块走 AnchorRegistry + 文本级高亮）
      // 未做 ⇒ 那样交付的是「能搜到计数、但点了既不滚动也不高亮」的半成品，
      // 用户会以为跳块坏了。占位是**诚实**的状态，也不会挡住 Esc 关闭这条回路。
      //
      // 提示里必须写明「怎么关」：占位条本身只有一个 ✕，用户第一反应是找 Esc。
      Row({ space: 8 }) {
        TablerIcon('search', 16, $r('app.color.muted_text'))
        Text('页内搜索：编辑器重铸后可用')
          .fontSize(13)
          .fontColor($r('app.color.muted_text'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .id('callaite_findInPagePlaceholder')
        Text('Esc 关闭')
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
          .opacity(0.7)
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
      // 兜底落点：焦点不在本条上时仍要能接管 Esc（与下面正式形态同一份路由器去重标记）
      .onKeyEvent((event: KeyEvent) => {
        if (OverlayKeyRouter.getInstance().handle(event, OverlayId.FIND_IN_PAGE)) {
          event.stopPropagation();
        }
      })
    } else {
      Row({ space: 8 }) {
        TablerIcon('search', 16, $r('app.color.muted_text'))

        TextInput({ placeholder: '页内搜索...', text: this.searchQuery })
          .fontSize(14)
          .layoutWeight(1)
          .height(32)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .onChange((value: string, previewText?: PreviewText) => {
            this.searchQuery = value;
            // U2.2/W11：上报 IME 预览文本 —— 组词态下的回车归输入法（见 OverlayKeyRouter 类头 §SDK 依据）
            OverlayKeyRouter.getInstance().reportImePreviewText(OverlayId.FIND_IN_PAGE, previewText);
            this.performSearch();
          })
          // ↵ 跳到下一个匹配 —— 走 onSubmit（输入法处理完合成之后才发出）；
          // 组词态的回车归输入法上屏（理由与实测见 OverlayKeyRouter 类头 §IME 守卫）。
          // 注：Shift+Enter=上一个 无法在 onSubmit 里判修饰键（其形参只有 EnterKeyType），
          // 该键位留给 U2.4 重做时随显隐反转一并接（本轮本组件尚不可达）。
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
