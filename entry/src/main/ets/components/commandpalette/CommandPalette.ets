import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { WorkspaceService } from '../../services/WorkspaceService';
import { PageData } from '../../core/models/Page';
import { AppState } from '../../state/AppState';
import { KeyCode } from '@kit.InputKit';

/**
 * CommandPalette — Obsidian 风格快速切换 / 命令面板。
 *
 * 键盘导航（本次补全，对应底部提示行声明的 ↑↓ / ↵ / esc）：
 *   - ↑ / ↓ 在**当前过滤后的列表**内移动高亮；
 *   - ↵ 打开高亮项（结果为空时为「创建页面」兜底行）；
 *   - esc 关闭面板。
 *
 * 焦点策略：面板打开时由本组件主动 requestFocus 到输入框，关闭时归还给宿主
 * （宿主通过 restoreFocusId 告知归还目标，默认 'contentAreaScroll'）。
 */
@Component
export struct CommandPalette {
  /** 输入框焦点 id；打开面板与点击面板空白处都会请求它 */
  static readonly INPUT_FOCUS_ID: string = 'commandPaletteInput';
  /** 列表最多渲染行数（既有行为，保持不变） */
  private static readonly MAX_VISIBLE: number = 15;

  @State queryText: string = '';
  /** 过滤后的完整结果集（不是渲染子集） */
  @State results: PageData[] = [];
  /**
   * 当前高亮行的下标。
   * 语义域 = clamp 之后的「渲染行」下标：
   *   results 非空 → [0, min(results.length, MAX_VISIBLE))
   *   results 为空 → 恒为 0（唯一的「创建页面」行）
   * 任何时刻都指向一个真实存在的渲染行，因此背景高亮永远可见，
   * 不会出现「下标越界导致看不出选中项」的情况。
   */
  @State selectedIndex: number = 0;
  /**
   * 鼠标悬停行下标；-1 表示无悬停。
   * 键鼠不打架的取舍：hover 不改写 selectedIndex，只在悬停期间让视觉高亮跟随鼠标；
   * 鼠标移出（onHover(false)）后键盘选中重新显形 —— 这样鼠标划过不会毁掉键盘位置，
   * 而按下 ↵ 永远打开键盘选中的那一项，不会出现「看起来选中 A、回车却打开 B」。
   */
  @State hoveredIndex: number = -1;

  /** 关闭面板回调（由宿主提供，避免面板直接耦合宿主实现） */
  onRequestClose: () => void = () => {};
  /** 面板关闭后焦点归还目标（宿主的焦点容器 id） */
  restoreFocusId: string = 'contentAreaScroll';

  /**
   * 结果列表的滚动控制器（S1-F 补丁）。
   *
   * 列表 15 行 × 48vp + 14 × 2vp 间距 = 748vp，远超面板 420vp 高度，
   * 因此第 9 行之后的键盘高亮会滚出视口 —— 必须把高亮行主动滚入可视区。
   *
   * 该字段故意不加 @State：Scroller 是稳定引用对象，不参与 ArkTS 状态观察。
   */
  private listScroller: Scroller = new Scroller();

  /** 打开时主动把焦点抢到输入框，消除与内容区 defaultFocus 的竞争 */
  private inputFocusRequested: boolean = false;
  /**
   * 上一次已被本面板消费的按键码；-1 表示当前没有「已消费待复位」的按键。
   *
   * 去重目的：输入框与根节点都挂了导航回调，同一个物理按键可能被两处各收到一次。
   * 不用 KeyEvent.timestamp 作为第二个判据 —— 该字段在本机 SDK 的 KeyEvent（手机/平板/2in1 形态）
   * 上会被编译期判为不可用（ArkTS 告警 "This API is unavailable to phone, tablet, 2in1"），
   * 因此改为「按键码单调标记」：同一按键码连续到达时只认第一次，
   * 收到**不同**按键码即复位标记，从而不会阻塞用户连按同一个键（长按连发）。
   */
  private lastHandledKeyCode: number = -1;

  aboutToAppear(): void {
    const ws = WorkspaceService.getInstance();
    this.results = ws.getAllPages();
    this.selectedIndex = 0;
    this.hoveredIndex = -1;
    this.focusInput();
  }

  /**
   * 关闭时归还焦点。
   * 宿主内容区在 aboutToAppear 里 requestFocus 过自己，但面板打开期间焦点被输入框拿走，
   * 关闭后若不显式归还，内容区的 onKeyEvent（全局快捷键）就不会再触发。
   */
  aboutToDisappear(): void {
    focusControl.requestFocus(this.restoreFocusId);
  }

