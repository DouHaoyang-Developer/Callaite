import { ImportService } from '../../services/ImportService';

/**
 * ImportDialog — 导入对话框。
 *
 * UI：
 *  - 选择导入文件路径（TextInput）
 *  - 选项：导入到当前页 / 作为新页面
 *  - 调用 ImportService 对应方法
 *  - 导入成功后显示 Block 数量
 */
@Component
export struct ImportDialog {
  @Prop pageName: string = '';
  @State filePath: string = '';
  @State mode: string = 'new'; // 'current' | 'new'
  @State message: string = '';
  @State messageType: string = '';
  @State isImporting: boolean = false;

  // 关闭回调
  onClose: () => void = () => {};

  /**
   * 执行导入。
   */
  private doImport(): void {
    if (this.filePath.length === 0) {
      this.showMsg('请输入文件路径', 'error');
      return;
    }
    if (this.mode === 'current' && this.pageName.length === 0) {
      this.showMsg('当前未打开任何页面', 'error');
      return;
    }

    this.isImporting = true;
    this.message = '';

    if (this.mode === 'current') {
      // 导入到当前页
      const ok = ImportService.importToPage(this.filePath, this.pageName);
      this.isImporting = false;
      if (ok) {
        // 重新解析以显示 Block 数量
        const r = ImportService.importMarkdownFile(this.filePath);
        this.showMsg('导入成功：' + r.blockCount.toString() + ' 个 Block', 'success');
      } else {
        this.showMsg('导入失败', 'error');
      }
    } else {
      // 作为新页面
      const pageName = ImportService.importAsNewPage(this.filePath);
      this.isImporting = false;
      if (pageName.length > 0) {
        const r = ImportService.importMarkdownFile(this.filePath);
        this.showMsg('导入成功：页面「' + pageName + '」，' + r.blockCount.toString() + ' 个 Block', 'success');
      } else {
        this.showMsg('导入失败', 'error');
      }
    }
  }

  private showMsg(text: string, type: string): void {
    this.message = text;
    this.messageType = type;
  }

  private msgColor(): ResourceColor {
    if (this.messageType === 'success') return $r('app.color.success');
    if (this.messageType === 'error') return $r('app.color.error');
    return $r('app.color.muted_text');
  }

  build() {
    Column({ space: 12 }) {
      // 标题栏
      Row() {
        Text('导入')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text'))
          .layoutWeight(1)
        Text('✕')
          .fontSize(16)
          .fontColor($r('app.color.muted_text'))
          .onClick(() => { this.onClose(); })
      }
      .width('100%')

      // 文件路径
      Column({ space: 6 }) {
        Text('Markdown 文件路径')
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
        TextInput({ text: this.filePath, placeholder: '例如 /data/notes/example.md' })
          .fontSize(13)
          .fontColor($r('app.color.text'))
          .backgroundColor($r('app.color.surface1'))
          .borderRadius(6)
          .width('100%')
          .onChange((v: string) => { this.filePath = v; })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 模式选择
      Column({ space: 6 }) {
        Text('导入到')
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
        Row({ space: 8 }) {
          this.ModeBtn('当前页', 'current')
          this.ModeBtn('新页面', 'new')
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 当前页面提示
      if (this.mode === 'current') {
        Text('当前页面：' + this.pageName)
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
          .width('100%')
      } else {
        Text('将以文件名作为新页面名称')
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
          .width('100%')
      }

      // 提示信息
      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(12)
          .fontColor(this.msgColor())
          .width('100%')
      }

      // 操作按钮
      Row({ space: 10 }) {
        Button('取消')
          .fontSize(13)
          .fontColor($r('app.color.text'))
          .backgroundColor($r('app.color.surface2'))
          .layoutWeight(1)
          .onClick(() => { this.onClose(); })
        Button(this.isImporting ? '导入中…' : '导入')
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.primary'))
          .layoutWeight(1)
          .enabled(!this.isImporting)
          .onClick(() => { this.doImport(); })
      }
      .width('100%')
    }
    .width(360)
    .padding(16)
    .backgroundColor($r('app.color.bg'))
    .borderRadius(10)
    .border({ width: 1, color: $r('app.color.border') })
  }

  @Builder
  ModeBtn(label: string, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.mode === value ? Color.White : $r('app.color.text'))
      .backgroundColor(this.mode === value
        ? $r('app.color.primary') : $r('app.color.surface1'))
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(6)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .onClick(() => { this.mode = value; })
  }
}
