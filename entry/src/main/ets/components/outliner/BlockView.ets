import { BlockData } from '../../core/models/Block';
import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';
import { ContentRenderer, ContentSegment, SegmentType } from '../../utils/ContentRenderer';
import { MathRenderer } from '../extensions/MathRenderer';
import { MermaidRenderer } from '../extensions/MermaidRenderer';
import { CodeBlock } from '../extensions/CodeBlock';
import { WebEditor } from './WebEditor';
import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { InlineQueryBlock } from '../query/InlineQueryBlock';
import {
  registerBlockRow,
  invalidateBlockRow,
  unregisterBlockRow
} from './BlockDragLayer';
import { requestSlashMenu } from './BlockListSlashSlot';

interface EmbedItem {
  kind: string;   // 'block' | 'page'
  value: string;
}

/**
 * BlockView — 单个 Block 的渲染组件。
 *
 * 对应 Logseq components/block.cljs (block 视图层)。
 *
 * 职责：
 *  - 渲染 Block 内容（支持 16 种 segment 类型）
 *  - 处理折叠/展开（点击 bullet 或 chevron）
 *  - 处理点击进入编辑、引用跳转
 *  - 渲染 SCHEDULED/DEADLINE 日期标签
 *  - 渲染 Block 引用嵌入（((uuid))）
 *  - 悬停时显示操作按钮
 */
@Component
export struct BlockView {
  @Prop blockUuid: string = '';
  /**
   * 本行缩进层级（= 缩进引导线格数）。
   *
   * ⚠️ 这里**曾经是 `@Prop depth`**（由 BlockList/BlockChildren 传 `row.level`）。
   * 它在「结构性变更」后不刷新（W9 实测、W10 修复）：
   *   `BlockList.refreshBlocks()` → `dataSource.setBlocks()` → `onDataReloaded()`，
   *   而 LazyForEach 的 keyGenerator 是 `row.uuid`。缩进/反缩进只改 `level`/`parentId`，
   *   **不改 uuid** ⇒ 键未变 ⇒ LazyForEach 不为该 item 重跑 itemGenerator ⇒
   *   传参对象不再生成 ⇒ `@Prop depth` 收不到新值，引导线/层级留在旧值。
   *   （同一路径下**被删除的行会正确消失**，因为它的键消失了 ⇒ 可证刷新通道本身没坏，
   *     坏的只是「键未变的项」这一格。）
   *
   * 现改为行内自读：`refreshBlock()` 从 `blockData.level` 取（`BlockTree.moveBlock`
   * 连子孙一起搬 level，见 BlockTree.ets:324-329），并由下面的 blocksVersion @Watch
   * 驱动重算。这样「层级的唯一真相」回到块数据本身，而不是靠父组件传参。
   */
  @State depth: number = 0;
  @State isEditing: boolean = false;
  @State showActions: boolean = false;
  @State displaySegments: ContentSegment[] = [];
  @State isHovered: boolean = false;
  @State isCollapsed: boolean = false;
  @State hasChildrenFlag: boolean = false;
  // 修复：bulletColor 声明为 @State，使用主题资源
  @State bulletColor: ResourceColor = $r('app.color.muted_text');
  // 选中状态（多选支持）
  @State isSelected: boolean = false;
  // ─── U1.4 块多选接通 ───
  /**
   * 全局多选模式开关（AppStorage，由 BlockSelection 的常显入口「选择」或 Ctrl+点击开启）。
   *
   * 为什么必须是「模式」而不是直接给长按加语义：块级长按已被 S1-H 的拖拽抓取占用
   * （见下方 LongPressGesture，500ms → reportRowGrab），把长按改判为选中会直接
   * 破坏已验收的拖拽。模式开关把「选中」搬到一条与任何手势都不冲突的路径上：
   * 关闭时本组件的行为与接线前逐字节等价。
   */
  @StorageLink('callaite_selectionMode') selectionMode: boolean = false;
  /**
   * 选中态版本号。
   *
   * `EditorService.selectedUuids` 是普通私有数组，不参与 ArkTS 状态观察，故以本序号
   * 为 watch 源：任何一处改动选中集合后 `AppState.bumpSelectionVersion()`，
   * 各可见行据此重算 `isSelected`（只影响边框与底色，不触碰块数据）。
   */
  @StorageLink('callaite_selectionVersion') @Watch('onSelectionVersionChanged') selectionVersion: number = 0;
  /**
   * 数据版本号 —— 结构性变更（缩进/反缩进/删除/移动/折叠/属性）后的**行内自刷新**通道。
   *
   * ⚠️ 为什么 BlockView 必须自己监听（W10 修复，缺陷 2 的正面）：
   *   本组件由 `LazyForEach(this.dataSource, itemGenerator, keyGenerator)` 创建，
   *   键是 `row.uuid`。缩进/反缩进这类**只改结构位、不改 uuid** 的操作里，
   *   键未变 ⇒ LazyForEach 不会重跑 itemGenerator ⇒
   *   ① `@Prop`（如原 `depth`）拿不到新值；
   *   ② 行内派生状态（`hasChildrenFlag` 的折箭头等）也不会被重算 ——
   *      它们只在 `aboutToAppear`/`refreshBlock` 里算过。
   *   表现为「数据与磁盘都变了、画面逐字节不变，离开该页再回来才对」。
   *
   * 本监听把刷新责任从「父组件传参」下移到「行自读自己的块数据」：
   *   bump 只发生在**结构性**操作（`AppState.bumpBlocksVersion`），
   *   文本输入走 `update-block` → DirtyPageTracker，**不** bump ⇒
   *   不存在「每次按键重算所有可见行」的开销。
   */
  @StorageLink('callaite_blocksVersion') @Watch('onBlocksVersionChanged') private blocksVersion: number = 0;
  // 内联查询文本（{{query ...}} 或 #+BEGIN_QUERY）
  @State inlineQuery: string = '';
  // Markdown 表格原始行（按行保留，支持单元格编辑）
  @State tableLines: string[] = [];
  @State isTable: boolean = false;
  @State editingCellLine: number = -1;
  @State editingCellCol: number = -1;
  @State editingCellText: string = '';
  // 正文字号（设置页可切换 12-16pt，默认 15）
  @StorageLink('callaite_fontSize') contentFontSize: number = 15;
  // 全局焦点块：其他块获焦时本块自动退出编辑态（内容已由编辑器防抖保存）
  @StorageLink('callaite_focusedBlock') @Watch('onGlobalFocusChanged') focusedBlockUuid: string = '';
  // ─── U2.1a 块定位高亮 ───
  // highlightedBlockUuid 是「谁被定位」，highlightSeq 是「第几次定位」。
  // 之所以 watch 序号而不是 uuid：连续点击同一个块时 uuid 值不变，@Watch 不触发，
  // 用户会看不到第二次反馈。序号单调递增，每次都触发。
  @StorageLink('callaite_highlightedBlock') highlightedBlockUuid: string = '';
  @StorageLink('callaite_highlightSeq') @Watch('onHighlightRequested') highlightSeq: number = 0;
  /** 本块当前是否处于高亮闪烁中（驱动底色 + 左侧色条） */
  @State isAnchorHighlighted: boolean = false;
  /** 闪烁计时器 id，重置/离场时清理，避免旧回调把新一轮高亮误关 */
  private highlightTimer: number = -1;
  /**
   * S1-H：行级长按上报。
   *
   * 语义：本行被长按 500ms → 把 (本行 uuid, 按下点窗口坐标 vp) 交给拖拽层。
   * 这里**只上报**，不做命中计算、不改数据 —— 命中测试、三态判定、落库全部在
   * BlockDragLayer 单实例内完成（整页只挂 1 个，故不存在每行手势与 List 滚动竞争）。
   *
   * 缺省为空实现：嵌入式（日志流 feed）与其它复用场景不传该回调 → 长按不产生任何行为。
   */
  onRowGrab: (uuid: string, globalX: number, globalY: number) => void = () => {};
  /**
   * U2.3：宿主 BlockList 的 Slash 入口注册键（行内 `/` 命令按钮按它路由到宿主）。
   *
   * 为什么用「注册键 + 模块级注册表」而不是回调 @Prop：
   *   本行会被 LazyForEach 复用，且结构性变更（缩进等）**不重跑 itemGenerator**
   *   ⇒ 传参型 @Prop 可能停在旧值上（AGENTS §7 陷阱 15）。注册键是个恒定字符串，
   *   陈旧与否都不影响正确性；真正的路由在 `requestSlashMenu` 里按当前注册表查。
   *   缺省 '' ⇒ 按钮不渲染（嵌入式等未接线的宿主行为与接线前等价）。
   */
  @Prop slashMenuListId: string = '';
  private blockData: BlockData | undefined;

