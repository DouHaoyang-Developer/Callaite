import { fileIo as fs, cloudSync, fileUri } from '@kit.CoreFileKit';
import { WorkspaceService } from './WorkspaceService';
import { EncryptionService } from './EncryptionService';
import { SubscriptionService } from './SubscriptionService';
import { FileService } from './FileService';
import { HuaweiAccountService } from './HuaweiAccountService';

/**
 * CloudSyncService — 端云协同文件同步服务。
 *
 * 使用 Core File Kit 的 cloudSync 能力：
 *  - 文件写入应用云目录（context.cloudFileDir），系统负责上云/下行
 *  - FileSync.start()/stop() 触发/停止同步任务
 *  - getCoreFileSyncState(uri) 查询单文件同步状态
 *
 * 安全：云端内容使用 AES-256-CBC 加密后写入；文件名做路径穿越校验；
 * 同步受 Free/Pro 配额门控与启用开关约束；冲突采用最后写入优先。
 */
export class CloudSyncService {
  private static syncEnabled: boolean = true;
  private static fileSync: cloudSync.FileSync | undefined;

  /** 获取应用云目录（端云协同文件所在目录）。 */
  static getCloudDir(): string {
    const ctx = FileService.getContext();
    if (ctx && ctx.cloudFileDir !== undefined && ctx.cloudFileDir !== '') {
      return ctx.cloudFileDir;
    }
    return '/data/storage/el2/cloud';
  }

  static initCloudDir(): void {
    try {
      const dir = CloudSyncService.getCloudDir();
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (_e) {
      // 云目录创建失败时不阻塞主流程
    }
  }

  /** 文件名安全校验：拒绝路径穿越、目录分隔符与非 .md 文件。 */
  private static isSafeFileName(fileName: string): boolean {
    if (fileName.length === 0) {
      return false;
    }
    if (fileName.indexOf('/') >= 0 || fileName.indexOf('\\') >= 0) {
      return false;
    }
    if (fileName.indexOf('..') >= 0) {
      return false;
    }
    return fileName.endsWith('.md');
  }

  /** 将本地页面加密后写入云目录（last-write-wins 冲突检测）。 */
  static async syncFileToCloud(localPath: string, fileName: string): Promise<boolean> {
    if (!CloudSyncService.syncEnabled) {
      return false;
    }
    if (!CloudSyncService.isSafeFileName(fileName)) {
      return false;
    }
    try {
      const cloudPath = CloudSyncService.getCloudDir() + '/' + fileName;
      const existing = CloudSyncService.listCloudFiles();
      let isNew = true;
      for (let i = 0; i < existing.length; i++) {
        if (existing[i] === fileName) {
          isNew = false;
          break;
        }
      }
      // 配额拦截：仅阻止新增文件，允许已同步文件的更新
      if (isNew && !SubscriptionService.canSyncGraph(existing.length)) {
        return false;
      }

      // 冲突检测：云端较新时跳过（避免用旧本地覆盖新云端）
      if (fs.accessSync(cloudPath)) {
        const cloudMtime = fs.statSync(cloudPath).mtime;
        const localMtime = fs.statSync(localPath).mtime;
        if (cloudMtime > localMtime) {
          return false;
        }
      }

      const content = fs.readTextSync(localPath);
      if (content === '') {
        return false;
      }
      await EncryptionService.init();
      const encrypted = await EncryptionService.encrypt(content);
      if (encrypted === undefined) {
        return false;
      }
      const file = fs.openSync(cloudPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, encrypted);
      fs.closeSync(file);
      return true;
    } catch (_e) {
      return false;
    }
  }

  /** 从云目录解密恢复本地文件（last-write-wins 冲突检测）。 */
  static async syncFileFromCloud(fileName: string, localPath: string): Promise<boolean> {
    if (!CloudSyncService.syncEnabled) {
      return false;
    }
    if (!CloudSyncService.isSafeFileName(fileName)) {
      return false;
    }
    try {
      const cloudPath = CloudSyncService.getCloudDir() + '/' + fileName;
      if (!fs.accessSync(cloudPath)) {
        return false;
      }
      // 冲突检测：本地较新时跳过（避免用旧云端覆盖新本地）
      if (fs.accessSync(localPath)) {
        const localMtime = fs.statSync(localPath).mtime;
        const cloudMtime = fs.statSync(cloudPath).mtime;
        if (localMtime > cloudMtime) {
          return false;
        }
      }
      const encrypted = fs.readTextSync(cloudPath);
      if (encrypted === '') {
        return false;
      }
      await EncryptionService.init();
      const plain = await EncryptionService.decrypt(encrypted);
      if (plain === undefined) {
        return false;
      }
      const file = fs.openSync(localPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, plain);
      fs.closeSync(file);
      return true;
    } catch (_e) {
      return false;
    }
  }

  /** 同步所有本地页面到云端，并触发系统同步任务。 */
  static async syncAll(): Promise<number> {
    if (!CloudSyncService.syncEnabled) {
      return 0;
    }
    // 绑定华为账号：端云协同依赖系统华为账号，未登录时直接跳过
    const accountOk = await HuaweiAccountService.isLoggedIn();
    if (!accountOk) {
      return 0;
    }
    const ws = WorkspaceService.getInstance();
    const repo = ws.getDataStore().getFileRepo();
    const root = repo.getGraphRoot();
    const pages = ws.getAllPages();
    let count = 0;
    for (let i = 0; i < pages.length; i++) {
      const localPath = repo.joinPath(root, pages[i].filePath);
      const ok = await CloudSyncService.syncFileToCloud(localPath, pages[i].filePath);
      if (ok) {
        count++;
      }
    }
    await CloudSyncService.startSync();
    return count;
  }

  /** 将 Block 元数据 JSON 加密后写入云目录并触发同步。 */
  static async syncMetadataToCloud(json: string): Promise<boolean> {
    if (!CloudSyncService.syncEnabled) {
      return false;
    }
    const accountOk = await HuaweiAccountService.isLoggedIn();
    if (!accountOk) {
      return false;
    }
    try {
      await EncryptionService.init();
      const encrypted = await EncryptionService.encrypt(json);
      if (encrypted === undefined) {
        return false;
      }
      const path = CloudSyncService.getCloudDir() + '/callaite_metadata.json';
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, encrypted);
      fs.closeSync(file);
      await CloudSyncService.startSync();
      return true;
    } catch (_e) {
      return false;
    }
  }

