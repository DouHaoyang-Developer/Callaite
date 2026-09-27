import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * RawfileWebBridge —— U3.5：向「$rawfile 承载页」注入内容的统一通道。
 *
 * 背景：CDN 离线化后，3 个渲染器不再把内容拼进 HTML 字符串（那条路依赖
 * `Web({src:'<html>'})`，而 HTML 字符串页面无法解析 `resource://rawfile/...`），
 * 改成 `Web({src: $rawfile('libs/<库>/page.html')})` + `runJavaScript(...)` 注入。
 *
 * 承载页统一暴露两个全局函数（三个页面完全一致，便于 ArkTS 侧只写一处）：
 *   · `window.u35Push(jsonText)`          —— 一次性投递一个 JSON 文档（字符串）
 *   · `window.u35Chunk(i, total, part)`   —— 分块投递，`i === total-1` 时页内自行拼装并调用 u35Push
 *
 * 转义方案（关键，避免引号/换行/反斜杠/中文把脚本拼炸）：
 *   载荷先用 `JSON.stringify(对象)` 生成 JSON **文本**，再用 `literal()` 把它变成
 *   一个**合法的 JS 字符串字面量**（含首尾引号）拼进 `window.u35Push(...)`。
 *   即 `window.u35Push("{...}")`，页内 `JSON.parse` 还原 —— 全程不手拼字符串。
 *   额外把 U+2028/U+2029 显式转义（JSON 里合法、旧版 JS 字符串字面量里非法）。
 *
 * 大载荷：单次 runJavaScript 的载荷超过 CHUNK 字符时自动切块，串行投递
 *   （后一块在前一块 resolve 之后再发，保证页内拼装顺序正确）。
 *   代理对（emoji）被切在中间也安全：ES2019 的 well-formed JSON.stringify
 *   会把落单代理项转义成 `\uXXXX`，拼接后逐字节还原。
 */
export class RawfileWebBridge {
  /** 单次 runJavaScript 的载荷上限（字符）。60KB 远低于引擎限制，且足以覆盖超长代码块。 */
  private static readonly CHUNK: number = 60000;

  /**
   * 把任意文本变成合法的 JS 字符串字面量（含引号）。
   * JSON.stringify 负责转义 `"` `\` 换行 回车 制表符 与全部控制字符；
   * 中文/emoji 不转义（原样传入，页内 JSON.parse 还原）。
   */
  static literal(text: string): string {
    let out: string = JSON.stringify(text);
    out = out.replace(new RegExp('\u2028', 'g'), '\\u2028');
    out = out.replace(new RegExp('\u2029', 'g'), '\\u2029');
    return out;
  }

  /** 需要的分块数（空载荷也算 1 块，保证页面至少被通知一次）。 */
  private static chunkCount(length: number): number {
    const n: number = Math.ceil(length / RawfileWebBridge.CHUNK);
    return n < 1 ? 1 : n;
  }

  /**
   * 投递一个 JSON 载荷（由调用方用 JSON.stringify(显式 interface 变量) 生成）。
   * 失败只写 hilog（tag 由调用方给出），不抛出。
   */
  static push(controller: webview.WebviewController, json: string, tag: string): void {
    const total: number = RawfileWebBridge.chunkCount(json.length);
    if (total <= 1) {
      controller.runJavaScript('window.u35Push(' + RawfileWebBridge.literal(json) + ')')
        .catch((e: Error) => {
          hilog.error(0x0000, tag, 'u35Push 注入失败: ' + e.message);
        });
      return;
    }
    hilog.info(0x0000, tag, '载荷 ' + json.length.toString() + ' 字符，分 ' + total.toString() + ' 块注入');
    RawfileWebBridge.pushChunk(controller, json, 0, total, tag);
  }

  private static pushChunk(controller: webview.WebviewController, json: string,
    index: number, total: number, tag: string): void {
    if (index >= total) {
      return;
    }
    const start: number = index * RawfileWebBridge.CHUNK;
    const part: string = json.substring(start, start + RawfileWebBridge.CHUNK);
    const js: string = 'window.u35Chunk(' + index.toString() + ',' + total.toString()
      + ',' + RawfileWebBridge.literal(part) + ')';
    controller.runJavaScript(js).then(() => {
      RawfileWebBridge.pushChunk(controller, json, index + 1, total, tag);
    }).catch((e: Error) => {
      hilog.error(0x0000, tag, 'u35Chunk ' + index.toString() + '/' + total.toString() + ' 注入失败: ' + e.message);
    });
  }
}
