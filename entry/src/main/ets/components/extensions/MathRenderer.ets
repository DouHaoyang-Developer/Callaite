import { webview } from '@kit.ArkWeb';

/**
 * MathRenderer — KaTeX 数学公式渲染器。
 * 使用 WebView + KaTeX CDN 渲染 LaTeX 公式。
 * 支持行内公式 ($...$) 和块公式 ($$...$$)。
 */
@Component
export struct MathRenderer {
  @Prop formula: string = '';
  @Prop displayMode: boolean = false;
  @State private htmlContent: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.buildHtml();
  }

  buildHtml(): void {
    // 以 JSON 字符串字面量安全嵌入公式，避免 </script> 与模板字符串注入。
    const json = JSON.stringify(this.formula)
      .replace(new RegExp('<', 'g'), '\\u003c');
    const display = this.displayMode ? 'true' : 'false';
    const fontSize = this.displayMode ? '18px' : '15px';
    const padding = this.displayMode ? '12px' : '2px';

    this.htmlContent = `<!DOCTYPE html><html><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
<script src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
<style>body{margin:0;padding:${padding};background:transparent;font-size:${fontSize};}
.katex{font-size:${fontSize};}.katex-display{margin:0;}</style></head><body>
<script>try{katex.render(JSON.parse(${json}),document.body,{displayMode:${display},throwOnError:false});}catch(e){document.body.innerText='[公式渲染失败]';}</script>
</body></html>`;
  }

  build() {
    Web({ src: this.htmlContent, controller: this.controller })
      .width(this.displayMode ? '100%' : 'auto')
      .height(this.displayMode ? 60 : 28)
      .backgroundColor(Color.Transparent)
      .javaScriptAccess(true)
  }
}
