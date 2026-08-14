import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { FileService } from './FileService';

export class EncryptionService {
  private static key: cryptoFramework.SymKey | undefined;
  private static readonly KEY_FILE_NAME = 'callaite_encryption.key';

  static async init(): Promise<void> {
    try {
      const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
      // 密钥持久化到应用沙箱文件，保证跨启动稳定，且不再使用硬编码种子。
      const keyData = EncryptionService.loadOrCreateKeyMaterial();
      EncryptionService.key = await symKeyGenerator.convertKey({ data: keyData });
    } catch (e) {
      console.error('[Encryption] Key init failed', e);
    }
  }

  /**
   * 加载或生成密钥材料（32 字节）。
   * 首次启动生成密码学安全随机密钥并写入沙箱文件，之后复用。
   */
  private static loadOrCreateKeyMaterial(): Uint8Array {
    const ctx = FileService.getContext();
    const keyPath = ctx ? ctx.filesDir + '/' + EncryptionService.KEY_FILE_NAME : '';
    if (keyPath !== '') {
      try {
        if (fs.accessSync(keyPath)) {
          const encoded = fs.readTextSync(keyPath).trim();
          if (encoded !== '') {
            const decoded = EncryptionService.base64ToUint8Array(encoded);
            if (decoded.length === 32) {
              return decoded;
            }
          }
        }
      } catch (_e) {
        // 读取失败则重新生成
      }
    }

    let keyBlob: cryptoFramework.DataBlob;
    try {
      const random = cryptoFramework.createRandom();
      keyBlob = random.generateRandomSync(32);
    } catch (_e) {
      // 随机数生成失败时回退为空数组，convertKey 将失败并进入外层 catch
      keyBlob = { data: new Uint8Array(0) };
    }
    if (keyPath !== '') {
      try {
        const file = fs.openSync(keyPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, EncryptionService.uint8ArrayToBase64(keyBlob.data));
        fs.closeSync(file);
      } catch (_e) {
        // 写入失败不影响内存使用
      }
    }
    return keyBlob.data;
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
