import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemeManager } from '../common/ThemeManager';
import { RawfileWebBridge } from '../../utils/RawfileWebBridge';

/** 注入给 libs/mermaid/page.html 的载荷（显式 interface —— ArkTS 不允许无类型对象字面量） */
interface MermaidPayload {
  diagram: string;
  dark: boolean;
}

const MERMAID_TAG: string = 'Callaite/MermaidRenderer';

/**
 * MermaidRenderer — Mermaid 图表渲染器。
 *
 * U3.5 改造：mermaid 由 jsdelivr CDN 改为**随包分发的 rawfile**，离线可用。
 *  - 承载页：`rawfile/libs/mermaid/page.html`（同目录相对引用 mermaid.min.js）
 *  - 内容：不再拼 HTML 字符串（原实现先把图表源码做 HTML 实体转义再塞进 `<div class="mermaid">`），
 *    改为 `runJavaScript` 注入 JSON 文档、页内 `mermaid.render(id, text)` 直接吃**原始文本**，
 *    少一层「转义 → DOM 反解析」往返；失败时以 `textContent` 原样回退显示。
 *  - 主题：沿用 CodeBlock.ets:21-22 的 `@StorageLink` + `@Watch` 范式，明暗切换即时重渲染
 *  - 对外接口（diagram 一个 @Prop）与高度策略（300）完全未变
 */
@Component
export struct MermaidRenderer {
  @Prop @Watch('onInputChanged') diagram: string = '';
  @State private loadError: string = '';
  @StorageLink('callaite_themeMode') @Watch('onThemeChanged') private themeMode: string = 'system';
  @StorageLink('callaite_systemColorMode') @Watch('onThemeChanged') private systemColorMode: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  /** 承载页是否已 onPageEnd：未就绪前 runJavaScript 会打到上一个文档，必须守住 */
  private pageReady: boolean = false;

  onInputChanged(): void {
    this.pushContent();
  }

  onThemeChanged(): void {
    this.pushContent();
  }

  /**
   * 把「图表源码 + 明暗」作为一个 JSON 文档推给承载页。
   * 转义完全交给 JSON.stringify + JS 字符串字面量包装，不手拼字符串。
   */
  pushContent(): void {
    if (!this.pageReady) {
      return;
    }
    const payload: MermaidPayload = {
      diagram: this.diagram,
      dark: ThemeManager.isDarkMode()
    };
    RawfileWebBridge.push(this.controller, JSON.stringify(payload), MERMAID_TAG);
  }

  build() {
    Column() {
      Web({ src: $rawfile('libs/mermaid/page.html'), controller: this.controller })
        .width('100%')
        .height(300)
        .backgroundColor($r('app.color.surface0'))
        .javaScriptAccess(true)
        .onPageEnd(() => {
          this.pageReady = true;
          this.loadError = '';
          this.pushContent();
        })
        .onErrorReceive((e) => {
          const mainFrame: boolean = e.request.isMainFrame();
          hilog.error(0x0000, MERMAID_TAG, '承载页资源加载失败 mainFrame=' + mainFrame.toString()
            + ' code=' + e.error.getErrorCode().toString() + ' info=' + e.error.getErrorInfo());
          if (mainFrame) {
            this.pageReady = false;
            this.loadError = 'code ' + e.error.getErrorCode().toString() + ' ' + e.error.getErrorInfo();
          }
        })

      // 诊断条：主文档加载失败时不静默白屏
      if (this.loadError.length > 0) {
        Text('图表承载页加载失败（rawfile/libs/mermaid/page.html）：' + this.loadError)
          .fontSize(11)
          .fontColor($r('app.color.danger'))
          .width('100%')
          .padding(8)
          .backgroundColor($r('app.color.surface2'))
      }
    }
    .width('100%')
  }
}
