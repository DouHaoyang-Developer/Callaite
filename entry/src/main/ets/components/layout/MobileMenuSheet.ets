import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { t } from '../../utils/i18n';
import { JournalService } from '../../services/JournalService';
import { TabState } from '../../state/TabState';

interface MenuRow {
  icon: string;
  label: string;
  action: string;
}

interface MenuGroup {
  title: string;
  rows: MenuRow[];
}

/**
 * MobileMenuSheet — Obsidian iOS "更多"菜单（Obsidian_iphone (3).jpg 复刻）。
 *
 * 结构优化：原先 9 个条目平铺 + 8 条分割线，视觉噪声大且难以扫读；
 * 现按「内容 / 视图 / 数据与系统」三组归类，组间用分割线分隔，减少认知负担。
 */
@Component
export struct MobileMenuSheet {
  @State hoveredAction: string = '';
  /**
   * 是否正在拖拽。
   * 拖拽期间 translate 必须**逐帧跟手**（动画时长 0），否则会落后于手指；
   * 抬手后切回 220ms 动画做档位吸附/回弹。两者靠这一个状态位切换。
   */
  @State dragging: boolean = false;
  /** 当前下拉位移（vp，0 = 完全展开）。仅改 translate，不改布局高度。 */
  @State dragOffset: number = 0;
  /**
   * 本 sheet 实测高度（vp），由 onAreaChange 写入。
   * 只用于把位移换算成 detent 档位，不参与渲染 ⇒ 普通字段即可，无需 @State。
   */
  private sheetHeight: number = 0;
  /** 手势起始位移快照：offsetY 是相对**手势起点**的累计位移，须叠加快照，不能逐帧累加。 */
  private dragStartOffset: number = 0;
  /** 抬手瞬间的甩动判定结果（由 onActionUpdate 写入，onActionEnd 读取） */
  private pendingFling: boolean = false;

  /**
   * ─── 下拉关闭 / detent 参数（全部 vp）───
   * 档位表见 detentOffsets()；为什么手写而不用 bindSheet 见 DragHandle 上方的长注释。
   *
   * ⚠️ 关键不变式：**档位 1 必须落在关闭线以内，否则该档位永远够不到**
   * （拖到它之前就已经触发关闭）。因此半展开档位刻意做得比关闭线浅：
   *   halfDetent ≤ 200  <  dismissDistance ≥ 260
   * 定参时用长内容（h=800）验算过：200 < 440，档位与关闭线之间留有约 240vp 的行程。
   *
   * 半展开档位参数：
   *   · RATIO 0.46 + MAX 200 —— 保证档位 1 明显浅于关闭线（见上方不变式）；
   *   · MAX 同时避免内容过高时把首组标题推出屏外；
   *   · MIN 120 —— 低于此值该档位无意义，直接退化为「单档位（仅完全展开）」。
   */
  private static readonly HALF_DETENT_RATIO: number = 0.46;
  private static readonly HALF_DETENT_MAX: number = 200;
  private static readonly HALF_DETENT_MIN: number = 120;
  /**
   * 下滑关闭的**位移**条件：超过内容高度的 55%，且至少 260vp。
   * 两个下限都要，缺一不可 ——
   *   · 只有比例：短内容时关闭线过浅，误关；
   *   · 只有常量：长内容时一拖就关，够不到档位 1。
   * 该值必须始终大于档位 1（构造上已保证，见 halfDetentOffset 末行的兜底）。
   */
  private static readonly DISMISS_RATIO: number = 0.55;
  private static readonly DISMISS_MIN: number = 260;
  /**
   * 下滑关闭的**速度**条件（vp/s）：快速轻甩即可关闭，不必拖到底。
   * 取 1100 而非更低，是为了不干扰「慢慢拖到档位 1」——
   * 900 时到达档位 1 的那一下抬手容易被误判成甩动而直接关闭。
   */
  private static readonly FLING_VELOCITY: number = 1100;
  /** 拖拽灵敏度：1.0 = 与手指 1:1（不放大，避免"指示条一动 sheet 窜出去"的廉价感） */
  private static readonly DRAG_FOLLOW: number = 1.0;

