import { FileService } from '../services/FileService';
import { fileIo as fs } from '@kit.CoreFileKit';

const STATE_FILE = 'app_state.json';

/**
 * 需要跨进程存活的 AppStorage 键。
 * 注：PersistentStorage.persistProp 在部分 SDK 上冷启动恢复不可靠（写入正常、恢复丢失），
 * 因此改用自管 JSON 文件，在 EntryAbility.onCreate 同步恢复、关键变更点同步保存。
 */
const STATE_KEYS: string[] = [
  'callaite_onboarded',
  'callaite_themeMode',
  'callaite_language',
  'callaite_config',
  'callaite_currentPage',
  'callaite_leftSidebarOpen',
  'callaite_rightSidebarOpen',
  'callaite_favorites',
  'callaite_recentPages',
  'callaite_rightSidebarBlocks'
];

export class StatePersistence {
  /**
   * 从状态文件恢复 AppStorage（必须在任何 UI 读取这些键之前调用）。
   */
  static load(): void {
    const ctx = FileService.getContext();
    if (!ctx) {
      return;
    }
    const path = ctx.filesDir + '/' + STATE_FILE;
    try {
      if (!fs.accessSync(path)) {
        return;
      }
      const raw = fs.readTextSync(path).trim();
      if (raw === '') {
        return;
      }
      const obj = JSON.parse(raw) as Record<string, Object>;
      for (let i = 0; i < STATE_KEYS.length; i++) {
        const k = STATE_KEYS[i];
        const v = obj[k];
        if (v !== undefined && v !== null) {
          AppStorage.setOrCreate(k, v);
        }
      }
    } catch (_e) {
      // 状态文件损坏时忽略，走默认值
    }
  }

  /**
   * 将当前 AppStorage 状态写入状态文件。
   */
  static save(): void {
    const ctx = FileService.getContext();
    if (!ctx) {
      return;
    }
    try {
      const parts: string[] = [];
      for (let i = 0; i < STATE_KEYS.length; i++) {
        const k = STATE_KEYS[i];
        const v = AppStorage.get<Object>(k);
        if (v === undefined) {
          continue;
        }
        parts.push(JSON.stringify(k) + ':' + JSON.stringify(v));
      }
      const content = '{' + parts.join(',') + '}';
      const path = ctx.filesDir + '/' + STATE_FILE;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
    } catch (_e) {
      // 保存失败不阻塞
    }
  }
}
