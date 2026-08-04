import { fileIo as fs } from '@kit.CoreFileKit';
import { WorkspaceService } from './WorkspaceService';

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

  static exportHtml(pageName: string): string {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(pageName);
    if (!page) return '';
    const blocks = ws.getPageBlocks(page.uuid);
    let html = '<!DOCTYPE html><html><head><meta charset="utf-8"><title>' + page.originalName + '</title></head><body>';
    html += '<h1>' + page.originalName + '</h1>';
    for (let i = 0; i < blocks.length; i++) {
      const indent = '&nbsp;'.repeat(blocks[i].level * 4);
      let line = blocks[i].content;
      line = line.replace(new RegExp('\\[\\[([^\\]]+)\\]\\]', 'g'), '<a href="$1">$1</a>');
      line = line.replace(new RegExp('\\*\\*(.+?)\\*\\*', 'g'), '<strong>$1</strong>');
      html += '<p>' + indent + line + '</p>';
    }
    html += '</body></html>';
    return html;
  }

  static exportOpml(pageNames: string[]): string {
    let opml = '<?xml version="1.0" encoding="utf-8"?><opml version="2.0"><head><title>Callaite Export</title></head><body>';
    for (let i = 0; i < pageNames.length; i++) {
      opml += '<outline text="' + pageNames[i] + '" />';
    }
    opml += '</body></opml>';
    return opml;
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
