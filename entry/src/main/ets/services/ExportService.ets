import { fileIo as fs } from '@kit.CoreFileKit';
import { WorkspaceService } from './WorkspaceService';
import { BlockData } from '../core/models/Block';
import { BlockMarker } from '../core/models/Constants';

/**
 * ExportService — 导出/导入服务。
 */
export class ExportService {

  static exportPage(pageName: string, targetDir: string): boolean {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(pageName);
    if (!page) return false;
    const repo = ws.getDataStore().getFileRepo();
    const src = repo.joinPath(repo.getGraphRoot(), page.filePath);
    const dst = repo.joinPath(targetDir, page.filePath);
    try {
      const content = fs.readTextSync(src);
      if (!content) return false;
      const file = fs.openSync(dst, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
      return true;
    } catch (_e) { return false; }
  }

  static exportAll(targetDir: string): number {
    const ws = WorkspaceService.getInstance();
    const pages = ws.getAllPages();
    let count = 0;
    for (let i = 0; i < pages.length; i++) {
      if (ExportService.exportPage(pages[i].originalName, targetDir)) count++;
    }
    return count;
  }

  /**
   * 将页面 Block 转换为完整 HTML 文档。
   * - <html><head><meta charset="utf-8"><title>页面名</title><style> 基础样式</style></head><body>
   * - Block 按 level 缩进（<ul><li> 嵌套）
   * - 支持 TODO 标记、页面引用、代码块、引用块
   * - 返回完整 HTML 字符串
   */
  static exportHtml(pageName: string): string {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(pageName);
    if (!page) return '';
    const blocks = ws.getPageBlocks(page.uuid);

    let html = '<!DOCTYPE html><html lang="zh-CN"><head>';
    html += '<meta charset="utf-8">';
    html += '<meta name="viewport" content="width=device-width, initial-scale=1">';
    html += '<title>' + ExportService.escapeHtml(page.originalName) + '</title>';
    html += '<style>';
    html += 'body { font-family: -apple-system, "Helvetica Neue", "PingFang SC", Arial, sans-serif; ';
    html += 'max-width: 860px; margin: 24px auto; padding: 0 16px; color: #1A1A1A; line-height: 1.6; }';
    html += 'h1 { font-size: 28px; border-bottom: 2px solid #E8E9EA; padding-bottom: 8px; margin-bottom: 16px; }';
    html += 'ul { padding-left: 24px; list-style: disc; }';
    html += 'li { margin: 4px 0; }';
    html += 'blockquote { border-left: 3px solid #5B9BD5; margin: 8px 0; padding: 6px 12px; ';
    html += 'color: #555; background: #F6F8FA; border-radius: 0 4px 4px 0; }';
    html += 'pre { background: #F3F3F4; padding: 12px; border-radius: 6px; overflow-x: auto; margin: 8px 0; }';
    html += 'pre code { font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace; ';
    html += 'font-size: 13px; color: #1A1A1A; background: transparent; padding: 0; }';
    html += 'code { font-family: "SFMono-Regular", Consolas, monospace; font-size: 13px; ';
    html += 'background: #F3F3F4; padding: 1px 4px; border-radius: 3px; }';
    html += 'a { color: #0458A6; text-decoration: none; }';
    html += 'a:hover { text-decoration: underline; }';
    html += 'hr { border: none; border-top: 1px dashed #ccc; margin: 16px 0; }';
    html += '.task-done { text-decoration: line-through; color: #999; }';
    html += '</style>';
    html += '</head><body>';
    html += '<h1>' + ExportService.escapeHtml(page.originalName) + '</h1>';

    html += ExportService.renderBlocks(blocks, ws);

    html += '</body></html>';
    return html;
  }

  /**
   * 递归渲染 Block 列表为嵌套 <ul><li>。
   */
  private static renderBlocks(blocks: BlockData[], ws: WorkspaceService): string {
    if (blocks.length === 0) return '';
    let html = '<ul>';
    for (let i = 0; i < blocks.length; i++) {
      const b = blocks[i];
      html += '<li>' + ExportService.renderBlockContent(b);
      const children = ws.getChildrenOfBlock(b.uuid);
      if (children.length > 0) {
        html += ExportService.renderBlocks(children, ws);
      }
      html += '</li>';
    }
    html += '</ul>';
    return html;
  }

  /**
   * 渲染单个 Block 内容（识别代码块、引用块、分隔符、TODO 标记）。
   */
  private static renderBlockContent(b: BlockData): string {
    const content = b.content;

    // 代码块 ```...
    if (content.indexOf('```') === 0) {
      const inner = content.substring(3);
      // 去掉首尾可能的换行
      const trimmed = inner.charAt(0) === '\n' ? inner.substring(1) : inner;
      return '<pre><code>' + ExportService.escapeHtml(trimmed) + '</code></pre>';
    }

    // 分隔符 ---
    if (content === '---' || content === '***' || content === '___') {
      return '<hr />';
    }

    // 引用块 >
    if (content.indexOf('>') === 0) {
      const quoteBody = content.substring(1).trim();
      return '<blockquote>' + ExportService.renderInline(quoteBody) + '</blockquote>';
    }

    // TODO 标记
    let prefix = '';
    if (b.marker === BlockMarker.TODO || b.marker === BlockMarker.LATER ||
        b.marker === BlockMarker.NOW || b.marker === BlockMarker.DOING) {
      prefix = '<input type="checkbox" disabled /> ';
    } else if (b.marker === BlockMarker.DONE) {
      prefix = '<input type="checkbox" checked disabled /> ';
    } else if (b.marker === BlockMarker.CANCELLED) {
      prefix = '<input type="checkbox" disabled /> ';
    }

    return prefix + ExportService.renderInline(content);
  }

  /**
   * 渲染内联标记：页面引用 [[xxx]]、加粗 **xxx**、行内代码 `xxx`、标签 #xxx。
   */
  private static renderInline(text: string): string {
    let s = ExportService.escapeHtml(text);
    // 页面引用 [[xxx]]
    s = s.replace(new RegExp('\\[\\[([^\\]]+)\\]\\]', 'g'), '<a href="#$1">$1</a>');
    // 加粗 **xxx**
    s = s.replace(new RegExp('\\*\\*(.+?)\\*\\*', 'g'), '<strong>$1</strong>');
    // 行内代码 `xxx`
    s = s.replace(new RegExp('`([^`]+)`', 'g'), '<code>$1</code>');
    // 标签 #xxx（中文/字母/数字/连字符）
    s = s.replace(new RegExp('#([\\w\\u4e00-\\u9fa5\\-]+)', 'g'),
      '<span style="color:#5B9BD5">#$1</span>');
    return s;
  }

  /**
   * HTML 实体转义。
   */
  private static escapeHtml(s: string): string {
    let r = s;
    r = r.replace(new RegExp('&', 'g'), '&amp;');
    r = r.replace(new RegExp('<', 'g'), '&lt;');
    r = r.replace(new RegExp('>', 'g'), '&gt;');
    r = r.replace(new RegExp('"', 'g'), '&quot;');
    return r;
  }

  static exportOpml(pageNames: string[]): string {
    let opml = '<?xml version="1.0" encoding="utf-8"?><opml version="2.0"><head><title>Callaite Export</title></head><body>';
    for (let i = 0; i < pageNames.length; i++) {
      opml += '<outline text="' + pageNames[i] + '" />';
    }
    opml += '</body></opml>';
    return opml;
  }

  /**
   * 导出 OPML 到文件。
   * @param pageNames 页面名列表
   * @param targetDir 目标目录
   * @returns 是否成功
   */
  static exportOpmlToFile(pageNames: string[], targetDir: string): boolean {
    const ws = WorkspaceService.getInstance();
    const repo = ws.getDataStore().getFileRepo();
    const opml = ExportService.exportOpml(pageNames);
    const dst = repo.joinPath(targetDir, 'callaite.opml');
    try {
      const file = fs.openSync(dst, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, opml);
      fs.closeSync(file);
      return true;
    } catch (_e) { return false; }
  }

  /**
   * 导出 HTML 到文件。
   * @param pageName 页面名
   * @param targetDir 目标目录
   * @returns 是否导出成功
   */
  static exportHtmlToFile(pageName: string, targetDir: string): boolean {
    const ws = WorkspaceService.getInstance();
    const repo = ws.getDataStore().getFileRepo();
    const html = ExportService.exportHtml(pageName);
    if (html.length === 0) return false;
    const fileName = pageName.replace('/', '_') + '.html';
    const dst = repo.joinPath(targetDir, fileName);
    try {
      const file = fs.openSync(dst, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, html);
      fs.closeSync(file);
      return true;
    } catch (_e) { return false; }
  }

  /**
   * 批量导出所有页面为 HTML。
   * @param targetDir 目标目录
   * @returns 成功导出的页面数量
   */
  static exportAllHtml(targetDir: string): number {
    const ws = WorkspaceService.getInstance();
    const pages = ws.getAllPages();
    let count = 0;
    for (let i = 0; i < pages.length; i++) {
      if (ExportService.exportHtmlToFile(pages[i].originalName, targetDir)) count++;
    }
    return count;
  }

  static importMarkdown(filePath: string): boolean {
    const ws = WorkspaceService.getInstance();
    const repo = ws.getDataStore().getFileRepo();
    const name = repo.fileNameWithoutExt(filePath);
    const dst = repo.joinPath(repo.getGraphRoot(), name + '.md');
    try {
      const content = fs.readTextSync(filePath);
      if (!content) return false;
      const file = fs.openSync(dst, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
      ws.loadGraph(repo.getGraphRoot());
      return true;
    } catch (_e) { return false; }
  }
}
