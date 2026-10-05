import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { AppState } from '../../state/AppState';
import { WorkspaceService } from '../../services/WorkspaceService';
import { countBacklinks } from '../../utils/BacklinkWarning';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

/**
 * 页面上下文菜单项。
 */
interface ContextMenuItem {
  key: string;
  label: string;
  iconName: string;
  iconColor: ResourceColor;
  danger: boolean;
}

/**
 * PageContextMenu — 页面右键菜单 / 上下文菜单。
 *
 * 两种挂载形态（二选一，由宿主决定）：
 *   A. **bindContextMenuWithResponse 路径（U1.1 主路径）**：宿主在树行上调用
 *      `.bindContextMenuWithResponse(this.TreeContextMenu)`，本组件以
 *      `@Builder ContextMenuWithResponse(kind: ResponseType)` 作为菜单内容被系统弹出。
 *      此时**不渲染遮罩**（noOverlay = true）：定位与「点外部关闭」都由系统菜单承担。
 *   B. **自绘浮层路径（降级 / 独立使用）**：宿主用 `isVisible` + `positionX/Y` 控制，
 *      本组件渲染全屏透明遮罩 + 绝对定位面板。
 *
 * 两种形态共用 ContextMenuPanel()，保证菜单外观与行为逐字一致。
 * 点击菜单外部关闭。支持重命名、收藏、删除、复制等操作。
 */
@Component
export struct PageContextMenu {
  @Prop pageName: string = '';
  @Prop isVisible: boolean = false;
  /**
   * 目标节点是否为中间目录节点（NamespaceUtils 的 isPage = false）。
   *
   * ⚠️ 必须在构造 `PageContextMenu({...})` 时传入、且**只在菜单弹出那一刻**取值：
   * 本组件在菜单打开期间被复用为同一实例，构造参数不会随宿主父节点的复用而更新，
   * 所以 getMenuItems() 读到的就是「右键那一刻的节点种类」—— 这正是需要的语义。
   */
  @Prop isFolder: boolean = false;
  /**
   * true = 不渲染全屏遮罩（由 bindContextMenuWithResponse 的系统菜单承接定位与关闭）。
   * false = 渲染遮罩 + position 定位（自绘浮层路径）。
   */
  @Prop noOverlay: boolean = false;
  @State positionX: number = 0;
  @State positionY: number = 0;

  // 回调：关闭菜单
  onClose: () => void = () => {};
  // 回调：菜单内的删除操作已执行完毕（仅删除项会触发，宿主据此刷新数据源）
  onDeleted: () => void = () => {};

  // 重命名对话框状态
  @State showRenameDialog: boolean = false;
  @State renameText: string = '';
  /**
   * 正在重命名的目标。
   *
   * ⚠️ 为什么不能直接用 this.pageName：pageName 是 @Prop，由宿主的 @Builder 每次重渲染时
   * 重新求值；对话框打开后宿主可能重渲染（如树重建）并把 pageName 改成别的行，
   * 那样「提交」会重命名错误的页面。这里在点「重命名」那一刻把目标钉住。
   */
  private renameTarget: string = '';

  /**
   * 菜单项列表。
   * 注意：必须是普通方法 —— struct 上的 getter 会被 ArkTS 编译器静默丢弃。
   *
   * 目录节点（isPage = false）没有真实页面文件，删除/收藏对其无意义
   * （DataStore.getPageByName 查不到 ⇒ 点了也是空操作），故只保留「打开 / 重命名 / 复制」。
   */
  getMenuItems(): ContextMenuItem[] {
    const items: ContextMenuItem[] = [];
    items[0] = {
      key: 'open',
      label: this.isFolder ? '展开/收起' : '打开页面',
      iconName: this.isFolder ? 'folder' : 'external-link',
      iconColor: $r('app.color.text'),
      danger: false
    };
    items[1] = {
      key: 'rename',
      label: t('rename'),
      iconName: 'edit',
      iconColor: $r('app.color.text'),
      danger: false
    };
    if (this.isFolder) {
      items[2] = {
        key: 'copy',
        label: '复制文件夹名',
        iconName: 'copy',
        iconColor: $r('app.color.text'),
        danger: false
      };
      return items;
    }
    items[2] = {
      key: 'favorite',
      label: '添加到收藏',
      iconName: 'pin',
      iconColor: $r('app.color.text'),
      danger: false
    };
    items[3] = {
      key: 'copy',
      label: '复制页面名',
      iconName: 'copy',
      iconColor: $r('app.color.text'),
      danger: false
    };
    items[4] = {
      key: 'sidebar',
      label: '在右侧栏打开',
      iconName: 'layout-sidebar-right',
      iconColor: $r('app.color.muted_text'),
      danger: false
    };
    items[5] = {
      key: 'delete',
      label: t('delete'),
      iconName: 'trash',
      iconColor: $r('app.color.danger'),
      danger: true
    };
    return items;
  }

