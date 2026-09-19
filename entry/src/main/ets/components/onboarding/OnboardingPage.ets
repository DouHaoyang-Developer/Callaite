import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { StatePersistence } from '../../state/StatePersistence';

interface ShortcutItem {
  keys: string;
  desc: string;
}

/** 引导内容最大宽度 —— 平板/2in1 下避免卡片与按钮被拉伸到全屏宽。 */
const CONTENT_MAX_WIDTH = 520;

/**
 * OnboardingPage — 首次使用引导页（4 步流程）。
 * Step 0：欢迎页
 * Step 1：创建 Graph 介绍
 * Step 2：快捷键介绍
 * Step 3：示例页面说明
 *
 * 自适应：内容列约束最大宽度 520vp 并居中，宽屏下不再通栏拉伸。
 * 动效：步骤切换带淡入 + 位移过渡，指示器宽度变化带动画。
 */
@Component
export struct OnboardingPage {
  @State currentStep: number = 0;
  private stepIndices: number[] = [0, 1, 2, 3];
  private shortcuts: ShortcutItem[] = [
    { keys: 'Ctrl + F', desc: '全文搜索' },
    { keys: 'Ctrl + P', desc: '命令面板' },
    { keys: 'Tab', desc: '缩进 Block' },
    { keys: 'Shift + Tab', desc: '反缩进 Block' },
    { keys: 'Enter', desc: '新建 Block' },
    { keys: 'Ctrl + Z', desc: '撤销操作' }
  ];

