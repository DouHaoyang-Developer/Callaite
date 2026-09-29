import { HomePage } from './HomePage';
import { IntegralEditor } from '../outliner/IntegralEditor';
import { BlockList } from '../outliner/BlockList';
import { JournalFeed } from './JournalFeed';
import { JournalService } from '../../services/JournalService';
import { SettingsPage } from '../settings/SettingsPage';
import { QueryBuilder } from '../query/QueryBuilder';
import { GraphView } from '../graph/GraphView';
import { Whiteboard } from '../whiteboard/Whiteboard';
import { FlashcardPage } from '../flashcard/FlashcardPage';
import { PdfPage } from '../extensions/PdfPage';
import { ProUpgradePage } from '../settings/ProUpgradePage';
import { WorkspaceService } from '../../services/WorkspaceService';
import { t } from '../../utils/i18n';
import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { PageData } from '../../core/models/Page';
import { bundleManager } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
// W7-U1.2：块属性面板（PropertyEditor）——本文件是它唯一的挂载点
import { PropertyEditor } from '../property/PropertyEditor';

@Component
export struct PageView {
  @StorageLink('callaite_currentPage') @Watch('onPageChanged') currentPage: string = 'Journal';
  /**
   * 分屏支持：副窗格通过 pageOverride 指定自己显示的路由，留空则跟随全局 currentPage。
   * 采用「覆盖式」而非「再造一份状态」，使主/副窗格复用同一套渲染与数据逻辑。
   */
  @Prop @Watch('onPageChanged') pageOverride: string = '';
  /**
   * S1-B：由 ContentArea 注入的 Block 列表滚动控制器，原样透传给 BlockList。
   *
   * 整页大纲页的滚动现在由 BlockList 内部的 List 承担（LazyForEach 虚拟化前提），
   * 上层若需要对该列表定位（U2.1a）必须拿到同一个 Scroller 实例，故在此透传。
   *
   * 不加 @Prop：Scroller 是稳定引用对象，无需参与状态观察；
   * 普通成员变量在父组件构造时同步赋值，build() 首次执行前已就绪。
   */
  blockScroller?: Scroller;
  @State displayName: string = '';
  /**
   * Properties 属性区折叠开关。
   * 默认展开（对齐 Obsidian：页面打开即看到属性表）；resolvePage 每次切页重置为展开，
   * 保证用户折叠后切页不会「看不到属性」。
   */
  @State showProperties: boolean = true;
  /** O4：整页四模式编辑器开关（页面切换时重置） */
  @State integralMode: boolean = false;
  @State pagePropKeys: string[] = [];
  @State pagePropValues: string[] = [];
  @State versionText: string = '';
  /**
   * W7-U1.2：块属性面板开关（页面级**常显**入口，标题下方操作行的「属性」药丸）。
   *
   * 落点理由（不按路线图挂 BlockView ActionsBar）：
   *  1) ActionsBar 的入口 dots 条件是 `isHovered || showActions`，而**触屏不产生
   *     onHover**（AGENTS §7 陷阱 11）⇒ 平板上整个 ActionsBar 不可达，挂上去等于没挂；
   *  2) 路线图原方案的 bindSheet 弹层在**独立子窗口**，uitest 注入不可达（陷阱 12），
   *     且 SheetType 只是偏好、可被系统改判（陷阱 6）；
   *  3) PropertyEditor 自带 `blockUuid === ''` 的「选择一个块以编辑属性」空态，
   *     说明它本就设计成**常驻面板 + 选中块驱动**，而非一次性的块内弹层。
   */
  @State showBlockProps: boolean = false;
  /**
   * 面板目标块：EditorService.setFocusedBlock() 写入的全局聚焦块。
   * 点击任意块行（BlockView 行 onClick 或内容区 onClick）都会更新它。
   */
  @StorageLink('callaite_focusedBlock') focusedBlockUuid: string = '';

  aboutToAppear(): void {
    this.resolvePage();
    // 从 bundle 读取真实版本号（不再硬编码）
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
      .then((info: bundleManager.BundleInfo) => {
        this.versionText = 'v' + info.versionName;
      })
      .catch(() => {
        this.versionText = '';
      });
  }

  /**
   * 显示标题：日志日期页（yyyy-MM-dd）显示本地化日期，其余显示页面名。
   * 注意：必须是普通方法 —— struct 上的 getter 会被 ArkTS 编译器静默丢弃。
   */
  getDisplayTitle(): string {
    if (/^\d{4}-\d{2}-\d{2}$/.test(this.displayName)) {
      return JournalService.formatJournalTitle(this.displayName);
    }
    return this.displayName;
  }

