import { PropertyType, BUILTIN_PROPERTY_NAMES } from './Constants';

// ─── PropertyBag: 替代 ArkTS 禁用的 Record<string, string> ───

/**
 * 属性键值对容器。内部使用 Map 存储，对外提供 get/set/has/keys 方法。
 * 对应 Logseq 中 Block 和 Page 的 properties map。
 */
export class PropertyBag {
  private data: Map<string, string> = new Map<string, string>();

  set(key: string, value: string): void {
    this.data.set(key, value);
  }

  get(key: string): string {
    return this.data.get(key) ?? '';
  }

  has(key: string): boolean {
    return this.data.has(key);
  }

  remove(key: string): void {
    this.data.delete(key);
  }

  keys(): string[] {
    const result: string[] = [];
    this.data.forEach((_v: string, k: string) => {
      result.push(k);
    });
    return result;
  }

  size(): number {
    return this.data.size;
  }

  forEach(callback: (key: string, value: string) => void): void {
    this.data.forEach((value: string, key: string) => {
      callback(key, value);
    });
  }

  /**
   * 序列化为 JSON 字符串用于持久化。
   * 格式：key1\x00value1\x00key2\x00value2 ...
   */
  toJSON(): string {
    const pairs: string[] = [];
    this.data.forEach((value: string, key: string) => {
      pairs.push(key);
      pairs.push(value);
    });
    return JSON.stringify(pairs);
  }

  /**
   * 从 JSON 字符串反序列化。
   */
  static fromJSON(json: string): PropertyBag {
    const bag = new PropertyBag();
    if (!json || json === '[]') {
      return bag;
    }
    try {
      const pairs: string[] = JSON.parse(json) as string[];
      if (pairs) {
        for (let i = 0; i < pairs.length; i = i + 2) {
          if (i + 1 < pairs.length) {
            bag.set(pairs[i], pairs[i + 1]);
          }
        }
      }
    } catch (_e) {
      // 解析失败返回空 bag
    }
    return bag;
  }
}

// ─── PropertySchema — 对应 Logseq property.cljs 中的 :property/schema ───

/**
 * 单个属性 Schema 定义。描述属性的名称、类型、默认值和枚举选项。
 */
export interface PropertySchema {
  name: string;
  type: PropertyType;
  description: string;
  defaultValue: string;
  options: string[]; // 枚举选项列表（用于下拉选择）
}

/**
 * 属性 Schema 注册表。管理所有自定义属性的类型定义。
 */
export class PropertySchemaRegistry {
  private schemas: Map<string, PropertySchema> = new Map<string, PropertySchema>();

  register(schema: PropertySchema): void {
    this.schemas.set(schema.name, schema);
  }

  get(name: string): PropertySchema | undefined {
    return this.schemas.get(name);
  }

  remove(name: string): void {
    this.schemas.delete(name);
  }

  getAll(): PropertySchema[] {
    const result: PropertySchema[] = [];
    this.schemas.forEach((schema: PropertySchema) => {
      result.push(schema);
    });
    return result;
  }

  /**
   * 判断属性是否为内置属性（tags, alias, created-at 等）。
   */
  static isBuiltin(name: string): boolean {
    for (let i = 0; i < BUILTIN_PROPERTY_NAMES.length; i++) {
      if (BUILTIN_PROPERTY_NAMES[i] === name) {
        return true;
      }
    }
    return false;
  }
}
