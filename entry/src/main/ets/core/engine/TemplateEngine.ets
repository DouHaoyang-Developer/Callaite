/**
 * TemplateEngine — 模板引擎。
 *
 * 对应 Logseq common/template.cljs。
 *
 * 支持的模板语法：
 *  - {{date}}                           → 当前日期（context.date）
 *  - {{title}}                          → 标题（context.title）
 *  - {{date:+7d|format "YYYY-MM-DD"}}   → 日期偏移 + 格式化
 *  - {{date:-1m|format "YYYY-MM"}}     → 日期减 1 月，仅年月
 *  - {{#if condition}}content{{/if}}    → 条件渲染
 *  - {{#each varName}}content{{/each}}  → 循环（varName 为 customVars 中的逗号分隔值）
 *  - {{customVar}}                      → 自定义变量（从 customVars 获取）
 *
 * 条件语法：
 *  - {{#if status=="draft"}}...{{/if}}  → 相等比较
 *  - {{#if status!="done"}}...{{/if}}   → 不等比较
 *  - {{#if flag}}...{{/if}}             → 存在性检查（customVars 中存在且非空）
 *
 * 循环语法：
 *  - {{#each tags}}tag: {{item}}{{/each}} → 遍历 customVars["tags"] 按逗号分割的列表
 *  - {{#each customVars}}                → 遍历所有 customVars 键值对（用 {{key}} {{value}}）
 */

/**
 * 模板渲染上下文。
 */
export interface TemplateContext {
  /** 页面名 */
  pageName: string;
  /** 当前日期 yyyy-MM-dd */
  date: string;
  /** 标题 */
  title: string;
  /** 自定义变量 */
  customVars: Map<string, string>;
}

/**
 * 模板引擎单例。
 */
export class TemplateEngine {
  private static instance: TemplateEngine | undefined;

  static getInstance(): TemplateEngine {
    if (!TemplateEngine.instance) {
      TemplateEngine.instance = new TemplateEngine();
    }
    return TemplateEngine.instance;
  }

  /**
   * 渲染模板。
   *
   * 处理顺序：
   *  1. {{#if}}...{{/if}} 条件块
   *  2. {{#each}}...{{/each}} 循环块
   *  3. {{date:offset|format}} 日期偏移
   *  4. {{date}}、{{title}}、{{customVar}} 简单替换
   *
   * @param template 模板字符串
   * @param context 渲染上下文
   * @returns 渲染后的字符串
   */
  render(template: string, context: TemplateContext): string {
    let result: string = template;

    // 1. 处理条件块
    result = this.processConditionals(result, context);

    // 2. 处理循环块
    result = this.processLoops(result, context);

    // 3. 处理日期偏移
    result = this.processDateOffsets(result, context);

    // 4. 处理简单变量替换
    result = this.processSimpleVars(result, context);

    return result;
  }

  // ─── 条件处理 ───

  /**
   * 处理 {{#if condition}}content{{/if}} 条件块。
   */
  private processConditionals(template: string, context: TemplateContext): string {
    let result: string = template;
    const ifRegex = new RegExp('\\{\\{#if\\s+(.+?)\\}\\}([\\s\\S]*?)\\{\\{/if\\}\\}', 'g');

    // 循环处理（避免嵌套 if 未被匹配）
    let safetyCounter: number = 0;
    while (safetyCounter < 100) {
      const match = ifRegex.exec(result);
      if (!match) {
        break;
      }
      const condition: string = match[1];
      const content: string = match[2];
      const fullMatch: string = match[0];

      const shouldRender: boolean = this.evaluateCondition(condition.trim(), context);
      const replacement: string = shouldRender ? content : '';

      result = result.replace(fullMatch, replacement);
      // 重置 lastIndex（因为 result 已变）
      ifRegex.lastIndex = 0;
      safetyCounter++;
    }

    return result;
  }