  /**
   * 步骤切换过渡：新步骤自右淡入，旧步骤向左淡出。
   */
  private stepTransition(): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Friction })
        .combine(TransitionEffect.translate({ x: 28 })),
      TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.Friction })
        .combine(TransitionEffect.translate({ x: -28 }))
    );
  }

  build() {
    Column({ space: 24 }) {
      this.StepIndicator()

      // ─── 步骤内容（宽屏限宽居中）───
      Column() {
        if (this.currentStep === 0) {
          Column() { this.StepWelcome() }
            .width('100%')
            .transition(this.stepTransition())
        } else if (this.currentStep === 1) {
          Column() { this.StepGraph() }
            .width('100%')
            .transition(this.stepTransition())
        } else if (this.currentStep === 2) {
          Column() { this.StepShortcuts() }
            .width('100%')
            .transition(this.stepTransition())
        } else {
          Column() { this.StepSample() }
            .width('100%')
            .transition(this.stepTransition())
        }
      }
      .layoutWeight(1)
      .width('100%')
      .constraintSize({ maxWidth: CONTENT_MAX_WIDTH })
      .justifyContent(FlexAlign.Center)

      // ─── 底部按钮（与内容同宽，宽屏不再通栏）───
      Row({ space: 12 }) {
        this.BottomButtons()
      }
      .width('100%')
      .constraintSize({ maxWidth: CONTENT_MAX_WIDTH })
    }
    .width('100%').height('100%')
    .padding({ left: 24, right: 24, top: 32, bottom: 32 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.surface0'))
  }

  @Builder
  StepIndicator() {
    Row({ space: 8 }) {
      ForEach(this.stepIndices, (idx: number) => {
        Row()
          .width(idx === this.currentStep ? 24 : 8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(idx === this.currentStep ? $r('app.color.primary') : $r('app.color.surface2'))
          .animation({ duration: 220, curve: Curve.EaseOut })
      }, (idx: number) => idx.toString())
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  StepWelcome() {
    Column({ space: 24 }) {
      TablerIcon('command', 40, $r('app.color.primary'))
      Text('欢迎使用 Callaite')
        .fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        .textAlign(TextAlign.Center)
      Text('兼具 Obsidian 与 Logseq 亮点的鸿蒙知识库')
        .fontSize(16).fontColor($r('app.color.muted_text'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Column({ space: 12 }) {
        this.FeatureItem('calendar', '日志', '每天自动创建日志页，记录生活与工作')
        this.FeatureItem('edit', '大纲编辑', '点击 Block 直接编辑，支持缩进折叠')
        this.FeatureItem('link', '双向链接', '[[页面]] 引用自动建立关联图谱')
        this.FeatureItem('layout-sidebar', '多端自适应', '手机悬浮玻璃操作，桌面标签页布局')
      }
      .width('100%').padding(20).backgroundColor($r('app.color.surface1')).borderRadius(12)
    }
    .width('100%').alignItems(HorizontalAlign.Center)
  }

  @Builder
  StepGraph() {
    Column({ space: 20 }) {
      TablerIcon('folder', 40, $r('app.color.primary'))
      Text('创建 Graph')
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        .textAlign(TextAlign.Center)
      Text('Callaite 将所有笔记以 Markdown 文件存储在你选择的本地目录中，支持随时导出与备份。')
        .fontSize(15).fontColor($r('app.color.muted_text'))
        .textAlign(TextAlign.Center)
      Text('当前使用应用默认目录，可在「设置」中切换。')
        .fontSize(13).fontColor($r('app.color.muted_text'))
        .textAlign(TextAlign.Center)
    }
    .width('100%').alignItems(HorizontalAlign.Center)
  }

  @Builder
  StepShortcuts() {
    Column({ space: 20 }) {
      TablerIcon('keyboard', 40, $r('app.color.primary'))
      Text('快捷键')
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        .textAlign(TextAlign.Center)

      Column({ space: 10 }) {
        ForEach(this.shortcuts, (item: ShortcutItem) => {
          Row({ space: 12 }) {
            Text(item.keys)
              .fontSize(13).fontColor($r('app.color.primary'))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor($r('app.color.surface2')).borderRadius(6)
            Text(item.desc)
              .fontSize(14).fontColor($r('app.color.text'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
        }, (item: ShortcutItem) => item.keys)
      }
      .width('100%').padding(16).backgroundColor($r('app.color.surface1')).borderRadius(12)
    }
    .width('100%').alignItems(HorizontalAlign.Center)
  }

  @Builder
  StepSample() {
    Column({ space: 20 }) {
      TablerIcon('check', 40, $r('app.color.primary'))
      Text('一切就绪')
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        .textAlign(TextAlign.Center)
      Text('现在开始记录你的第一条笔记。点击「开始使用」进入应用，开启你的知识管理之旅。')
        .fontSize(15).fontColor($r('app.color.muted_text'))
        .textAlign(TextAlign.Center)
    }
    .width('100%').alignItems(HorizontalAlign.Center)
  }

  @Builder
  FeatureItem(icon: string, title: string, desc: string) {
    Row({ space: 12 }) {
      TablerIcon(icon, 22, $r('app.color.primary'))
      Column({ space: 2 }) {
        Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text'))
        Text(desc).fontSize(13).fontColor($r('app.color.muted_text'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  /**
   * 主按钮 —— 正常/悬停/按下三态。
   */
  @Builder
  PrimaryButton(label: string, onTap: () => void) {
    Button(label)
      .fontSize(16)
      .layoutWeight(1)
      .height(44)
      .type(ButtonType.Capsule)
      .backgroundColor($r('app.color.primary'))
      .fontColor($r('app.color.on_primary'))
      .stateStyles({
        normal: { .opacity(1) },
        pressed: { .opacity(0.78) }
      })
      .animation({ duration: 140, curve: Curve.EaseOut })
      .onClick(() => {
        onTap();
      })
  }

  /**
   * 次按钮 —— 正常/悬停/按下三态。
   */
  @Builder
  SecondaryButton(label: string, onTap: () => void) {
    Button(label)
      .fontSize(15)
      .layoutWeight(1)
      .height(44)
      .type(ButtonType.Capsule)
      .backgroundColor($r('app.color.surface2'))
      .fontColor($r('app.color.text'))
      .stateStyles({
        normal: { .opacity(1) },
        pressed: { .opacity(0.7) }
      })
      .animation({ duration: 140, curve: Curve.EaseOut })
      .onClick(() => {
        onTap();
      })
  }

  @Builder
  BottomButtons() {
    if (this.currentStep > 0) {
      this.SecondaryButton('上一步', () => {
        if (this.currentStep > 0) {
          this.currentStep = this.currentStep - 1;
        }
      })
    }
    if (this.currentStep < 3) {
      this.PrimaryButton('下一步', () => {
        if (this.currentStep < 3) {
          this.currentStep = this.currentStep + 1;
        }
      })
    } else {
      Button('开始使用')
        .fontSize(16)
        .layoutWeight(1)
        .height(48)
        .type(ButtonType.Capsule)
        .backgroundColor($r('app.color.primary'))
        .fontColor($r('app.color.on_primary'))
        .stateStyles({
          normal: { .opacity(1) },
          pressed: { .opacity(0.78) }
        })
        .animation({ duration: 140, curve: Curve.EaseOut })
        .onClick(() => {
          AppStorage.setOrCreate('callaite_onboarded', true);
          AppState.setCurrentPage('Journal');
          // 立即持久化引导完成标志（若应用在此刻被杀死，下次启动不再显示引导）
          StatePersistence.save();
        })
    }
  }
}
