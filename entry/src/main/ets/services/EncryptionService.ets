import { cryptoFramework } from '@kit.CryptoArchitectureKit';

export class EncryptionService {
  private static key: cryptoFramework.SymKey | undefined;

  static async init(): Promise<void> {
    try {
      const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
      const keyData = new Uint8Array(32);
      const seed = 'callaite_enc_key_v1_2026_xxxx';
      for (let i = 0; i < 32; i++) {
        keyData[i] = seed.charCodeAt(i % seed.length);
      }
      EncryptionService.key = await symKeyGenerator.convertKey({ data: keyData });
    } catch (e) {
      console.error('[Encryption] Key init failed', e);
    }
  }

  static async encrypt(plaintext: string): Promise<string | undefined> {
    if (!EncryptionService.key) return undefined;
    try {
      const cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
      const ivParams: cryptoFramework.IvParamsSpec = { iv: { data: EncryptionService.generateIv() }, algName: 'IvParamsSpec' };
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, EncryptionService.key, ivParams);
      const input = EncryptionService.stringToUint8Array(plaintext);
      const result = await cipher.doFinal({ data: input });
      if (result && result.data) {
        return EncryptionService.uint8ArrayToBase64(result.data);
      }
      return undefined;
    } catch (e) {
      return undefined;
    }
  }

  static async decrypt(encryptedBase64: string): Promise<string | undefined> {
    if (!EncryptionService.key) return undefined;
    try {
      const decipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
      const ivParams: cryptoFramework.IvParamsSpec = { iv: { data: EncryptionService.generateIv() }, algName: 'IvParamsSpec' };
      await decipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, EncryptionService.key, ivParams);
      const input = EncryptionService.base64ToUint8Array(encryptedBase64);
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
    const iv = new Uint8Array(12);
    for (let i = 0; i < 12; i++) {
      iv[i] = Math.floor(Math.random() * 256);
    }
    return iv;
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
    const result = new Uint8Array(str.length);
    for (let i = 0; i < str.length; i++) {
      result[i] = str.charCodeAt(i) & 0xFF;
    }
    return result;
  }

  private static uint8ArrayToString(data: Uint8Array): string {
    let result = '';
    for (let i = 0; i < data.length; i++) {
      result += String.fromCharCode(data[i]);
    }
    return result;
  }
}
