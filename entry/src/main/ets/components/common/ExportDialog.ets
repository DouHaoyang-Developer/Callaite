import { fileIo as fs } from '@kit.CoreFileKit';
import { ExportService } from '../../services/ExportService';
import { WorkspaceService } from '../../services/WorkspaceService';
import { PickerService } from '../../services/PickerService';
import { FileService } from '../../services/FileService';
// 与 ExportService 内部写入文件时使用的同一套命名映射，避免两边推导结果不一致
import { pageNameToFileName } from '../../core/models/Page';

/**
 * ExportDialog — 导出对话框。
 *
 * UI：
 *  - 选择导出格式（Markdown / HTML）
 *  - 选择范围（当前页 / 全部页面）
 *  - 通过系统保存选择器指定保存位置
 *  - 导出成功后显示提示
 *
 * 接线说明：既有 ExportService 的入参是「目标目录」，而 pickSaveTarget 返回的是
 * 「目标文件 URI」。为不改写导出实现，这里采用两段式：
 *   ① 先让用户选定保存位置（URI，同时确定文件名与后缀）；
 *   ② 再把既有导出流程写到应用缓存目录（复用原逻辑），最后把产物拷到该 URI。
 */
@Component
export struct ExportDialog {
  @Prop pageName: string = '';
  @State format: string = 'md';
  @State scope: string = 'current';
  /** 保存目标 URI（由系统保存选择器返回；空串 = 尚未选择） */
  @State saveUri: string = '';
  @State saveName: string = '';
  @State message: string = '';
  @State messageType: string = '';
  @State isExporting: boolean = false;
  /** 选择位置进行中：防重复拉起并在按钮上给出可见反馈 */
  @State isPicking: boolean = false;

  // 关闭回调
  onClose: () => void = () => {};

  aboutToAppear(): void {
    // 不再预填目录：保存位置由系统保存选择器决定（见 pickSaveTarget）。
    // 每次打开对话框都要求重新选择，避免复用上一次的授权 URI（跨进程重启后可能已失效）。
    this.saveUri = '';
    this.saveName = '';
  }

  // ─── 保存位置与文件名 ───

  private suffix(): string {
    if (this.format === 'html') return '.html';
    if (this.format === 'opml') return '.opml';
    return '.md';
  }

  private suggestedFileName(): string {
    if (this.format === 'opml') {
      return 'callaite.opml';
    }
    if (this.scope === 'current' && this.pageName.length > 0) {
      return pageNameToFileName(this.pageName) + this.suffix();
    }
    return 'callaite-export' + this.suffix();
  }

  /**
   * 拉起系统保存选择器选择保存位置。
   * 失败/取消时给出可读提示（拉起异常已由 PickerService hilog.error 打点）。
   */
  private async pickSaveTarget(): Promise<void> {
    if (this.isPicking) {
      return;
    }
    this.isPicking = true;
    try {
      const fileName = this.suggestedFileName();
      const uri = await PickerService.pickSaveTarget(fileName, this.suffix());
      if (uri.length === 0) {
        this.showMsg('未选择保存位置', 'error');
        return;
      }
      this.saveUri = uri;
      this.saveName = fileName;
      this.showMsg('保存到：' + fileName, 'info');
    } finally {
      this.isPicking = false;
    }
  }

  /**
   * 执行导出。
   *
   * 既有 ExportService 仍按「目标目录」写入，这里的目录固定为应用缓存下的
   * 临时目录；写完后再把产物拷贝到用户选定的 URI。
   */
  private async doExport(): Promise<void> {
    if (this.saveUri.length === 0) {
      this.showMsg('请先选择保存位置', 'error');
      return;
    }
    if (this.scope === 'current' && this.pageName.length === 0) {
      this.showMsg('当前未打开任何页面', 'error');
      return;
    }

    this.isExporting = true;
    this.message = '';

    const ctx = FileService.getContext();
    if (!ctx) {
      this.isExporting = false;
      this.showMsg('应用上下文未就绪，无法导出', 'error');
      return;
    }
    const tempDir = ctx.cacheDir + '/export_tmp';
    try {
      fs.mkdirSync(tempDir, true);
    } catch (_e) {
      // 目录已存在时也会抛错；真正的写入失败由下方 ExportService 结果暴露
    }

    const fileName = this.produceFiles(tempDir);

    this.isExporting = false;
    if (fileName.length === 0) {
      this.showMsg('导出失败，请重试', 'error');
      return;
    }

    const src = tempDir + '/' + fileName;
    if (!ExportDialog.exists(src)) {
      // 产物文件名推导与 ExportService 实际写入不一致时的兜底：宁可报错也不谎报成功
      this.showMsg('导出产物缺失：' + fileName, 'error');
      return;
    }
    if (PickerService.copyUriToSandbox(src, this.saveUri)) {
      // 系统保存选择器一次只给一个文件 URI：范围=全部页面时其余产物仍在缓存临时目录，
      // 这里明确告知，避免用户误以为全部页面都已落到所选位置。
      this.showMsg('已导出：' + fileName + this.scopeNote(), 'success');
    } else {
      this.showMsg('写入所选位置失败：' + fileName + '（导出中未能覆盖该文件）', 'error');
    }
  }

