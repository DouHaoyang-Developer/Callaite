import { distributedKVStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

export class CollaborationService {
  private static instance: CollaborationService | undefined;
  private kvManager: distributedKVStore.KVManager | undefined;
  private kvStore: distributedKVStore.SingleKVStore | undefined;
  private storeId: string = 'callaite_collab_store';
  private listeners: Map<string, CollabCallback> = new Map<string, CollabCallback>();

  static getInstance(): CollaborationService {
    if (!CollaborationService.instance) {
      CollaborationService.instance = new CollaborationService();
    }
    return CollaborationService.instance;
  }

  async init(context: Context): Promise<void> {
    try {
      const mgrConfig: distributedKVStore.KVManagerConfig = {
        bundleName: 'com.example.callaite',
        context: context
      };
      this.kvManager = distributedKVStore.createKVManager(mgrConfig);

      const options: distributedKVStore.Options = {
        createIfMissing: true,
        encrypt: false,
        autoSync: true,
        kvStoreType: distributedKVStore.KVStoreType.SINGLE_VERSION,
        securityLevel: distributedKVStore.SecurityLevel.S2
      };

      this.kvStore = await this.kvManager.getKVStore(this.storeId, options) as distributedKVStore.SingleKVStore;

      this.kvStore.on('dataChange', distributedKVStore.SubscribeType.SUBSCRIBE_TYPE_ALL,
        (data: distributedKVStore.ChangeNotification) => {
          const entries = data.updateEntries;
          if (!entries) return;
          for (let i = 0; i < entries.length; i++) {
            const key = entries[i].key;
            const value: string = entries[i].value !== undefined ? entries[i].value.toString() : '';
            const cb = this.listeners.get(key);
            if (cb) cb(key, value);
          }
        }
      );

      console.info('[Collaboration] KVStore initialized');
    } catch (e) {
      const err = e as BusinessError;
      console.error('[Collaboration] Init failed: ' + err.message);
    }
  }

  async putBlock(blockUuid: string, value: string): Promise<void> {
    if (!this.kvStore) return;
    try { await this.kvStore.put(blockUuid, value); } catch (_e) {}
  }

  async getBlock(blockUuid: string): Promise<string | undefined> {
    if (!this.kvStore) return undefined;
    try {
      const result = this.kvStore.get(blockUuid);
      return typeof result === 'string' ? result : undefined;
    } catch (_e) { return undefined; }
  }

  async deleteBlock(blockUuid: string): Promise<void> {
    if (!this.kvStore) return;
    try { await this.kvStore.delete(blockUuid); } catch (_e) {}
  }

  onBlockChange(blockUuid: string, callback: CollabCallback): void {
    this.listeners.set(blockUuid, callback);
  }

  offBlockChange(blockUuid: string): void {
    this.listeners.delete(blockUuid);
  }

  // sync handled automatically via autoSync: true in KVStore config

  destroy(): void {
    this.listeners.clear();
    if (this.kvManager && this.kvStore) {
      this.kvManager.closeKVStore('com.example.callaite', 'callaite_collab_store');
    }
  }
}

type CollabCallback = (uuid: string, value: string) => void;