  /**
   * 按意图分组 —— 创建/浏览内容、切换视图、数据与系统设置。
   */
  private groups(): MenuGroup[] {
    const g: MenuGroup[] = [];

    const content: MenuRow[] = [];
    content[0] = { icon: 'search', label: t('quick_switch'), action: 'switcher' };
    content[1] = { icon: 'file-plus', label: t('new_page'), action: 'newPage' };
    content[2] = { icon: 'calendar-plus', label: t('open_today_journal'), action: 'today' };
    content[3] = { icon: 'list', label: t('nav_all_pages'), action: 'allPages' };
    g[0] = { title: t('menu_group_content'), rows: content };

    const view: MenuRow[] = [];
    view[0] = { icon: 'hierarchy', label: t('view_graph'), action: 'graph' };
    view[1] = { icon: 'layout-grid', label: t('new_whiteboard'), action: 'whiteboard' };
    view[2] = { icon: 'layout-sidebar-right', label: t('sidebar_right'), action: 'rightSidebar' };
    g[1] = { title: t('menu_group_view'), rows: view };

    const sys: MenuRow[] = [];
    sys[0] = { icon: 'upload', label: t('import'), action: 'import' };
    sys[1] = { icon: 'settings', label: t('settings'), action: 'settings' };
    g[2] = { title: t('menu_group_system'), rows: sys };

    return g;
  }

  private close(): void {
    AppStorage.setOrCreate('callaite_mobileMenuOpen', false);
  }

  private handle(row: MenuRow): void {
    this.close();
    if (row.action === 'switcher' || row.action === 'newPage') {
      // U1.6：这两项是「快速切换 / 新建页面」语义 → 命令面板（过滤页面名，无命中即按输入建页）。
      // 移动端的全局搜索入口是底部胶囊栏的放大镜 pill（仍走 setSearchPanelOpen）。
      AppState.setCommandPaletteOpen(true);
    } else if (row.action === 'graph') {
      TabState.newTab('Graph');
    } else if (row.action === 'whiteboard') {
      TabState.newTab('Whiteboards');
    } else if (row.action === 'today') {
      JournalService.ensureTodayJournal();
      AppState.setCurrentPage('Journal');
    } else if (row.action === 'allPages') {
      TabState.newTab('AllPages');
    } else if (row.action === 'rightSidebar') {
      AppState.toggleRightSidebar();
    } else if (row.action === 'import') {
      AppState.setImportDialogOpen(true);
    } else if (row.action === 'settings') {
      AppState.setCurrentPage('Settings');
    }
  }

  /**
   * 把 Area 的 Length（string | number | Resource）收窄为 vp 数值。
   * 布局回调中 height 实际是 number，但类型仍是 Length 联合体；ArkTS 禁用 any/unknown，
   * 直接断言为 number 不安全，故用 typeof 收窄（同 BlockView.areaVp 的做法）。
   */
  private static areaVp(value: Length | undefined): number {
    if (value === undefined) {
      return 0;
    }
    if (typeof value === 'number') {
      return value;
    }
    return 0;
  }

  /**
   * 半展开 detent 的位移值（vp）。
   * 上限 HALF_DETENT_MAX 保证档位 1 仍露出首组菜单；内容过矮时该档位无意义，返回 0
   * （此时 detents 退化为 [0, 0]，等价于只有「完全展开」一档）。
   * 末行的兜底是**不变式保护**：档位 1 若被算到关闭线之外就永远够不到，
   * 宁可退化成单档位，也不要留一个拖不到的档位。调参时务必保持。
   */
  private halfDetentOffset(): number {
    if (this.sheetHeight <= 0) {
      return 0;
    }
    const raw = this.sheetHeight * MobileMenuSheet.HALF_DETENT_RATIO;
    const capped = raw < MobileMenuSheet.HALF_DETENT_MAX ? raw : MobileMenuSheet.HALF_DETENT_MAX;
    if (capped < MobileMenuSheet.HALF_DETENT_MIN) {
      return 0;
    }
    return capped < this.dismissDistance() ? capped : 0;
  }