  build() {
    Column() {
      // 搜索输入框
      Row({ space: 8 }) {
        TablerIcon('search', 16, $r('app.color.muted_text'))
        TextInput({ placeholder: t('placeholder_search'), text: this.queryText })
          .id(CommandPalette.INPUT_FOCUS_ID)
          .fontSize(16)
          .layoutWeight(1)
          .height(48)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .caretColor($r('app.color.primary'))
          .onChange((value: string) => {
            this.queryText = value;
            this.doSearch(value);
          })
          // ↓↓ 键盘导航的落点：输入框是面板打开后的持焦节点，
          //    挂在这里保证按键一定送到（不依赖祖先节点的按键冒泡是否可达）。
          // onKeyPreIme 先于 IME 拿到按键 —— 这是「TextInput 吞掉 ↑↓」的常见坑：
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
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .border({ width: { bottom: 1 }, color: $r('app.color.border') })

      // 搜索结果
      // S1-F 补丁：宿主由 Scroll 改为 List。
      // 依据 SDK `component/scroll.d.ts:488` —— Scroller.scrollToIndex 的 NOTE 明确
      // 「This API only works for the ArcList, Grid, List, and WaterFlow components」，
      // **不含 Scroll**；Scroll 上只有 scrollTo/scrollBy（同文件 :538 的 NOTE 列出 Scroll）。
      // 因此「高亮行滚入视口」只能靠 List 宿主实现（列表本身的滚动能力与 Scroll 等价）。
      // 行高 48 + List space 2 = 原来的 Column space 2 间距，逐项渲染（≤15 行），视觉零变化。
      List({ space: 2, scroller: this.listScroller }) {
        if (this.visibleCount() === 0) {
          // 无命中：保留既有「创建页面」兜底行，并把它纳入键盘导航（它是唯一的第 0 行）
          ListItem() {
            Row({ space: 8 }) {
              Text(t('placeholder_search_no_match'))
                .fontSize(15)
                .fontColor($r('app.color.muted_text'))
            }
            .width('100%')
            .height(40)
            .padding({ left: 16, right: 16 })
          }

          ListItem() {
            Row({ space: 8 }) {
              TablerIcon('plus', 16, $r('app.color.primary'))
              Text(t('create_page_prefix') + this.queryText)
                .fontSize(15)
                .fontColor($r('app.color.primary'))
                .maxLines(1)
                .layoutWeight(1)
            }
            .width('100%')
            .height(48)
            .padding({ left: 16, right: 16 })
            .borderRadius(6)
            .backgroundColor(this.rowBackground(0))
            .onHover((isHover: boolean) => {
              this.setHovered(0, isHover);
            })
            .onClick(() => {
              this.activateItem(0);
            })
          }
        } else {
          ForEach(this.visiblePages(), (page: PageData, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                if (page.journalDay !== '') {
                  TablerIcon('calendar', 16, $r('app.color.muted_text'))
                } else {
                  TablerIcon('file', 16, $r('app.color.muted_text'))
                }

                Column({ space: 2 }) {
                  Text(page.originalName)
                    .fontSize(15)
                    .fontColor($r('app.color.text'))
                  if (page.tags.length > 0) {
                    Text(page.tags.join(', '))
                      .fontSize(12)
                      .fontColor($r('app.color.muted_text'))
                      .maxLines(1)
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .width('100%')
              .height(48)
              .padding({ left: 16, right: 16 })
              .borderRadius(6)
              .backgroundColor(this.rowBackground(index))
              .onHover((isHover: boolean) => {
                this.setHovered(index, isHover);
              })
              .onClick(() => {
                this.activateItem(index);
              })
            }
          }, (page: PageData) => page.uuid)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: 8, left: 8, right: 8 })
      .scrollBar(BarState.Auto)

      // 底部快捷键提示行
      this.KeyHintFooter()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    // 兜底落点：若焦点因故落到列表区域（而非输入框），这里仍能接管 ↑↓ / ↵ / esc。
    // 与输入框上的回调靠 lastHandledKeyCode 去重，不会出现一次按键走两格。
    .onKeyEvent((event: KeyEvent) => {
      if (this.handleNavKey(event)) {
        event.stopPropagation();
      }
    })
  }

  // ─── 列表派生数据 ───

  /**
   * 渲染行的页面子集（受 MAX_VISIBLE 限制）。
   * @returns 过滤后列表的前 MAX_VISIBLE 项
   */
  private visiblePages(): PageData[] {
    return this.results.slice(0, CommandPalette.MAX_VISIBLE);
  }

  /**
   * 渲染行总数：results 为空时为 1（「创建页面」兜底行），否则为截断后的结果数。
   * 键盘导航与高亮 clamp 都以本方法为准 —— 即**始终作用于过滤后的列表**。
   * @returns 可导航行数
   */
  private visibleCount(): number {
    if (this.results.length === 0) {
      return 1;
    }
    return this.results.length < CommandPalette.MAX_VISIBLE
      ? this.results.length
      : CommandPalette.MAX_VISIBLE;
  }

  /**
   * 行背景色。
   * 优先级：鼠标悬停 > 键盘选中 > 透明。
   * @param index 渲染行下标
   * @returns 该行的背景色
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

  // ─── 键盘导航 ───

  /**
   * 统一的导航按键处理。
   *
   * 去重：同一个物理事件可能同时被输入框与根节点收到（见 lastHandledKeyCode 说明），
   * 同一按键码连续到达时只处理第一次，保证一次按压只产生一步状态变化。
   *
   * @param event ArkUI KeyEvent
   * @returns true 表示已消费（调用方应停止传播）
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
    // 未消费的按键（普通字符、Tab、Shift 等）复位标记，
    // 这样用户「↓ ↓ ↓」连按时每一步都会被接受。
    this.lastHandledKeyCode = -1;
    return false;
  }

  /**
   * 按键 → 动作映射。
   * @param keyCode 按键码
   * @returns 是否被本面板消费
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
      this.close();
      return true;
    }
    return false;
  }

  /**
   * 把当前高亮行滚入可视区（S1-F 补丁的核心）。
   *
   * 为什么是 scrollToIndex 而不是 scrollTo：
   *   Scroller.scrollToIndex(value, smooth, align) 的 align=ScrollAlign.AUTO 语义为
   *   「目标项已完整可见则不动，否则按最短滚动距离把它完整显示出来」
   *   （SDK scroll.d.ts:501-504），与「键盘移动时尽量少滚动」的期望完全一致；
   *   而 scrollTo({ yOffset }) 需要自己按「行高 × 行数」估算偏移，
   *   在有 padding、无命中兜底行（40vp）与 48vp 行混排时会算错，
   *   且 ScrollOptions 单位/边界换算易出偏差。
   *   smooth 取 false：即时定位，避免动画期间（>200vp/s）列表项不响应点击
   *   （SDK scroll.d.ts:366-368 的已知约束）。
   *
   * 调用时机：只在 selectedIndex 真正发生变化之后调用。此时目标 ListItem 已存在
   * （列表全部渲染，≤15 行），列表也已布局完成，下标有效。
   */
  private scrollHighlightIntoView(): void {
    this.listScroller.scrollToIndex(this.selectedIndex, false, ScrollAlign.AUTO);
  }

  /**
   * 移动高亮。到底/到顶后停留在边界（不做环绕，避免误触回到底部）。
   * @param delta -1 上移，1 下移
   */
  private moveSelection(delta: number): void {
    const count: number = this.visibleCount();
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

  /**
   * 打开当前高亮行。
   */
  private activateSelected(): void {
    this.activateItem(this.selectedIndex);
  }

  /**
   * 打开指定渲染行：命中页面则跳转，否则按输入内容创建页面。
   * @param index 渲染行下标
   */
  private activateItem(index: number): void {
    const pages: PageData[] = this.visiblePages();
    if (index >= 0 && index < pages.length) {
      this.openPage(pages[index].originalName);
      return;
    }
    this.createPage();
  }

  /**
   * 关闭面板：走宿主的关闭回调，并显式归还焦点。
   */
  private close(): void {
    this.onRequestClose();
    focusControl.requestFocus(this.restoreFocusId);
  }

  /**
   * 把焦点抢到输入框。
   * 用下一帧请求：aboutToAppear 阶段组件尚未完成布局，立即 requestFocus 可能落空。
   */
  private focusInput(): void {
    if (this.inputFocusRequested) {
      return;
    }
    this.inputFocusRequested = true;
    setTimeout(() => {
      focusControl.requestFocus(CommandPalette.INPUT_FOCUS_ID);
    }, 0);
  }

  // ─── 鼠标悬停 ───

  /**
   * 更新悬停行。离开时仅在「确实是当前悬停项」的情况下复位，避免快速划过时误清。
   * @param index 渲染行下标
   * @param isHover 是否进入
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

  // ─── 搜索 ───

  /**
   * 执行过滤搜索。
   * 过滤后必须把 selectedIndex 归零：否则旧下标可能越界或指向另一个页面，
   * 导致「输入后回车打开了意料之外的页面」。
   * S1-F 补丁：下标归零后同步把列表滚回顶部，否则高亮第 0 行却停在旧的滚动位置，
   * 第 0 行同样会不可见（与 ↑↓ 同一个缺陷的另一半）。
   * @param query 查询串
   */
  doSearch(query: string): void {
    const ws = WorkspaceService.getInstance();
    if (query === '') {
      this.results = ws.getAllPages();
    } else {
      this.results = ws.searchPages(query);
    }
    this.selectedIndex = 0;
    this.hoveredIndex = -1;
    this.scrollHighlightIntoView();
  }

  // ─── 动作 ───

  private openPage(name: string): void {
    AppState.setCurrentPage(name);
    this.onRequestClose();
  }

  private createPage(): void {
    AppState.setCurrentPage(this.queryText);
    this.onRequestClose();
  }

  /**
   * 底部快捷键提示行（对齐 Obsidian 图 6：↑↓ 选择 / ↵ 打开 / esc 关闭）。
   * 本次 S1-F 起，这三条提示均已有对应实现。
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
