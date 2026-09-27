import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RawfileWebBridge } from '../../utils/RawfileWebBridge';

/** 注入给 libs/katex/page.html 的载荷（显式 interface —— ArkTS 不允许无类型对象字面量） */
interface MathPayload {
  formula: string;
  displayMode: boolean;
}

const MATH_TAG: string = 'Callaite/MathRenderer';

/**
 * MathRenderer — KaTeX 数学公式渲染器。
 *
 * U3.5 改造：KaTeX 由 jsdelivr CDN 改为**随包分发的 rawfile**，离线可用。
 *  - 承载页：`rawfile/libs/katex/page.html`（同目录相对引用 katex.min.js / katex.min.css）
 *  - 字体：katex.min.css 内的 `fonts/KaTeX_*.woff2` 是**相对 CSS 自身**的路径，
 *    CSS 与承载页同目录，故解析到 `libs/katex/fonts/*`（已在模拟器实测 loaded）
 *  - 内容：不再拼 HTML 字符串，改为 `runJavaScript` 注入 JSON 文档（见 RawfileWebBridge）
 *  - 对外接口（formula / displayMode 两个 @Prop）与尺寸策略完全未变
 *  - 失败可诊断：ArkTS 侧 hilog 打点 + 承载页内可见的「[公式渲染失败…]」文案，无静默白屏
 */
@Component
export struct MathRenderer {
  @Prop @Watch('onInputChanged') formula: string = '';
  @Prop @Watch('onInputChanged') displayMode: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  /** 承载页是否已 onPageEnd：未就绪前 runJavaScript 会打到上一个文档，必须守住 */
  private pageReady: boolean = false;

  onInputChanged(): void {
    this.pushContent();
  }

  /**
   * 把「公式 + 是否块级」作为一个 JSON 文档推给承载页。
   * 转义完全交给 JSON.stringify + JS 字符串字面量包装，不手拼字符串
   * （原实现把 JSON 直接嵌进 `<script>`，依赖额外的 `<` 转义，这里统一收口）。
   */
  pushContent(): void {
    if (!this.pageReady) {
      return;
    }
    const payload: MathPayload = {
      formula: this.formula,
      displayMode: this.displayMode
    };
    RawfileWebBridge.push(this.controller, JSON.stringify(payload), MATH_TAG);
  }

  build() {
    Web({ src: $rawfile('libs/katex/page.html'), controller: this.controller })
      .width(this.displayMode ? '100%' : 'auto')
      .height(this.displayMode ? 60 : 28)
      .backgroundColor(Color.Transparent)
      .javaScriptAccess(true)
      .onPageEnd(() => {
        this.pageReady = true;
        this.pushContent();
      })
      .onErrorReceive((e) => {
        hilog.error(0x0000, MATH_TAG, '承载页资源加载失败 mainFrame=' + e.request.isMainFrame().toString()
          + ' code=' + e.error.getErrorCode().toString() + ' info=' + e.error.getErrorInfo());
        if (e.request.isMainFrame()) {
          this.pageReady = false;
        }
      })
      .onHttpErrorReceive((e) => {
        // resource:// 不走 HTTP，正常情况永不触发；保留仅为失败可诊断
        hilog.error(0x0000, MATH_TAG, '承载页 HTTP 错误 code=' + e.response.getResponseCode().toString());
      })
  }
}
