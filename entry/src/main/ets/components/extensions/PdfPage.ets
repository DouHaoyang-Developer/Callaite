import { fileIo as fs } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { WorkspaceService } from '../../services/WorkspaceService';
import { PickerService } from '../../services/PickerService';
import { AppState } from '../../state/AppState';
import { TablerIcon } from '../common/Icons';
import { PdfViewer } from './PdfViewer';

/**
 * PdfPage — PDF 列表页。
 *
 * 列出知识库根目录下的 .pdf 文件，点击后在页内打开 PdfViewer。
 */
@Component
export struct PdfPage {
  @State private pdfFiles: string[] = [];
  @State private selectedFile: string = '';
  /** 选择器/拷贝进行中：防重复拉起，并在按钮上给出可见反馈 */
  @State private pickSaving: boolean = false;

  aboutToAppear(): void {
    this.loadPdfFiles();
  }

  private loadPdfFiles(): void {
    const repo = WorkspaceService.getInstance().getDataStore().getFileRepo();
    const root = repo.getGraphRoot();
    const result: string[] = [];
    try {
      const entries = fs.listFileSync(root);
      for (let i = 0; i < entries.length; i++) {
        if (entries[i].endsWith('.pdf')) {
          result.push(entries[i]);
        }
      }
    } catch (_e) {
      // 目录不可用时返回空列表
    }
    this.pdfFiles = result;
  }

  private openPdf(fileName: string): void {
    this.selectedFile = fileName;
  }

  /**
   * 「导入 PDF」——拉起系统文档选择器（DocumentViewPicker），
   * 把选中的 .pdf 拷入知识库根目录后刷新列表。
   *
   * 失败路径（均给出可读 toast，不静默）：
   *  - 用户取消：不提示、不报错；
   *  - 拉起失败 / 上下文未就绪：toast 显示 PickerService 返回的可读原因（同时 hilog.error 打点）；
   *  - 拷贝失败：toast 提示失败数量与文件类型提示。
   */
  private async importPdf(): Promise<void> {
    if (this.pickSaving) {
      return;
    }
    this.pickSaving = true;
    try {
      const filters: string[] = ['.pdf'];
      const pick = await PickerService.pickDocuments(filters, 10);
      if (!pick.success) {
        if (pick.error.length > 0) {
          promptAction.openToast({ message: pick.error }).catch(() => {});
        }
        return;
      }

      const repo = WorkspaceService.getInstance().getDataStore().getFileRepo();
      const root = repo.getGraphRoot();
      repo.ensureDir(root);

      let copied = 0;
      let failed = 0;
      let skipped = 0;
      for (let i = 0; i < pick.uris.length; i++) {
        const fileName = PickerService.fileNameOf(pick.uris[i]);
        if (fileName.length === 0 || !fileName.toLowerCase().endsWith('.pdf')) {
          skipped++;
          continue;
        }
        const dest = this.resolveFreePath(root, fileName);
        if (PickerService.copyUriToSandbox(pick.uris[i], dest)) {
          copied++;
        } else {
          failed++;
        }
      }

      this.loadPdfFiles();
      this.toastImportResult(copied, failed, skipped);
    } finally {
      this.pickSaving = false;
    }
  }

  /**
   * 生成知识库目录内不冲突的目标路径（同名时追加 -1 / -2 …）。
   */
  private resolveFreePath(root: string, fileName: string): string {
    const repo = WorkspaceService.getInstance().getDataStore().getFileRepo();
    const first = repo.joinPath(root, fileName);
    let candidate = first;
    let n = 1;
    while (PdfPage.pathExists(candidate)) {
      const dotIdx = fileName.lastIndexOf('.');
      const base = dotIdx > 0 ? fileName.substring(0, dotIdx) : fileName;
      const ext = dotIdx > 0 ? fileName.substring(dotIdx) : '';
      candidate = repo.joinPath(root, base + '-' + n.toString() + ext);
      n++;
      if (n > 100) {
        break;
      }
    }
    return candidate;
  }

