import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { AppState } from '../../state/AppState';
import { WorkspaceService } from '../../services/WorkspaceService';
import { pasteboard } from '@kit.BasicServicesKit';

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
 * 浮动定位在指定坐标处，提供页面快捷操作。
 * 点击菜单外部关闭。支持重命名、收藏、删除、复制等操作。
 */
@Component
export struct PageContextMenu {
  @Prop pageName: string = '';
  @Prop isVisible: boolean = false;
  @State positionX: number = 0;
  @State positionY: number = 0;

  // 回调：关闭菜单
  onClose: () => void = () => {};

  // 重命名对话框状态
  @State showRenameDialog: boolean = false;
  @State renameText: string = '';

  /**
   * 菜单项列表。
   * 注意：必须是普通方法 —— struct 上的 getter 会被 ArkTS 编译器静默丢弃。
   */
  getMenuItems(): ContextMenuItem[] {
    const items: ContextMenuItem[] = [];
    items[0] = {
      key: 'open',
      label: '打开页面',
      iconName: 'external-link',
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
   */
  handleMenuAction(key: string): void {
    switch (key) {
      case 'open':
        AppState.setCurrentPage(this.pageName);
        this.onClose();
        break;
      case 'rename':
        this.renameText = this.pageName;
        this.showRenameDialog = true;
        break;
      case 'favorite':
        AppState.addFavorite(this.pageName);
        this.onClose();
        break;
      case 'copy':
        this.copyToClipboard(this.pageName);
        this.onClose();
        break;
      case 'sidebar':
        AppState.addRightSidebarBlock({
          id: 'page-' + this.pageName,
          type: 'page',
          title: this.pageName,
          pageName: this.pageName,
          collapsed: false
        });
        this.onClose();
        break;
      case 'delete':
        this.confirmDelete();
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

  confirmDelete(): void {
    this.onClose();
    this.getUIContext().showAlertDialog({
      title: t('delete'),
      message: `确认删除页面 "${this.pageName}"？此操作不可撤销。`,
      primaryButton: {
        value: t('cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: t('delete'),
        fontColor: $r('app.color.danger'),
        action: (): void => {
          const ws = WorkspaceService.getInstance();
          const page = ws.getPageByName(this.pageName);
          if (page) {
            ws.getDataStore().deletePage(page.uuid);
          }
        }
      }
    });
  }

  commitRename(): void {
    if (this.renameText !== '' && this.renameText !== this.pageName) {
      const ws = WorkspaceService.getInstance();
      const page = ws.getPageByName(this.pageName);
      if (page) {
        ws.getDataStore().renamePage(page.uuid, this.renameText);
      }
    }
    this.showRenameDialog = false;
    this.renameText = '';
    this.onClose();
  }

  cancelRename(): void {
    this.showRenameDialog = false;
    this.renameText = '';
  }

  build() {
    if (this.isVisible) {
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

        // ─── 菜单面板 ───
        if (!this.showRenameDialog) {
          Column({ space: 0 }) {
            // 页面名标题
            Row({ space: 8 }) {
              TablerIcon('file', 14, $r('app.color.primary'))
              Text(this.pageName)
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
              this.MenuItemRow(item)
            }, (item: ContextMenuItem) => item.key)
          }
          .width(220)
          .position({ x: this.positionX, y: this.positionY })
          .backgroundColor($r('app.color.surface1'))
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.border') })
          .shadow({ radius: 12, color: 'rgba(0,0,0,0.15)', offsetX: 0, offsetY: 4 })
        }

        // ─── 重命名对话框 ───
        if (this.showRenameDialog) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.4)')
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.cancelRename(); })

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
              Button(t('cancel'))
                .fontSize(13)
                .layoutWeight(1)
                .height(36)
                .backgroundColor($r('app.color.surface2'))
                .fontColor($r('app.color.text'))
                .onClick(() => { this.cancelRename(); })

              Button(t('confirm'))
                .fontSize(13)
                .layoutWeight(1)
                .height(36)
                .backgroundColor($r('app.color.primary'))
                .fontColor(Color.White)
                .onClick(() => { this.commitRename(); })
            }
            .width('100%')
          }
          .width(300)
          .padding(20)
          .backgroundColor($r('app.color.surface1'))
          .borderRadius(10)
          .border({ width: 1, color: $r('app.color.border') })
        }
      }
      .width('100%')
      .height('100%')
    } else {
      Column().width(0).height(0)
    }
  }

  @Builder
  MenuItemRow(item: ContextMenuItem) {
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
    .onClick(() => { this.handleMenuAction(item.key); })
  }
}
