import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';

interface ShortcutItem {
  keys: string;
  desc: string;
}

/**
 * OnboardingPage — 首次使用引导页（4 步流程）。
 * Step 0：欢迎页
 * Step 1：创建 Graph 介绍
 * Step 2：快捷键介绍
 * Step 3：示例页面说明
 */
@Component
export struct OnboardingPage {
  @State currentStep: number = 0;
  @State showDirHint: boolean = false;
  private stepIndices: number[] = [0, 1, 2, 3];
  private shortcuts: ShortcutItem[] = [
    { keys: 'Ctrl + F', desc: '全文搜索' },
    { keys: 'Ctrl + P', desc: '命令面板' },
    { keys: 'Tab', desc: '缩进 Block' },
    { keys: 'Shift + Tab', desc: '反缩进 Block' },
    { keys: 'Enter', desc: '新建 Block' },
    { keys: 'Ctrl + Z', desc: '撤销操作' }
  ];

  build() {
    Column({ space: 24 }) {
      this.StepIndicator()

      Column({ space: 24 }) {
        if (this.currentStep === 0) {
          this.StepWelcome()
        } else if (this.currentStep === 1) {
          this.StepGraph()
        } else if (this.currentStep === 2) {
          this.StepShortcuts()
        } else {
          this.StepSample()
        }
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)

      this.BottomButtons()
    }
    .width('100%').height('100%').padding(32)
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
      Text('Logseq 风格的鸿蒙知识管理应用')
        .fontSize(16).fontColor($r('app.color.muted_text'))

      Column({ space: 12 }) {
        this.FeatureItem('calendar', '日志', '每天自动创建日志页，记录生活与工作')
        this.FeatureItem('edit', '大纲编辑', '点击 Block 直接编辑，支持缩进折叠')
        this.FeatureItem('link', '双向链接', '[[页面]] 引用自动建立关联图谱')
        this.FeatureItem('search', '全文搜索', '快捷搜索所有页面和 Block')
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
      Text('Callaite 将所有笔记以 Markdown 文件存储在你选择的本地目录中，支持随时导出与备份。')
        .fontSize(15).fontColor($r('app.color.muted_text'))
        .textAlign(TextAlign.Center)
      Button('选择目录')
        .fontSize(15).height(40).type(ButtonType.Capsule)
        .backgroundColor($r('app.color.surface2')).fontColor($r('app.color.text'))
        .onClick(() => {
          this.showDirHint = !this.showDirHint;
        })
      if (this.showDirHint) {
        Text('目录选择功能将在设置中提供，当前使用应用默认目录。')
          .fontSize(13).fontColor($r('app.color.muted_text'))
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%').alignItems(HorizontalAlign.Center)
  }

  @Builder
  StepShortcuts() {
    Column({ space: 20 }) {
      TablerIcon('keyboard', 40, $r('app.color.primary'))
      Text('快捷键')
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))

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
      Text('示例页面已就绪')
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
      Text('我们已为你创建示例页面，包含基础用法演示。点击「开始使用」进入应用，开始你的知识管理之旅。')
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
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  BottomButtons() {
    Row({ space: 12 }) {
      if (this.currentStep > 0) {
        Button('上一步')
          .fontSize(15).layoutWeight(1).height(44).type(ButtonType.Capsule)
          .backgroundColor($r('app.color.surface2')).fontColor($r('app.color.text'))
          .onClick(() => {
            if (this.currentStep > 0) {
              this.currentStep = this.currentStep - 1;
            }
          })
      }
      if (this.currentStep < 3) {
        Button('下一步')
          .fontSize(15).layoutWeight(1).height(44).type(ButtonType.Capsule)
          .backgroundColor($r('app.color.primary')).fontColor(Color.White)
          .onClick(() => {
            if (this.currentStep < 3) {
              this.currentStep = this.currentStep + 1;
            }
          })
      } else {
        Button('开始使用')
          .fontSize(16).layoutWeight(1).height(48).type(ButtonType.Capsule)
          .backgroundColor($r('app.color.primary')).fontColor(Color.White)
          .onClick(() => {
            AppStorage.setOrCreate('callaite_onboarded', true);
            AppState.setCurrentPage('Journal');
          })
      }
    }
    .width('100%')
  }
}
