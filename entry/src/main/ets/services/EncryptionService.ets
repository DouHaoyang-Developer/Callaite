import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from './FileService';

/**
 * 密钥材料查询结果。
 * 不变量：要么 bytes 非空，要么 error 非空，绝不会「两者都空」——
 * 避免调用方把一次失败误当成「拿到了一把空密钥」。
 */
interface KeyMaterialResult {
  bytes: Uint8Array | undefined;
  error: string;
}

/**
 * EncryptionService — 端云协同内容加密。
 *
 * 密钥（AES-256，32 字节）持久化位置：**系统 AssetStoreKit（关键资产存储）**。
 * 存储介质由 AssetStore 托管并加密，应用进程无法直接读取明文密钥。
 *
 * 历史实现曾把密钥以 base64 明文写入沙箱文件 `callaite_encryption.key`，
 * 这是被安全审查定性的真实缺陷。本实现改为：
 *   首次运行若 AssetStore 无密钥而旧明文文件存在 → 读出原密钥写入 AssetStore
 *   → 校验回读一致 → 覆写擦除并删除旧文件。
 * **不轮换密钥**：始终沿用同一把密钥，既有密文继续可解。
 *
 * 失败处理：AssetStore 读写失败会 hilog.error 并置 errorMessage，
 * 密钥保持 undefined（encrypt/decrypt 返回 undefined），
 * 绝不回退到空密钥或新随机密钥——那会让既有数据「看起来损坏」。
 */
export class EncryptionService {
  private static key: cryptoFramework.SymKey | undefined;
  private static readonly KEY_FILE_NAME = 'callaite_encryption.key';
  /** AssetStore 中该密钥的别名（AssetStore 内唯一标识）。 */
  private static readonly ASSET_ALIAS = 'callaite_encryption_key_v1';
  /** 最后一次初始化失败原因；空串表示无错误。 */
  private static errorMessage: string = '';
  private static readonly DOMAIN: number = 0x0000;
  private static readonly TAG: string = 'EncryptionService';
  private static readonly KEY_SIZE_BYTES = 32;

  static async init(): Promise<void> {
    // 密钥已就绪则复用，避免每次加解密都重新访问 AssetStore。
    if (EncryptionService.key) {
      return;
    }

    const result = await EncryptionService.loadOrCreateKeyMaterial();
    if (result.bytes === undefined) {
      const reason = result.error !== '' ? result.error : 'key material unavailable';
      EncryptionService.errorMessage = reason;
      hilog.error(EncryptionService.DOMAIN, EncryptionService.TAG,
        'Encryption key unavailable, encrypt/decrypt will fail: %{public}s', reason);
      return;
    }

    try {
      const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
      const keyBlob: cryptoFramework.DataBlob = { data: result.bytes };
      EncryptionService.key = await symKeyGenerator.convertKey(keyBlob);
      EncryptionService.errorMessage = '';
    } catch (e) {
      const err = e as BusinessError;
      EncryptionService.errorMessage = 'convertKey failed: ' + EncryptionService.errText(err);
      hilog.error(EncryptionService.DOMAIN, EncryptionService.TAG,
        'Failed to convert key material: %{public}s', EncryptionService.errText(err));
    }
  }

  /**
   * 最近一次 init() 的失败原因；空串表示正常。
   * 供上层（设置页/诊断）判断加密能力是否可用——失败不再静默。
   */
  static getLastError(): string {
    return EncryptionService.errorMessage;
  }

  /**
   * 加载密钥材料（32 字节）。按优先级：
   *   1. AssetStore 已有 → 直接使用（不做轮换）；
   *   2. AssetStore 无、旧明文文件在 → 迁移到 AssetStore，成功后抹掉旧文件；
   *   3. 两者皆无 → 生成新随机密钥写入 AssetStore（原行为）。
   */
  private static async loadOrCreateKeyMaterial(): Promise<KeyMaterialResult> {
    const stored = await EncryptionService.readAssetKey();

    if (stored.bytes) {
      return stored;
    }
    if (stored.error !== '') {
      // AssetStore 真实故障（服务不可用/IPC 失败/参数错误…）。
      // 此时不能新建密钥：既有资产可能仍在，换钥匙等于让历史密文永久不可解。
      return stored;
    }

    // 到这里说明 AssetStore 明确返回 NOT_FOUND。
    const legacy = EncryptionService.loadLegacyKeyFile();
    if (legacy.error !== '') {
      // 旧明文文件存在但内容不可用：必须显式失败。
      // 若此时静默生成新密钥，旧密文将再也解不开——正是要避免的「看起来损坏」。
      return legacy;
    }
    if (legacy.bytes) {
      return await EncryptionService.migrateLegacyKey(legacy.bytes);
    }

    // 全新安装：生成新密钥并入库。
    return await EncryptionService.createFreshKey();
  }

