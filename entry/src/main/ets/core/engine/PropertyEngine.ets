import { WorkspaceService } from '../../services/WorkspaceService';
import { BlockData } from '../models/Block';
import { PropertyBag } from '../models/Property';

/**
 * PropertyEngine — 属性引擎。
 *
 * 对应 Logseq db/frontend/property.cljs + property/schema.cljs。
 *
 * 职责：
 *  - Block 属性的 CRUD（增删改查）
 *  - 属性 Schema 注册与类型校验
 *  - 按属性筛选 Block
 *  - 内置属性管理
 *
 * 注意：
 *  本文件定义了独立的 PropertyType 枚举（数值型）和 PropertySchema 接口，
 *  与 core/models/Constants.ets 中的 PropertyType（字符串型）不同，
 *  仅供 PropertyEngine 内部使用。
 */

// ─── 属性类型枚举（数值型，供 PropertyEngine 使用） ───

export enum PropertyType {
  TEXT = 0,
  NUMBER = 1,
  CHECKBOX = 2,
  DATE = 3,
  TAGS = 4,
  LIST = 5
}

// ─── 属性 Schema 接口 ───

/**
 * 单个属性 Schema 定义。
 * 描述属性的名称、类型、默认值和可选枚举值。
 */
export interface PropertySchema {
  /** 属性名 */
  name: string;
  /** 属性类型 */
  type: PropertyType;
  /** 默认值 */
  defaultValue: string;
  /** TAGS/LIST 类型的可选值列表 */
  options: string[];
}

// ─── 内置属性名列表 ───

const BUILTIN_PROPERTIES: string[] = [
  'alias',
  'tags',
  'created-at',
  'updated-at',
  'type',
  'public',
  'template',
  'template-list'
];

// ─── PropertyEngine 主体 ───

export class PropertyEngine {
  private static instance: PropertyEngine | undefined;

  // 属性 Schema 注册表
  private schemas: Map<string, PropertySchema> = new Map<string, PropertySchema>();

  static getInstance(): PropertyEngine {
    if (!PropertyEngine.instance) {
      PropertyEngine.instance = new PropertyEngine();
    }
    return PropertyEngine.instance;
  }

  // ─── Block 属性 CRUD ───

  /**
   * 设置 Block 属性。
   *
   * 如果属性已存在则更新，不存在则新增。
   * 写入前会进行 Schema 校验（若已注册 Schema）。
   * 同时更新 propertiesOrder 以保持属性显示顺序。
   *
   * @param blockUuid Block UUID
   * @param name 属性名
   * @param value 属性值
   */
  setProperty(blockUuid: string, name: string, value: string): void {
    const block = this.getBlock(blockUuid);
    if (!block) {
      return;
    }

    // Schema 校验
    if (!this.validateProperty(name, value)) {
      return;
    }

    // 设置属性值
    block.properties.set(name, value);
    block.updatedAt = Date.now();

    // 如果是新属性，追加到 propertiesOrder
    let exists = false;
    for (let i = 0; i < block.propertiesOrder.length; i++) {
      if (block.propertiesOrder[i] === name) {
        exists = true;
        break;
      }
    }
    if (!exists) {
      block.propertiesOrder.push(name);
    }

    // 持久化
    this.saveBlockPage(blockUuid);
  }

  /**
   * 获取 Block 属性值。
   *
   * @param blockUuid Block UUID
   * @param name 属性名
   * @returns 属性值；Block 不存在或属性未设置时返回空字符串
   */
  getProperty(blockUuid: string, name: string): string {
    const block = this.getBlock(blockUuid);
    if (!block) {
      return '';
    }
    return block.properties.get(name);
  }

  /**
   * 移除 Block 属性。
   *
   * 同时从 propertiesOrder 中移除对应条目。
   *
   * @param blockUuid Block UUID
   * @param name 属性名
   */
  removeProperty(blockUuid: string, name: string): void {
    const block = this.getBlock(blockUuid);
    if (!block) {
      return;
    }

    block.properties.remove(name);
    block.updatedAt = Date.now();

    // 从 propertiesOrder 中移除
    const newOrder: string[] = [];
    for (let i = 0; i < block.propertiesOrder.length; i++) {
      if (block.propertiesOrder[i] !== name) {
        newOrder.push(block.propertiesOrder[i]);
      }
    }
    block.propertiesOrder = newOrder;

    // 持久化
    this.saveBlockPage(blockUuid);
  }

  /**
   * 获取 Block 的所有属性。
   *
   * @param blockUuid Block UUID
   * @returns 属性键值对 Map；Block 不存在时返回空 Map
   */
  getAllProperties(blockUuid: string): Map<string, string> {
    const result = new Map<string, string>();
    const block = this.getBlock(blockUuid);
    if (!block) {
      return result;
    }

    const keys = block.properties.keys();
    for (let i = 0; i < keys.length; i++) {
      result.set(keys[i], block.properties.get(keys[i]));
    }
    return result;
  }

