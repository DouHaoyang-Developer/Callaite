import { webview } from '@kit.ArkWeb';
import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemeManager } from '../common/ThemeManager';
import { TablerIcon } from '../common/Icons';
import { RawfileWebBridge } from '../../utils/RawfileWebBridge';

/** 注入给 libs/highlight/page.html 的载荷（显式 interface —— ArkTS 不允许无类型对象字面量） */
interface HighlightPayload {
  code: string;
  language: string;
  dark: boolean;
}

/** 承载页加载失败时的可见诊断（不允许静默白屏） */
interface HighlightLoadError {
  message: string;
  code: number;
  mainFrame: boolean;
}

const CODE_BLOCK_TAG: string = 'Callaite/CodeBlock';

/**
 * CodeBlock — 代码块语法高亮渲染组件。
 *
 * U3.5 改造：highlight.js 由 CDN 改为**随包分发的 rawfile**，离线可用。
 *  - 承载页：`rawfile/libs/highlight/page.html`（同目录相对引用 highlight.min.js 与两个主题 CSS）
 *  - 亮色主题: github.min.css / 暗色主题: github-dark.min.css，由承载页 JS 切换 `<link disabled>`
 *  - 内容：不再拼 HTML 字符串，改为 `runJavaScript` 注入单个 JSON 文档（见 RawfileWebBridge）
 *  - WebView 高度通过 JS 桥接回传实际内容高度实现自适应（桥接协议未变）
 */
@Component
export struct CodeBlock {
  @Prop @Watch('onInputChanged') code: string = '';
  @Prop @Watch('onInputChanged') language: string = '';
  @State private webHeight: number = 200;
  @State private copied: boolean = false;
  @State private loadError: string = '';
  @StorageLink('callaite_themeMode') @Watch('onThemeChanged') private themeMode: string = 'system';
  @StorageLink('callaite_systemColorMode') @Watch('onThemeChanged') private systemColorMode: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridgeObj: CodeBlockBridge = new CodeBlockBridge(this);
  /** 承载页是否已 onPageEnd：未就绪前 runJavaScript 会打到上一个文档，必须守住 */
  private pageReady: boolean = false;

  onInputChanged(): void {
    this.pushContent();
  }

  onThemeChanged(): void {
    this.pushContent();
  }

  /**
   * 把「代码 + 语言 + 明暗」作为一个 JSON 文档推给承载页。
   * 转义完全交给 JSON.stringify + JS 字符串字面量包装，不手拼字符串；
   * 载荷超过 60KB 由 RawfileWebBridge 自动分块串行投递。
   */
  pushContent(): void {
    if (!this.pageReady) {
      return;
    }
    const lang: string = CodeBlock.sanitizeLanguage(this.language);
    const payload: HighlightPayload = {
      code: this.code,
      language: lang,
      dark: ThemeManager.isDarkMode()
    };
    RawfileWebBridge.push(this.controller, JSON.stringify(payload), CODE_BLOCK_TAG);
  }

  /**
   * 供 JS 桥接对象回填实测内容高度（原实现由 CodeBlockBridge 直接写 private 状态，
   * 因 CodeBlock 此前从未被任何模块 import、未参与编译而未被发现）。
   */
  setWebHeight(height: number): void {
    if (height > 0) {
      this.webHeight = height > CodeBlock.MAX_WEB_HEIGHT ? CodeBlock.MAX_WEB_HEIGHT : height;
    }
  }

  /**
   * ⚠️ Web 组件高度上限（承载页自身 max-height:2000px + 内边距，这里留余量）。
   *
   * 必须有上限：ArkWeb 把一个「几万像素高」的 Web 组件整块交给渲染器时会超出
   * surface 尺寸上限而**整片不绘制** —— 实测承载页 29300px / 56600px 高时 Web 全白，
   * 而页内 DOM、innerHTML 长度、document.body.scrollHeight 全部正常（即内容在、画不出）。
   * 承载页已用 `#u35-scroll{max-height:2000px;overflow-y:auto}` 封顶并在代码块内部滚动，
   * 这里再兜一层，保证永远不把超大高度交给 Web。
   * 影响面：仅 > 约 95 行的超长代码块，改为块内滚动；普通代码块高度行为完全不变。
   */
  private static readonly MAX_WEB_HEIGHT: number = 2200;

  /**
   * 清洗语言名，仅保留字母/数字/连字符/下划线，防止属性注入。
   */
  private static sanitizeLanguage(raw: string): string {
    let out = '';
    for (let i = 0; i < raw.length; i++) {
      const ch = raw.charAt(i);
      const code = ch.charCodeAt(0);
      if ((code >= 48 && code <= 57) ||
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        ch === '-' || ch === '_') {
        out += ch;
      }
    }
    return out === '' ? 'plaintext' : out;
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

      // 代码高亮渲染区：加载随包 rawfile 承载页（离线，无 CDN）
      if (this.loadError.length > 0) {
        // 降级路径：承载页主文档加载失败 → 直接渲染等宽纯文本，不留白块、不静默
        Column() {
          Text('语法高亮不可用，已降级为等宽纯文本')
            .fontSize(11)
            .fontColor($r('app.color.danger'))
          Text('rawfile/libs/highlight/page.html 加载失败：' + this.loadError)
            .fontSize(11)
            .fontColor($r('app.color.muted_text'))
            .margin({ top: 2 })
          Text(this.code)
            .fontSize(13)
            .fontFamily('monospace')
            .lineHeight(20)
            .fontColor($r('app.color.text'))
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: 8 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(12)
        .backgroundColor($r('app.color.surface2'))
      } else {
        Web({ src: $rawfile('libs/highlight/page.html'), controller: this.controller })
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
            this.pageReady = true;
            this.loadError = '';
            // 页面库就绪后再注入内容
            this.pushContent();
            // 再主动测量一次高度（内容注入是异步的，第二次兜底）
            setTimeout(() => {
              try {
                this.controller.runJavaScript(
                  'setTimeout(function(){if(window.nativeProxy){window.nativeProxy.onHeightReady(document.body.scrollHeight);}},50);'
                );
              } catch (_e) {
                // ignore
              }
            }, 120);
          })
          .onErrorReceive((e) => {
            const detail: HighlightLoadError = {
              message: e.error.getErrorInfo(),
              code: e.error.getErrorCode(),
              mainFrame: e.request.isMainFrame()
            };
            hilog.error(0x0000, CODE_BLOCK_TAG, '承载页资源加载失败 mainFrame=' + detail.mainFrame.toString()
              + ' code=' + detail.code.toString() + ' info=' + detail.message);
            if (detail.mainFrame) {
              this.pageReady = false;
              this.loadError = 'code ' + detail.code.toString() + ' ' + detail.message;
            }
          })
      }
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
    this.parent.setWebHeight(height);
  }
}