  aboutToAppear(): void {
    this.refreshBlock();
    // S1-H：先作废本 uuid 的旧行矩形（组件被 LazyForEach 复用时几何会立刻变化，
    // 作废可保证「旧几何绝不参与命中」），真正的矩形由 onAreaChange 回填。
    invalidateBlockRow(this.blockUuid);
    // U2.1a：本块可能是「滚到目标行时才被 LazyForEach 创建」的。@Watch 只在值**变化**时
    // 触发，创建晚于高亮写入的实例不会收到回调，故此处按当前值补一次自检。
    this.applyAnchorHighlightIfTarget();
  }

  aboutToDisappear(): void {
    // 组件被 LazyForEach 回收时清掉计时器，避免回调打到已销毁的实例上
    if (this.highlightTimer !== -1) {
      clearTimeout(this.highlightTimer);
      this.highlightTimer = -1;
    }
    // S1-H：行被回收 → 从命中表反注册。这是「幽灵行」的第一道防线
    // （块 uuid 消失后若无记录清理，命中测试可能落到一个已不存在的行矩形上）。
    unregisterBlockRow(this.blockUuid);
  }

  /**
   * U2.1a：收到「定位到此块」的请求 → 闪烁高亮。
   *
   * 为什么用 animateTo 而不是 .animation()：
   * .animation() 是「属性变化的隐式动画」，需要在同一次属性赋值里带 duration；
   * 而这里要做的是「亮 → 保持 → 灭」的标准闪烁，animateTo 能把两次赋值各自包进
   * 独立动画，并且 onFinish 回调可以精确在熄灭动画结束后清理状态。
   *
   * 时序：亮起 260ms（立即，无淡入延迟感）→ 保持 520ms → 熄灭 420ms。
   */
  onHighlightRequested(): void {
    if (this.highlightedBlockUuid !== this.blockUuid) {
      // 被定位的不是本块：确保本块不残留高亮
      if (this.isAnchorHighlighted) {
        this.isAnchorHighlighted = false;
      }
      return;
    }
    this.startAnchorFlash();
  }

  /**
   * 仅当当前高亮目标就是本块时启动闪烁（供 aboutToAppear 补触发使用）。
   */
  private applyAnchorHighlightIfTarget(): void {
    if (this.highlightedBlockUuid === this.blockUuid && this.highlightedBlockUuid !== '') {
      this.startAnchorFlash();
    }
  }

  /**
   * 闪烁执行体：亮 → 保持 → 灭。重复触发时先取消上一轮计时器。
   *
   * 用 `this.getUIContext().animateTo()`（UIContext.d.ts:4703）而不是全局 `animateTo()`：
   * 全局版本已被标记 deprecated（编译告警 "'animateTo' has been deprecated"），
   * 而本组件是 CustomComponent，`getUIContext()`（common.d.ts:24715）可直接取到实例。
   */
  private startAnchorFlash(): void {
    if (this.highlightTimer !== -1) {
      clearTimeout(this.highlightTimer);
      this.highlightTimer = -1;
    }
    this.isAnchorHighlighted = true;
    this.highlightTimer = setTimeout(() => {
      this.highlightTimer = -1;
      const ui = this.getUIContext();
      ui.animateTo({ duration: 420, curve: Curve.EaseOut, onFinish: () => {
        this.isAnchorHighlighted = false;
      } }, () => {
        this.isAnchorHighlighted = false;
      });
    }, 520);
  }