  /** 位移关闭线（vp）：比例与常量取大者，见 DISMISS_RATIO 注释 */
  private dismissDistance(): number {
    if (this.sheetHeight <= 0) {
      return MobileMenuSheet.DISMISS_MIN;
    }
    const byRatio = this.sheetHeight * MobileMenuSheet.DISMISS_RATIO;
    return byRatio > MobileMenuSheet.DISMISS_MIN ? byRatio : MobileMenuSheet.DISMISS_MIN;
  }

  /**
   * 档位位移表（升序）：0 = 完全展开，1 = 半展开。
   * @Builder 之外的手写 detent —— 要加第 3 档只需在此追加一个位移值，
   * settle() 的「取最近档」循环会自动纳入，无需改动其它代码。
   */
  private detentOffsets(): number[] {
    const list: number[] = [];
    list[0] = 0;
    list[1] = this.halfDetentOffset();
    return list;
  }

  /**
   * 写入目标位移。
   * 不在这里调 animateTo —— 位移的缓动统一由 build 里 `.animation()` 承担
   * （拖拽中时长 0 = 跟手，抬手后时长 220ms = 吸附/回弹）。
   * 两套动画机制同时作用于 translate 会互相覆盖，只保留声明式这一套。
   */
  private setOffset(target: number): void {
    this.dragOffset = target;
  }

  /**
   * 抬手决策：先判「是否关闭」，否则吸附到最近 detent。
   *
   * 顺序很重要 —— 速度关闭必须优先于档位吸附，否则快速下滑会被吸回档位 1，
   * 用户看到的是"甩不下去"。
   */
  private settle(): void {
    const dy = this.dragOffset;
    const dismissByDistance = dy >= this.dismissDistance();
    const dismissByFling = this.pendingFling;
    if (dismissByDistance || dismissByFling) {
      this.dismissByDrag();
      return;
    }
    // 吸附到最近的档位
    const detents = this.detentOffsets();
    let best = detents[0];
    for (let i = 0; i < detents.length; i++) {
      const cur = detents[i];
      if (Math.abs(cur - dy) < Math.abs(best - dy)) {
        best = cur;
      }
    }
    this.setOffset(best);
  }

  /** 下滑关闭：先复位位移再收起，避免下次打开"半截悬空"残留 */
  private dismissByDrag(): void {
    this.dragOffset = 0;
    this.close();
  }

