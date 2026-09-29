import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { AppState } from '../../state/AppState';
import { WorkspaceService } from '../../services/WorkspaceService';
import { PageData } from '../../core/models/Page';
import { BlockData } from '../../core/models/Block';
import { BlockAnchorService, BlockRevealResult } from '../../services/BlockAnchorService';
import { KeyCode } from '@kit.InputKit';

/**
 * 搜索结果项。
 */
interface SearchResultItem {
  type: string;
  pageName: string;
  blockUuid: string;
  content: string;
  matchedText: string;
}

/**
 * 文本分段（用于搜索高亮）。
 */
interface TextSegment {
  text: string;
  isMatch: boolean;
}

/**
 * SearchPanel — 全局搜索面板。
 *
 * 对应 Logseq 的全局搜索（Cmd+K / Ctrl+K）。
 * 搜索范围：页面名 + Block 内容。结果上限 50 条。
 * 空搜索词时显示最近访问的页面。
 */
@Component
export struct SearchPanel {
  /** 输入框焦点 id —— 打开面板时把键盘焦点抢到这里（TextInputController 无 requestFocus 方法） */
  static readonly INPUT_FOCUS_ID: string = 'searchPanelInput';
  /**
   * 面板关闭后焦点归还目标。
   * 与 CommandPalette 同一约定：内容区焦点容器（ContentArea.scrollId() 的主窗格 id）。
   * 不归还的话，面板关闭后内容区的 onKeyEvent（全局快捷键）会收不到按键。
   */
  static readonly RESTORE_FOCUS_ID: string = 'contentAreaScroll';
  /**
   * 输入防抖阈值（ms）。
   *
   * 为什么是 200：
   *   · executeSearch 的代价 = 1 次页面名过滤 + **全库块内容线性扫描**
   *     （逐页 getPageBlocks 再逐块 indexOf），是 O(全库块数) 的重活；
   *     不防抖时「输入 6 个字的词」要跑 6 次全库扫描。
   *   · 下限：熟练打字相邻键的间隔约 100–250ms，取 <150ms 基本挡不住连击；
   *   · 上限：>300ms 用户会感知「输入后结果没跟上」（输入即搜的体感阈值约 250ms）。
   *   200ms 落在两者之间：一次连击合并成一次扫描，且仍在 250ms 体感阈值内。
   * 说明：防抖只作用于**键盘输入路径**（onChange）；程序化搜索
   * （如点标签注入 '#tag'）仍走 executeSearch 立即出结果，不让用户等。
   */
  private static readonly SEARCH_DEBOUNCE_MS: number = 200;

  @StorageLink('callaite_searchPanelOpen') @Watch('onPanelVisibilityChanged') isOpen: boolean = false;

  @State searchQuery: string = '';
  @State results: SearchResultItem[] = [];
  @State isSearching: boolean = false;
  @State recentPages: string[] = [];
  /**
   * 当前高亮行下标（语义与 CommandPalette.selectedIndex 一致：clamp 之后的**显示行**下标）。
   * 空搜索词时显示行 = 最近访问页面，非空时 = 搜索结果，任何时刻都指向真实存在的行。
   */
  @State selectedIndex: number = 0;
  /**
   * 鼠标悬停行下标；-1 表示无悬停。hover 不改写 selectedIndex（键鼠不打架），
   * 与 CommandPalette.hoveredIndex 同一取舍。
   */
  @State hoveredIndex: number = -1;

  private inputController: TextInputController = new TextInputController();
  /** 结果列表滚动控制器（List 宿主，用于把高亮行滚入视口） */
  private listScroller: Scroller = new Scroller();
  /**
   * 上一次已被本面板消费的按键码；-1 表示当前没有「已消费待复位」的按键。
   * 去重理由同 CommandPalette：输入框与根节点都挂了导航回调，同一物理按键可能被两处各收到一次；
   * 同一按键码连续到达只认第一次，收到**不同**按键码即复位（长按连发不被阻塞）。
   */
  private lastHandledKeyCode: number = -1;
  /** 输入防抖定时器句柄；-1 表示当前无待触发任务 */
  private debounceTimer: number = -1;

