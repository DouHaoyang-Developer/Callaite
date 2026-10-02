import { TablerIcon } from '../common/Icons';
import { WorkspaceService } from '../../services/WorkspaceService';
import { BacklinkInfo } from '../../core/db/DataStore';
import { AnchorRegistry, AnchorSource } from '../../services/AnchorRegistry';

/**
 * BacklinkDisplay — 反链展示信息（含从 Block 中提取的 tags 和时间戳）。
 *
 * BacklinkInfo 仅包含 sourceBlockId/sourceContent/sourcePageName/isBlockRef，
 * 筛选和排序所需的 tags/createdAt/updatedAt 通过 sourceBlockId 查询 Block 获取。
 */
export interface BacklinkDisplay {
  sourceBlockId: string;
  sourceContent: string;
  sourcePageName: string;
  isBlockRef: boolean;
  tags: string[];
  createdAt: number;
  updatedAt: number;
}

/**
 * BacklinkFilters — 反链筛选 UI 组件。
 *
 * 对应 Logseq sidebar/backlinks.cljs 中的筛选与排序面板。
 *
 * 功能：
 *  - 文本筛选（按 content 包含）
 *  - 标签筛选（下拉选择标签）
 *  - 排序（更新时间 / 创建时间 / 内容字母序）
 *
 * 用法：
 *   BacklinkFilters({ pageName: 'MyPage' })                       // 自带工具栏（独占面板）
 *   BacklinkFilters({ pageName: 'MyPage', showToolbar: false })   // 仅列表，工具栏由宿主渲染
 *
 * ⚠️ W8-U1.3：本文件此前**全仓零引用**，因此从未进入 ArkTS 编译图 ——
 * 接线时实测它内藏一处真编译错误（`Select(...).fontSize(13)`：
 * `Property 'fontSize' does not exist on type 'SelectAttribute'`）。
 * 是「先接线再修错」而不是「先修错再接线」才把它暴露出来的（AGENTS §7 陷阱 1）。
 * 详见右下角 showToolbar 注释与 RightSidebar 的挂载说明。
 */
@Component
export struct BacklinkFilters {
  /** 目标页面名（反链指向的页面） */
  @Prop @Watch('onPageNameChanged') pageName: string;
  /**
   * 外部数据版本号 —— 宿主在反链数据可能变化时自增它即可触发重新拉取。
   *
   * 为什么需要：本组件只在 aboutToAppear 里 loadBacklinks()，而宿主（右侧栏）会在
   * 切页 / 聚焦块变化 / 增删块后刷新反链。没有这个入口时，面板会一直显示
   * **首次挂载那一刻**的陈旧数据（且因为数据没变，界面上看不出任何异常）。
   */
  @Prop @Watch('onDataVersionChanged') dataVersion: number = 0;
  /**
   * 是否渲染本组件自带的筛选工具栏与计数行。
   *
   * - true （默认）：自成一体，适合把本组件当作**独占的反链面板**整体挂载。
   * - false：只渲染反链列表；工具栏与计数由宿主负责（RightSidebar 就是这样用的 ——
   *   它把「筛选/搜索/+」三个图标做成了**常显热区**，因为触屏不产生 onHover
   *   （AGENTS §7 陷阱 11），把入口藏在 hover 里等于在平板上不存在）。
   */
  @Prop showToolbar: boolean = true;
  /**
   * 是否渲染「共 N 条反链」计数行。
   *
   * 与 showToolbar 分开是因为宿主可能**分别**挂两次本组件（RightSidebar 就是这样）：
   * 一次只取筛选工具栏、一次只取列表。若把计数绑死在 showToolbar 上，
   * 筛选面板与列表会各画一行相同的计数（重复 UI）。
   */
  @Prop showCount: boolean = true;
  /**
   * 是否渲染反链列表本体。
   *
   * 同样与上面两个开关分开：RightSidebar 挂**两次**本组件 ——
   * 筛选面板那次只取工具栏（`showList: false`），列表那次只取计数 + 列表。
   * 两次都带上列表就会把同一批反链画两遍。
   */
  @Prop showList: boolean = true;
  /**
   * 只渲染标签下拉（RightSidebar 的「筛选」面板）。
   *
   * W8-U1.3：右侧栏只有 ~248vp 宽，把「文本输入 + 标签下拉 + 排序按钮」全平铺时
   * 每个控件都被压到不可用（实测输入框只剩 8px）。因此**按筛选维度拆开渲染**：
   *  · showTagOnly  —— filter 图标：按标签收窄
   *  · showQueryOnly—— search 图标：按关键词收窄
   *  · 排序按钮两者都带（排序是视角切换，不是筛选维度）
   * 这样既避开了宽度预算问题，也让两个图标各自有**互不相同**的实义。
   */
  @Prop showTagOnly: boolean = false;
  /** 只渲染文本输入框（RightSidebar 的「搜索」面板） */
  @Prop showQueryOnly: boolean = false;
  /** 文本筛选词 */
  @State filterText: string = '';
  /** 标签筛选（空字符串表示不筛选） */
  @State filterTag: string = '';
  /** 排序方式：'updated' / 'created' / 'content' */
  @State sortBy: string = 'updated';
  /** 原始反链列表 */
  @State backlinks: BacklinkInfo[] = [];
  /** 所有可用标签（用于下拉） */
  @State allTags: string[] = [];

