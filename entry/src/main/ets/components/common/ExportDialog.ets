import { ExportService } from '../../services/ExportService';
import { WorkspaceService } from '../../services/WorkspaceService';

/**
 * ExportDialog — 导出对话框。
 *
 * UI：
 *  - 选择导出格式（Markdown / HTML）
 *  - 选择范围（当前页 / 全部页面）
 *  - 目标目录输入框
 *  - 导出成功后显示提示
 */
@Component
export struct ExportDialog {
  @Prop pageName: string = '';
  @State format: string = 'md';
  @State scope: string = 'current';
  @State targetDir: string = '';
  @State message: string = '';
  @State messageType: string = '';
  @State isExporting: boolean = false;

  // 关闭回调
  onClose: () => void = () => {};

  aboutToAppear(): void {
    const ws = WorkspaceService.getInstance();
    try {
      const repo = ws.getDataStore().getFileRepo();
      this.targetDir = repo.joinPath(repo.getGraphRoot(), 'export');
    } catch (_e) {
      this.targetDir = '';
    }
  }

  /**
   * 执行导出。
   */
  private doExport(): void {
    if (this.targetDir.length === 0) {
      this.showMsg('请输入目标目录', 'error');
      return;
    }
    if (this.scope === 'current' && this.pageName.length === 0) {
      this.showMsg('当前未打开任何页面', 'error');
      return;
    }

    this.isExporting = true;
    this.message = '';

    let ok = false;
    let detail = '';

    if (this.format === 'md') {
      if (this.scope === 'current') {
        ok = ExportService.exportPage(this.pageName, this.targetDir);
        detail = this.pageName + '.md';
      } else {
        const n = ExportService.exportAll(this.targetDir);
        ok = n > 0;
        detail = '共 ' + n.toString() + ' 个页面';
      }
    } else if (this.format === 'html') {
      if (this.scope === 'current') {
        ok = ExportService.exportHtmlToFile(this.pageName, this.targetDir);
        detail = this.pageName + '.html';
      } else {
        const n = ExportService.exportAllHtml(this.targetDir);
        ok = n > 0;
        detail = '共 ' + n.toString() + ' 个页面';
      }
    } else {
      // opml
      if (this.scope === 'current') {
        const names: string[] = [this.pageName];
        ok = ExportService.exportOpmlToFile(names, this.targetDir);
        detail = this.pageName + '.opml';
      } else {
        const pages = WorkspaceService.getInstance().getAllPages();
        const names: string[] = [];
        for (let i = 0; i < pages.length; i++) {
          names.push(pages[i].originalName);
        }
        ok = ExportService.exportOpmlToFile(names, this.targetDir);
        detail = '共 ' + names.length.toString() + ' 个页面';
      }
    }

    this.isExporting = false;
    if (ok) {
      this.showMsg('导出成功：' + detail, 'success');
    } else {
      this.showMsg('导出失败：' + detail, 'error');
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
        Text('导出')
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

      // 格式选择
      Column({ space: 6 }) {
        Text('格式')
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
        Row({ space: 8 }) {
          this.FormatBtn('Markdown', 'md')
          this.FormatBtn('HTML', 'html')
          this.FormatBtn('OPML', 'opml')
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 范围选择
      Column({ space: 6 }) {
        Text('范围')
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
        Row({ space: 8 }) {
          this.ScopeBtn('当前页', 'current')
          this.ScopeBtn('全部页面', 'all')
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 目标目录
      Column({ space: 6 }) {
        Text('目标目录')
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
        TextInput({ text: this.targetDir, placeholder: '请输入目标目录路径' })
          .fontSize(13)
          .fontColor($r('app.color.text'))
          .backgroundColor($r('app.color.surface1'))
          .borderRadius(6)
          .width('100%')
          .onChange((v: string) => { this.targetDir = v; })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 当前页面提示
      if (this.scope === 'current') {
        Text('当前页面：' + this.pageName)
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
        Button(this.isExporting ? '导出中…' : '导出')
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.primary'))
          .layoutWeight(1)
          .enabled(!this.isExporting)
          .onClick(() => { this.doExport(); })
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
  FormatBtn(label: string, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.format === value ? Color.White : $r('app.color.text'))
      .backgroundColor(this.format === value
        ? $r('app.color.primary') : $r('app.color.surface1'))
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(6)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .onClick(() => { this.format = value; })
  }

  @Builder
  ScopeBtn(label: string, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.scope === value ? Color.White : $r('app.color.text'))
      .backgroundColor(this.scope === value
        ? $r('app.color.primary') : $r('app.color.surface1'))
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(6)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .onClick(() => { this.scope = value; })
  }
}