  aboutToAppear(): void {
    // U1.6：本组件改由 ContentArea 按 callaite_searchPanelOpen **挂载**（打开才创建实例）。
    // @Watch 只在「挂载期间键值变化」时触发、不在初始化时触发，
    // 因此打开时的初始化（最近访问 / 标签过滤 / 抢焦点）必须放在这里，不能只靠 onPanelVisibilityChanged。
    this.recentPages = AppState.getRecentPages();
    this.initializeOnOpen();
  }

  aboutToDisappear(): void {
    // 面板关闭（被卸载）时清掉未触发的防抖任务，避免对已销毁组件的回调。
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    // 归还焦点：否则面板关闭后内容区的全局快捷键（onKeyEvent）收不到按键。
    focusControl.requestFocus(SearchPanel.RESTORE_FOCUS_ID);
  }

  /**
   * 面板显隐变化时的处理（打开分支与 aboutToAppear 共用 initializeOnOpen）。
   */
  onPanelVisibilityChanged(): void {
    if (this.isOpen) {
      this.recentPages = AppState.getRecentPages();
      this.initializeOnOpen();
    } else {
      this.searchQuery = '';
      this.results = [];
      this.selectedIndex = 0;
      this.hoveredIndex = -1;
    }
  }

  /**
   * 打开面板时的初始化：
   *   1. 高亮归零；
   *   2. 消费标签点击产生的过滤请求（'#tag' 直接出结果，不走防抖）；
   *   3. 把键盘焦点抢到输入框 —— 下一帧请求：aboutToAppear 阶段尚未完成布局，立即 requestFocus 会落空。
   */
  private initializeOnOpen(): void {
    this.selectedIndex = 0;
    this.hoveredIndex = -1;
    const tagFilter = AppStorage.get<string>('callaite_tagFilter');
    if (tagFilter && tagFilter !== '') {
      AppStorage.setOrCreate('callaite_tagFilter', '');
      this.searchQuery = '#' + tagFilter;
      this.executeSearch(this.searchQuery);
    }
    setTimeout(() => {
      if (this.isOpen) {
        focusControl.requestFocus(SearchPanel.INPUT_FOCUS_ID);
      }
    }, 0);
  }