  /** 启动系统文件同步任务。 */
  static async startSync(): Promise<void> {
    try {
      await CloudSyncService.getFileSync().start();
    } catch (_e) {
      // 云状态未就绪/无网络时忽略
    }
  }

  /** 停止系统文件同步任务。 */
  static async stopSync(): Promise<void> {
    try {
      await CloudSyncService.getFileSync().stop();
    } catch (_e) {
      // 忽略
    }
  }

  /** 获取最近一次同步完成时间戳（ms），失败返回 0。 */
  static async getLastSyncTime(): Promise<number> {
    try {
      return await CloudSyncService.getFileSync().getLastSyncTime();
    } catch (_e) {
      return 0;
    }
  }

  /** 查询单文件同步状态，失败返回 -1。 */
  static getFileSyncState(fileName: string): number {
    if (!CloudSyncService.isSafeFileName(fileName)) {
      return -1;
    }
    try {
      const path = CloudSyncService.getCloudDir() + '/' + fileName;
      const uri = fileUri.getUriFromPath(path);
      return cloudSync.getCoreFileSyncState(uri);
    } catch (_e) {
      return -1;
    }
  }

  static listCloudFiles(): string[] {
    try {
      const entries = fs.listFileSync(CloudSyncService.getCloudDir());
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

  static canSync(syncedGraphCount: number): boolean {
    return SubscriptionService.canSyncGraph(syncedGraphCount);
  }

  static countSyncedGraphs(): number {
    return CloudSyncService.listCloudFiles().length;
  }

  static setEnabled(enabled: boolean): void {
    CloudSyncService.syncEnabled = enabled;
  }

  static isEnabled(): boolean {
    return CloudSyncService.syncEnabled;
  }

  private static getFileSync(): cloudSync.FileSync {
    if (!CloudSyncService.fileSync) {
      CloudSyncService.fileSync = new cloudSync.FileSync();
    }
    return CloudSyncService.fileSync;
  }
}