  aboutToAppear(): void {
    this.reloadFromSource();
  }

  /** pageName 变化（宿主换了目标页）⇒ 重新拉取 */
  onPageNameChanged(): void {
    this.reloadFromSource();
  }

  /** 宿主自增 dataVersion ⇒ 重新拉取 */
  onDataVersionChanged(): void {
    this.reloadFromSource();
  }

  /**
   * 重新拉取反链数据与标签表。
   */
  reloadFromSource(): void {
    this.loadBacklinks();
    this.allTags = WorkspaceService.getInstance().getAllTags();
  }

  /**
   * 加载反链数据。
   *
   * 口径与 `RightSidebar.refreshCaches()` / `BacklinkWarning.countBacklinks()` 完全一致：
   * 都走 `WorkspaceService` 的反链读取入口（单一数据源，不另开口径）。
   *
   * ⚠️ S3-W1：改用 `getBacklinksFresh()` 而不是 `getDataStore().getBacklinks()` ——
   *   前者在读之前先 flush 脏页，否则「刚打完 `[[x]]`、索引还没对账」时读到的是旧索引，
   *   面板会显示成 W12-3 的样子（假阴性）。**索引口径没变**，变的只是读取时机。
   */
  loadBacklinks(): void {
    const ws = WorkspaceService.getInstance();
    this.backlinks = ws.getBacklinksFresh(this.pageName);
  }

