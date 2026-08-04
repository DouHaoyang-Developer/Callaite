import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { AppState } from '../../state/AppState';
import { SubscriptionService } from '../../services/SubscriptionService';

/**
 * ProUpgradePage — Pro 升级引导页。
 *
 * 展示 Free vs Pro 功能对比表，提供购买入口。
 * 对应 Logseq settings.cljs account 区域。
 */
@Component
export struct ProUpgradePage {
  @State isPro: boolean = false;
  @State isPurchasing: boolean = false;

  aboutToAppear(): void {
    this.isPro = SubscriptionService.checkPro();
  }

  build() {
    Column({ space: 20 }) {
      // 标题
      Row({ space: 12 }) {
        Row() { TablerIcon('arrow-left', 18, $r('app.color.text')) }
        .width(36).height(36)
        .onClick(() => { AppState.setCurrentPage('Settings'); })

        Text('Callaite Pro')
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
      }
      .width('100%')
      .padding({ top: 24, bottom: 12 })

      if (this.isPro) {
        this.ProActiveView()
      } else {
        this.UpgradeView()
      }

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ProActiveView() {
    Column({ space: 12 }) {
      TablerIcon('check', 40, $r('app.color.success'))
      Text('已是 Pro 会员')
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
      Text('享受全部高级功能')
        .fontSize(14).fontColor($r('app.color.muted_text'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 60 })
  }

  @Builder
  UpgradeView() {
    Column({ space: 16 }) {
      // 功能对比
      Column({ space: 8 }) {
        this.FeatureRow('云同步 Graph 数量', '1 个', '10 个')
        this.FeatureRow('云端同步', '✓', '✓')
        this.FeatureRow('闪卡系统', '—', '✓')
        this.FeatureRow('PDF 标注', '—', '✓')
        this.FeatureRow('主题自定义', '亮/暗', '全部主题')
        this.FeatureRow('多端流转', '✓', '✓')
        this.FeatureRow('数据加密', '✓', '✓')
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.surface1'))
      .borderRadius(12)

      // 购买按钮
      Button(this.isPurchasing ? '处理中...' : '升级 Pro · ¥12/月')
        .fontSize(16)
        .width('100%')
        .height(48)
        .type(ButtonType.Capsule)
        .backgroundColor($r('app.color.primary'))
        .fontColor(Color.White)
        .enabled(!this.isPurchasing)
        .onClick(() => {
          this.handlePurchase();
        })

      Text('订阅将通过华为应用市场 IAP 完成，可随时取消。')
        .fontSize(11).fontColor($r('app.color.muted_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  FeatureRow(feature: string, free: string, pro: string) {
    Row() {
      Text(feature).fontSize(14).fontColor($r('app.color.text')).layoutWeight(1)
      Text(free).fontSize(13).fontColor($r('app.color.muted_text')).width(60).textAlign(TextAlign.Center)
      Text(pro).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.primary')).width(60).textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(36)
    .border({ width: { bottom: 0.5 }, color: $r('app.color.border') })
  }

  async handlePurchase(): Promise<void> {
    this.isPurchasing = true;
    const success = await SubscriptionService.purchasePro();
    this.isPurchasing = false;
    if (success) {
      this.isPro = true;
    }
  }
}