  // ─── Schema 管理 ───

  /**
   * 注册属性 Schema。
   *
   * 注册后，setProperty 会根据 Schema 进行值校验。
   * 若 Schema 已存在则覆盖。
   *
   * @param name 属性名
   * @param type 属性类型
   * @param defaultValue 默认值
   * @param options TAGS/LIST 类型的可选值列表
   */
  registerSchema(name: string, type: PropertyType, defaultValue: string, options: string[]): void {
    const schema: PropertySchema = {
      name: name,
      type: type,
      defaultValue: defaultValue,
      options: options
    };
    this.schemas.set(name, schema);
  }

  /**
   * 获取属性 Schema。
   *
   * @param name 属性名
   * @returns Schema 定义；未注册时返回 undefined
   */
  getSchema(name: string): PropertySchema | undefined {
    return this.schemas.get(name);
  }

  /**
   * 校验属性值是否符合 Schema 约束。
   *
   * - 未注册 Schema 的属性：始终通过
   * - NUMBER：必须为有效数字
   * - CHECKBOX：必须为 "true" 或 "false"
   * - DATE：必须为 yyyy-MM-dd 格式
   * - TAGS/LIST：若 options 非空，每个值必须在 options 中
   * - TEXT：始终通过
   *
   * @param name 属性名
   * @param value 待校验的值
   * @returns 校验通过返回 true，否则返回 false
   */
  validateProperty(name: string, value: string): boolean {
    const schema = this.schemas.get(name);
    if (!schema) {
      // 未注册 Schema：接受任意值
      return true;
    }

    if (schema.type === PropertyType.TEXT) {
      return true;
    }

    if (schema.type === PropertyType.NUMBER) {
      // 校验数字格式（支持负数和小数）
      const numRegex = new RegExp('^-?\\d+(\\.\\d+)?$');
      return numRegex.test(value);
    }

    if (schema.type === PropertyType.CHECKBOX) {
      return value === 'true' || value === 'false';
    }

    if (schema.type === PropertyType.DATE) {
      // 校验 yyyy-MM-dd 格式
      const dateRegex = new RegExp('^\\d{4}-\\d{2}-\\d{2}$');
      return dateRegex.test(value);
    }

    if (schema.type === PropertyType.TAGS || schema.type === PropertyType.LIST) {
      // 若 options 为空，接受任意值
      if (schema.options.length === 0) {
        return true;
      }
      // TAGS/LIST 支持逗号分隔的多值
      const values = value.split(',');
      for (let i = 0; i < values.length; i++) {
        const v = values[i].trim();
        let found = false;
        for (let j = 0; j < schema.options.length; j++) {
          if (schema.options[j] === v) {
            found = true;
            break;
          }
        }
        if (!found) {
          return false;
        }
      }
      return true;
    }

    return true;
  }

  // ─── 内置属性 ───

  /**
   * 获取内置属性名列表。
   *
   * 内置属性是 Logseq 预定义的特殊属性，具有特定语义：
   *  - alias: 页面别名
   *  - tags: 标签
   *  - created-at: 创建时间
   *  - updated-at: 更新时间
   *  - type: 页面类型
   *  - public: 是否公开
   *  - template: 模板引用
   *  - template-list: 模板列表
   */
  getBuiltinProperties(): string[] {
    const result: string[] = [];
    for (let i = 0; i < BUILTIN_PROPERTIES.length; i++) {
      result.push(BUILTIN_PROPERTIES[i]);
    }
    return result;
  }

  // ─── 属性筛选 ───

  /**
   * 按属性筛选页面中的 Block。
   *
   * 遍历页面所有 Block（含嵌套），返回 properties 中
   * 指定 key 的值等于指定 value 的 Block 列表。
   *
   * @param pageId 页面 UUID
   * @param key 属性名
   * @param value 期望的属性值（精确匹配）
   * @returns 匹配的 Block 列表
   */
  filterByProperty(pageId: string, key: string, value: string): BlockData[] {
    const result: BlockData[] = [];
    const blocks = WorkspaceService.getInstance().getDataStore().getPageBlocks(pageId);

    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];
      if (block.properties.has(key)) {
        const blockValue = block.properties.get(key);
        if (blockValue === value) {
          result.push(block);
        }
      }
    }

    return result;
  }

  // ─── 辅助方法 ───

  /**
   * 获取 Block（封装 WorkspaceService 调用）。
   */
  private getBlock(blockUuid: string): BlockData | undefined {
    return WorkspaceService.getInstance().getBlock(blockUuid);
  }

  /**
   * 保存 Block 所属的页面（封装 DataStore 调用）。
   */
  private saveBlockPage(blockUuid: string): void {
    const pageUuid = WorkspaceService.getInstance().getDataStore().getPageUuidForBlock(blockUuid);
    if (pageUuid) {
      WorkspaceService.getInstance().getDataStore().savePage(pageUuid);
    }
  }
}