  /**
   * 响应式内容留白：窄屏（手机）20vp，宽屏（平板/2in1）48vp。
   * Logseq 桌面端内容区更宽，移动端更紧凑。
   */
  getContentPadding(): number {
    try {
      const d = display.getDefaultDisplaySync();
      if (d.width / d.densityPixels < 600) {
        return 20;
      }
    } catch (_e) {
      // 取不到显示信息时用窄屏值
    }
    return 48;
  }

  /**
   * currentPage 变更时重新解析页面名与属性。
   * 修复：此前仅在 aboutToAppear 调用 resolvePage，切换页面后标题/属性不刷新。
   */
  /**
   * 当前窗格实际渲染的路由。
   * 主窗格（pageOverride 为空）跟随全局 currentPage；副窗格使用自身覆盖值。
   */
  private page(): string {
    return this.pageOverride !== '' ? this.pageOverride : this.currentPage;
  }

  onPageChanged(): void {
    this.resolvePage();
  }

  resolvePage(): void {
    // 页面切换时退出整页编辑模式
    this.integralMode = false;
    // 页面切换时属性区回到默认展开态（避免上一页的折叠状态把新页属性藏起来）
    this.showProperties = true;
    if (this.page() === 'Journal') {
      JournalService.ensureTodayJournal();
      this.displayName = JournalService.getTodayDateString();
    } else {
      this.displayName = this.page();
    }
    this.loadProperties();
  }

