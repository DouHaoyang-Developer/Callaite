import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';

/**
 * OnboardingPage — 首次使用引导页。
 * 仅在首次启动时显示，介绍核心功能。
 */
@Component
export struct OnboardingPage {
  @State currentStep: number = 0;

  build() {
    Column({ space: 24 }) {
      Blank()
      TablerIcon('command', 40, $r('app.color.primary'))
      Text('欢迎使用 Callaite').fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
      Text('Logseq 风格的鸿蒙知识管理应用').fontSize(16).fontColor($r('app.color.muted_text'))

      Column({ space: 12 }) {
        this.FeatureItem('calendar', '日志', '每天自动创建日志页，记录生活与工作')
        this.FeatureItem('edit', '大纲编辑', '点击 Block 直接编辑，支持缩进折叠')
        this.FeatureItem('link', '双向链接', '[[页面]] 引用自动建立关联图谱')
        this.FeatureItem('search', '全文搜索', '快捷搜索所有页面和 Block')
      }
      .width('100%').padding(20).backgroundColor($r('app.color.surface1')).borderRadius(12)

      Button('开始使用')
        .fontSize(16).width('100%').height(48).type(ButtonType.Capsule)
        .backgroundColor($r('app.color.primary')).fontColor(Color.White)
        .onClick(() => {
          AppState.setCurrentPage('Journal');
          AppStorage.setOrCreate('callaite_onboarded', true);
        })

      Blank()
    }
    .width('100%').height('100%').padding(32)
    .backgroundColor($r('app.color.surface0'))
  }

  @Builder
  FeatureItem(icon: string, title: string, desc: string) {
    Row({ space: 12 }) {
      TablerIcon(icon, 22, $r('app.color.primary'))
      Column({ space: 2 }) {
        Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text'))
        Text(desc).fontSize(13).fontColor($r('app.color.muted_text'))
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }
}