  /**
   * 评估条件表达式。
   *
   * 支持的语法：
   *  - "key==value"  → customVars[key] === value
   *  - "key!=value"  → customVars[key] !== value
   *  - "key"         → customVars 中存在 key 且值非空
   */
  private evaluateCondition(condition: string, context: TemplateContext): boolean {
    // 检查 == 相等
    const eqIdx: number = condition.indexOf('==');
    if (eqIdx > 0) {
      const key: string = condition.substring(0, eqIdx).trim();
      const expected: string = condition.substring(eqIdx + 2).trim();
      const actual: string = context.customVars.get(key) ?? '';
      return actual === expected;
    }

    // 检查 != 不等
    const neqIdx: number = condition.indexOf('!=');
    if (neqIdx > 0) {
      const key: string = condition.substring(0, neqIdx).trim();
      const expected: string = condition.substring(neqIdx + 2).trim();
      const actual: string = context.customVars.get(key) ?? '';
      return actual !== expected;
    }

    // 存在性检查
    const value: string = context.customVars.get(condition.trim()) ?? '';
    return value !== '';
  }

  // ─── 循环处理 ───

  /**
   * 处理 {{#each varName}}content{{/each}} 循环块。
   *
   * varName 指向 customVars 中的一个键，其值按逗号分割为数组。
   * content 中的 {{item}} 被替换为当前数组元素。
   */
  private processLoops(template: string, context: TemplateContext): string {
    let result: string = template;
    const eachRegex = new RegExp('\\{\\{#each\\s+(\\S+)\\}\\}([\\s\\S]*?)\\{\\{/each\\}\\}', 'g');

    let safetyCounter: number = 0;
    while (safetyCounter < 100) {
      const match = eachRegex.exec(result);
      if (!match) {
        break;
      }
      const varName: string = match[1];
      const content: string = match[2];
      const fullMatch: string = match[0];

      // 获取变量值并按逗号分割
      const rawValue: string = context.customVars.get(varName) ?? '';
      const items: string[] = rawValue === '' ? [] : rawValue.split(',');

      // 为每个元素渲染 content
      let loopResult: string = '';
      for (let i = 0; i < items.length; i++) {
        const item: string = items[i].trim();
        const rendered: string = content.replace(new RegExp('\\{\\{item\\}\\}', 'g'), item);
        loopResult = loopResult + rendered;
      }

      result = result.replace(fullMatch, loopResult);
      eachRegex.lastIndex = 0;
      safetyCounter++;
    }

    return result;
  }

  // ─── 日期偏移 ───

  /**
   * 处理 {{date:offset|format "FORMAT"}} 日期偏移。
   */
  private processDateOffsets(template: string, context: TemplateContext): string {
    let result: string = template;
    const dateOffsetRegex = new RegExp('\\{\\{date:([^}]+)\\}\\}', 'g');

    let safetyCounter: number = 0;
    while (safetyCounter < 100) {
      const match = dateOffsetRegex.exec(result);
      if (!match) {
        break;
      }
      const fullMatch: string = match[0];
      const params: string = match[1];

      // 解析 offset 和 format
      let offsetStr: string = '';
      let formatStr: string = 'YYYY-MM-DD';

      const pipeIdx: number = params.indexOf('|');
      if (pipeIdx >= 0) {
        offsetStr = params.substring(0, pipeIdx).trim();
        const formatPart: string = params.substring(pipeIdx + 1).trim();
        // 提取引号内的格式字符串
        const formatMatch = formatPart.match(new RegExp('"([^"]+)"'));
        if (formatMatch) {
          formatStr = formatMatch[1];
        }
      } else {
        offsetStr = params.trim();
      }

      // 计算偏移后的时间戳
      const offsetMs: number = this.parseDateOffset(offsetStr);
      const baseTimestamp: number = this.parseDateString(context.date);
      const targetTimestamp: number = baseTimestamp + offsetMs;

      // 格式化
      const formatted: string = this.formatDate(targetTimestamp, formatStr);
      result = result.replace(fullMatch, formatted);
      dateOffsetRegex.lastIndex = 0;
      safetyCounter++;
    }

    return result;
  }