  /**
   * 执行菜单项操作。
   *
   * @param key 菜单项 key
   * @param targetName 操作目标页面名。由菜单内容 Builder 从**触发菜单的那一行**捕获后传入 ——
   *   菜单打开的这一刻同时只有一个目标，把它作为参数传进来比读 @Prop 更可靠。
   */
  handleMenuAction(key: string, targetName: string): void {
    switch (key) {
      case 'open':
        // 目录节点（isFolder）的「展开/收起」由宿主的 onClick 语义承接：
        // 与行点击保持一致，统一走 setCurrentPage（宿主监听该状态刷新展开态）。
        AppState.setCurrentPage(targetName);
        this.onClose();
        break;
      case 'rename':
        this.renameTarget = targetName;
        this.renameText = targetName;
        this.showRenameDialog = true;
        break;
      case 'favorite':
        AppState.addFavorite(targetName);
        this.onClose();
        break;
      case 'copy':
        this.copyToClipboard(targetName);
        this.onClose();
        break;
      case 'sidebar':
        AppState.addRightSidebarBlock({
          id: 'page-' + targetName,
          type: 'page',
          title: targetName,
          pageName: targetName,
          collapsed: false
        });
        this.onClose();
        break;
      case 'delete':
        this.confirmDelete(targetName);
        break;
      default:
        break;
    }
  }

  copyToClipboard(text: string): void {
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    const systemPasteboard = pasteboard.getSystemPasteboard();
    systemPasteboard.setData(pasteData).then(() => {
      // 复制成功
    }).catch((_err: Error) => {
      // 复制失败
    });
  }

