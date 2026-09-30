import { BlockData } from '../../core/models/Block';
import { WorkspaceService } from '../../services/WorkspaceService';
import { TablerIcon } from '../common/Icons';
import { OverlayKeyRouter, OverlayId, OverlayKeyBinding } from '../../utils/OverlayKeyRouter';
import { KeyCode } from '@kit.InputKit';

/**
 * FindInPage — 页内搜索浮动组件。
 *
 * 在当前页面所有 Block 中搜索文本，提供上/下导航。
 * 对应 Logseq 的 find-in-page 功能。
 *
 * 用法：
 *   FindInPage({ pageId: 'xxx' })
 *   通过组件引用调用 show() / hide() 控制显隐。
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
  @State isVisible: boolean = false;
  @State searchQuery: string = '';
  @State matchCount: number = 0;
  @State currentMatch: number = 0;
  @State matchedUuids: string[] = [];
  @StorageLink('callaite_blocksVersion') @Watch('onRefresh') private blocksVersion: number = 0;

  aboutToAppear(): void {
    // 初始隐藏，等待 show() 调用。
    // U2.2/W11：登记进按键路由器。开合态以**本组件自己的 isVisible 为准** ——
    // 不按「已挂载」登记为打开，否则会出现「浮层没显示却在吞按键」的静默失效。
    //
    // ─── ⚠️ 可达性（W12 重新核对后的准确结论，替换 W11 的旧描述）───
    // 症结不是「两个互不相通的显隐标志」，而是**只有一半**：
    //   · 宿主 `BlockList.findInPageVisible` 确实决定是否构造本组件，但**全仓 0 调用**
    //     （`toggleFindInPage` / `showFindInPage` / `hideFindInPage` 三个方法也无调用点）
    //     ⇒ 组件从未被构造 ⇒ 下面的 `isVisible`（初始 false，只有 `show()` 能置 true，
    //     而 `show()` 同样 0 调用）**根本没机会参与**。
    //   · 因此真正的缺口是「**没有触发源**」这一条，与 SlashMenu 本轮修掉的缺陷同型；
    //     `isVisible` 只是第二道（且当前不可达的）闸门。
    //
    // ─── 本轮（U2.3/W12）为什么**不**一并修 ───
    //   1. 计划把 FindInPage 的可达性放在 **U2.4「FindInPage 重做」**：显隐控制反转
    //      （删内部 isVisible，改 `@StorageLink('callaite_findInPageOpen')`）、
    //      渲染位置从 BlockList 内联移到 MainContainer 顶部 Stack、navigate 走
    //      `AnchorRegistry` + 文本级高亮 —— 三项都在 U2.4 里，现在补触发源会在
    //      下个窗口被整体改写（同一模块两轮 churn）。
    //   2. 本轮验收面（快捷键重排 + cyclePriority→SlashMenu + SlashMenu 可达）
    //      不依赖它；而给它接一个「只能开、搜不了、不会跳块」的入口属于
    //      「把 0 调用换成 0 效果」，比现状更糟（会产生可点但无用的 UI）。
    //   3. 键位也还没到：计划的 U2.3 只注册 `Ctrl+Shift+F`，而**打开后应显示的是
    //      「编辑器重铸后可用」占位提示**（计划 §U2.4 原文）—— 本轮注册它会打开一条
    //      什么都不做的搜索栏，不注册则与现状等价。⇒ **两者都不做，留空给 U2.4**。
    //
    // 已按 §待验收清单登记：`FindInPage` 全链路（显示/搜索/跳块/高亮/Esc）待 U2.4 验收。
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
   */
  show(): void {
    this.isVisible = true;
    OverlayKeyRouter.getInstance().setOverlayOpen(OverlayId.FIND_IN_PAGE, true);
  }

  /**
   * 隐藏并清空搜索状态。
   */
  hide(): void {
    this.isVisible = false;
    // 路由开合态必须同步 —— 否则搜索栏消失后仍会继续吞掉 esc/enter。
    OverlayKeyRouter.getInstance().setOverlayOpen(OverlayId.FIND_IN_PAGE, false);
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