  @Builder
  GroupHeader(title: string) {
    Text(title)
      .fontSize(11)
      .fontColor($r('app.color.muted_text'))
      .letterSpacing(0.6)
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 4 })
  }

  @Builder
  MenuRowItem(row: MenuRow) {
    Row({ space: 14 }) {
      TablerIcon(row.icon, 22, $r('app.color.text'))
      Text(row.label)
        .fontSize(16)
        .fontColor($r('app.color.text'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(52)
    .padding({ left: 20, right: 20 })
    .stateStyles({
      normal: {
        .backgroundColor(this.hoveredAction === row.action ? $r('app.color.surface2') : Color.Transparent)
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onHover((isHover: boolean) => {
      this.hoveredAction = isHover ? row.action : '';
    })
    .onClick(() => {
      this.handle(row);
    })
  }

  /**
   * 顶部拖拽握把区。
   *
   * ─── 为什么本窗口没有改用 bindSheet（S1-G 路线取舍）───
   * 为拿到 detents 而把观感改坏 = 拿核心资产换次要能力：
   *   · bindSheet 的 SheetSize.FIT_CONTENT（common.d.ts:7977）虽能内容自适应高度，
   *     但其宽度铺满整屏、贴底、遮罩全屏，与当前 24vp 顶部圆角悬浮卡不一致；
   *   · 唯一可能保形的 preferType = SheetType.POPUP（common.d.ts:11833）只是**偏好**，
   *     系统可依窗口尺寸/设备形态改为 BOTTOM，属不可控观感风险；
   *   · 本项目 FloatingPanel.ets:6-11 有实测记录：bindSheet 导致"贴底、下留白 0、
   *     圆角只在外层"。
   * 故以手写 PanGesture 补齐「真实可拖 + 下滑关闭 + detents」三项能力，
   * 视觉规格（指示条 36x4/r2、行高 52、顶部圆角 24）保持逐像素不变。
   *
   * 视觉不变：指示条仍为 36x4、圆角 2；总占位仍为 14vp（上 8 + 下 6）。
   * 但把热区从 4vp 抬到 18vp —— 4vp 高在拇指下几乎点不中。此处受视觉规格约束，
   * 只能取 54x18 的折中（官方点击热区下限 48vp，纵向仍偏小）；
   * 因此**整张卡片**都挂了同一个下拉手势（见 build 的 .gesture），
   * 握把区只是显式提示。横向拖动不会触发（PanDirection.Vertical）。
   */
  @Builder
  DragHandle() {
    Stack() {
      Column()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(this.dragging ? $r('app.color.muted_text') : $r('app.color.border'))
    }
    .width(54)
    .height(18)
    // 占位与改动前完全一致：上 8 + 下 6 = 14vp（指示条自身 4vp 含在其中）
    // 注意：@Builder 的返回值是 void，加边距只能写在 Builder 内部，不能在调用处链式追加
    .margin({ top: 8, bottom: 6 })
  }

  /** 垂直拖拽手势：跟手换算位移 + 抬手吸附/关闭 */
  private dragGesture(): PanGestureInterface {
    return PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 3 })
      .onActionStart(() => {
        this.pendingFling = false;
        this.dragging = true;
        this.dragStartOffset = this.dragOffset;
      })
      .onActionUpdate((event: GestureEvent) => {
        const raw = this.dragStartOffset + event.offsetY * MobileMenuSheet.DRAG_FOLLOW;
        let next = raw;
        if (next < 0) {
          // 已完全展开还继续上拉：给 0.25 的阻尼，制造"到头"的手感，而不是硬顶住
          next = raw * 0.25;
        }
        const limit = this.sheetHeight > 0 ? this.sheetHeight : 800;
        if (next > limit) {
          next = limit;
        }
        this.dragOffset = next;
        // 速度阈值在抬手瞬间判定，避免拖拽中途误关
        this.pendingFling = event.velocityY > MobileMenuSheet.FLING_VELOCITY;
      })
      .onActionEnd(() => {
        this.settle();
        this.dragging = false;
      })
      .onActionCancel(() => {
        // 触摸被系统打断（来电/通知）：回到最近档位而不是卡在中间
        this.dragging = false;
        this.settle();
      });
  }

  build() {
    Column() {
      // 顶部拖动指示条（真实可拖：见 dragGesture）
      this.DragHandle()

      ForEach(this.groups(), (group: MenuGroup, gi: number) => {
        if (gi > 0) {
          Divider()
            .color($r('app.color.border'))
            .width('90%')
            .margin({ top: 6 })
        }
        this.GroupHeader(group.title)
        ForEach(group.rows, (row: MenuRow) => {
          this.MenuRowItem(row)
        }, (row: MenuRow) => group.title + '_' + row.action)
      }, (group: MenuGroup) => group.title)

      Blank().height(12)
    }
    .width('100%')
    .padding({ bottom: 24 })
    .backgroundColor($r('app.color.surface1'))
    .borderRadius({ topLeft: 24, topRight: 24 })
    .border({ width: { top: 0.5 }, color: $r('app.color.glass_border') })
    // 下拉跟手/吸附：只改 translate，不改布局高度 ⇒ 不会引发子节点重新布局
    .translate({ y: this.dragOffset })
    .animation({ duration: this.dragging ? 0 : 220, curve: Curve.FastOutSlowIn })
    .gesture(this.dragGesture())
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const h = MobileMenuSheet.areaVp(newArea.height);
      if (h > 0) {
        this.sheetHeight = h;
      }
    })
  }
}
