import { fileIo as fs } from '@kit.CoreFileKit';
import { SubscriptionService } from './SubscriptionService';

export class CloudSyncService {
  private static readonly CLOUD_DIR = '/data/storage/el2/cloud/files';
  private static syncEnabled: boolean = true;

  static initCloudDir(): void {
    try {
      if (!fs.accessSync(CloudSyncService.CLOUD_DIR)) {
        fs.mkdirSync(CloudSyncService.CLOUD_DIR, true);
      }
    } catch (_e) {
      // ignore
    }
  }

  static syncFileToCloud(localPath: string, fileName: string): boolean {
    try {
      const cloudPath = CloudSyncService.CLOUD_DIR + '/' + fileName;
      const content = fs.readTextSync(localPath);
      if (!content) return false;
      const file = fs.openSync(cloudPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
      return true;
    } catch (e) {
      return false;
    }
  }

  static syncFileFromCloud(fileName: string, localPath: string): boolean {
    try {
      const cloudPath = CloudSyncService.CLOUD_DIR + '/' + fileName;
      if (!fs.accessSync(cloudPath)) return false;
      const content = fs.readTextSync(cloudPath);
      if (!content) return false;
      const file = fs.openSync(localPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
      return true;
    } catch (e) {
      return false;
    }
  }

  static listCloudFiles(): string[] {
    try {
      const entries = fs.listFileSync(CloudSyncService.CLOUD_DIR);
      const result: string[] = [];
      for (let i = 0; i < entries.length; i++) {
        if (entries[i].endsWith('.md')) result.push(entries[i]);
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
}
