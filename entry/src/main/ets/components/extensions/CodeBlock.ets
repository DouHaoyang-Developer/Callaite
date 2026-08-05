import { webview } from '@kit.ArkWeb';
import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ThemeManager } from '../common/ThemeManager';

/**
 * CodeBlock — 代码块语法高亮渲染组件。
 * 使用 WebView + highlight.js (CDN) 实现代码高亮。
 *  - 亮色主题: github.min.css
 *  - 暗色主题: github-dark.min.css
 * 自动跟随应用主题；顶部栏显示语言名与复制按钮。
 * WebView 高度通过 JS 桥接回传实际内容高度实现自适应。
 */
@Component
export struct CodeBlock {
  @Prop @Watch('onInputChanged') code: string = '';
  @Prop @Watch('onInputChanged') language: string = '';
  @State private htmlContent: string = '';
  @State private webHeight: number = 200;
  @State private copied: boolean = false;
  @StorageLink('callaite_themeMode') @Watch('onThemeChanged') private themeMode: string = 'system';
  @StorageLink('callaite_systemColorMode') @Watch('onThemeChanged') private systemColorMode: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridgeObj: CodeBlockBridge = new CodeBlockBridge(this);

  aboutToAppear(): void {
    this.htmlContent = this.buildHtml();
  }

  onInputChanged(): void {
    this.htmlContent = this.buildHtml();
  }

  onThemeChanged(): void {
    this.htmlContent = this.buildHtml();
  }

  /**
   * 转义 HTML 特殊字符，防止代码内容破坏 HTML 结构。
   */
  escapeHtml(str: string): string {
    return str
      .replace(new RegExp('&', 'g'), '&amp;')
      .replace(new RegExp('<', 'g'), '&lt;')
      .replace(new RegExp('>', 'g'), '&gt;')
      .replace(new RegExp('"', 'g'), '&quot;')
      .replace(new RegExp("'", 'g'), '&#39;');
  }

  /**
   * 构建完整 HTML 文档：加载 highlight.js 与主题 CSS，包裹代码并触发高亮。
   */
  buildHtml(): string {
    const dark: boolean = ThemeManager.isDarkMode();
    const themeName: string = dark ? 'github-dark' : 'github';
    const bg: string = dark ? '#0d1117' : '#f6f8fa';
    const fg: string = dark ? '#c9d1d9' : '#24292f';
    const lang: string = this.language ? this.language : 'plaintext';
    const langClass: string = `language-${lang}`;
    const escaped: string = this.escapeHtml(this.code);

    return `<!DOCTYPE html><html><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/${themeName}.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<style>
*{margin:0;padding:0;box-sizing:border-box;}
body{background:${bg};color:${fg};padding:12px 14px;-webkit-overflow-scrolling:touch;}
pre{margin:0;padding:0;background:transparent;white-space:pre-wrap;word-break:break-word;}
code{font-family:'SF Mono','JetBrains Mono',Monaco,Consolas,monospace;font-size:13px;line-height:1.5;background:transparent;padding:0;}
</style></head><body>
<pre><code class="${langClass}">${escaped}</code></pre>
<script>
try{hljs.highlightAll();}catch(e){}
function notifyHeight(){
  var h=document.body.scrollHeight;
  if(window.nativeProxy&&h>0){window.nativeProxy.onHeightReady(h);}
}
window.addEventListener('load',function(){setTimeout(notifyHeight,50);});
setTimeout(notifyHeight,200);
</script>
</body></html>`;
  }

  /**
   * 复制代码到系统剪贴板，并在按钮上短暂显示「已复制」状态。
   */
  copyCode(): void {
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.code);
    pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
      this.copied = true;
      setTimeout(() => { this.copied = false; }, 2000);
    }).catch((_err: BusinessError) => {
      // 复制失败：静默忽略
    });
  }

  build() {
    Column() {
      // 顶部语言标签栏 + 复制按钮
      Row() {
        Text(this.language ? this.language : 'text')
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
          .fontFamily('monospace')
        Blank()
        Row() {
          TablerIcon(this.copied ? 'check' : 'copy', 14, $r('app.color.muted_text'))
          Text(this.copied ? '已复制' : '复制')
            .fontSize(12)
            .fontColor($r('app.color.muted_text'))
            .margin({ left: 4 })
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(4)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => this.copyCode())
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.surface1'))
      .border({ width: { bottom: 1 }, color: { bottom: $r('app.color.border') } })

      // 代码高亮渲染区
      Web({ src: this.htmlContent, controller: this.controller })
        .width('100%')
        .height(this.webHeight)
        .backgroundColor($r('app.color.surface1'))
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .javaScriptProxy({
          object: this.bridgeObj,
          name: 'nativeProxy',
          methodList: ['onHeightReady'],
          controller: this.controller
        })
        .onPageEnd(() => {
          // 页面加载完成后主动测量一次高度
          try {
            this.controller.runJavaScript(
              'setTimeout(function(){if(window.nativeProxy){window.nativeProxy.onHeightReady(document.body.scrollHeight);}},50);'
            );
          } catch (_e) {
            // ignore
          }
        })
    }
    .width('100%')
    .borderRadius(6)
    .clip(true)
    .backgroundColor($r('app.color.surface1'))
    .border({ width: 1, color: $r('app.color.border') })
  }
}

/**
 * CodeBlockBridge — JS 桥接对象。
 * 被 WebView JavaScript 调用，回传内容实际高度以自适应 WebView 高度。
 */
class CodeBlockBridge {
  private parent: CodeBlock;
  constructor(parent: CodeBlock) { this.parent = parent; }

  onHeightReady(height: number): void {
    if (height > 0) {
      this.parent.webHeight = height;
    }
  }
}