  /**
   * 解析日期偏移字符串为毫秒数。
   *
   * @param offset 偏移字符串，如 "+7d"、"-1m"、"+1y"
   * @returns 毫秒数
   */
  private parseDateOffset(offset: string): number {
    if (offset === '') {
      return 0;
    }

    // 解析符号
    let sign: number = 1;
    let rest: string = offset;
    if (offset.charAt(0) === '+') {
      sign = 1;
      rest = offset.substring(1);
    } else if (offset.charAt(0) === '-') {
      sign = -1;
      rest = offset.substring(1);
    }

    // 解析数值和单位
    const unit: string = rest.charAt(rest.length - 1);
    const numStr: string = rest.substring(0, rest.length - 1);
    const num: number = parseInt(numStr, 10);
    if (isNaN(num)) {
      return 0;
    }

    const dayMs: number = 24 * 60 * 60 * 1000;
    if (unit === 'd') {
      return sign * num * dayMs;
    }
    if (unit === 'm') {
      return sign * num * 30 * dayMs;
    }
    if (unit === 'y') {
      return sign * num * 365 * dayMs;
    }
    return 0;
  }

  /**
   * 将 yyyy-MM-dd 字符串解析为时间戳。
   */
  private parseDateString(dateStr: string): number {
    if (dateStr === '') {
      return Date.now();
    }
    const parts: string[] = dateStr.split('-');
    if (parts.length !== 3) {
      return Date.now();
    }
    const year: number = parseInt(parts[0], 10);
    const month: number = parseInt(parts[1], 10) - 1;
    const day: number = parseInt(parts[2], 10);
    const date: Date = new Date(year, month, day);
    return date.getTime();
  }

  /**
   * 格式化时间戳。
   *
   * 支持的格式占位符：
   *  - YYYY → 4 位年份
   *  - MM   → 2 位月份
   *  - DD   → 2 位日期
   *  - HH   → 2 位小时
   *  - mm   → 2 位分钟
   *  - ss   → 2 位秒
   *
   * @param timestamp 时间戳 (ms)
   * @param format 格式字符串
   * @returns 格式化后的日期字符串
   */
  private formatDate(timestamp: number, format: string): string {
    const date: Date = new Date(timestamp);
    const year: number = date.getFullYear();
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    const hours: number = date.getHours();
    const minutes: number = date.getMinutes();
    const seconds: number = date.getSeconds();

    let result: string = format;
    result = result.replace(new RegExp('YYYY', 'g'), year.toString());
    result = result.replace(new RegExp('MM', 'g'), month < 10 ? '0' + month.toString() : month.toString());
    result = result.replace(new RegExp('DD', 'g'), day < 10 ? '0' + day.toString() : day.toString());
    result = result.replace(new RegExp('HH', 'g'), hours < 10 ? '0' + hours.toString() : hours.toString());
    result = result.replace(new RegExp('mm', 'g'), minutes < 10 ? '0' + minutes.toString() : minutes.toString());
    result = result.replace(new RegExp('ss', 'g'), seconds < 10 ? '0' + seconds.toString() : seconds.toString());
    return result;
  }

  // ─── 简单变量替换 ───

  /**
   * 处理 {{date}}、{{title}}、{{pageName}}、{{customVar}} 简单替换。
   */
  private processSimpleVars(template: string, context: TemplateContext): string {
    let result: string = template;

    // 替换内置变量
    result = result.replace(new RegExp('\\{\\{date\\}\\}', 'g'), context.date);
    result = result.replace(new RegExp('\\{\\{title\\}\\}', 'g'), context.title);
    result = result.replace(new RegExp('\\{\\{pageName\\}\\}', 'g'), context.pageName);

    // 替换自定义变量
    context.customVars.forEach((value: string, key: string) => {
      const pattern: string = '\\{\\{' + this.escapeRegex(key) + '\\}\\}';
      result = result.replace(new RegExp(pattern, 'g'), value);
    });

    return result;
  }

  /**
   * 转义正则表达式特殊字符。
   */
  private escapeRegex(str: string): string {
    let result: string = '';
    for (let i = 0; i < str.length; i++) {
      const ch: string = str.charAt(i);
      if (ch === '(' || ch === ')' || ch === '[' || ch === ']' ||
          ch === '{' || ch === '}' || ch === '.' || ch === '*' ||
          ch === '+' || ch === '?' || ch === '|' || ch === '^' ||
          ch === '$' || ch === '\\') {
        result = result + '\\' + ch;
      } else {
        result = result + ch;
      }
    }
    return result;
  }
}
