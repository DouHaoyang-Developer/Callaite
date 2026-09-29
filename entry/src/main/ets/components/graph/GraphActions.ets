import { AppState, RightSidebarBlock } from '../../state/AppState';
import { WorkspaceService } from '../../services/WorkspaceService';
import { TablerIcon } from '../common/Icons';
import { pasteboard } from '@kit.BasicServicesKit';
import { countBacklinks } from '../../utils/BacklinkWarning';

/**
 * GraphActions — 图谱节点操作菜单。
 *
 * 在 GraphView 中长按节点后弹出，提供：
 *  - 打开页面
 *  - 收藏 / 取消收藏
 *  - 复制页面名（pasteboard）
 *  - 查看反链（切换到右侧栏反链视图）
 *  - 删除页面（带二次确认 + 删除前反链计数预警）
 *
 * 使用 Stack 浮动定位在 (positionX, positionY)。
 * 点击遮罩层（菜单外部）通过 onClose 回调关闭。
 */
@Component
export struct GraphActions {
  @Prop pageName: string;
  @Prop isVisible: boolean;
  @Prop positionX: number = 0;
  @Prop positionY: number = 0;

  /** 关闭回调（由父组件传入，用于点击外部或操作完成后关闭菜单） */
  onClose: () => void = () => {};

  /** 是否显示删除确认对话框 */
  @State private showDeleteConfirm: boolean = false;
  /**
   * 删除确认弹窗里的反链条数（惰性计算）。
   * ⚠️ 只在用户点「删除页面」那一刻算一次 —— 反链是遍历全库索引，
   * 绝不能放进 build()/菜单渲染，否则每次长按弹菜单都要扫全库。
   * -1 表示「尚未计算」，用于断言展示路径不会漏算。
   */
  @State private backlinkCount: number = -1;
  /** 当前页面是否已收藏 */
  @State private isFavorite: boolean = false;

  aboutToAppear(): void {
    this.refreshFavoriteStatus();
  }

