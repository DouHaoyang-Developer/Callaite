import { webview } from '@kit.ArkWeb';
import { ThemeManager } from '../common/ThemeManager';

/**
 * MermaidRenderer — Mermaid 图表渲染器。
 * 使用 WebView + Mermaid CDN 渲染流程图、时序图、甘特图等。
 * 支持主题适配（dark/light）与渲染失败回退为原始文本。
 */
@Component
export struct MermaidRenderer {
  @Prop diagram: string = '';
  @State private htmlContent: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.buildHtml();
  }

  buildHtml(): void {
    const escaped = this.diagram
      .replace(new RegExp('\\\\', 'g'), '\\\\')
      .replace(new RegExp('`', 'g'), '\\`')
      .replace(new RegExp('\\$', 'g'), '\\$');

    const isDark = ThemeManager.isDarkMode();
    const theme = isDark ? 'dark' : 'default';
    const bgColor = isDark ? '#1C1C1D' : '#FCFCFC';
    const textColor = isDark ? '#E0E0E0' : '#1A1A1A';

    this.htmlContent = `<!DOCTYPE html><html><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width">
<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
<style>body{margin:8px;padding:0;background:${bgColor};}svg{max-width:100%;}.fallback{color:${textColor};font-family:monospace;font-size:13px;white-space:pre-wrap;padding:8px;}</style></head><body>
<pre class="fallback" id="fallback" style="display:none;">${escaped}</pre>
<div class="mermaid" id="diagram">${escaped}</div>
<script>
try{
  mermaid.initialize({startOnLoad:true,theme:'${theme}',securityLevel:'loose'});
  setTimeout(function(){
    var svg=document.querySelector('#diagram svg');
    if(!svg){
      var dg=document.getElementById('diagram');
      var fb=document.getElementById('fallback');
      if(dg) dg.style.display='none';
      if(fb) fb.style.display='block';
    }
  },1200);
}catch(e){
  var dg=document.getElementById('diagram');
  var fb=document.getElementById('fallback');
  if(dg) dg.style.display='none';
  if(fb) fb.style.display='block';
}
</script>
</body></html>`;
  }

  build() {
    Web({ src: this.htmlContent, controller: this.controller })
      .width('100%')
      .height(300)
      .backgroundColor($r('app.color.surface0'))
      .javaScriptAccess(true)
  }
}