  /**
   * 删除确认 —— 唯一职责是**承载反链计数预警**，而不是新增一道阻断式二次确认。
   *
   * 与 LeftSidebar.deletePage 完全同一口径（同一 countBacklinks、同一分流规则）：
   *   · N = 0（绝大多数页面）：**不弹任何框**，一次点击直接删 —— 保留本组件改造前
   *     「confirmDelete 弹固定文案确认框」之外既有裁定的一致性；这里之所以在 N=0 时
   *     省掉确认框，是为了和 LeftSidebar 对齐（同一页面从两处删除应得到同一风险语义），
   *     且反链为 0 时那句「此操作不可撤销」对用户不构成额外决策信息。
   *   · N > 0：才弹一次知情提示，按钮文案「取消 / 仍要删除」，不置 memorized，
   *     用户可以一路确认下去，永不被永久拦截。
   *
   * ⚠️ 反链只在用户点击「删除」这一刻算一次（countBacklinks 的惰性约束：
   * 禁止放进 build() / 列表渲染 / hover 回调）。
   */
  confirmDelete(targetName: string): void {
    this.onClose();
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(targetName);
    if (!page) {
      // 目标不是真实页面（目录节点 / 页面已被别处删掉）：无事可做
      return;
    }
    const n: number = countBacklinks(ws.getDataStore(), targetName);
    if (n <= 0) {
      this.doDelete(page.uuid);
      return;
    }
    this.getUIContext().showAlertDialog({
      title: t('delete'),
      message: '「' + targetName + '」被 ' + n.toString() + ' 处引用，删除后这些链接将失效。\n\n'
        + '此操作不可撤销，确定继续吗？',
      primaryButton: {
        value: t('cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: '仍要删除',
        fontColor: $r('app.color.danger'),
        action: (): void => {
          this.doDelete(page.uuid);
        }
      }
    });
  }

  /** 真正执行删除。删除后回调宿主刷新数据源（PageTree 需重建树）。 */
  doDelete(pageUuid: string): void {
    const ws = WorkspaceService.getInstance();
    ws.getDataStore().deletePage(pageUuid);
    this.onDeleted();
  }

  commitRename(): void {
    const from: string = this.renameTarget !== '' ? this.renameTarget : this.pageName;
    if (this.renameText !== '' && this.renameText !== from) {
      const ws = WorkspaceService.getInstance();
      const page = ws.getPageByName(from);
      if (page) {
        // S4-W27（H2）：改名可能被拒（新名与**别的页**映射到同一个文件）。
        // 本仓既有提示机制 = promptAction.openToast（全仓 30 处在用），不新造。
        // 必须在下方的 `onClose()` **之前**取出结果 —— 关掉菜单不影响提示条。
        if (!ws.getDataStore().renamePage(page.uuid, this.renameText)) {
          promptAction.openToast({
            message: '已存在同名文件，未重命名：「' + this.renameText + '」'
          }).catch(() => {});
        }
      }
    }
    this.showRenameDialog = false;
    this.renameText = '';
    this.renameTarget = '';
    this.onClose();
  }

  cancelRename(): void {
    this.showRenameDialog = false;
    this.renameText = '';
    this.renameTarget = '';
  }

  build() {
    if (this.isVisible) {
      if (this.noOverlay) {
        // ─── bindContextMenuWithResponse / bindMenu 路径 ───
        // ⚠️ 这里**必须真正产出菜单内容**。曾一度写成 `Column().width(0).height(0)` 并指望
        //    「菜单内容由 @Builder ContextMenuWithResponse 提供」—— 那是错的：
        //    ContextMenuWithResponse 在菜单里的角色就是把**本组件**当内容渲染，
        //    若本组件自身是 0×0，菜单里就是一个空盒子（实测：同菜单内前后两个 Text
        //    都正常显示，中间的本组件位置是一段空白 ✗）。
        this.ContextMenuPanel(this.pageName)
      } else {
        Stack() {
          // ─── 透明遮罩：点击外部关闭 ───
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.01)')
            .onClick(() => {
              if (!this.showRenameDialog) {
                this.onClose();
              }
            })

          // ─── 菜单面板（自绘浮层路径：外层只负责绝对定位，chrome 在 ContextMenuPanel 内） ───
          // 外层宽度用 '100%' 而非 220：面板根节点是 width(220)，
          // 若外层写死 220 会让菜单项行（layoutWeight）没有确定宽度基准。
          if (!this.showRenameDialog) {
            Column({ space: 0 }) {
              this.ContextMenuPanel(this.pageName)
            }
            .width('100%')
            .position({ x: this.positionX, y: this.positionY })
          }

          // ─── 重命名对话框（自绘浮层路径：带全屏遮罩） ───
          if (this.showRenameDialog) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('rgba(0,0,0,0.4)')
              .justifyContent(FlexAlign.Center)
              .onClick(() => { this.cancelRename(); })

            this.RenameDialog()
          }
        }
        .width('100%')
        .height('100%')
      }
    }
  }

  /**
   * 菜单内容（含重命名对话框）—— 两种挂载形态共用，保证外观/行为逐字一致。
   *
   * 含面板 chrome（宽度/底色/圆角/描边/投影）：
   *   · 自绘浮层路径：外层 Column 只负责 `.position({x,y})`；
   *   · bindContextMenuWithResponse / bindMenu 路径：由 build() 直接产出（菜单即内容）。
   *
   * @param targetName 操作目标（触发菜单那一刻的行名），由 Builder 参数显式传递。
   */
  @Builder
  ContextMenuPanel(targetName: string) {
    if (this.showRenameDialog) {
      // 系统菜单容器内不再叠一层全屏遮罩（会盖住菜单自身），只输出对话框本体。
      this.RenameDialog()
    } else {
      // ─── 菜单面板 ───
      Column({ space: 0 }) {
        // 页面名标题
        Row({ space: 8 }) {
          TablerIcon(this.isFolder ? 'folder' : 'file', 14, $r('app.color.primary'))
          Text(targetName)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 8 })
        .border({ width: { bottom: 1 }, color: $r('app.color.border') })

        // 菜单项
        ForEach(this.getMenuItems(), (item: ContextMenuItem) => {
          this.MenuItemRow(item, targetName)
        }, (item: ContextMenuItem) => item.key)
      }
      .width(220)
      .backgroundColor($r('app.color.surface1'))
      .borderRadius(8)
      .border({ width: 1, color: $r('app.color.border') })
      .shadow({ radius: 12, color: 'rgba(0,0,0,0.15)', offsetX: 0, offsetY: 4 })
    }
  }

  /** 重命名对话框本体（两种挂载形态共用；遮罩由各自路径负责） */
  @Builder
  RenameDialog() {
    Column({ space: 12 }) {
      Text(t('rename'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text'))
        .width('100%')

      TextInput({ text: this.renameText, placeholder: '输入新页面名' })
        .fontSize(14)
        .height(38)
        .borderRadius(6)
        .backgroundColor($r('app.color.surface2'))
        .onChange((value: string) => {
          this.renameText = value;
        })
        .onSubmit(() => { this.commitRename(); })

      Row({ space: 10 }) {
        Button(t('cancel')).type(ButtonType.Capsule)
          .fontSize(13)
          .layoutWeight(1)
          .height(36)
          .backgroundColor($r('app.color.surface2'))
          .fontColor($r('app.color.text'))
          .onClick(() => { this.cancelRename(); })

        Button(t('confirm')).type(ButtonType.Capsule)
          .fontSize(13)
          .layoutWeight(1)
          .height(36)
          .backgroundColor($r('app.color.primary'))
          .fontColor($r('app.color.on_primary'))
          .onClick(() => { this.commitRename(); })
      }
      .width('100%')
    }
    .width(280)
    .padding(20)
    .backgroundColor($r('app.color.surface1'))
    .borderRadius(10)
    .border({ width: 1, color: $r('app.color.border') })
  }

  @Builder
  MenuItemRow(item: ContextMenuItem, targetName: string) {
    Row({ space: 10 }) {
      TablerIcon(item.iconName, 14, item.iconColor)
      Text(item.label)
        .fontSize(13)
        .fontColor(item.danger ? $r('app.color.danger') : $r('app.color.text'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(36)
    .padding({ left: 14, right: 14 })
    .onClick(() => { this.handleMenuAction(item.key, targetName); })
  }
}