  private static pathExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_e) {
      return false;
    }
  }

  private toastImportResult(copied: number, failed: number, skipped: number): void {
    let message = '';
    if (copied > 0) {
      message = '已导入 ' + copied.toString() + ' 个 PDF';
    } else if (failed === 0 && skipped > 0) {
      message = '所选文件不是 .pdf，未导入';
    } else {
      message = '导入失败';
    }
    if (failed > 0) {
      message = message + '，失败 ' + failed.toString() + ' 个';
    }
    if (skipped > 0 && copied > 0) {
      message = message + '，跳过 ' + skipped.toString() + ' 个非 PDF 文件';
    }
    promptAction.openToast({ message: message }).catch(() => {});
  }

  private fullPath(fileName: string): string {
    const repo = WorkspaceService.getInstance().getDataStore().getFileRepo();
    return repo.joinPath(repo.getGraphRoot(), fileName);
  }

  build() {
    if (this.selectedFile !== '') {
      Column() {
        Row({ space: 8 }) {
          Row() {
            TablerIcon('arrow-left', 20, $r('app.color.text'))
          }
          .width(32).height(32)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => { this.selectedFile = ''; })

          Text('PDF 阅读')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text'))
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })

        PdfViewer({ filePath: this.fullPath(this.selectedFile), fileName: this.selectedFile })
      }
      .width('100%')
      .height('100%')
    } else {
      Column({ space: 0 }) {
        Row({ space: 8 }) {
          Row() {
            TablerIcon('arrow-left', 20, $r('app.color.text'))
          }
          .width(32).height(32)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => { AppState.setCurrentPage('Journal'); })

          Text('PDF')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text'))
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })

        if (this.pdfFiles.length === 0) {
          Column({ space: 8 }) {
            TablerIcon('file-off', 40, $r('app.color.muted_text'))
            Text('暂无 PDF 文件')
              .fontSize(14)
              .fontColor($r('app.color.muted_text'))
            Text('点击「导入 PDF」从系统文件中选择，或放入知识库目录后刷新')
              .fontSize(12)
              .fontColor($r('app.color.muted_text'))

            // 空状态操作区：此前仅有图标 + 两行文案，无任何可点控件（死胡同）。
            // 主按钮 = 重新扫描知识库目录（复用本页 loadPdfFiles）；次按钮 = 拉起系统选择器导入 .pdf。
            Row({ space: 12 }) {
              Button('刷新')
                .type(ButtonType.Normal)
                .fontSize(14)
                .fontColor($r('app.color.on_primary'))
                .backgroundColor($r('app.color.primary'))
                .height(40)
                .borderRadius(6)
                .padding({ left: 24, right: 24 })
                .onClick(() => { this.loadPdfFiles(); })

              Button(this.pickSaving ? '导入中…' : '导入 PDF')
                .type(ButtonType.Normal)
                .fontSize(14)
                .fontColor($r('app.color.text'))
                .backgroundColor($r('app.color.surface2'))
                .height(40)
                .borderRadius(6)
                .padding({ left: 24, right: 24 })
                .enabled(!this.pickSaving)
                .onClick(() => { this.importPdf(); })
            }
            .margin({ top: 12 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          List({ space: 6 }) {
            ForEach(this.pdfFiles, (fileName: string) => {
              ListItem() {
                Row({ space: 10 }) {
                  TablerIcon('file', 16, $r('app.color.primary'))
                  Text(fileName)
                    .fontSize(14)
                    .fontColor($r('app.color.text'))
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 12, bottom: 12 })
                .borderRadius(6)
                .backgroundColor($r('app.color.surface1'))
                .onClick(() => { this.openPdf(fileName); })
              }
            }, (fileName: string) => fileName)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16 })
        }
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.surface0'))
    }
  }
}