  /**
   * 查询当前页面是否已在收藏列表中。
   */
  private refreshFavoriteStatus(): void {
    const favs = AppState.getFavorites();
    let found = false;
    for (let i = 0; i < favs.length; i++) {
      if (favs[i] === this.pageName) {
        found = true;
        break;
      }
    }
    this.isFavorite = found;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 全屏透明遮罩：点击外部关闭菜单
      Column()
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          this.onClose();
        })

      // 删除确认对话框
      if (this.showDeleteConfirm) {
        this.buildDeleteConfirm()
      }

      // 菜单面板
      Column({ space: 0 }) {
        // 标题栏
        Row({ space: 6 }) {
          TablerIcon('circle-dot', 14, $r('app.color.primary'))
          Text(this.pageName)
            .fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .border({ width: { bottom: 1 }, color: $r('app.color.border') })

        // 打开页面
        this.menuRow('external-link', '打开页面', $r('app.color.text'), () => {
          AppState.setCurrentPage(this.pageName);
          this.onClose();
        })

        // 收藏 / 取消收藏
        this.menuRow(
          this.isFavorite ? 'star-filled' : 'star',
          this.isFavorite ? '取消收藏' : '收藏',
          this.isFavorite ? $r('app.color.warning') : $r('app.color.text'),
          () => {
            if (this.isFavorite) {
              AppState.removeFavorite(this.pageName);
            } else {
              AppState.addFavorite(this.pageName);
            }
            this.isFavorite = !this.isFavorite;
            this.onClose();
          }
        )

        // 复制页面名
        this.menuRow('copy', '复制页面名', $r('app.color.text'), () => {
          this.copyPageName();
          this.onClose();
        })

        // 查看反链
        this.menuRow('link', '查看反链', $r('app.color.link'), () => {
          this.openBacklinksView();
          this.onClose();
        })

        // 删除页面
        this.menuRow('trash', '删除页面', $r('app.color.danger'), () => {
          this.prepareDeleteConfirm();
        })
      }
      .width(180)
      .borderRadius(8)
      .backgroundColor($r('app.color.surface2'))
      .shadow({ radius: 12, color: '#66000000', offsetX: 0, offsetY: 4 })
      .position({ x: this.clampedX(), y: this.clampedY() })
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 菜单项行（图标 + 文本 + 点击回调）。
   * 使用 @Builder 以在 build() 中复用。
   */
  @Builder menuRow(iconName: string, label: string, tint: ResourceColor, action: () => void) {
    Row({ space: 10 }) {
      TablerIcon(iconName, 16, tint)
      Text(label)
        .fontSize(13).fontColor(tint).layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .onClick(() => {
      action();
    })
  }

  /**
   * 打开删除确认框：**此处**才算反链（遍历全库索引），一次删除只算一次。
   * 反链数为 0 时弹窗文案与改造前逐字相同（不产生噪音行）。
   */
  private prepareDeleteConfirm(): void {
    this.backlinkCount = countBacklinks(WorkspaceService.getInstance().getDataStore(), this.pageName);
    this.showDeleteConfirm = true;
  }

  /**
   * 删除确认对话框。
   */
  @Builder buildDeleteConfirm() {
    Column({ space: 12 }) {
      Text('确认删除')
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
      Text(this.deleteConfirmMessage())
        .fontSize(12).fontColor($r('app.color.muted_text'))
      Row({ space: 8 }) {
        Text('取消')
          .fontSize(13).fontColor($r('app.color.muted_text'))
          .layoutWeight(1).textAlign(TextAlign.Center)
          .padding({ top: 8, bottom: 8 })
          .borderRadius(6).backgroundColor($r('app.color.surface1'))
          .onClick(() => {
            this.showDeleteConfirm = false;
          })
        Text('删除')
          .fontSize(13).fontColor($r('app.color.danger'))
          .layoutWeight(1).textAlign(TextAlign.Center)
          .padding({ top: 8, bottom: 8 })
          .borderRadius(6).backgroundColor($r('app.color.surface1'))
          .onClick(() => {
            this.confirmDelete();
          })
      }
      .width('100%')
    }
    .width(220)
    .padding(16)
    .borderRadius(10)
    .backgroundColor($r('app.color.surface2'))
    .shadow({ radius: 16, color: '#80000000', offsetX: 0, offsetY: 4 })
    .position({ x: '50%', y: '40%' })
    .markAnchor({ x: '50%', y: '50%' })
  }

  /**
   * 复制页面名到系统剪贴板。
   */
  private copyPageName(): void {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.pageName);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteData).then(() => {
        // 复制成功
      });
    } catch (e) {
      // 忽略剪贴板写入失败
    }
  }

  /**
   * 切换到反链视图：将反链块添加到右侧栏并打开。
   */
  private openBacklinksView(): void {
    const block: RightSidebarBlock = {
      id: 'graph-backlinks-' + this.pageName + '-' + Date.now(),
      type: 'backlinks',
      title: '反链: ' + this.pageName,
      pageName: this.pageName,
      collapsed: false
    };
    AppState.addRightSidebarBlock(block);
    AppState.setRightSidebarOpen(true);
  }

  /**
   * 删除确认文案。
   *
   * ⚠️ 文案核实（勿凭印象改）：`DataStore.deletePage` → `FileRepository.deleteFile`
   * → `fs.unlinkSync`，是**物理删除**；回收站侧（原 core/engine/RecycleEngine.ets 与
   * components/settings/RecycleBinPage.ets）零引用、列表恒空，已在 U1.5 死代码清扫中
   * 删除，本仓不存在任何回收站数据通路。因此「此操作不可撤销」是**准确**的，
   * 绝不能改写成「将移入回收站」——那会是谎报可恢复。
   * 若将来重新引入回收站（需同时落地引擎 + 落盘 + 入口页），必须同步改这里。
   */
  private deleteConfirmMessage(): string {
    let msg: string = '确定要删除页面「' + this.pageName + '」吗？此操作不可撤销。';
    if (this.backlinkCount > 0) {
      msg += '\n\n此页面被 ' + this.backlinkCount.toString() + ' 处引用，删除后这些链接将失效。';
    }
    return msg;
  }

  /**
   * 执行删除页面。
   */
  private confirmDelete(): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.pageName);
    if (page) {
      ws.getDataStore().deletePage(page.uuid);
    }
    AppState.removeFavorite(this.pageName);
    this.showDeleteConfirm = false;
    this.onClose();
  }

  /**
   * 水平位置边界约束：避免菜单超出右侧屏幕。
   */
  private clampedX(): number {
    const max = 320; // 估算屏幕宽度下限
    if (this.positionX + 180 > max) {
      return this.positionX - 180;
    }
    return this.positionX;
  }

  /**
   * 垂直位置边界约束：避免菜单超出底部。
   */
  private clampedY(): number {
    const max = 480; // 估算屏幕高度下限
    if (this.positionY + 220 > max) {
      return this.positionY - 220;
    }
    return this.positionY;
  }
}
