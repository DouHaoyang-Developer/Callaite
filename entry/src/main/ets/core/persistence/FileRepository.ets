import { fileIo as fs } from '@kit.CoreFileKit';

/**
 * FileRepository — 文件持久化层。
 *
 * 使用 CoreFileKit fd-based API 进行 .md 文件的读写操作。
 * 对应 Logseq frontend/fs.cljs + handler/repo.cljs。
 *
 * 注意：ArkTS 中必须通过 fd 读写，不存在 fs.writeSync(path, string) 这类便捷方法。
 */
export class FileRepository {
  private graphRoot: string = '';

  /**
   * 设置 Graph（知识库）根目录。
   * 必须在应用启动时调用。
   */
  setGraphRoot(path: string): void {
    this.graphRoot = path;
    this.ensureDir(path);
  }

  getGraphRoot(): string {
    return this.graphRoot;
  }

  // ─── 目录操作 ───

  /**
   * 确保目录存在（递归创建）。
   */
  ensureDir(dirPath: string): void {
    try {
      const exists = fs.accessSync(dirPath);
      if (!exists) {
        fs.mkdirSync(dirPath, true);
      }
    } catch (_e) {
      try {
        fs.mkdirSync(dirPath, true);
      } catch (_innerErr) {
        console.error('[FileRepository] Failed to create directory: ' + dirPath);
      }
    }
  }

  /**
   * 列出目录下所有 .md 文件（非递归）。
   */
  listMdFiles(dirPath: string): string[] {
    try {
      const entries = fs.listFileSync(dirPath);
      const result: string[] = [];
      for (let i = 0; i < entries.length; i++) {
        if (entries[i].endsWith('.md')) {
          result.push(entries[i]);
        }
      }
      return result;
    } catch (_e) {
      return [];
    }
  }

  /**
   * 列出目录下所有子目录。
   */
  listDirs(dirPath: string): string[] {
    try {
      const result: string[] = [];
      const entries = fs.listFileSync(dirPath);
      for (let i = 0; i < entries.length; i++) {
        // 排除隐藏目录和 pages 目录本身需要的递归
        if (!entries[i].startsWith('.') && !entries[i].endsWith('.md')) {
          result.push(entries[i]);
        }
      }
      return result;
    } catch (_e) {
      return [];
    }
  }

  // ─── 文件操作 ───

  /**
   * 检查文件是否存在。
   */
  fileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_e) {
      return false;
    }
  }

  /**
   * 读取文本文件（同步）。
   */
  readTextSync(path: string): string {
    try {
      return fs.readTextSync(path);
    } catch (e) {
      console.error('[FileRepository] Failed to read file: ' + path, e);
      return '';
    }
  }

  /**
   * 写入文本文件（同步，通过 fd）。
   */
  writeTextSync(path: string, content: string): void {
    try {
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
    } catch (e) {
      console.error('[FileRepository] Failed to write file: ' + path, e);
    }
  }

  /**
   * 删除文件。
   */
  deleteFile(path: string): void {
    try {
      fs.unlinkSync(path);
    } catch (e) {
      console.error('[FileRepository] Failed to delete file: ' + path, e);
    }
  }

  /**
   * 获取文件最后修改时间戳（ms）。
   */
  getModifiedTime(path: string): number {
    try {
      const stat = fs.statSync(path);
      return stat.mtime;
    } catch (_e) {
      return 0;
    }
  }

  // ─── 路径工具 ───

  /**
   * 拼接路径。
   */
  joinPath(...segments: string[]): string {
    let result = '';
    for (let i = 0; i < segments.length; i++) {
      if (result === '') {
        result = segments[i];
      } else {
        if (result.endsWith('/')) {
          result = result + segments[i];
        } else {
          result = result + '/' + segments[i];
        }
      }
    }
    return result;
  }

  /**
   * 获取文件名（不含扩展名）。
   */
  fileNameWithoutExt(path: string): string {
    const parts = path.split('/');
    const name = parts[parts.length - 1];
    const dotIndex = name.lastIndexOf('.');
    if (dotIndex > 0) {
      return name.substring(0, dotIndex);
    }
    return name;
  }
}
