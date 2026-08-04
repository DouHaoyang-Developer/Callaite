import { webview } from '@kit.ArkWeb';

/**
 * MermaidRenderer — Mermaid 图表渲染器。
 * 使用 WebView + Mermaid CDN 渲染流程图、时序图等。
 */
@Component
export struct MermaidRenderer {
  @Prop code: string = '';
  @State private htmlContent: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.buildHtml();
  }

  buildHtml(): void {
    const escaped = this.code
      .replace(new RegExp('\\\\', 'g'), '\\\\')
      .replace(new RegExp('`', 'g'), '\\`')
      .replace(new RegExp('\\$', 'g'), '\\$');

    this.htmlContent = `<!DOCTYPE html><html><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width">
<script src="https://cdn.jsdelivr.net/npm/mermaid@10.9.0/dist/mermaid.min.js"></script>
<style>body{margin:8px;padding:0;background:white;}svg{max-width:100%;}</style></head><body>
<div class="mermaid">${escaped}</div>
<script>mermaid.initialize({startOnLoad:true,theme:'default',securityLevel:'loose'});</script>
</body></html>`;
  }

  build() {
    Web({ src: this.htmlContent, controller: this.controller })
      .width('100%')
      .height(300)
      .backgroundColor(Color.White)
      .javaScriptAccess(true)
  }
}