  /**
   * 多页面导出时补充说明：所选位置只收到 1 个文件。
   */
  private scopeNote(): string {
    if (this.scope !== 'all') {
      return '';
    }
    const total = WorkspaceService.getInstance().getAllPages().length;
    return '；所选位置仅保存该 1 个文件（共 ' + total.toString() +
      ' 个页面已导出至缓存临时目录）。如需逐页保存到本地，请选择「当前页」。';
  }

  private static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_e) {
      return false;
    }
  }

  /**
   * 复用原有导出流程写入临时目录，返回实际产出的文件名；
   * 失败返回空串。产物文件名由 ExportService 决定（与其内部命名保持一致）。
   */
  private produceFiles(tempDir: string): string {
    let ok = false;

    if (this.format === 'md') {
      if (this.scope === 'current') {
        ok = ExportService.exportPage(this.pageName, tempDir);
        if (ok) return pageNameToFileName(this.pageName) + '.md';
        return '';
      }
      const n = ExportService.exportAll(tempDir);
      return n > 0 ? 'callaite-export.md' : '';
    }

    if (this.format === 'html') {
      if (this.scope === 'current') {
        ok = ExportService.exportHtmlToFile(this.pageName, tempDir);
        if (ok) return pageNameToFileName(this.pageName) + '.html';
        return '';
      }
      const n = ExportService.exportAllHtml(tempDir);
      return n > 0 ? 'callaite-export.html' : '';
    }

    // opml
    if (this.scope === 'current') {
      const names: string[] = [this.pageName];
      ok = ExportService.exportOpmlToFile(names, tempDir);
    } else {
      const pages = WorkspaceService.getInstance().getAllPages();
      const names: string[] = [];
      for (let i = 0; i < pages.length; i++) {
        names.push(pages[i].originalName);
      }
      ok = ExportService.exportOpmlToFile(names, tempDir);
    }
    return ok ? 'callaite.opml' : '';
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

      // 保存位置
      Column({ space: 6 }) {
        Text('保存位置')
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
        Row({ space: 8 }) {
          Button(this.isPicking ? '选择中…' : '选择保存位置').type(ButtonType.Capsule)
            .fontSize(13)
            .fontColor($r('app.color.on_primary'))
            .backgroundColor($r('app.color.primary'))
            .layoutWeight(1)
            .enabled(!this.isPicking)
            .onClick(() => { this.pickSaveTarget(); })
          Text(this.suggestedFileName())
            .fontSize(11)
            .fontColor($r('app.color.muted_text'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        Text(this.saveUri.length === 0
          ? '尚未选择保存位置'
          : '已选：' + this.saveName)
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
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
        Button('取消').type(ButtonType.Capsule)
          .fontSize(13)
          .fontColor($r('app.color.text'))
          .backgroundColor($r('app.color.surface2'))
          .layoutWeight(1)
          .onClick(() => { this.onClose(); })
        Button(this.isExporting ? '导出中…' : '导出').type(ButtonType.Capsule)
          .fontSize(13)
          .fontColor($r('app.color.on_primary'))
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
      .fontColor(this.format === value ? $r('app.color.on_primary') : $r('app.color.text'))
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
      .fontColor(this.scope === value ? $r('app.color.on_primary') : $r('app.color.text'))
      .backgroundColor(this.scope === value
        ? $r('app.color.primary') : $r('app.color.surface1'))
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(6)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .onClick(() => { this.scope = value; })
  }
}