  loadProperties(): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.displayName);
    const keys: string[] = [];
    const values: string[] = [];
    if (page) {
      page.properties.forEach((key: string, value: string) => {
        keys.push(key);
        values.push(value);
      });
    }
    this.pagePropKeys = keys;
    this.pagePropValues = values;
  }

  build() {
    if (this.page() === 'Settings') {
      SettingsPage()
    } else if (this.page() === 'Journal') {
      // 日志首页 = 时间流 feed（Logseq all-journals）
      JournalFeed()
    } else if (this.page() === 'Graph') {
      GraphView()
    } else if (this.page() === 'Whiteboards') {
      Whiteboard()
    } else if (this.page() === 'Flashcards') {
      FlashcardPage()
    } else if (this.page() === 'Pdf') {
      PdfPage()
    } else if (this.page() === 'ProUpgrade') {
      ProUpgradePage()
    } else if (this.page() === 'Home') {
      HomePage()
    } else if (this.page() === 'AllPages') {
      this.AllPagesView()
    } else if (this.page() === 'Recycle') {
      this.RecycleView()
    } else if (this.page() === 'About') {
      this.AboutView()
    } else {
      // 外层容器：内容列限宽 960vp 并水平居中（--ls-main-content-max-width）
      // W7-U1.2：外层 Column → Stack —— 在其上叠一块**非模态**块属性面板。
      // 「非模态」是刻意的：面板要求「边看面板边点选块切换目标」，
      // 加全屏遮罩会把正文块行全部挡死（点不到块 = 面板永远只能编辑同一个块）。
      Stack({ alignContent: Alignment.Center }) {
        Column({ space: 0 }) {
        // 页面标题（Logseq 风格: 大号粗体；日志日期页显示本地化日期）
        Text(this.getDisplayTitle())
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
          .width('100%')
          .padding({ top: 20, bottom: 8 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // ─── Properties 属性区（对齐 Obsidian：文件顶部即渲染属性表）───
        // 数据源复用 loadProperties() 填充的 pagePropKeys/pagePropValues（同源同序，未新造数据通路）。
        // 空属性时整块不渲染；仅展示，不做行内编辑。
        if (this.pagePropKeys.length > 0) {
          this.PropertiesSection()
        }

        // ─── 编辑模式切换（O4：整页四模式编辑器）───
        Row({ space: 8 }) {
          Row({ space: 6 }) {
            TablerIcon(this.integralMode ? 'list' : 'edit', 14,
              this.integralMode ? $r('app.color.primary') : $r('app.color.muted_text'))
            Text(this.integralMode ? '返回大纲视图' : '整页编辑')
              .fontSize(11)
              .fontColor(this.integralMode ? $r('app.color.primary') : $r('app.color.muted_text'))
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(4)
          .backgroundColor($r('app.color.surface2'))
          .onClick(() => { this.integralMode = !this.integralMode; })

          // W7-U1.2：块属性面板入口 —— **常显**（不挂 onHover：触屏无 hover ⇒ 只挂 hover 的入口等于不存在）
          Row({ space: 6 }) {
            TablerIcon('adjustments', 14,
              this.showBlockProps ? $r('app.color.primary') : $r('app.color.muted_text'))
            Text('属性')
              .fontSize(11)
              .fontColor(this.showBlockProps ? $r('app.color.primary') : $r('app.color.muted_text'))
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(4)
          .backgroundColor($r('app.color.surface2'))
          .onClick(() => { this.showBlockProps = !this.showBlockProps; })
          Blank()
        }
        .width('100%')
        .padding({ top: 2, bottom: 2 })

        if (this.integralMode) {
          IntegralEditor({ pageName: this.page(), onClose: (): void => {
            this.integralMode = false;
          }})
        } else {
        // Block 列表
        // ─── S1-B：原内层 Scroll 已移除 ───
        // 迁移前：外层 ContentArea.Scroll > PageView.Scroll > BlockList(LazyForEach in Column)。
        // 这个内层 Scroll 既让外层 Scroll 高度不受约束，又使 LazyForEach 的最近滚动祖先
        // 与真正的滚动承担者错位；现在 BlockList 内部自带 List 作为唯一滚动容器，
        // 再套一层 Scroll 只会重新引入双层滚动冲突，故直接移除。
        //
        // layoutWeight(1) 取代原 Scroll.layoutWeight(1)：BlockList 自身 height('100%')，
        // 由本容器给出确定高度，其内部 List 才有确定视口（虚拟化计算视口的前提）。
        Column() {
          BlockList({ pageName: this.displayName, scroller: this.blockScroller })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Blank()
        }
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: 960 })
      .alignItems(HorizontalAlign.Start)

        // ─── W7-U1.2 块属性面板（非模态浮层；面板外的区域仍可点选块）───
        if (this.showBlockProps) {
          this.BlockPropsPanel()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.getContentPadding(), right: this.getContentPadding() })
    }
  }

  /**
   * W7-U1.2：面板目标块 uuid —— 三重校验，任一不成立一律回空串。
   *
   * 为什么必须校验：`PropertyEngine.setProperty` 对不存在的块是**静默 return**
   *（PropertyEngine.ets:92-95），若不校验就会出现「输入框能打字、磁盘无变化」的假成功。
   * 回空串则 PropertyEditor 走它自带的「选择一个块以编辑属性」空态，不会给出假象。
   *
   * 三重校验：① 有聚焦块；② 该 uuid 在 BlockTree 里真实存在；③ 它属于**当前页**
   *（聚焦块是全局键，切页后可能仍指向上一个页面的块）。
   */
  private resolvedBlockUuid(): string {
    const uuid = this.focusedBlockUuid;
    if (uuid === '') {
      return '';
    }
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(uuid);
    if (block === undefined) {
      return '';
    }
    const page = ws.getPageByName(this.displayName);
    if (page === undefined || block.pageId !== page.uuid) {
      return '';
    }
    return uuid;
  }

  /** 面板副标题：当前目标块的内容预览（未选中时给出可操作提示） */
  private blockPropsHint(): string {
    const uuid = this.resolvedBlockUuid();
    if (uuid === '') {
      return '未选中块 —— 点选正文中任意块行即可编辑其属性';
    }
    const block = WorkspaceService.getInstance().getBlock(uuid);
    if (block === undefined) {
      return '未选中块 —— 点选正文中任意块行即可编辑其属性';
    }
    const text = block.content.trim();
    if (text === '') {
      return '（空块）';
    }
    if (text.length > 32) {
      return text.substring(0, 32) + '…';
    }
    return text;
  }

  /**
   * W7-U1.2：块属性面板 —— 承载 PropertyEditor（此前全仓零挂载）。
   *
   * 观感：居中的浮层卡片，**无遮罩**（非模态，见 build 内注释）。
   * 不用 bindSheet / bindMenu：那类弹层在独立子窗口，设备注入不可达（陷阱 12）。
   */
  @Builder
  BlockPropsPanel() {
    Column({ space: 0 }) {
      // 标题栏：图标 + 标题 + 目标块预览 + 关闭
      Row({ space: 8 }) {
        TablerIcon('adjustments', 16, $r('app.color.primary'))
        Column({ space: 2 }) {
          Text('块属性')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text'))
          Text(this.blockPropsHint())
            .fontSize(11)
            .fontColor($r('app.color.muted_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row() {
          TablerIcon('x', 16, $r('app.color.muted_text'))
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .width(32)
        .height(32)
        .borderRadius(4)
        .onClick(() => { this.showBlockProps = false; })
      }
      .width('100%')
      .height(52)
      .padding({ left: 14, right: 8 })

      Divider().color($r('app.color.border'))

      // 属性编辑主体（PropertyEditor 自带空态与添加属性对话框）
      Column() {
        PropertyEditor({ blockUuid: this.resolvedBlockUuid() })
      }
      .width('100%')
      .layoutWeight(1)

      Divider().color($r('app.color.border'))
      Text('提示：面板打开时可直接点选正文里的其它块来切换目标')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
        .width('100%')
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    }
    .width('92%')
    .constraintSize({ maxWidth: 480 })
    .height('68%')
    .backgroundColor($r('app.color.surface1'))
    .borderRadius(12)
    .border({ width: 0.6, color: $r('app.color.border') })
    .shadow({ radius: 24, color: 'rgba(0,0,0,0.22)', offsetY: 8 })
    .clip(true)
  }

  /**
   * Properties 属性区 — 对齐 Obsidian 文件顶部属性表。
   *
   * 位置：页面标题行与正文块列表之间（日志页 / 普通页同一分支，两处同时生效）。
   * 数据：loadProperties() 写入的 pagePropKeys / pagePropValues（同源同序）。
   * 观感：标题行沿用 SectionHeader 风格（13vp 弱化色 + 底部分隔线）；
   *       每行属性名固定 120vp 弱化色、属性值 text 色，行高 28vp。
   *
   * 注：本区仅展示**页面属性**（page.properties，来自 frontmatter），不做行内编辑。
   *     块属性（BlockData.properties）的编辑入口是属性面板
   *     （components/property/PropertyEditor.ets）——W7-U1.2 起由本文件
   *     BlockPropsPanel() 真实挂载（此前该面板全仓零挂载，本注释描述的是一个不存在的入口）。
   */
  @Builder
  PropertiesSection() {
    Column({ space: 0 }) {
      // 标题行（可折叠，默认展开；空属性时由调用处整块跳过）
      Row({ space: 6 }) {
        Text(this.showProperties ? '−' : '+')
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
          .width(12)
        Text(t('properties'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.muted_text'))
          .layoutWeight(1)
        Text(this.pagePropKeys.length.toString())
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
          .opacity(0.7)
      }
      .width('100%')
      .height(28)
      .padding({ left: 4, right: 4 })
      .onClick(() => { this.showProperties = !this.showProperties; })

      Divider().color($r('app.color.border'))

      if (this.showProperties) {
        ForEach(this.pagePropKeys, (key: string, idx: number) => {
          Row({ space: 0 }) {
            Text(key)
              .fontSize(13)
              .fontColor($r('app.color.muted_text'))
              .width(120)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.pagePropValues[idx])
              .fontSize(13)
              .fontColor($r('app.color.text'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .height(28)
          .padding({ left: 4, right: 4 })
        }, (key: string) => key)
      }
    }
    .width('100%')
    .padding({ top: 4, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  QueryView() {
    Column({ space: 16 }) {
      Text('图谱 / 查询').fontSize(32).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        .width('100%').padding({ top: 24, bottom: 8 })
      Scroll() { QueryBuilder() }.width('100%').layoutWeight(1)
      Blank()
    }
    .width('100%').height('100%').padding({ left: 24, right: 24 }).alignItems(HorizontalAlign.Start)
  }

  /**
   * 所有页面视图 — 对应 logseq all_pages.cljs。
   * 修复：此前 LeftSidebar 点击"所有页面"会跳到不存在的 AllPages 页面。
   */
  /** W3：AllPages 列表排序方向（对齐 Obsidian 文件列表的可切换排序） */
  @State allPagesAsc: boolean = true;

  /** AllPages 列表数据：按名称排序（升/降由 allPagesAsc 控制） */
  private sortedPages(): PageData[] {
    const src = WorkspaceService.getInstance().getAllPages();
    const arr: PageData[] = [];
    for (let i = 0; i < src.length; i++) {
      arr.push(src[i]);
    }
    const asc = this.allPagesAsc;
    arr.sort((a: PageData, b: PageData): number => {
      const x = a.originalName.toLowerCase();
      const y = b.originalName.toLowerCase();
      if (x < y) { return asc ? -1 : 1; }
      if (x > y) { return asc ? 1 : -1; }
      return 0;
    });
    return arr;
  }

  /** 列表操作行按钮（28vp 热区） */
  @Builder
  ListAction(icon: string, onTap: () => void) {
    Row() {
      TablerIcon(icon, 15, $r('app.color.icon_color'))
    }
    .width(28)
    .height(28)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(6)
    .onClick(() => {
      onTap();
    })
  }
  @Builder
  AllPagesView() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Text(t('nav_all_pages'))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 20, bottom: 12 })

      // ─── W3：列表顶部操作行（对齐 Obsidian 文件列表的视图切换 + 操作行）───
      Row({ space: 4 }) {
        this.ListAction('file-plus', (): void => {
          AppStorage.setOrCreate('callaite_newFileDialogOpen', true);
        })
        this.ListAction('arrows-sort', (): void => {
          this.allPagesAsc = !this.allPagesAsc;
        })
        Blank()
        // 「名称 ↑」此前是纯 Text（不可点），而真正切换排序的按钮中心相距 906vp —— 
        // 用户看到指示却点不动。此处把指示本身做成可点热区（28vp 高，符合热区规范）。
        Row() {
          Text(this.allPagesAsc ? '名称 ↑' : '名称 ↓')
            .fontSize(11)
            .fontColor($r('app.color.muted_text'))
        }
        .height(28)
        .padding({ left: 6, right: 6 })
        .borderRadius(6)
        .onClick(() => {
          this.allPagesAsc = !this.allPagesAsc;
        })
        this.ListAction('search', (): void => {
          AppState.setSearchPanelOpen(true);
        })
      }
      .width('100%')
      .height(32)
      .padding({ left: 16, right: 16 })
      .border({ width: { bottom: 1 }, color: $r('app.color.border') })

      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.sortedPages(), (page: PageData) => {
            Row({ space: 12 }) {
              TablerIcon(page.journalDay !== '' ? 'calendar' : 'file', 16, $r('app.color.muted_text'))
              Column({ space: 2 }) {
                Text(page.originalName)
                  .fontSize(15)
                  .fontColor($r('app.color.text'))
                if (page.tags.length > 0) {
                  Text(page.tags.join(', '))
                    .fontSize(11)
                    .fontColor($r('app.color.muted_text'))
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text(new Date(page.updatedAt).toLocaleDateString())
                .fontSize(11)
                .fontColor($r('app.color.muted_text'))
            }
            .width('100%')
            // W2：行高 48 → 32vp（Obsidian 文件列表 24–28px；原 48vp 使一屏可见条目减半，
            // 实测行距 48vp、标题到首行 64.5vp）。改后 32vp 行高仍高于官方 40vp 热区下限的
            // 触达判定由整行 onClick 承担（行宽满宽，纵向 32vp 可接受）。
            .height(32)
            .padding({ left: 12, right: 12 })
            .borderRadius(6)
            .onClick(() => { AppState.setCurrentPage(page.originalName); })
          }, (page: PageData) => page.uuid)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 48, right: 48 })
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 回收站视图 — 对应 logseq recycle.cljs。
   */
  @Builder
  RecycleView() {
    Column({ space: 0 }) {
      Text(t('nav_recycle'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text'))
        .width('100%')
        .padding({ top: 20, bottom: 12 })

      Column({ space: 12 }) {
        TablerIcon('trash', 40, $r('app.color.muted_text'))
        Text('回收站暂无内容')
          .fontSize(14)
          .fontColor($r('app.color.muted_text'))
      }
      .width('100%')
      .padding({ top: 60 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 48, right: 48 })
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 关于视图 — 对应 logseq about 页面。
   */
  @Builder
  AboutView() {
    Column({ space: 16 }) {
      Text(t('nav_about'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text'))
        .width('100%')
        .padding({ top: 20, bottom: 12 })

      Column({ space: 8 }) {
        TablerIcon('bolt', 48, $r('app.color.primary'))
        Text(t('app_name'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
        if (this.versionText !== '') {
          Text(this.versionText)
            .fontSize(13)
            .fontColor($r('app.color.muted_text'))
        }
        Text(t('onboarding_desc'))
          .fontSize(13)
          .fontColor($r('app.color.muted_text'))
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ top: 40 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 48, right: 48 })
    .alignItems(HorizontalAlign.Start)
  }
}
