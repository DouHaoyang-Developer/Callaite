import { TablerIcon } from '../common/Icons';
import { FileService } from '../../services/FileService';
import { CloudSyncService } from '../../services/CloudSyncService';
import { AppState } from '../../state/AppState';
import { promptAction } from '@kit.ArkUI';

/**
 * VaultSwitcherDialog —— 仓库切换器（对齐 Obsidian 图 11 深色大模态）。
 *
 * 布局：左侧仓库列表（当前仓库）+ 右侧 Logo/应用版本/操作区。
 * 单库架构下的对应动作：重新加载索引 / 立即同步 / 打开设置。
 * 打开方式：左栏 Vault 行 chevron（AppStorage 'callaite_vaultSwitcherOpen'）。
 */
@Component
export struct VaultSwitcherDialog {
  @StorageLink('callaite_vaultSwitcherOpen') open: boolean = false;

  private close(): void {
    AppStorage.setOrCreate('callaite_vaultSwitcherOpen', false);
  }

  /** 深色固定配色（对齐 Obsidian 仓库切换器在明暗主题下均为深色） */
  private static readonly BG: string = '#1E1E1E';
  private static readonly BG_SIDE: string = '#252525';
  private static readonly TXT: string = '#DADADA';
  private static readonly MUTED: string = '#999999';
  private static readonly SEL: string = '#333333';

  build() {
    if (this.open) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.55)')
          .onClick(() => {
            this.close();
          })

        // 深色模态（左列表 + 右操作区，对齐图 11）
        Row({ space: 0 }) {
          // ─── 左：仓库列表 ───
          Column({ space: 2 }) {
            Text('仓库')
              .fontSize(11)
              .fontColor(VaultSwitcherDialog.MUTED)
              .width('100%')
              .padding({ left: 14, top: 12, bottom: 8 })

            Row({ space: 8 }) {
              TablerIcon('database', 14, VaultSwitcherDialog.TXT)
              Text('Callaite 同步仓库')
                .fontSize(12.5)
                .fontColor(VaultSwitcherDialog.TXT)
                .layoutWeight(1)
                .maxLines(1)
            }
            .width('100%')
            .padding({ left: 14, right: 10, top: 9, bottom: 9 })
            .borderRadius(6)
            .backgroundColor(VaultSwitcherDialog.SEL)

            Blank()
          }
          .width('40%')
          .height('100%')
          .backgroundColor(VaultSwitcherDialog.BG_SIDE)
          .padding({ bottom: 12 })

          // ─── 右：Logo + 操作 ───
          Column({ space: 14 }) {
            Blank()

            Column({ space: 8 }) {
              // Logo 占位（宝石图标）
              TablerIcon('diamond', 40, '#A88BFA')
              Text('Callaite')
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor(VaultSwitcherDialog.TXT)
              Text('HarmonyOS 1.1.1')
                .fontSize(11)
                .fontColor(VaultSwitcherDialog.MUTED)
            }
            .alignItems(HorizontalAlign.Center)

            Blank()

            // 管理仓库 → 设置
            Row() {
              Column({ space: 3 }) {
                Text('管理仓库')
                  .fontSize(12.5)
                  .fontColor(VaultSwitcherDialog.TXT)
                Text('查看当前仓库与偏好设置。')
                  .fontSize(10)
                  .fontColor(VaultSwitcherDialog.MUTED)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text('打开')
                .fontSize(11.5)
                .fontColor(VaultSwitcherDialog.TXT)
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .borderRadius(6)
                .backgroundColor(VaultSwitcherDialog.SEL)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              AppState.setCurrentPage('Settings');
              this.close();
            })

            // 同步远端仓库
            Row() {
              Column({ space: 3 }) {
                Text('同步远端仓库')
                  .fontSize(12.5)
                  .fontColor(VaultSwitcherDialog.TXT)
                Text('将一个远端仓库的内容同步到 Obsidian 中。')
                  .fontSize(10)
                  .fontColor(VaultSwitcherDialog.MUTED)
                  .maxLines(1)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text('同步')
                .fontSize(11.5)
                .fontColor(VaultSwitcherDialog.TXT)
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .borderRadius(6)
                .backgroundColor(VaultSwitcherDialog.SEL)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              CloudSyncService.syncAll().then((count: number) => {
                promptAction.openToast({ message: '同步完成：' + count + ' 个文件' });
              }).catch(() => {
                promptAction.openToast({ message: '同步失败，请检查网络' });
              });
              this.close();
            })

            // 语言
            Row({ space: 6 }) {
              TablerIcon('world', 13, VaultSwitcherDialog.MUTED)
              Text('语言：简体中文')
                .fontSize(11)
                .fontColor(VaultSwitcherDialog.MUTED)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(6)
            .border({ width: 1, color: VaultSwitcherDialog.SEL })
          }
          .width('60%')
          .height('100%')
          .padding(16)
        }
        .width('62%')
        .constraintSize({ maxWidth: 620, minHeight: 320, maxHeight: 420 })
        .height(320)
        .borderRadius(12)
        .clip(true)
        .border({ width: 1, color: VaultSwitcherDialog.SEL })
      }
      .width('100%')
      .height('100%')
    }
  }
}
