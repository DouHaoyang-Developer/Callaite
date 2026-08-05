import { fileIo as fs } from '@kit.CoreFileKit';

/**
 * Viewport — 白板视口状态（具名类型，替代内联对象类型以符合 ArkTS 约束）。
 */
interface Viewport {
  x: number;
  y: number;
  scale: number;
}

/**
 * WbShapeData — 白板形状数据。
 */
interface WbShapeData {
  id: string;
  /** 形状类型：'rect' | 'ellipse' | 'text' | 'line' | 'path' */
  type: string;
  x: number;
  y: number;
  width: number;
  height: number;
  rotation: number;
  fillColor: string;
  strokeColor: string;
  strokeWidth: number;
  text: string;
  zIndex: number;
}

/**
 * WbConnectorData — 形状之间的连线数据。
 */
interface WbConnectorData {
  id: string;
  fromShapeId: string;
  toShapeId: string;
  fromX: number;
  fromY: number;
  toX: number;
  toY: number;
  label: string;
  color: string;
  width: number;
}

/**
 * WbPageRefData — 页面引用块（白板中嵌入的页面快照）。
 */
interface WbPageRefData {
  id: string;
  pageName: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

/**
 * CanvasFileData — .canvas 文件的完整数据结构（JSON Canvas 1.0 规范子集）。
 */
interface CanvasFileData {
  version: string;
  shapes: WbShapeData[];
  connectors: WbConnectorData[];
  pageRefs: WbPageRefData[];
  viewport: Viewport;
}

/** 默认画布版本 */
const CANVAS_VERSION = '1.0';

/** 默认空视口 */
const DEFAULT_VIEWPORT: Viewport = { x: 0, y: 0, scale: 1 };

/**
 * WhiteboardFileService — 白板文件服务（单例）。
 *
 * 负责 .canvas JSON 文件的读写、列表、删除。
 * 使用 CoreFileKit fd-based API（openSync/writeSync/closeSync）写入，
 * readTextSync 读取，listFileSync 列目录，unlinkSync 删除。
 *
 * 对应 Callaite CanvasFileService / Logseq Whiteboards 持久化层。
 */
export class WhiteboardFileService {
  private static instance: WhiteboardFileService | undefined;

  private constructor() {}

  static getInstance(): WhiteboardFileService {
    if (!WhiteboardFileService.instance) {
      WhiteboardFileService.instance = new WhiteboardFileService();
    }
    return WhiteboardFileService.instance;
  }

  /**
   * 保存画布数据为 .canvas JSON 文件。
   * 自动创建父目录（若不存在）。
   */
  saveCanvas(filePath: string, data: CanvasFileData): void {
    const parentDir = this.getParentDir(filePath);
    if (parentDir.length > 0) {
      this.ensureDir(parentDir);
    }
    try {
      const json = JSON.stringify(data);
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, json);
      fs.closeSync(file);
    } catch (e) {
      console.error('[WhiteboardFileService] Failed to save canvas: ' + filePath, e);
    }
  }

  /**
   * 加载 .canvas 文件并解析为 CanvasFileData。
   * 文件不存在或解析失败时返回 undefined。
   */
  loadCanvas(filePath: string): CanvasFileData | undefined {
    try {
      const exists = fs.accessSync(filePath);
      if (!exists) {
        return undefined;
      }
      const raw = fs.readTextSync(filePath);
      if (raw.length === 0) {
        return undefined;
      }
      const parsed = JSON.parse(raw) as CanvasFileData;
      if (!parsed || !parsed.version) {
        return undefined;
      }
      return parsed;
    } catch (e) {
      console.error('[WhiteboardFileService] Failed to load canvas: ' + filePath, e);
      return undefined;
    }
  }

  /**
   * 列出指定目录下所有 .canvas 文件名（不含路径）。
   */
  listCanvasFiles(dir: string): string[] {
    try {
      const exists = fs.accessSync(dir);
      if (!exists) {
        return [];
      }
      const entries = fs.listFileSync(dir);
      const result: string[] = [];
      for (let i = 0; i < entries.length; i++) {
        if (entries[i].endsWith('.canvas')) {
          result.push(entries[i]);
        }
      }
      return result;
    } catch (e) {
      console.error('[WhiteboardFileService] Failed to list canvas files: ' + dir, e);
      return [];
    }
  }

  /**
   * 删除指定的 .canvas 文件。
   */
  deleteCanvas(filePath: string): void {
    try {
      fs.unlinkSync(filePath);
    } catch (e) {
      console.error('[WhiteboardFileService] Failed to delete canvas: ' + filePath, e);
    }
  }

  /**
   * 创建空画布数据（便捷工厂）。
   */
  createEmptyCanvas(): CanvasFileData {
    const data: CanvasFileData = {
      version: CANVAS_VERSION,
      shapes: [],
      connectors: [],
      pageRefs: [],
      viewport: DEFAULT_VIEWPORT
    };
    return data;
  }

  /**
   * 确保目录存在，不存在则递归创建。
   */
  private ensureDir(dir: string): void {
    if (dir.length === 0) {
      return;
    }
    try {
      const exists = fs.accessSync(dir);
      if (exists) {
        return;
      }
    } catch (_e) {
      // accessSync 抛异常视为不存在
    }
    try {
      fs.mkdirSync(dir, true);
    } catch (e) {
      console.error('[WhiteboardFileService] Failed to create directory: ' + dir, e);
    }
  }

  /**
   * 从文件路径提取父目录。
   * 例: '/a/b/c.canvas' → '/a/b'
   */
  private getParentDir(filePath: string): string {
    const idx = filePath.lastIndexOf('/');
    if (idx > 0) {
      return filePath.substring(0, idx);
    }
    return '';
  }
}

export { CanvasFileData, Viewport, WbShapeData, WbConnectorData, WbPageRefData };