  /**
   * 构建标签下拉选项（含"全部标签"选项）。
   */
  getTagOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    const allOption: SelectOption = { value: '全部标签' };
    options.push(allOption);
    for (let i = 0; i < this.allTags.length; i++) {
      const option: SelectOption = { value: this.allTags[i] };
      options.push(option);
    }
    return options;
  }

  /**
   * 获取排序按钮显示文本。
   */
  getSortLabel(): string {
    if (this.sortBy === 'updated') {
      return '按更新时间';
    }
    if (this.sortBy === 'created') {
      return '按创建时间';
    }
    return '按内容排序';
  }

  /**
   * 循环切换排序方式：updated → created → content → updated
   */
  cycleSort(): void {
    if (this.sortBy === 'updated') {
      this.sortBy = 'created';
    } else if (this.sortBy === 'created') {
      this.sortBy = 'content';
    } else {
      this.sortBy = 'updated';
    }
  }

  /**
   * 当前是否有任何筛选生效（决定空态文案）。
   */
  hasActiveFilter(): boolean {
    return this.filterText !== '' || this.filterTag !== '';
  }

  /**
   * 将 BacklinkInfo 转换为 BacklinkDisplay（补充 tags 和时间戳）。
   */
  private enrichBacklink(info: BacklinkInfo): BacklinkDisplay {
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(info.sourceBlockId);
    const tags: string[] = [];
    let createdAt: number = 0;
    let updatedAt: number = 0;
    if (block) {
      for (let i = 0; i < block.tags.length; i++) {
        tags.push(block.tags[i]);
      }
      createdAt = block.createdAt;
      updatedAt = block.updatedAt;
    }
    const display: BacklinkDisplay = {
      sourceBlockId: info.sourceBlockId,
      sourceContent: info.sourceContent,
      sourcePageName: info.sourcePageName,
      isBlockRef: info.isBlockRef,
      tags: tags,
      createdAt: createdAt,
      updatedAt: updatedAt
    };
    return display;
  }

  /**
   * 获取筛选 + 排序后的反链列表。
   */
  getFilteredBacklinks(): BacklinkDisplay[] {
    // 1. 转换为 BacklinkDisplay
    const enriched: BacklinkDisplay[] = [];
    for (let i = 0; i < this.backlinks.length; i++) {
      enriched.push(this.enrichBacklink(this.backlinks[i]));
    }

    // 2. 筛选
    const filtered: BacklinkDisplay[] = [];
    const lowerFilter = this.filterText.toLowerCase();
    for (let i = 0; i < enriched.length; i++) {
      const item = enriched[i];
      // 文本筛选：content 包含筛选词
      if (lowerFilter !== '') {
        if (item.sourceContent.toLowerCase().indexOf(lowerFilter) < 0) {
          continue;
        }
      }
      // 标签筛选：tags 包含选中标签
      if (this.filterTag !== '') {
        let tagFound = false;
        for (let j = 0; j < item.tags.length; j++) {
          if (item.tags[j] === this.filterTag) {
            tagFound = true;
            break;
          }
        }
        if (!tagFound) {
          continue;
        }
      }
      filtered.push(item);
    }

    // 3. 排序
    if (this.sortBy === 'updated') {
      filtered.sort((a: BacklinkDisplay, b: BacklinkDisplay): number => {
        return b.updatedAt - a.updatedAt;
      });
    } else if (this.sortBy === 'created') {
      filtered.sort((a: BacklinkDisplay, b: BacklinkDisplay): number => {
        return b.createdAt - a.createdAt;
      });
    } else {
      // content：按内容字母序
      filtered.sort((a: BacklinkDisplay, b: BacklinkDisplay): number => {
        if (a.sourceContent < b.sourceContent) {
          return -1;
        }
        if (a.sourceContent > b.sourceContent) {
          return 1;
        }
        return 0;
      });
    }

    return filtered;
  }

  /**
   * 筛选工具栏（文本 / 标签 / 排序）。
   *
   * ⚠️ 原实现把 `Select(...).fontSize(13)` 写在这里 —— SelectAttribute 没有 fontSize，
   * 是接线时暴露出的编译错误。字号改由 Select 自身默认样式承担（与同仓其余 Select 一致）。
   */
  @Builder
  FilterToolbar() {
    Row({ space: 6 }) {
      // 文本筛选输入框（showTagOnly 时隐藏 —— 见 showTagOnly 注释的宽度预算说明）
      if (!this.showTagOnly) {
        TextInput({ text: this.filterText, placeholder: '筛选反链...' })
          .fontSize(13)
          .layoutWeight(1)
          .height(32)
          .backgroundColor($r('app.color.surface2'))
          .borderRadius(6)
          .onChange((value: string) => {
            this.filterText = value;
          })
      }

      // 标签下拉（showQueryOnly 时隐藏）
      if (!this.showQueryOnly) {
        Select(this.getTagOptions())
          .selected(0)
          .value(this.filterTag === '' ? '全部标签' : this.filterTag)
          .height(32)
          .width(120)
          .backgroundColor($r('app.color.surface2'))
          .borderRadius(6)
          .onSelect((index: number, text: string) => {
            if (text === '全部标签') {
              this.filterTag = '';
            } else {
              this.filterTag = text;
            }
          })
      }

      // 排序按钮（两种面板都带）
      Row({ space: 3 }) {
        TablerIcon('arrows-sort', 13, $r('app.color.muted_text'))
        Text(this.getSortLabel())
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
          .maxLines(1)
      }
      .height(32)
      .padding({ left: 8, right: 8 })
      .backgroundColor($r('app.color.surface2'))
      .borderRadius(6)
      .onClick(() => {
        this.cycleSort();
      })
    }
    .width('100%')
  }

  build() {
    // 纯工具栏模式（宿主只取筛选工具栏）：不套外层 padding，让宿主控制缩进。
    //
    // ⚠️ W8-U1.3 踩坑记录：这里原先还有一个 `showCountOnly()` 的早返回分支，
    // 结果是「计数行画出来了、反链列表整块不渲染」—— 因为那个分支只输出 CountRow，
    // 而列表是在下方 else 的 Column 里调的。设备实测表现为
    // 「共 2 条反链」下面一片空白（列表宿主节点 0 高度），极易被误判成数据为空。
    // 教训：分支化的 build() 里，任何「只输出一部分」的早返回都必须重新核对
    // 它漏掉了哪些本该输出的部分。
    if (this.showToolbarOnly()) {
      this.FilterToolbar()
    } else {
      Column({ space: 12 }) {
        if (this.showToolbar) {
          this.FilterToolbar()
        }
        if (this.showCount) {
          this.CountRow()
        }
        // ─── 反链列表 ───
        //
        // ★ W12 修复（切页后反链列表不刷新）：本段**刻意内联在 build() 里**，
        //   而不是抽成 `BacklinkList(filtered)` 那样的**带参 @Builder**。
        //
        //   实测（W12，2in1，`2026-09-25` ⇄ `2026-09-30`）：
        //     · 计数行（`CountRow` 直接读 `this.getFilteredBacklinks()`）**切页后正确更新**；
        //     · 列表（`@Builder BacklinkList(filtered)` 里的 `ForEach`）**不更新** ——
        //       切到反链为 0 的页面后，上一条反链卡片**仍留在屏幕上**，
        //       形成「计数 0 / 列表 1」的自相矛盾画面（截图与 `dumpLayout` 双证）。
        //   插桩实测的判据：切页后 `@Prop @Watch` 确实跑到了、`@State backlinks` 确实刷新了
        //     （`BF.watch page=2026-09-25 raw=0 showList=true`），
        //     ⇒ **数据层是新的，只有 ForEach 没重跑**。
        //   机制与 AGENTS 陷阱 15 同族：**参数化 `@Builder` 里的 `ForEach` 不随「参数变化」重跑**
        //     （它只认自己被创建那次的数据；本例 `filtered` 由 1 条变 0 条，ForEach 仍渲染旧 1 条）。
        //   ⇒ 修法就是**让 ForEach 直接依赖 `@State`**：内联进 build()，
        //     数据源改为 `this.getFilteredBacklinks()`（与计数行同源，两处口径不可能再打架）。
        //   ⚠️ 不要为了「复用」把它再抽回带参 @Builder —— 那正是本缺陷的成因。
        if (this.showList) {
          if (this.getFilteredBacklinks().length === 0) {
            Column({ space: 8 }) {
              TablerIcon('link-off', 28, $r('app.color.muted_text'))
              // 空态分两种：本来就没有反链 vs 有反链但被筛掉了 —— 后者要给出可操作提示，
              // 否则用户看到「暂无反链」会以为数据没了（筛选态下的静默误导）。
              Text(this.hasActiveFilter() ? '没有匹配的反链（请调整筛选条件）' : '暂无反链')
                .fontSize(13)
                .fontColor($r('app.color.muted_text'))
            }
            .width('100%')
            .padding({ top: 32, bottom: 32 })
            .alignItems(HorizontalAlign.Center)
          } else {
            Column({ space: 0 }) {
              ForEach(this.getFilteredBacklinks(), (item: BacklinkDisplay) => {
                this.BacklinkItem(item)
              }, (item: BacklinkDisplay) => item.sourceBlockId)
            }
            .width('100%')
          }
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    }
  }

  /** 宿主只想取筛选工具栏（RightSidebar 的「筛选」/「搜索」面板） */
  private showToolbarOnly(): boolean {
    return this.showToolbar && !this.showCount && !this.showList;
  }

  /** 计数行 */
  @Builder
  CountRow() {
    Row({ space: 6 }) {
      TablerIcon('link', 14, $r('app.color.muted_text'))
      Text('共 ' + this.getFilteredBacklinks().length.toString() + ' 条反链')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
    }
    .width('100%')
  }

  /**
   * U2.1b：点击反链条目 → 跳到**来源块**（这是第三处锚点来源）。
   *
   * 迁移前的实况：本列表项**没有任何 onClick** —— 反链面板只能看、不能跳
   * （`BacklinkItem` 的 @Builder 根节点上没有任何手势；全文件唯一的 onClick 是排序按钮）。
   * 于是 c7fbff7 提交说明里的「三处来源（搜索/大纲/反链）」实际只有两处接线，
   * 反链这条路径缺失。这里把它接到**同一个入口** `AnchorRegistry`。
   *
   * 语义：反链的 `sourceBlockId` 是**引用发生的那个块**，它属于**别的页面**
   * （`DataStore.getBacklinks` 用 `getPageUuidForBlock(sourceBlockId)` 反查页），
   * 因此这条路径天然是「跨页 + 等一帧」那一支 —— 由 Registry 统一判定与处理。
   * 若来源块是子块且其祖先处于折叠态，服务会先展开祖先再等一帧滚动（DEFERRED），
   * 这也是「等一帧」那条路径的真实用武之地。
   *
   * 不传 onDismiss：右侧栏不是模态，跳转后应保持打开（Obsidian 同款行为），
   * 与搜索面板「必须先关面板」正好相反 —— 这个差异由调用方声明、由 Registry 执行。
   */
  private jumpToSource(item: BacklinkDisplay): void {
    AnchorRegistry.getInstance().jump({
      blockUuid: item.sourceBlockId,
      source: AnchorSource.BACKLINK,
      pageNameHint: item.sourcePageName
    });
  }

  /**
   * 单条反链渲染。
   */
  @Builder
  BacklinkItem(item: BacklinkDisplay) {    Column({ space: 4 }) {
      // 来源页面名 + 引用类型
      Row({ space: 6 }) {
        TablerIcon(item.isBlockRef ? 'hash' : 'file', 12, $r('app.color.primary'))
        Text(item.sourcePageName)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      // 内容预览
      Text(item.sourceContent)
        .fontSize(12)
        .fontColor($r('app.color.text'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      // 标签
      if (item.tags.length > 0) {
        Row({ space: 4 }) {
          ForEach(item.tags, (tag: string) => {
            Text('#' + tag)
              .fontSize(10)
              .fontColor($r('app.color.muted_text'))
              .padding({ left: 4, right: 4, top: 2, bottom: 2 })
              .backgroundColor($r('app.color.surface2'))
              .borderRadius(3)
          }, (tag: string) => tag)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .margin({ top: 4, bottom: 4 })
    .borderRadius(6)
    .backgroundColor($r('app.color.surface1'))
    .border({ width: 1, color: $r('app.color.border') })
    // U2.1b：整卡可点 ⇒ 跳到来源块（第三处锚点来源；此前本列表项完全不可点）
    .onClick(() => {
      this.jumpToSource(item);
    })
  }
}