  /**
   * 输入即搜的**防抖入口**（只给 TextInput.onChange 用）。
   *
   * 连续输入时只保留最后一次：每次按键先清掉上一个待触发任务，200ms 内没有新按键才真正
   * executeSearch —— 即「一次连击 = 一次全库扫描」。阈值取值理由见 SEARCH_DEBOUNCE_MS。
   * 高亮下标在按键当帧就归零（不等防抖结束），否则防抖窗口内高亮还停在旧列表的下标上。
   */
  private scheduleSearch(query: string): void {
    this.selectedIndex = 0;
    this.hoveredIndex = -1;
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
    }
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = -1;
      this.executeSearch(query);
    }, SearchPanel.SEARCH_DEBOUNCE_MS);
  }

  /**
   * 执行搜索：页面名 + Block 内容。
   */
  executeSearch(query: string): void {
    // 每次重算结果集都把高亮与悬停归零：否则旧下标可能越界、或指向另一条结果，
    // 出现「看起来选中 A、回车却打开 B」（与 CommandPalette.doSearch 同一处理）。
    this.selectedIndex = 0;
    this.hoveredIndex = -1;
    if (query === '') {
      this.results = [];
      // 空词时列表换成「最近访问」，把视口一起带回顶部
      this.scrollHighlightIntoView();
      return;
    }

    this.isSearching = true;
    const ws = WorkspaceService.getInstance();
    const items: SearchResultItem[] = [];
    const lowerQuery = query.toLowerCase();

    // 标签搜索：`#tag` 前缀时按标签索引查找页面
    if (query.startsWith('#') && query.length > 1) {
      const tag = query.substring(1);
      const pagesByTag = ws.getPagesByTag(tag);
      for (let i = 0; i < pagesByTag.length && items.length < 50; i++) {
        const item: SearchResultItem = {
          type: 'page',
          pageName: pagesByTag[i].originalName,
          blockUuid: '',
          content: pagesByTag[i].originalName,
          matchedText: query
        };
        items.push(item);
      }
      this.results = items;
      this.isSearching = false;
      this.scrollHighlightIntoView();
      return;
    }

    // 1. 搜索页面名
    const pages = ws.searchPages(query);
    for (let i = 0; i < pages.length && items.length < 50; i++) {
      const item: SearchResultItem = {
        type: 'page',
        pageName: pages[i].originalName,
        blockUuid: '',
        content: pages[i].originalName,
        matchedText: query
      };
      items.push(item);
    }

    // 2. 搜索 Block 内容
    if (items.length < 50) {
      const allPages = ws.getAllPages();
      for (let pi = 0; pi < allPages.length && items.length < 50; pi++) {
        const page = allPages[pi];
        const blocks = ws.getDataStore().getPageBlocks(page.uuid);
        for (let bi = 0; bi < blocks.length && items.length < 50; bi++) {
          const block = blocks[bi];
          if (block.content.toLowerCase().indexOf(lowerQuery) !== -1) {
            const item: SearchResultItem = {
              type: 'block',
              pageName: page.originalName,
              blockUuid: block.uuid,
              content: block.content,
              matchedText: query
            };
            items.push(item);
          }
        }
      }
    }

    this.results = items;
    this.isSearching = false;
    // 结果集换了，列表回到顶部（否则高亮第 0 行却停在旧的滚动位置）
    this.scrollHighlightIntoView();
  }

  /**
   * 获取显示结果：空搜索词时返回最近页面。
   */
  getDisplayResults(): SearchResultItem[] {
    if (this.searchQuery !== '') {
      return this.results;
    }

    const items: SearchResultItem[] = [];
    for (let i = 0; i < this.recentPages.length; i++) {
      const item: SearchResultItem = {
        type: 'page',
        pageName: this.recentPages[i],
        blockUuid: '',
        content: this.recentPages[i],
        matchedText: ''
      };
      items.push(item);
    }
    return items;
  }

  // ─── 键盘导航（沿用 CommandPalette 的 onKeyPreIme 主路径 + onKeyEvent + 去重标记） ───

  /** 显示行总数（键盘导航与高亮 clamp 都以本方法为准）。 */
  private displayCount(): number {
    return this.getDisplayResults().length;
  }

  /**
   * 结果列表第 0 个 ListItem 是「最近访问」标题行时返回 1，否则返回 0。
   * scrollToIndex 收的是 **ListItem 下标**，而 selectedIndex 是**结果行**下标，需要这个偏移。
   */
  private listIndexOffset(): number {
    return this.searchQuery === '' ? 1 : 0;
  }

  /**
   * 行背景色：鼠标悬停 > 键盘选中 > 透明（与 CommandPalette.rowBackground 同一优先级，
   * 悬停期间不显示键盘选中，避免「看起来选中 A、回车却打开 B」）。
   */
  private rowBackground(index: number): ResourceColor {
    if (this.hoveredIndex === index) {
      return $r('app.color.surface2');
    }
    if (this.hoveredIndex < 0 && this.selectedIndex === index) {
      return $r('app.color.accent_soft');
    }
    return Color.Transparent;
  }

  /**
   * 更新悬停行；离开时仅在「确实是当前悬停项」时复位，避免快速划过误清。
   */
  private setHovered(index: number, isHover: boolean): void {
    if (isHover) {
      this.hoveredIndex = index;
      return;
    }
    if (this.hoveredIndex === index) {
      this.hoveredIndex = -1;
    }
  }

  /**
   * 把当前高亮行滚入可视区。
   * 用 scrollToIndex(align=AUTO)：目标已完整可见则不动，否则按最短距离显示完整
   * （SDK scroll.d.ts:501-504）；smooth 取 false 即时定位，避免动画期间列表项不响应点击。
   */
  private scrollHighlightIntoView(): void {
    if (this.displayCount() === 0) {
      return;
    }
    this.listScroller.scrollToIndex(this.selectedIndex + this.listIndexOffset(), false, ScrollAlign.AUTO);
  }

  /**
   * 移动高亮。到底/到顶后停留在边界（不做环绕，避免误触回到底部）。
   */
  private moveSelection(delta: number): void {
    const count: number = this.displayCount();
    if (count === 0) {
      return;
    }
    let next: number = this.selectedIndex + delta;
    if (next < 0) {
      next = 0;
    }
    if (next > count - 1) {
      next = count - 1;
    }
    if (next === this.selectedIndex) {
      return;
    }
    this.selectedIndex = next;
    // 高亮移到哪一行，哪一行就必须在视口内 —— 否则用户看不出选中项。
    this.scrollHighlightIntoView();
  }

  /** 打开当前高亮行。 */
  private activateSelected(): void {
    const rows: SearchResultItem[] = this.getDisplayResults();
    if (this.selectedIndex >= 0 && this.selectedIndex < rows.length) {
      this.navigateToResult(rows[this.selectedIndex]);
    }
  }

  /**
   * 统一的导航按键处理（与 CommandPalette.handleNavKey 逐条对齐）。
   *
   * 去重：同一个物理事件可能同时被输入框与根节点收到，同一按键码连续到达只处理第一次；
   * 收到**不同**按键码即复位标记，从而不会阻塞用户连按同一个键（长按连发）。
   */
  private handleNavKey(event: KeyEvent): boolean {
    // 只处理按下（Down）；Up 事件直接放行，避免同一次按压被处理两次。
    if (event.type !== KeyType.Down) {
      return false;
    }
    if (this.lastHandledKeyCode === event.keyCode) {
      return false;
    }
    if (this.applyNavKey(event.keyCode)) {
      this.lastHandledKeyCode = event.keyCode;
      return true;
    }
    // 未消费的按键（普通字符、Tab、Shift 等）复位标记，这样「↓ ↓ ↓」连按时每一步都会被接受。
    this.lastHandledKeyCode = -1;
    return false;
  }

  /**
   * 按键 → 动作映射：↑↓ 选择 / ↵ 打开 / esc 关闭。
   */
  private applyNavKey(keyCode: number): boolean {
    if (keyCode === KeyCode.KEYCODE_DPAD_UP) {
      this.moveSelection(-1);
      return true;
    }
    if (keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      this.moveSelection(1);
      return true;
    }
    if (keyCode === KeyCode.KEYCODE_ENTER || keyCode === KeyCode.KEYCODE_NUMPAD_ENTER) {
      this.activateSelected();
      return true;
    }
    if (keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.closePanel();
      return true;
    }
    return false;
  }

  /**
   * 点击搜索结果跳转。
   *
   * U2.1a：块结果（type='block' 且带 blockUuid）此前只切页、不定位，用户落到页面顶部后
   * 仍需自己找那一行。现在切页后追加一次块定位（滚到该块并闪烁高亮）。
   *
   * 时序：setCurrentPage 只改 AppStorage，PageView/BlockList 的 List 与 LazyForEach 数据源
   * 在下一帧才重建完成，而 SDK 明确要求 scrollToIndex 必须在数据刷新完成后调用
   * （scroll.d.ts:489-490），故用 revealBlockDeferred 等一帧。
   * 若目标页恰好已经是当前页，则直接同步定位，不等帧。
   */
  navigateToResult(result: SearchResultItem): void {
    // 防重入：↵ 已在 onKeyPreIme 里被消费一次，IME 仍可能再抛一次 onSubmit；
    // 面板已进入关闭流程时第二次调用会重复切页 / 重复触发块定位闪烁。
    if (!this.isOpen) {
      return;
    }
    const isBlockResult = result.type === 'block' && result.blockUuid !== '';
    if (!isBlockResult) {
      AppState.setCurrentPage(result.pageName);
      this.isOpen = false;
      return;
    }

    const anchor = BlockAnchorService.getInstance();
    const alreadyOnPage = anchor.getActivePageName() === result.pageName;
    AppState.setCurrentPage(result.pageName);
    // 先关面板再定位：面板遮罩会盖住内容区，不关用户就看不到刚跳到的位置。
    // 本字段与 ContentArea 的挂载键是同一把（callaite_searchPanelOpen），置 false 后随即被卸载。
    this.isOpen = false;

    if (alreadyOnPage) {
      // 同页内跳转：数据源未变，可以立即定位
      const samePageResult: BlockRevealResult = anchor.revealBlockByUuid(result.blockUuid);
      anchor.notifyIfFailed(samePageResult);
      return;
    }
    // 跨页跳转：等 List 重建完成后再定位（失败会自行 toast，不静默）
    anchor.revealBlockDeferredByUuid(result.blockUuid);
  }

  closePanel(): void {
    this.isOpen = false;
  }

  /**
   * 将文本按搜索词拆分为分段（匹配段标记 isMatch=true）。
   */
  splitHighlight(text: string, query: string): TextSegment[] {
    if (query === '' || text === '') {
      const seg: TextSegment = { text: text, isMatch: false };
      return [seg];
    }

    const lowerText = text.toLowerCase();
    const lowerQuery = query.toLowerCase();
    const segments: TextSegment[] = [];
    let idx = 0;

    while (idx < text.length) {
      const found = lowerText.indexOf(lowerQuery, idx);
      if (found === -1) {
        const seg: TextSegment = { text: text.substring(idx), isMatch: false };
        segments.push(seg);
        break;
      }
      if (found > idx) {
        const seg: TextSegment = { text: text.substring(idx, found), isMatch: false };
        segments.push(seg);
      }
      const matchSeg: TextSegment = {
        text: text.substring(found, found + query.length),
        isMatch: true
      };
      segments.push(matchSeg);
      idx = found + query.length;
    }

    return segments;
  }

  build() {
    if (this.isOpen) {
      Stack() {
        // ─── 半透明遮罩 ───
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.4)')
          .onClick(() => { this.closePanel(); })

        // ─── 搜索面板 ───
        Column({ space: 0 }) {
          // 搜索框
          Row({ space: 10 }) {
            TablerIcon('search', 20, $r('app.color.muted_text'))

            TextInput({ text: this.searchQuery, controller: this.inputController, placeholder: '搜索页面或内容...' })
              .id(SearchPanel.INPUT_FOCUS_ID)
              .fontSize(14)
              .layoutWeight(1)
              .height(40)
              .backgroundColor(Color.Transparent)
              .caretColor($r('app.color.primary'))
              .onChange((value: string) => {
                this.searchQuery = value;
                // 输入即搜，但走 200ms 防抖（阈值理由见 SEARCH_DEBOUNCE_MS）
                this.scheduleSearch(value);
              })
              .onSubmit(() => {
                // ↵ 打开当前高亮行（与 onKeyPreIme 的 ENTER 分支同一动作，由 navigateToResult 防重入）
                this.activateSelected();
              })
              // ↓↓ 键盘导航的落点：输入框是面板打开后的持焦节点，挂在这里保证按键一定送到。
              // onKeyPreIme 先于 IME 拿到按键 —— 这是「TextInput 吞掉 ↑↓」的坑：
              // 有 IME 时方向键会被输入法当作候选词选择键消费，onKeyEvent 可能收不到。
              .onKeyPreIme((event: KeyEvent) => {
                return this.handleNavKey(event);
              })
              .onKeyEvent((event: KeyEvent) => {
                const handled: boolean = this.handleNavKey(event);
                if (handled) {
                  event.stopPropagation();
                }
              })

            Row() {
              TablerIcon('x', 16, $r('app.color.muted_text'))
            }
            .alignItems(VerticalAlign.Center)
            .width(28)
            .height(28)
            .justifyContent(FlexAlign.Center)
            .borderRadius(4)
            .onClick(() => { this.closePanel(); })
          }
          .width('100%')
          .padding({ left: 16, right: 12, top: 8, bottom: 8 })
          .border({ width: { bottom: 1 }, color: $r('app.color.border') })

          // 结果区域
          if (this.getDisplayResults().length === 0) {
            Column({ space: 8 }) {
              TablerIcon('search', 32, $r('app.color.muted_text'))
              Text(this.searchQuery === '' ? '开始搜索' : '未找到结果')
                .fontSize(14)
                .fontColor($r('app.color.muted_text'))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            // 结果区宿主必须是 List（不是 Scroll）：Scroller.scrollToIndex 的 NOTE 只对
            // ArcList/Grid/List/WaterFlow 生效（SDK scroll.d.ts:488），而键盘移动高亮时
            // 必须把高亮行滚入视口 —— 与 CommandPalette S1-F 补丁同一取舍。
            List({ space: 0, scroller: this.listScroller }) {
              // 空搜索词时显示"最近访问"标题；它是第 0 个 ListItem，
              // 故 scrollToIndex 需要 listIndexOffset() 的 +1 偏移。
              if (this.searchQuery === '') {
                ListItem() {
                  Row({ space: 6 }) {
                    TablerIcon('refresh', 14, $r('app.color.muted_text'))
                    Text(t('recent').toUpperCase())
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.muted_text'))
                  }
                  .width('100%')
                  .padding({ left: 16, top: 10, bottom: 6 })
                }
              }

              ForEach(this.getDisplayResults(), (result: SearchResultItem, index: number) => {
                ListItem() {
                  this.ResultItem(result, index)
                }
              }, (result: SearchResultItem, index: number) => index.toString())
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }

          // 键盘提示行：与 CommandPalette 同源文案（↑↓ 选择 / ↵ 打开 / esc 关闭）
          this.KeyHintFooter()
        }
        .width('80%')
        .constraintSize({ maxHeight: '70%' })
        .backgroundColor($r('app.color.surface1'))
        .borderRadius(10)
        .border({ width: 1, color: $r('app.color.border') })
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.2)', offsetX: 0, offsetY: 8 })
        // 兜底落点：焦点若因故落到列表区域（而非输入框），这里仍能接管 ↑↓ / ↵ / esc；
        // 与输入框上的回调靠 lastHandledKeyCode 去重，不会出现一次按键走两格。
        .onKeyEvent((event: KeyEvent) => {
          if (this.handleNavKey(event)) {
            event.stopPropagation();
          }
        })
      }
      .width('100%')
      .height('100%')
      // Stack 没有 justifyContent（原写法是编译期报错属性），去掉它并显式声明居中：
      // Stack 的默认对齐本就是 Center，这里用 alignContent 把「面板在遮罩上居中」写清楚。
      .alignContent(Alignment.Center)
    } else {
      Column().width(0).height(0)
    }
  }

  @Builder
  ResultItem(result: SearchResultItem, index: number) {
    Row({ space: 10 }) {
      // 图标
      if (result.type === 'page') {
        TablerIcon('file', 16, $r('app.color.primary'))
      } else {
        TablerIcon('indent-increase', 16, $r('app.color.muted_text'))
      }

      // 内容
      Column({ space: 3 }) {
        if (result.type === 'page') {
          // 页面结果：高亮页面名
          Text() {
            ForEach(this.splitHighlight(result.content, this.searchQuery), (seg: TextSegment, idx: number) => {
              Span(seg.text)
                .fontSize(14)
                .fontColor(seg.isMatch ? $r('app.color.primary') : $r('app.color.text'))
                .backgroundColor(seg.isMatch ? $r('app.color.search_highlight') : 'rgba(0,0,0,0)')
            }, (seg: TextSegment, idx: number) => idx.toString())
          }
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          // Block 结果：内容预览 + 所属页面
          Text() {
            ForEach(this.splitHighlight(result.content, this.searchQuery), (seg: TextSegment, idx: number) => {
              Span(seg.text)
                .fontSize(13)
                .fontColor(seg.isMatch ? $r('app.color.primary') : $r('app.color.text'))
                .backgroundColor(seg.isMatch ? $r('app.color.search_highlight') : 'rgba(0,0,0,0)')
            }, (seg: TextSegment, idx: number) => idx.toString())
          }
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 4 }) {
            TablerIcon('file', 14, $r('app.color.muted_text'))
            Text(result.pageName)
              .fontSize(11)
              .fontColor($r('app.color.muted_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .borderRadius(6)
    // 高亮：鼠标悬停 > 键盘选中 > 透明（见 rowBackground）
    .backgroundColor(this.rowBackground(index))
    .onHover((isHover: boolean) => {
      this.setHovered(index, isHover);
    })
    .onClick(() => { this.navigateToResult(result); })
  }

  /**
   * 底部快捷键提示行 —— 与 CommandPalette.KeyHintFooter 同源同文案
   * （↑↓ 选择 / ↵ 打开 / esc 关闭），本面板这三条均已有对应实现。
   */
  @Builder
  KeyHintFooter() {
    Row({ space: 10 }) {
      this.HintPair('↑↓', t('hint_select'))
      this.HintPair('↵', t('hint_open'))
      this.HintPair('esc', t('hint_close'))
      Blank()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .border({ width: { top: 1 }, color: $r('app.color.border') })
  }

  @Builder
  HintPair(key: string, label: string) {
    Row({ space: 4 }) {
      Text(key)
        .fontSize(10)
        .fontColor($r('app.color.text'))
        .padding({ left: 5, right: 5, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor($r('app.color.surface2'))
      Text(label)
        .fontSize(10)
        .fontColor($r('app.color.muted_text'))
    }
    .alignItems(VerticalAlign.Center)
  }
}