  refreshBlock(): void {
    const ws = WorkspaceService.getInstance();
    this.blockData = ws.getBlock(this.blockUuid);
    // U1.4：一并同步选中态。必要性：LazyForEach 复用/新建行时本方法是唯一的入口
    // （aboutToAppear 与各类刷新都经过它），若此处不取，复用出来的行会带着上一行的
    // isSelected 残留；@Watch 只在版本号**变化**时触发，创建晚于 bump 的实例收不到回调。
    this.isSelected = EditorService.getInstance().isSelected(this.blockUuid);
    if (this.blockData) {
      // 层级从块数据现读（不再依赖父组件传参，见 depth 字段注释）
      this.depth = this.blockData.level;
      this.displaySegments = ContentRenderer.parse(this.blockData.content);
      this.isCollapsed = this.blockData.collapsed;
      this.hasChildrenFlag = ws.getChildrenOfBlock(this.blockUuid).length > 0;
      this.inlineQuery = BlockView.extractQuery(this.blockData.content);
      this.tableLines = BlockView.extractTableLines(this.blockData.content);
      this.isTable = this.tableLines.length >= 2;
    }
  }

  build() {
    if (!this.blockData) {
      Row().width('100%').height(0)
    } else {
      Column() {
        // 选中态边框包裹
        Column() {
          // ⚠️ 必须是 Flex + ItemAlign.Stretch，不能是 Row：
          //   引导线要「撑满本行高度」，而 Row 的高度又由子节点算出 —— 若引导线用
          //   height('100%')，百分比只能对着**父级约束上限**（List 视口）解析，形成
          //   「子节点撑高父节点、父节点再抬高子节点」的循环，结果整行被拉到视口高度
          //   （实测 depth=1 的行 h=691，depth=0 的行 h=36）。
          //   Flex 的 Stretch 语义下，未设交叉轴尺寸的子节点不参与容器高度计算、
          //   只在容器高度定下来后被拉伸，循环因此被打断。
          Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) {
            // 缩进引导线
            if (this.depth > 0) {
              ForEach(this.buildGuideArray(), (idx: number) => {
                // 引导线格：内层也用 Flex(Stretch) 而不是 height('100%')，全程无百分比高度
                Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) {
                  Column().width(1).backgroundColor($r('app.color.border')).margin({ left: 8 })
                  Blank().width(15)
                }.width(24)
              }, (idx: number) => idx.toString())
            }

            Row({ space: 8 }) {
              // ─── U1.4：多选模式下的行内选择圈（常显，不依赖 hover） ───
              // 触屏不产生 onHover（AGENTS §7 陷阱 11），故这里不做任何显隐条件判断：
              // 进入多选模式即出现，退出即消失。
              if (this.selectionMode) {
                this.SelectionToggle()
              }

              // Bullet + 折叠箭头
              this.BulletControl()

              // Marker（TODO/DOING/DONE）
              if (this.blockData.marker !== '') {
                Text(this.blockData.marker)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.getMarkerColor(this.blockData.marker))
                  .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                  .borderRadius(3)
                  .backgroundColor(this.getMarkerBg(this.blockData.marker))
                  .onClick(() => {
                    EditorService.getInstance().setFocusedBlock(this.blockUuid);
                    EditorService.getInstance().cycleMarker();
                    this.refreshBlock();
                  })
              }

              // 优先级标记
              if (this.blockData.priority !== '') {
                Text('[#' + this.blockData.priority + ']')
                  .fontSize(11)
                  .fontColor($r('app.color.warning'))
                  .fontWeight(FontWeight.Bold)
                  .margin({ right: 2 })
              }

              // 内容区域
              if (this.isEditing) {
                WebEditor({
                  blockUuid: this.blockUuid,
                  initialContent: this.blockData.content,
                  pageName: this.resolvePageName(),
                  fontSize: this.contentFontSize,
                  onSave: () => {
                    this.isEditing = false;
                    this.refreshBlock();
                  },
                  onAction: (_a: string, _d: string) => {
                    this.refreshBlock();
                  }
                }).layoutWeight(1)
              } else {
                Column() {
                  if (this.isTable) {
                    this.TableView()
                  } else if (BlockView.isPureQueryBlock(this.blockData.content)) {
                    InlineQueryBlock({ queryText: this.inlineQuery })
                  } else {
                    // 内容 segments
                    this.ContentSegments()
                    if (this.inlineQuery !== '') {
                      InlineQueryBlock({ queryText: this.inlineQuery })
                    }
                  }

                  // SCHEDULED / DEADLINE 日期标签
                  if (this.blockData !== undefined &&
                      (this.blockData.scheduled !== '' || this.blockData.deadline !== '')) {
                    this.DateLabels(this.blockData)
                  }
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }
            }.layoutWeight(1)

            // 悬停操作按钮
            if (this.isHovered || this.showActions) {
              Row() {
                TablerIcon('dots', 16, $r('app.color.muted_text'))
              }
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .width(20).height(20)
              .onClick(() => {
                this.showActions = !this.showActions;
              })
            }
          }.width('100%').padding({ top: 4, bottom: 4 })
          .onHover((isHover: boolean) => {
            this.isHovered = isHover;
            this.bulletColor = isHover ? $r('app.color.primary') : $r('app.color.muted_text');
          })
          // S1-H：行矩形登记。onAreaChange 给出的 position/globalPosition/height
          // 单位均为 vp（SDK Area：width/height/position/globalPosition 全部 vp），
          // globalPosition 即窗口坐标系 —— 与手指的 FingerInfo.globalY / TouchObject.windowY
          // 同一坐标系，拖拽层可直接相减得到列表局部坐标。
          // 每次布局变化（滚动、展开、LazyForEach 复用）都会重新触发，因此命中表始终是最新几何。
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            registerBlockRow(
              this.blockUuid,
              BlockView.areaVp(newArea.globalPosition.y),
              BlockView.areaVp(newArea.height),
              this.depth
            );
          })
          // S1-H：长按激活拖拽。
          // 这里只挂**长按**（不挂 Pan）—— 长按 500ms 内手指不动，List 的滚动识别器
          // 因不满足距离条件而判负，故不与 S1-B 的 List 纵向滚动竞争；
          // 真正的位移跟踪由拖拽层单实例的 onTouch 承担。
          .gesture(
            LongPressGesture({ fingers: 1, repeat: false, duration: 500 })
              .onAction((event: GestureEvent) => {
                this.reportRowGrab(event);
              })
          )
          .onClick((event: ClickEvent) => {
            // U1.4：Ctrl+点击（桌面）＝进入多选并切换本行选中，与 Logseq/Obsidian 一致。
            // 触屏等价入口是行内选择圈（SelectionToggle），不依赖任何按键 ——
            // 本窗口的验收入口因此不走 Ctrl 路径（uitest 的按键注入不达 ArkUI 按键管线）。
            if (BlockView.ctrlPressed(event)) {
              this.selectViaCtrl();
              return;
            }
            // 多选模式下点击行内容不再改焦点：焦点留在编辑器会让
            // WebEditor / 快捷键的语义与「正在多选」互相干扰。
            if (this.selectionMode) {
              return;
            }
            if (!this.isEditing) {
              EditorService.getInstance().setFocusedBlock(this.blockUuid);
            }
          })
          .backgroundColor(this.anchorRowBg())
          .borderRadius(4)
          .border({
            width: { left: this.isAnchorHighlighted ? 3 : 0 },
            color: $r('app.color.primary')
          })

