import { fileIo as fs } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { WorkspaceService } from '../../services/WorkspaceService';
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
   * 「导入 PDF」——项目当前未接入系统文件选择器（picker）能力，
   * 因此给出明确的落盘路径提示，而不是静默失效或臆造不存在的 API。
   */
  private showImportHint(): void {
    promptAction.openToast({ message: '请将 .pdf 放入知识库目录后点击刷新' }).catch(() => {});
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
            Text('将 .pdf 文件放入知识库目录后刷新')
              .fontSize(12)
              .fontColor($r('app.color.muted_text'))

            // 空状态操作区：此前仅有图标 + 两行文案，无任何可点控件（死胡同）。
            // 主按钮 = 重新扫描知识库目录（复用本页 loadPdfFiles）；次按钮 = 导入路径提示。
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

              Button('导入 PDF')
                .type(ButtonType.Normal)
                .fontSize(14)
                .fontColor($r('app.color.text'))
                .backgroundColor($r('app.color.surface2'))
                .height(40)
                .borderRadius(6)
                .padding({ left: 24, right: 24 })
                .onClick(() => { this.showImportHint(); })
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
