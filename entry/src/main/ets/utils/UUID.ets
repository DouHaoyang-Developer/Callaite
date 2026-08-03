/**
 * UUID v4 生成器 — 对应 Logseq common/uuid.cljs。
 *
 * 使用随机数生成符合 RFC 4122 v4 格式的 UUID 字符串。
 * 格式：xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
 */
export class UUID {
  /**
   * 生成一个新的 UUID v4 字符串。
   */
  static generate(): string {
    const template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx';
    let result = '';
    for (let i = 0; i < template.length; i++) {
      const c = template.charAt(i);
      if (c === 'x') {
        const r = Math.floor(Math.random() * 16);
        result += r.toString(16);
      } else if (c === 'y') {
        // y 位为 8, 9, a, 或 b
        const r = (Math.floor(Math.random() * 4) + 8);
        result += r.toString(16);
      } else {
        result += c;
      }
    }
    return result;
  }

  /**
   * 验证字符串是否为合法的 UUID 格式。
   */
  static isValid(uuid: string): boolean {
    if (uuid.length !== 36) {
      return false;
    }
    const segments = uuid.split('-');
    if (segments.length !== 5) {
      return false;
    }
    if (segments[0].length !== 8) {
      return false;
    }
    if (segments[1].length !== 4) {
      return false;
    }
    if (segments[2].length !== 4) {
      return false;
    }
    if (segments[3].length !== 4) {
      return false;
    }
    if (segments[4].length !== 12) {
      return false;
    }
    return true;
  }

  /**
   * 截取 UUID 的前 8 位作为短标识符（用于显示）。
   */
  static short(uuid: string): string {
    if (uuid.length >= 8) {
      return uuid.substring(0, 8);
    }
    return uuid;
  }
}
