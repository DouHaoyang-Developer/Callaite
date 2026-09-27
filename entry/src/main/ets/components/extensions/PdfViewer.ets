import { webview } from '@kit.ArkWeb';
import { fileIo as fs } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { buffer } from '@kit.ArkTS';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WorkspaceService } from '../../services/WorkspaceService';
import { FileService } from '../../services/FileService';
import { AppState } from '../../state/AppState';
import { JournalService } from '../../services/JournalService';
import { PreferencesStore } from '../../utils/PreferencesStore';

const DOMAIN = 0x0001;
const TAG = 'PdfViewer';

/** PDF 高亮专用 preferences 实例名（含模块名，稳定性要求：改名即丢数据） */
const PDF_HL_STORE_NAME = 'callaite_pdf_highlights';
/** 旧版自研持久化文件后缀：<pdf 绝对路径>.highlights.json（仅用于一次性迁移） */
const LEGACY_HL_SUFFIX = '.highlights.json';

/**
 * JS → ArkTS 桥接对象，用于接收 pdf.js 文本层中的选中文本。
 */
class PdfBridge {
  onAnnotate: (text: string, pageNumber: number) => void =
    (text: string, pageNumber: number) => {};

  annotate(text: string, pageNumber: number): void {
    this.onAnnotate(text, pageNumber);
  }
}

interface PdfHighlight {
  page: number;
  text: string;
}

/**
 * PdfViewer — PDF 阅读与标注组件（P2）。
 *
 * 通过 WebView + pdf.js CDN 渲染 PDF，文本层支持鼠标/触摸选中。
 * 选中文本后 JS 调用 window.callaitePdf.annotate(text, page) 回调到 ArkTS，
 * 再在当前页/今日日志页追加一条 Block 标注。
 */
@Component
export struct PdfViewer {
  @Prop filePath: string = '';
  @Prop fileName: string = '';
  @State private htmlContent: string = '';
  @State private highlightCount: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: PdfBridge = new PdfBridge();
  private highlights: PdfHighlight[] = [];

  aboutToAppear(): void {
    this.bridge.onAnnotate = (text: string, pageNumber: number) => {
      this.createAnnotation(text, pageNumber);
    };
    this.highlights = PdfViewer.loadHighlights(this.filePath);
    this.highlightCount = this.highlights.length;
    const dataUrl = PdfViewer.readPdfAsDataUrl(this.filePath);
    this.htmlContent = PdfViewer.buildHtml(dataUrl, PdfViewer.highlightsToJson(this.highlights));
  }

  private createAnnotation(text: string, pageNumber: number): void {
    const trimmed = text.trim();
    if (trimmed === '') {
      return;
    }
    const ws = WorkspaceService.getInstance();
    let pageName = AppState.getCurrentPage();
    if (pageName === 'Journal') {
      pageName = JournalService.getTodayDateString();
    }
    let page = ws.getPageByName(pageName);
    if (!page) {
      pageName = JournalService.getTodayDateString();
      page = ws.getPageByName(pageName);
    }
    if (!page) {
      return;
    }
    const content = 'PDF 标注 (' + this.fileName + ':' + pageNumber.toString() + '): "' + trimmed.substring(0, 200) + '"';
    ws.executeOp({
      type: 'insert-block',
      content: content,
      pageId: page.uuid,
      parentId: page.uuid,
      leftId: '',
      level: 0
    });
    ws.savePage(page.uuid);
    // 持久化页内高亮
    const highlight: PdfHighlight = { page: pageNumber, text: trimmed };
    this.highlights.push(highlight);
    const persisted: boolean = PdfViewer.saveHighlights(this.filePath, this.highlights);
    this.highlightCount = this.highlights.length;
    if (persisted) {
      promptAction.openToast({ message: '已添加 PDF 标注' }).catch(() => {});
    } else {
      // 不静默：高亮未落盘时明确告知（日志中已有 hilog.error 详情）
      promptAction.openToast({ message: '已添加 PDF 标注，但高亮保存失败' }).catch(() => {});
    }
  }

  private prevPage(): void {
    try {
      this.controller.runJavaScript('if(window.pdfGoPrev) window.pdfGoPrev();').catch(() => {});
    } catch (_e) {
      // 忽略 JS 执行异常
    }
  }

  private nextPage(): void {
    try {
      this.controller.runJavaScript('if(window.pdfGoNext) window.pdfGoNext();').catch(() => {});
    } catch (_e) {
      // 忽略 JS 执行异常
    }
  }