          // 展开的操作栏
          if (this.showActions) {
            this.ActionsBar()
          }

          // Block 引用嵌入渲染
          if (this.hasEmbedSegments()) {
            this.EmbedBlocks()
          }
        }
        .width('100%')
        // U1.4 选中态视觉：2vp 主题色描边 + 一层弱底色（两层通道同时表达，
        // 单靠描边在浅色页面上不够醒目；底色取 surface2，与 hover/锚点高亮同一档）。
        .backgroundColor(this.isSelected ? $r('app.color.surface2') : Color.Transparent)
        .border(this.isSelected ? { width: 2, color: $r('app.color.primary') } : { width: 0, color: Color.Transparent })
        .borderRadius(4)
      }.width('100%').padding({ left: 16, right: 16 })
    }
  }

  // ─── Bullet + 折叠控制 ───

  /**
   * U2.1a 高亮行底色。
   * ArkTS 结构性限制：不能内联嵌套三元（风格表里「嵌套三元 > 2 层」被禁），
   * 且 @Builder 不能返回值，故底色计算独立成显式类型的命名方法。
   */
  private anchorRowBg(): ResourceColor {
    if (this.isAnchorHighlighted) {
      return $r('app.color.surface2');
    }
    if (this.isHovered) {
      return $r('app.color.surface2');
    }
    return Color.Transparent;
  }

  /**
   * U1.4：行内选择圈（仅多选模式渲染）。
   *
   * 为什么用「圈」而不是复用 bullet：bullet 的点击已绑定「折叠/展开子块」与「进入编辑」
   * 两个语义（见 BulletControl），再叠一层选中语义会让同一个 16vp 圆点承担三义；
   * 且 bullet 没有形状状态可表达选中与否。选择圈是独立节点，语义与视觉都单一。
   *
   * 尺寸 24vp（= 48px @ density 2）—— 不依赖 hover、不需要长按，触屏可直接点中；
   * 并挂 `id` 供 uitest dumpLayout 精确定位（本窗口的验收坐标即由此而来）。
   */
  @Builder
  SelectionToggle() {
    Row() {
      if (this.isSelected) {
        TablerIcon('check', 14, $r('app.color.surface0'))
      }
    }
    .width(24).height(24)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(12)
    .backgroundColor(this.isSelected ? $r('app.color.primary') : Color.Transparent)
    .border({ width: this.isSelected ? 0 : 1.5, color: $r('app.color.muted_text') })
    .id('callaite_selectionToggle_' + this.blockUuid)
    .onClick(() => {
      this.toggleRowSelection();
    })
  }

  @Builder
  BulletControl() {
    Row({ space: 2 }) {
      // 折叠箭头（有子 Block 时显示，Logseq block-control：半透明 + 展开时旋转 90°）
      if (this.hasChildrenFlag) {
        Row() {
          TablerIcon('chevron-right', 10, $r('app.color.muted_text'))
        }
        .width(14).height(14)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .opacity(0.4)
        .rotate({ angle: this.isCollapsed ? 0 : 90 })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => {
          this.toggleCollapse();
        })
      }

      // Bullet 圆点（Logseq bullet-container：hover 显示圆环 + 圆点放大）
      Row() {
        Circle({ width: this.isHovered ? 7 : 6, height: this.isHovered ? 7 : 6 })
          .fill(this.bulletColor)
      }
      .width(16).height(16)
      .justifyContent(FlexAlign.Center)
      .borderRadius(8)
      .border({ width: 1, color: this.isHovered ? this.bulletColor : Color.Transparent })
      .margin({ top: 3 })
      .animation({ duration: 150, curve: Curve.EaseOut })
      .onClick(() => {
        // 有子 Block 时点击 bullet 切换折叠
        if (this.hasChildrenFlag) {
          this.toggleCollapse();
        } else {
          this.enterEdit();
        }
      })

      // U2.3：行内 Slash 命令入口
      this.SlashEntryButton()
    }
  }

  /**
   * U2.3：行内 Slash 命令入口（`/`）。
   *
   * 为什么放在 bullet 组内、且**常显**：
   *   · 常显是硬约束 —— 触屏不产生 onHover（AGENTS §7 陷阱 11），
   *     而本仓原本唯一的「操作入口」是 hover 才出现的 `dots` 按钮 ⇒ 平板上点不到；
   *   · 放在 bullet 之后（而不是行尾）：行尾会随内容长度漂移，且会把正文挤窄；
   *     bullet 组是定宽的固定锚点，位置稳定、每行一致、能精确定位（验收要靠坐标）。
   *   · 命中区 22×22vp（= 44×44px @ density 2）—— 高于 24vp 的可点下限，
   *     与 bullet 自身 16vp 的命中区不重叠（`Row({space:2})` 已留 2vp 间隔）。
   *
   * 目标块 = 本行（`this.blockUuid`）—— 这正是 SlashMenu 里 cyclePriority 等
   * 块级命令需要的语义：操作对象是「点了按钮的那一行」，不是「编辑器焦点在哪」。
   */
  @Builder
  SlashEntryButton() {
    if (this.slashMenuListId !== '') {
      Row() {
        TablerIcon('command', 13, $r('app.color.muted_text'))
      }
      .width(22).height(22)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .borderRadius(4)
      .margin({ top: 2 })
      .id('callaite_slashEntry_' + this.blockUuid)
      .onClick(() => {
        // 只上报，不自己开菜单：开合态与菜单挂载点都在宿主 BlockList
        // （见 BlockListSlashSlot 的模块注释）。
        requestSlashMenu(this.slashMenuListId, this.blockUuid);
      })
    }
  }

  toggleCollapse(): void {
    const ws = WorkspaceService.getInstance();
    ws.executeOp({
      type: 'collapse',
      uuid: this.blockUuid,
      collapsed: !this.isCollapsed
    });
    this.refreshBlock();
    // 触发父组件刷新（通过 AppState 全局版本号）
    AppState.bumpBlocksVersion();
  }

  // ─── 内容 Segments 渲染 ───

  @Builder
  ContentSegments() {
    Row({ space: 0 }) {
      if (this.displaySegments.length === 0) {
        Text(' ')
          .fontSize(this.contentFontSize)
          .fontColor($r('app.color.muted_text'))
          .height(28)
      } else {
        ForEach(this.displaySegments, (seg: ContentSegment, idx: number) => {
          this.RenderSegment(seg, idx)
        }, (seg: ContentSegment, idx: number) => idx.toString())
      }
    }
    .width('100%')
    // 整行可点击进入编辑（此前仅 Text 本体响应，空块的 Text(' ') 只有几像素宽，
    // 点击行内空白处无法进入编辑 —— 表现为"编辑器点了没反应"）。
    // 带自身 onClick 的 segment（[[链接]]/#标签 等）优先消费事件，不触发编辑。
    .onClick((event: ClickEvent) => {
      // U1.4：Ctrl+点击的**选中**由行容器统一处理（ArkUI 点击事件默认向上冒泡，
      // 见 SDK common.d.ts:18621 与「事件冒泡」文档）。这里只让位，不自行切换选中 ——
      // 若两处都切换，一次 Ctrl+点击会被切换两次，净效果变成「没选中」。
      if (BlockView.ctrlPressed(event)) {
        return;
      }
      this.enterEdit();
    })
  }

  @Builder
  RenderSegment(seg: ContentSegment, idx: number) {
    if (seg.type === SegmentType.IMAGE) {
      Image(seg.text)
        .width(120).height(80)
        .objectFit(ImageFit.Cover)
        .borderRadius(4)
    } else if (seg.type === SegmentType.MATH_BLOCK) {
      MathRenderer({ formula: seg.text, displayMode: true })
    } else if (seg.type === SegmentType.MATH_INLINE) {
      MathRenderer({ formula: seg.text, displayMode: false })
    } else if (seg.type === SegmentType.MERMAID) {
      MermaidRenderer({ diagram: seg.text })
    } else if (seg.type === SegmentType.BLOCKQUOTE) {
      // ⚠️ 与缩进引导线同一个坑：左侧引用条不能写 height('100%')。
      //    它的父级 Row 高度由内容决定，百分比只能对着父级**约束上限**（List 视口）解析，
      //    形成「子节点撑高父节点 → 父节点再抬高子节点」的循环 —— 实测该行被拉到 ~400vp，
      //    页面表现为「引用块下方一大片空白」。改用 Flex(Stretch)，全程无百分比高度。
      Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) {
        Column().width(3).backgroundColor($r('app.color.border')).margin({ right: 8 })
        Text(seg.text).fontSize(14).fontColor($r('app.color.muted_text')).fontStyle(FontStyle.Italic).layoutWeight(1)
      }.width('100%').padding({ left: 4, top: 2, bottom: 2 })
    } else if (seg.type === SegmentType.PAGE_REF || seg.type === SegmentType.PAGE_EMBED) {
      Text('[[' + seg.text + ']]')
        .fontSize(this.contentFontSize)
        .fontColor($r('app.color.link'))
        .height(28)
        .onClick(() => {
          AppState.setCurrentPage(seg.text);
        })
    } else if (seg.type === SegmentType.BLOCK_REF) {
      Text('((' + seg.text.substring(0, 8) + '))')
        .fontSize(this.contentFontSize)
        .fontColor($r('app.color.primary'))
        .height(28)
        .onClick(() => {
          // 跳转到 Block 所在页面
          const ws = WorkspaceService.getInstance();
          const block = ws.getBlock(seg.text);
          if (block) {
            const pageUuid = ws.getPageUuidForBlock(seg.text);
            if (pageUuid) {
              const page = ws.getDataStore().getPage(pageUuid);
              if (page) {
                AppState.setCurrentPage(page.originalName);
              }
            }
          }
        })
    } else if (seg.type === SegmentType.CODE && seg.extra !== undefined) {
      // U3.5 接线：**整块围栏代码块**（ContentRenderer 只在 ```...``` 整段场景下写 extra）
      // → 交给 CodeBlock 做 highlight.js 高亮（离线 rawfile 承载页）。
      // 红线：行内 `code` 段不带 extra，仍走下方 Text 分支，普通块零改动。
      CodeBlock({ code: seg.text, language: seg.extra })
    } else if (seg.type === SegmentType.TAG_REF) {
      Text('#' + seg.text)
        .fontSize(this.contentFontSize)
        .fontColor($r('app.color.success'))
        .height(28)
        .onClick(() => {
          AppState.setCurrentPage(seg.text);
        })
    } else if (seg.type === SegmentType.LINK) {
      Text(seg.extra !== undefined && seg.extra !== '' ? seg.extra : seg.text)
        .fontSize(this.contentFontSize)
        .fontColor($r('app.color.link'))
        .decoration({ type: TextDecorationType.Underline, color: $r('app.color.link') })
        .height(28)
        .onClick(() => {
          ContentRenderer.handleClick(SegmentType.LINK, seg.text);
        })
    } else {
      Text(seg.text)
        .fontSize(this.contentFontSize)
        .fontColor(ContentRenderer.getSegmentColor(seg.type))
        .fontWeight(seg.type === SegmentType.BOLD ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(seg.type === SegmentType.ITALIC ? FontStyle.Italic : FontStyle.Normal)
        .decoration({
          type: seg.type === SegmentType.STRIKETHROUGH ? TextDecorationType.LineThrough : TextDecorationType.None,
          color: $r('app.color.muted_text')
        })
        .backgroundColor(seg.type === SegmentType.HIGHLIGHT ? $r('app.color.highlight') : Color.Transparent)
        .fontFamily(seg.type === SegmentType.CODE ? 'monospace' : '')
        .height(28)
        .onClick(() => {
          if (ContentRenderer.isClickable(seg.type)) {
            ContentRenderer.handleClick(seg.type, seg.text);
          } else {
            this.enterEdit();
          }
        })
    }
  }

  // ─── SCHEDULED / DEADLINE 日期标签 ───

  @Builder
  DateLabels(data: BlockData) {
    Row({ space: 8 }) {
      if (data.scheduled !== '') {
        Row({ space: 4 }) {
          TablerIcon('calendar-event', 16, $r('app.color.primary'))
          Text('SCHEDULED: ' + data.scheduled)
            .fontSize(11)
            .fontColor($r('app.color.primary'))
        }
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(3)
        .backgroundColor($r('app.color.surface2'))
      }
      if (data.deadline !== '') {
        Row({ space: 4 }) {
          TablerIcon('alarm', 16, $r('app.color.error'))
          Text('DEADLINE: ' + data.deadline)
            .fontSize(11)
            .fontColor($r('app.color.error'))
        }
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(3)
        .backgroundColor($r('app.color.surface2'))
      }
    }
    .width('100%')
    .padding({ top: 2, left: 2 })
  }

  // ─── 操作栏 ───

  @Builder
  ActionsBar() {
    Row({ space: 4 }) {
      // 缩进
      Button() { TablerIcon('indent-increase', 18, $r('app.color.text')) }
        .width(36).height(36).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          EditorService.getInstance().indentBlock();
          this.refreshBlock();
          this.showActions = false;
          AppState.bumpBlocksVersion();
        })
      // 反缩进
      Button() { TablerIcon('indent-decrease', 18, $r('app.color.text')) }
        .width(36).height(36).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          EditorService.getInstance().outdentBlock();
          this.refreshBlock();
          this.showActions = false;
          AppState.bumpBlocksVersion();
        })
      // 上移
      Button() { TablerIcon('arrow-up', 18, $r('app.color.text')) }
        .width(36).height(36).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          EditorService.getInstance().moveBlockUp();
          this.refreshBlock();
          this.showActions = false;
          AppState.bumpBlocksVersion();
        })
      // 下移
      Button() { TablerIcon('arrow-down', 18, $r('app.color.text')) }
        .width(36).height(36).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          EditorService.getInstance().moveBlockDown();
          this.refreshBlock();
          this.showActions = false;
          AppState.bumpBlocksVersion();
        })
      // 折叠/展开
      if (this.hasChildrenFlag) {
        Button() {
          TablerIcon(this.isCollapsed ? 'chevron-down' : 'chevron-up', 18, $r('app.color.text'))
        }
        .width(36).height(36).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          this.toggleCollapse();
          this.showActions = false;
        })
      }
      // 删除
      Button() { TablerIcon('trash', 18, $r('app.color.error')) }
        .width(36).height(36).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          WorkspaceService.getInstance().executeOp({ type: 'delete-block', uuid: this.blockUuid });
          this.refreshBlock();
          this.showActions = false;
          AppState.bumpBlocksVersion();
        })
    }.width('100%').padding({ left: 24, right: 8, bottom: 4 })
  }

  // ─── 引用 / 嵌入渲染 ───

  @Builder
  EmbedBlocks() {
    Column({ space: 4 }) {
      ForEach(this.getEmbedItems(), (item: EmbedItem) => {
        this.EmbedItemView(item)
      }, (item: EmbedItem) => item.kind + ':' + item.value)
    }.width('100%')
  }

  @Builder
  EmbedItemView(item: EmbedItem) {
    Column({ space: 2 }) {
      if (item.kind === 'page') {
        Text('![[' + item.value + ']]')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.link'))
          .width('100%')
        ForEach(this.getPageEmbedLines(item.value), (line: string, idx: number) => {
          Text(line)
            .fontSize(12)
            .fontColor($r('app.color.muted_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }, (line: string, idx: number) => idx.toString())
      } else {
        Text(this.getBlockContent(item.value))
          .fontSize(13)
          .fontColor($r('app.color.muted_text'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface2'))
    .borderRadius(4)
    .border({ width: { left: 2 }, color: $r('app.color.primary') })
    .padding({ left: 12, right: 8, top: 6, bottom: 6 })
  }

  @Builder
  TableView() {
    Column() {
      ForEach(this.tableLines, (line: string, li: number) => {
        if (!BlockView.isSeparatorRow(BlockView.splitTableRow(line))) {
          Row() {
            ForEach(BlockView.splitTableRow(line), (cell: string, ci: number) => {
              if (this.editingCellLine === li && this.editingCellCol === ci) {
                TextInput({ text: this.editingCellText })
                  .fontSize(12)
                  .fontColor($r('app.color.text'))
                  .layoutWeight(1)
                  .height(32)
                  .padding({ left: 4, right: 4 })
                  .backgroundColor($r('app.color.surface0'))
                  .onChange((v: string) => { this.editingCellText = v; })
                  .onSubmit(() => { this.commitCellEdit(); })
              } else {
                Text(cell)
                  .fontSize(12)
                  .fontColor($r('app.color.text'))
                  .fontWeight(li === 0 ? FontWeight.Medium : FontWeight.Normal)
                  .layoutWeight(1)
                  .padding({ left: 6, right: 6, top: 5, bottom: 5 })
                  .backgroundColor(li === 0 ? $r('app.color.surface2') : Color.Transparent)
                  .border({ width: { right: 1, bottom: 1 }, color: $r('app.color.border') })
                  .onClick(() => { this.startCellEdit(li, ci, cell); })
              }
            }, (cell: string, ci: number) => li.toString() + '-' + ci.toString())
          }
          .width('100%')
        }
      }, (line: string, li: number) => li.toString())
    }
    .width('100%')
    .border({ width: 1, color: $r('app.color.border') })
    .borderRadius(4)
    .padding({ top: 4, bottom: 4 })
  }

  // ─── 辅助方法 ───

  enterEdit(): void {
    // U1.4：多选模式下点击行内容**不再进入编辑**。
    // 理由：进入编辑态后整行被 WebEditor 覆盖（BlockView build 的 isEditing 分支），
    // 选择圈随之消失，用户无法继续多选；且编辑器持焦会与「正在多选」的语义互相干扰。
    // 这里只做「让位」，选中动作本身由 SelectionToggle 承担（单一写入口，避免
    // 点击冒泡到行容器时同一行被切换两次 → 净效果为无变化）。
    if (this.selectionMode) {
      return;
    }
    EditorService.getInstance().setFocusedBlock(this.blockUuid);
    this.isEditing = true;
  }

  // ─── U1.4 块多选 ───

  /**
   * 数据版本号变化 → 本行重读自己的块数据（缺陷 2 的修复入口）。
   *
   * 与「把结构位并入 keyGenerator」的候选修法相比，本方案**不改变行的身份**
   * （LazyForEach 的键仍是 `row.uuid`），因此：
   *   · 行内局部状态（`isEditing` 编辑态、`showActions` 展开的操作栏、`isHovered`、
   *     表格单元格编辑态 `editingCellLine/Col/Text`）**保持存活**，不会被结构变更打断；
   *   · `BlockDragLayer` 的命中表是按 **BlockView 实例**注册/反注册的
   *     （aboutToAppear→register、aboutToDisappear→unregister、onAreaChange→回填矩形），
   *     实例不重建 ⇒ 命中表不会在结构变更时被成批清空重建，S1-H 拖拽风险面最小。
   * 代价：结构变更时对**可见行**各跑一次 `refreshBlock()`（含 ContentRenderer.parse）。
   * 该开销只发生在结构性操作上（文本输入不 bump，见字段注释），可接受。
   */
  onBlocksVersionChanged(): void {
    this.refreshBlock();
  }

  /**
   * 选中态版本号变化 → 重算本行选中态。
   * 与 refreshBlock 的分工：本方法**不重读块内容**（选中不改数据），只重算 isSelected，
   * 避免每次点选都触发一遍 ContentRenderer.parse 等重活。
   */
  onSelectionVersionChanged(): void {
    this.isSelected = EditorService.getInstance().isSelected(this.blockUuid);
  }

  /**
   * 切换本行的选中态 —— 本组件内选中集合的**唯一写入口**。
   *
   * 写完立即 bump selectionVersion：本行的 isSelected 已就地更新，bump 是为了让
   * 其它行（LazyForEach 中已创建但未参与本次点击的实例）同步 —— 例如「全选」之后
   * 可见行都要亮起描边。
   */
  toggleRowSelection(): void {
    const editor = EditorService.getInstance();
    editor.toggleSelection(this.blockUuid);
    this.isSelected = editor.isSelected(this.blockUuid);
    AppState.bumpSelectionVersion();
  }

  /**
   * Ctrl+点击（桌面路径）：未进入多选模式则先进入，再切换本行。
   *
   * ⚠️ 这只是**桌面便利路径**，不是本窗口的验收入口：uitest 注入的按键不达 ArkUI
   * 按键管线（AGENTS §3），因而 Ctrl 路径在本机无法自证。触屏等价入口是行内选择圈
   * （SelectionToggle）与底部常显的「选择」按钮，二者都不经过任何按键。
   */
  private selectViaCtrl(): void {
    if (!AppState.isSelectionMode()) {
      AppState.setSelectionMode(true);
    }
    this.toggleRowSelection();
  }

  /**
   * 读取点击事件的 Ctrl 修饰键状态。
   * `getModifierKeyState` 在 BaseEvent 上是可选方法（common.d.ts:8166），
   * 取不到时按「未按下」处理，绝不因此改变普通点击的既有行为。
   */
  private static ctrlPressed(event: ClickEvent): boolean {
    try {
      return event.getModifierKeyState!(['ctrl']);
    } catch (e) {
      return false;
    }
  }

  /**
   * S1-H：把 Area 的 Length（string | number | Resource）取成 vp 数值。
   * 布局回调中 position/height 实际都是 number（vp），但类型仍是 Length 联合体，
   * ArkTS 禁用 any，故必须显式收窄；取不到数值时返回 0（= 未完成布局，不参与命中）。
   */
  static areaVp(value: Length | undefined): number {
    if (value === undefined) {
      return 0;
    }
    if (typeof value === 'number') {
      return value;
    }
    return 0;
  }

  /**
   * S1-H：长按上报 —— 只把「哪一行 + 手指在窗口坐标系的落点」交给拖拽层。
   *
   * 为什么必须带坐标：拖拽层是**整页唯一**的覆盖层，它需要知道长按落在哪一行；
   * 若在此处自行判定目标，就会与拖拽层的命中逻辑形成第二份实现（本项目的既有教训）。
   * 手指不可用（fingerList 为空，如键鼠触发）时按不可用（-1）上报，拖拽层据此放弃本次拖拽。
   */
  private reportRowGrab(event: GestureEvent): void {
    const fingers = event.fingerList;
    if (fingers === undefined || fingers.length === 0) {
      this.onRowGrab(this.blockUuid, -1, -1);
      return;
    }
    this.onRowGrab(this.blockUuid, fingers[0].globalX, fingers[0].globalY);
  }

  /**
   * 全局焦点变化回调：焦点落到别的块（或被清除）时退出本块编辑态。
   * 内容安全：WebEditor 已在 input 事件中 400ms 防抖自动保存。
   */
  onGlobalFocusChanged(): void {
    if (this.isEditing && this.focusedBlockUuid !== this.blockUuid) {
      this.isEditing = false;
      this.refreshBlock();
    }
  }

  private startCellEdit(line: number, col: number, text: string): void {
    this.editingCellLine = line;
    this.editingCellCol = col;
    this.editingCellText = text;
  }

  private clearCellEdit(): void {
    this.editingCellLine = -1;
    this.editingCellCol = -1;
    this.editingCellText = '';
  }

  private commitCellEdit(): void {
    if (this.editingCellLine < 0 || this.editingCellCol < 0) {
      return;
    }
    const line = this.tableLines[this.editingCellLine];
    const cells = BlockView.splitTableRow(line);
    if (this.editingCellCol < cells.length) {
      cells[this.editingCellCol] = this.editingCellText.trim();
      this.tableLines[this.editingCellLine] = '| ' + cells.join(' | ') + ' |';
      const newContent = this.tableLines.join('\n');
      EditorService.getInstance().updateBlockContent(this.blockUuid, newContent);
    }
    this.clearCellEdit();
    this.refreshBlock();
  }

  resolvePageName(): string {
    const ws = WorkspaceService.getInstance();
    const pid = ws.getPageUuidForBlock(this.blockUuid);
    if (pid) {
      const p = ws.getDataStore().getIndexStore().getPage(pid);
      if (p) return p.originalName;
    }
    return '';
  }

  buildGuideArray(): number[] {
    const a: number[] = [];
    for (let i = 0; i < this.depth; i++) {
      a.push(i);
    }
    return a;
  }

  hasEmbedSegments(): boolean {
    for (let i = 0; i < this.displaySegments.length; i++) {
      const t = this.displaySegments[i].type;
      if (t === SegmentType.BLOCK_EMBED || t === SegmentType.PAGE_EMBED) return true;
    }
    return false;
  }

  getEmbedItems(): EmbedItem[] {
    const items: EmbedItem[] = [];
    for (let i = 0; i < this.displaySegments.length; i++) {
      const seg = this.displaySegments[i];
      if (seg.type === SegmentType.BLOCK_EMBED) {
        items.push({ kind: 'block', value: seg.text });
      } else if (seg.type === SegmentType.PAGE_EMBED) {
        items.push({ kind: 'page', value: seg.text });
      }
    }
    return items;
  }

  getPageEmbedLines(pageName: string): string[] {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(pageName);
    if (!page) {
      return [];
    }
    const blocks = ws.getPageBlocks(page.uuid);
    const lines: string[] = [];
    for (let i = 0; i < blocks.length && i < 5; i++) {
      lines.push(blocks[i].content.substring(0, 80));
    }
    return lines;
  }

  getBlockContent(uuid: string): string {
    const ws = WorkspaceService.getInstance();
    const b = ws.getBlock(uuid);
    if (b) return b.content.substring(0, 120);
    return uuid.substring(0, 8) + '...';
  }

  static extractQuery(content: string): string {
    const beginIdx = content.indexOf('#+BEGIN_QUERY');
    const endIdx = content.indexOf('#+END_QUERY');
    if (beginIdx >= 0 && endIdx > beginIdx) {
      const inner = content.substring(beginIdx + '#+BEGIN_QUERY'.length, endIdx);
      const open = inner.indexOf('(');
      const close = inner.lastIndexOf(')');
      if (open >= 0 && close > open) {
        return inner.substring(open, close + 1).trim();
      }
      return inner.trim();
    }
    const qIdx = content.indexOf('{{query');
    if (qIdx >= 0) {
      let start = qIdx + '{{query'.length;
      if (start < content.length && content.charAt(start) === ':') {
        start = start + 1;
      }
      let end = content.indexOf('}}', start);
      if (end < 0) {
        end = content.length;
      }
      return content.substring(start, end).trim();
    }
    return '';
  }

  static isPureQueryBlock(content: string): boolean {
    const trimmed = content.trim();
    return trimmed.startsWith('#+BEGIN_QUERY') || trimmed.startsWith('{{query');
  }

  static extractTableLines(content: string): string[] {
    const lines = content.split('\n');
    const result: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i].trim();
      if (t === '') {
        continue;
      }
      if (!t.startsWith('|')) {
        return [];
      }
      result.push(t);
    }
    return result.length >= 2 ? result : [];
  }

  static parseTable(content: string): string[][] {
    const lines = content.split('\n');
    const tableLines: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i].trim();
      if (t === '') {
        continue;
      }
      if (!t.startsWith('|')) {
        return [];
      }
      tableLines.push(t);
    }
    if (tableLines.length < 2) {
      return [];
    }
    const rows: string[][] = [];
    for (let i = 0; i < tableLines.length; i++) {
      const cells = BlockView.splitTableRow(tableLines[i]);
      if (BlockView.isSeparatorRow(cells)) {
        continue;
      }
      rows.push(cells);
    }
    return rows;
  }

  static splitTableRow(line: string): string[] {
    let inner = line;
    if (inner.startsWith('|')) {
      inner = inner.substring(1);
    }
    if (inner.endsWith('|')) {
      inner = inner.substring(0, inner.length - 1);
    }
    const parts = inner.split('|');
    const cells: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      cells.push(parts[i].trim());
    }
    return cells;
  }

  static isSeparatorRow(cells: string[]): boolean {
    for (let i = 0; i < cells.length; i++) {
      const c = cells[i];
      let ok = true;
      for (let j = 0; j < c.length; j++) {
        const ch = c.charAt(j);
        if (ch !== '-' && ch !== ':' && ch !== ' ') {
          ok = false;
          break;
        }
      }
      if (!ok) {
        return false;
      }
    }
    return cells.length > 0;
  }

  getMarkerColor(m: string): ResourceColor {
    if (m === 'DONE') return $r('app.color.marker_done');
    if (m === 'DOING') return $r('app.color.marker_doing');
    if (m === 'TODO') return $r('app.color.marker_todo');
    if (m === 'LATER') return $r('app.color.marker_later');
    if (m === 'NOW') return $r('app.color.marker_doing');
    if (m === 'CANCELLED') return $r('app.color.marker_cancelled');
    return $r('app.color.muted_text');
  }

  getMarkerBg(m: string): ResourceColor {
    if (m === 'DONE') return $r('app.color.marker_done_bg');
    if (m === 'DOING') return $r('app.color.marker_doing_bg');
    if (m === 'TODO') return $r('app.color.marker_todo_bg');
    if (m === 'LATER') return $r('app.color.marker_later_bg');
    if (m === 'NOW') return $r('app.color.marker_doing_bg');
    if (m === 'CANCELLED') return $r('app.color.marker_cancelled_bg');
    return Color.Transparent;
  }
}