  /**
   * 从 AssetStore 读取密钥。
   * error 为空串仅表示「AssetStore 明确回答：不存在」，真实故障会给出可读文案。
   */
  private static async readAssetKey(): Promise<KeyMaterialResult> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS,
      EncryptionService.stringToUint8Array(EncryptionService.ASSET_ALIAS));
    // ALL 表示同时返回属性与明文。
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    // 与写入时保持一致（AssetStore 会把该属性纳入匹配）。
    query.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);

    let res: Array<asset.AssetMap> = [];
    try {
      res = await asset.query(query);
    } catch (e) {
      const err = e as BusinessError;
      if (err.code === asset.ErrorCode.NOT_FOUND) {
        return EncryptionService.failure('');
      }
      return EncryptionService.failure(
        'AssetStore query failed: ' + EncryptionService.errText(err));
    }

    // 契约上未命中会抛 NOT_FOUND，这里防御性检查空结果。
    if (!res || res.length === 0) {
      return EncryptionService.failure('');
    }
    const secret = res[0].get(asset.Tag.SECRET);
    if (!(secret instanceof Uint8Array) || secret.length !== EncryptionService.KEY_SIZE_BYTES) {
      const got: number = secret instanceof Uint8Array ? secret.length : -1;
      return EncryptionService.failure(
        'AssetStore returned unexpected key size: ' + got.toString() +
          ' (expected ' + EncryptionService.KEY_SIZE_BYTES.toString() + ')');
    }
    const bytes: KeyMaterialResult = { bytes: secret, error: '' };
    return bytes;
  }

  /**
   * 旧明文密钥文件读取（迁移来源）。
   * 只读不删——删除必须等 AssetStore 写入并回读校验成功之后。
   * 文件不存在 → bytes/error 皆空；文件在但内容非法 → error 非空（显式失败）。
   */
  private static loadLegacyKeyFile(): KeyMaterialResult {
    const keyPath = EncryptionService.legacyKeyPath();
    if (keyPath === '') {
      return EncryptionService.failure(
        'App context unavailable, cannot look for legacy key file');
    }

    let exists = false;
    try {
      exists = fs.accessSync(keyPath);
    } catch (e) {
      const err = e as BusinessError;
      return EncryptionService.failure(
        'Failed to access legacy key file: ' + EncryptionService.errText(err));
    }
    if (!exists) {
      return EncryptionService.failure('');
    }

    let raw = '';
    try {
      raw = fs.readTextSync(keyPath).trim();
    } catch (e) {
      const err = e as BusinessError;
      return EncryptionService.failure(
        'Failed to read legacy key file: ' + EncryptionService.errText(err));
    }
    if (raw === '') {
      // 空文件无从取密钥：继续走「生成新密钥」即可，不是错误。
      hilog.warn(EncryptionService.DOMAIN, EncryptionService.TAG,
        'Legacy key file is empty, will generate a new key');
      return EncryptionService.failure('');
    }

    let decoded: Uint8Array;
    try {
      decoded = EncryptionService.base64ToUint8Array(raw);
    } catch (e) {
      const err = e as BusinessError;
      return EncryptionService.failure(
        'Legacy key file is not valid base64: ' + EncryptionService.errText(err));
    }
    if (decoded.length !== EncryptionService.KEY_SIZE_BYTES) {
      return EncryptionService.failure(
        'Legacy key file holds ' + decoded.length.toString() +
          ' bytes, expected ' + EncryptionService.KEY_SIZE_BYTES.toString());
    }
    // 回编码比对：能挡住截断/夹杂空白等「长度碰巧对但内容已损坏」的情况。
    if (EncryptionService.uint8ArrayToBase64(decoded) !== raw) {
      return EncryptionService.failure(
        'Legacy key file content is corrupted (base64 round-trip mismatch)');
    }

    const ok: KeyMaterialResult = { bytes: decoded, error: '' };
    return ok;
  }

  /**
   * 迁移：旧明文密钥 → AssetStore（**原密钥，不轮换**）。
   * 只有「写入成功 + 回读与原文逐字节一致」才擦除旧文件；
   * 任何一步失败都保留旧文件并返回错误，下次启动可重试。
   */
  private static async migrateLegacyKey(bytes: Uint8Array): Promise<KeyMaterialResult> {
    const written = await EncryptionService.writeAssetKey(bytes);
    if (written !== '') {
      await EncryptionService.removeAssetKey();
      return EncryptionService.failure('Key migration failed: ' + written);
    }

    hilog.info(EncryptionService.DOMAIN, EncryptionService.TAG,
      'Encryption key migrated to AssetStore');

    const wiped = EncryptionService.wipeLegacyKeyFile(bytes.length);
    if (!wiped) {
      // 密钥本身可用，不算致命；但明文仍在，必须留下可见告警。
      hilog.error(EncryptionService.DOMAIN, EncryptionService.TAG,
        'Legacy plaintext key file could not be erased, it is still on disk');
    }

    const migrated: KeyMaterialResult = { bytes: bytes, error: '' };
    return migrated;
  }

  /** 全新安装：生成 32 字节随机密钥并写入 AssetStore。 */
  private static async createFreshKey(): Promise<KeyMaterialResult> {
    let keyBlob: cryptoFramework.DataBlob;
    try {
      const random = cryptoFramework.createRandom();
      keyBlob = random.generateRandomSync(EncryptionService.KEY_SIZE_BYTES);
    } catch (e) {
      const err = e as BusinessError;
      return EncryptionService.failure(
        'Secure random generation failed: ' + EncryptionService.errText(err));
    }
    if (keyBlob.data.length !== EncryptionService.KEY_SIZE_BYTES) {
      return EncryptionService.failure(
        'Secure random returned ' + keyBlob.data.length.toString() + ' bytes, expected ' +
          EncryptionService.KEY_SIZE_BYTES.toString());
    }

    const written = await EncryptionService.writeAssetKey(keyBlob.data);
    if (written !== '') {
      await EncryptionService.removeAssetKey();
      return EncryptionService.failure('Failed to store new encryption key: ' + written);
    }

    hilog.info(EncryptionService.DOMAIN, EncryptionService.TAG,
      'New encryption key generated and stored in AssetStore');
    const created: KeyMaterialResult = { bytes: keyBlob.data, error: '' };
    return created;
  }

  /**
   * 写入 AssetStore 并回读校验。
   * 返回空串表示成功；非空为失败原因。
   * 回读校验是必须的：只有确认系统真的能原样取回这把密钥，才敢删掉明文来源。
   */
  private static async writeAssetKey(bytes: Uint8Array): Promise<string> {
    const attr: asset.AssetMap = new Map();
    attr.set(asset.Tag.ALIAS,
      EncryptionService.stringToUint8Array(EncryptionService.ASSET_ALIAS));
    attr.set(asset.Tag.SECRET, bytes);
    // DEVICE_FIRST_UNLOCKED：开机首次解锁后可访问（含重启后的后台云同步场景）；
    // 无锁屏密码的设备上等价于 DEVICE_POWERED_ON，因此模拟器同样可用。
    attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    // 不参与端云同步：与旧实现「仅本机文件」的暴露面保持一致。
    attr.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);

    try {
      await asset.add(attr);
    } catch (e) {
      const err = e as BusinessError;
      return 'asset.add failed: ' + EncryptionService.errText(err);
    }

    const readback = await EncryptionService.verifyReadback(bytes);
    if (readback !== '') {
      return 'read-back verification failed: ' + readback;
    }
    return '';
  }

  /** 回读 AssetStore 并与期望字节逐字节比对。返回空串表示一致。 */
  private static async verifyReadback(expected: Uint8Array): Promise<string> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS,
      EncryptionService.stringToUint8Array(EncryptionService.ASSET_ALIAS));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);

    let res: Array<asset.AssetMap> = [];
    try {
      res = await asset.query(query);
    } catch (e) {
      const err = e as BusinessError;
      return 'asset.query failed: ' + EncryptionService.errText(err);
    }
    if (!res || res.length === 0) {
      return 'asset not found right after write';
    }
    const secret = res[0].get(asset.Tag.SECRET);
    if (!(secret instanceof Uint8Array)) {
      return 'secret is missing or not a byte array';
    }
    if (secret.length !== expected.length) {
      return 'size mismatch, got ' + secret.length.toString() +
        ' expected ' + expected.length.toString();
    }
    for (let i = 0; i < expected.length; i++) {
      if (secret[i] !== expected[i]) {
        return 'byte mismatch at offset ' + i.toString();
      }
    }
    return '';
  }

  /** 删除本应用的密钥资产。用于写入/回读失败后的清理，避免留下错误密钥。 */
  private static async removeAssetKey(): Promise<void> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS,
      EncryptionService.stringToUint8Array(EncryptionService.ASSET_ALIAS));
    try {
      await asset.remove(query);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(EncryptionService.DOMAIN, EncryptionService.TAG,
        'Failed to clean up half-written key asset: %{public}s',
        EncryptionService.errText(err));
    }
  }

  /**
   * 抹除旧明文密钥文件：先原地覆写随机字节，再删除文件，最后校验确已消失。
   * 只「不再读写」是不够的——明文必须真的不在了。
   * 返回 true 表示文件已确认不存在。
   */
  private static wipeLegacyKeyFile(sizeHint: number): boolean {
    const keyPath = EncryptionService.legacyKeyPath();
    if (keyPath === '') {
      return false;
    }

    let file: fs.File | undefined = undefined;
    try {
      if (fs.accessSync(keyPath)) {
        // TRUNC 先把文件截到 0，确保即便后面的覆写失败也不会残留旧内容。
        file = fs.openSync(keyPath,
          fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        // 用密码学随机数覆写同样长度，避免留下可被判别的固定填充。
        let filler: Uint8Array;
        try {
          const random = cryptoFramework.createRandom();
          filler = random.generateRandomSync(sizeHint).data;
        } catch (_e) {
          filler = new Uint8Array(sizeHint);
        }
        fs.writeSync(file.fd, filler.buffer);
        // 归零后再写一遍，缩短底层块设备上残留旧数据的时间窗。
        fs.writeSync(file.fd, new Uint8Array(sizeHint).buffer);
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(EncryptionService.DOMAIN, EncryptionService.TAG,
        'Failed to overwrite legacy key file: %{public}s', EncryptionService.errText(err));
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
        } catch (_e) {
          // 关闭失败不阻塞后续删除
        }
      }
    }

    // 真正的抹除：删除文件。
    try {
      if (fs.accessSync(keyPath)) {
        fs.unlinkSync(keyPath);
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(EncryptionService.DOMAIN, EncryptionService.TAG,
        'Failed to delete legacy key file: %{public}s', EncryptionService.errText(err));
    }

    let stillThere = true;
    try {
      stillThere = fs.accessSync(keyPath);
    } catch (_e) {
      stillThere = false;
    }
    if (stillThere) {
      hilog.error(EncryptionService.DOMAIN, EncryptionService.TAG,
        'Legacy plaintext key file still exists after wipe attempt');
    } else {
      hilog.info(EncryptionService.DOMAIN, EncryptionService.TAG,
        'Legacy plaintext key file erased');
    }
    return !stillThere;
  }

  private static legacyKeyPath(): string {
    const ctx = FileService.getContext();
    if (!ctx) {
      return '';
    }
    return ctx.filesDir + '/' + EncryptionService.KEY_FILE_NAME;
  }

  /** 空 error 串 = 「明确不存在」；非空 = 真实失败原因。bytes 恒为 undefined。 */
  private static failure(error: string): KeyMaterialResult {
    const r: KeyMaterialResult = { bytes: undefined, error: error };
    return r;
  }

  private static errText(err: BusinessError): string {
    if (err === undefined) {
      return 'unknown error';
    }
    return 'code=' + err.code.toString() + ' ' + err.message;
  }

  static async encrypt(plaintext: string): Promise<string | undefined> {
    if (!EncryptionService.key) return undefined;
    try {
      const cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
      // AES-CBC 要求 16 字节 IV，且解密时必须使用与加密相同的 IV。
      const iv = EncryptionService.generateIv();
      const ivParams: cryptoFramework.IvParamsSpec = { iv: { data: iv }, algName: 'IvParamsSpec' };
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, EncryptionService.key, ivParams);
      const input = EncryptionService.stringToUint8Array(plaintext);
      const result = await cipher.doFinal({ data: input });
      if (result && result.data) {
        // 密文格式：base64(IV):base64(ciphertext)
        return EncryptionService.uint8ArrayToBase64(iv) + ':' + EncryptionService.uint8ArrayToBase64(result.data);
      }
      return undefined;
    } catch (e) {
      return undefined;
    }
  }

  static async decrypt(encryptedBase64: string): Promise<string | undefined> {
    if (!EncryptionService.key) return undefined;
    try {
      const parts = encryptedBase64.split(':');
      if (parts.length !== 2) {
        return undefined;
      }
      const iv = EncryptionService.base64ToUint8Array(parts[0]);
      if (iv.length !== 16) {
        return undefined;
      }
      const decipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
      const ivParams: cryptoFramework.IvParamsSpec = { iv: { data: iv }, algName: 'IvParamsSpec' };
      await decipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, EncryptionService.key, ivParams);
      const input = EncryptionService.base64ToUint8Array(parts[1]);
      const result = await decipher.doFinal({ data: input });
      if (result && result.data) {
        return EncryptionService.uint8ArrayToString(result.data);
      }
      return undefined;
    } catch (e) {
      return undefined;
    }
  }

  private static generateIv(): Uint8Array {
    // 使用密码学安全随机数生成 16 字节 IV（AES 块大小）。
    try {
      const random = cryptoFramework.createRandom();
      const blob = random.generateRandomSync(16);
      return blob.data;
    } catch (_e) {
      return new Uint8Array(16);
    }
  }

  private static uint8ArrayToBase64(data: Uint8Array): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result = '';
    for (let i = 0; i < data.length; i += 3) {
      const b1 = data[i]; const b2 = i + 1 < data.length ? data[i + 1] : 0; const b3 = i + 2 < data.length ? data[i + 2] : 0;
      result += chars.charAt(b1 >> 2) + chars.charAt(((b1 & 3) << 4) | (b2 >> 4));
      result += i + 1 < data.length ? chars.charAt(((b2 & 15) << 2) | (b3 >> 6)) : '=';
      result += i + 2 < data.length ? chars.charAt(b3 & 63) : '=';
    }
    return result;
  }

  private static base64ToUint8Array(str: string): Uint8Array {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const result = new Uint8Array(str.length * 3 / 4);
    let idx = 0;
    for (let i = 0; i < str.length; i += 4) {
      const c1 = chars.indexOf(str.charAt(i)); const c2 = chars.indexOf(str.charAt(i + 1));
      const c3 = str.charAt(i + 2) === '=' ? 0 : chars.indexOf(str.charAt(i + 2));
      const c4 = str.charAt(i + 3) === '=' ? 0 : chars.indexOf(str.charAt(i + 3));
      result[idx++] = (c1 << 2) | (c2 >> 4);
      if (str.charAt(i + 2) !== '=') result[idx++] = ((c2 & 15) << 4) | (c3 >> 2);
      if (str.charAt(i + 3) !== '=') result[idx++] = ((c3 & 3) << 6) | c4;
    }
    return result.slice(0, idx);
  }

  private static stringToUint8Array(str: string): Uint8Array {
    // 使用 UTF-8 编码，正确处理中文等多字节字符。
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(str);
  }

  private static uint8ArrayToString(data: Uint8Array): string {
    const decoder = new util.TextDecoder();
    return decoder.decodeToString(data);
  }
}