  private static readPdfAsDataUrl(path: string): string {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(path);
      const ab = new ArrayBuffer(stat.size);
      const readLen = fs.readSync(file.fd, ab);
      fs.closeSync(file);
      const base64 = buffer.from(ab, 0, readLen).toString('base64');
      return 'data:application/pdf;base64,' + base64;
    } catch (_e) {
      return '';
    }
  }

  private static loadHighlights(filePath: string): PdfHighlight[] {
    const ctx = FileService.getContext();
    if (!ctx) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'loadHighlights: context 未就绪，页面高亮无法读取');
      return [];
    }
    let store: preferences.Preferences;
    try {
      store = PreferencesStore.open(ctx, PDF_HL_STORE_NAME);
    } catch (e) {
      PreferencesStore.logError(PDF_HL_STORE_NAME, 'getPreferencesSync', e as Object);
      return [];
    }
    try {
      // ─── 一次性迁移 ───
      // 触发条件：preferences 中没有该 PDF 的键，且旧的 <filePath>.highlights.json 存在。
      // 只要键已存在（哪怕值是空数组的 JSON "[]"），就说明已迁移/已由新路径写过，不再读旧文件。
      if (!store.hasSync(filePath)) {
        PdfViewer.migrateLegacyHighlights(store, filePath);
      }
      if (!store.hasSync(filePath)) {
        return [];
      }
      // 值统一以 JSON 文本存储（PdfHighlight[] 不是 preferences 支持的 Array<object> 类型）
      const raw: string = store.getSync(filePath, '') as string;
      if (raw === '') {
        return [];
      }
      return JSON.parse(raw) as PdfHighlight[];
    } catch (e) {
      PreferencesStore.logError(PDF_HL_STORE_NAME, 'loadHighlights ' + filePath, e as Object);
      return [];
    }
  }

  /**
   * 把旧的 <filePath>.highlights.json 迁入 preferences，随后删除旧文件。
   *
   * 旧文件内容本身就是 PdfHighlight[] 的 JSON 文本，**原样搬入** preferences 的字符串值，
   * 因此迁移后 JSON.parse 得到的数组与迁移前逐字段一致。
   */
  private static migrateLegacyHighlights(store: preferences.Preferences, filePath: string): void {
    const legacyPath = filePath + LEGACY_HL_SUFFIX;
    let exists = false;
    try {
      exists = fs.accessSync(legacyPath);
    } catch (e) {
      PreferencesStore.logError(PDF_HL_STORE_NAME, 'accessSync(legacy)', e as Object);
      return;
    }
    if (!exists) {
      return;
    }
    try {
      const raw = fs.readTextSync(legacyPath).trim();
      if (raw !== '') {
        store.putSync(filePath, raw);
        store.flushSync();
      }
      // 迁移完成：旧文件不再是真相来源，删除它
      fs.unlinkSync(legacyPath);
      PreferencesStore.logInfo(PDF_HL_STORE_NAME, 'migrated highlights, removed ' + legacyPath);
    } catch (e) {
      PreferencesStore.logError(PDF_HL_STORE_NAME, 'migrate legacy highlights ' + legacyPath, e as Object);
    }
  }

  /**
   * 写入高亮。
   * @returns true 表示已 flush 落盘；false 表示失败（已 hilog.error，调用方据此提示用户）。
   */
  private static saveHighlights(filePath: string, highlights: PdfHighlight[]): boolean {
    const ctx = FileService.getContext();
    if (!ctx) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'saveHighlights: context 未就绪，高亮未持久化');
      return false;
    }
    try {
      const store: preferences.Preferences = PreferencesStore.open(ctx, PDF_HL_STORE_NAME);
      store.putSync(filePath, JSON.stringify(highlights));
      // XML 存储（默认）必须 flush 才真正落盘
      store.flushSync();
      return true;
    } catch (e) {
      PreferencesStore.logError(PDF_HL_STORE_NAME, 'saveHighlights ' + filePath, e as Object);
      return false;
    }
  }

  private static highlightsToJson(highlights: PdfHighlight[]): string {
    return JSON.stringify(highlights).replace(new RegExp('<', 'g'), '\\u003c');
  }

  private static buildHtml(dataUrl: string, highlightsJson: string): string {
    return `<!DOCTYPE html><html><head><meta charset="utf-8">
<script src="https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.min.js"></script>
<style>
html,body{margin:0;padding:0;background:#303032;color:#e0e0e0;}
#viewer{overflow:auto;height:100vh;text-align:center;padding:10px;}
.page{position:relative;margin:8px auto;box-shadow:0 0 10px rgba(0,0,0,.5);background:#fff;}
canvas{display:block;margin:0 auto;}
.textLayer{position:absolute;left:0;top:0;right:0;bottom:0;overflow:hidden;line-height:1;text-align:initial;}
.textLayer span{color:transparent;position:absolute;white-space:pre;cursor:text;transform-origin:0% 0%;}
::selection{background:rgba(59,130,246,.35);}
</style></head><body>
<div id="viewer"></div>
<script>
var url='${dataUrl}';
var pdfHighlights=${highlightsJson}||[];
var pdfDoc=null,pageNum=1,pageRendering=false,pageNumPending=null,scale=1.3;
pdfjsLib.GlobalWorkerOptions.workerSrc='https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.worker.min.js';
function applyHighlights(textLayer,pageNumber){
  if(!textLayer||!pdfHighlights||pdfHighlights.length===0)return;
  var spans=textLayer.querySelectorAll('span');
  if(!spans||spans.length===0)return;
  for(var h=0;h<pdfHighlights.length;h++){
    if(pdfHighlights[h].page!==pageNumber)continue;
    var target=String(pdfHighlights[h].text||'').replace(/\\s+/g,' ').trim();
    if(target.length===0)continue;
    var texts=[];
    for(var i=0;i<spans.length;i++){texts.push(spans[i].textContent||'');}
    var full=texts.join('');
    var norm=full.replace(/\\s+/g,' ');
    var idx=norm.indexOf(target);
    if(idx<0){idx=full.indexOf(target);}
    if(idx<0)continue;
    var pos=0;
    for(var j=0;j<spans.length;j++){
      var len=texts[j].length;
      var end=pos+len;
      if(end>idx&&pos<idx+target.length){
        spans[j].style.backgroundColor='rgba(255,235,59,0.45)';
      }
      pos=end;
    }
  }
}
function renderPage(num){
  pageRendering=true;
  pdfDoc.getPage(num).then(function(page){
    var viewport=page.getViewport({scale:scale});
    var viewer=document.getElementById('viewer');
    viewer.innerHTML='';
    var container=document.createElement('div');
    container.className='page';
    container.style.width=viewport.width+'px';
    container.style.height=viewport.height+'px';
    var canvas=document.createElement('canvas');
    canvas.width=viewport.width;
    canvas.height=viewport.height;
    var ctx=canvas.getContext('2d');
    container.appendChild(canvas);
    var textLayer=document.createElement('div');
    textLayer.className='textLayer';
    container.appendChild(textLayer);
    viewer.appendChild(container);
    page.render({canvasContext:ctx,viewport:viewport}).promise.then(function(){
      return page.getTextContent();
    }).then(function(textContent){
      try{
        pdfjsLib.renderTextLayer({textContentSource:textContent,container:textLayer,viewport:viewport,textDivs:[]});
      }catch(e){}
      applyHighlights(textLayer,num);
      pageRendering=false;
      if(pageNumPending!==null){renderPage(pageNumPending);pageNumPending=null;}
    }).catch(function(e){
      pageRendering=false;
      if(pageNumPending!==null){renderPage(pageNumPending);pageNumPending=null;}
    });
  });
}
function queueRenderPage(num){
  if(pageRendering){pageNumPending=num;}else{renderPage(num);}
}
window.pdfGoPrev=function(){if(pageNum<=1)return;pageNum--;queueRenderPage(pageNum);};
window.pdfGoNext=function(){if(!pdfDoc||pageNum>=pdfDoc.numPages)return;pageNum++;queueRenderPage(pageNum);};
document.addEventListener('mouseup',function(){
  var sel=window.getSelection();
  if(!sel)return;
  var text=sel.toString().replace(/\\s+/g,' ').trim();
  if(text.length>0){
    try{window.callaitePdf.annotate(text,pageNum);}catch(e){}
    pdfHighlights.push({page:pageNum,text:text});
    applyHighlights(document.querySelector('.textLayer'),pageNum);
    sel.removeAllRanges();
  }
});
pdfjsLib.getDocument(url).promise.then(function(pdf){pdfDoc=pdf;renderPage(pageNum);});
</script></body></html>`;
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Text(this.fileName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text('高亮 ' + this.highlightCount.toString())
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))

        Button('上一页').type(ButtonType.Capsule)
          .fontSize(12)
          .height(30)
          .backgroundColor($r('app.color.surface2'))
          .fontColor($r('app.color.text'))
          .onClick(() => { this.prevPage(); })

        Button('下一页').type(ButtonType.Capsule)
          .fontSize(12)
          .height(30)
          .backgroundColor($r('app.color.surface2'))
          .fontColor($r('app.color.text'))
          .onClick(() => { this.nextPage(); })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      Web({ src: this.htmlContent, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .javaScriptProxy({
          object: this.bridge,
          name: 'callaitePdf',
          methodList: ['annotate'],
          controller: this.controller
        })
        .backgroundColor('#303032')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface0'))
  }
}
