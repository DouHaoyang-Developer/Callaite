import { JournalService } from './JournalService';

/**
 * TemplateService — 模板引擎。
 *
 * 支持变量：
 *   {{date}}          — 今天日期 yyyy-MM-dd
 *   {{title}}         — 当前页面标题
 *   {{date:+Nd}}      — N 天后 yyyy-MM-dd
 *   {{date:-Nd}}      — N 天前 yyyy-MM-dd
 *   {{time}}          — 当前时间 HH:mm
 *
 * 对应 Logseq outliner/template.cljs (170行)。
 */
export class TemplateService {

  /**
   * 展开模板字符串中的变量。
   * @param template 模板文本
   * @param pageTitle 当前页面标题（用于 {{title}}）
   * @returns 展开后的文本
   */
  static expand(template: string, pageTitle: string): string {
    let result = template;

    // {{date}}
    result = result.replace(new RegExp('\\{\\{date\\}\\}', 'g'), JournalService.getTodayDateString());

    // {{time}}
    const now = new Date();
    const h = now.getHours().toString().padStart(2, '0');
    const m = now.getMinutes().toString().padStart(2, '0');
    result = result.replace(new RegExp('\\{\\{time\\}\\}', 'g'), h + ':' + m);

    // {{title}}
    result = result.replace(new RegExp('\\{\\{title\\}\\}', 'g'), pageTitle);

    // {{date:+Nd}} / {{date:-Nd}}
    result = TemplateService.expandDateOffset(result);

    return result;
  }

  /**
   * 展开 {{date:+Nd}} 和 {{date:-Nd}} 格式。
   */
  private static expandDateOffset(text: string): string {
    const regex = new RegExp('\\{\\{date:([+-])(\\d+)d\\}\\}', 'g');
    let match = regex.exec(text);
    let result = text;

    // 手动循环替代 while(regex.exec)（避免 ArkTS RegExp state 问题）
    const matches: DateOffsetMatch[] = [];
    const allRegex = new RegExp('\\{\\{date:([+-])(\\d+)d\\}\\}', 'g');
    let m = allRegex.exec(text);
    while (m) {
      const entry: DateOffsetMatch = {
        full: m[0],
        sign: m[1],
        days: parseInt(m[2])
      };
      matches.push(entry);
      m = allRegex.exec(text);
    }

    for (let i = 0; i < matches.length; i++) {
      const entry = matches[i];
      const offsetDate = new Date();
      const delta = entry.sign === '+' ? entry.days : -entry.days;
      offsetDate.setDate(offsetDate.getDate() + delta);
      const year = offsetDate.getFullYear().toString();
      const month = (offsetDate.getMonth() + 1).toString().padStart(2, '0');
      const day = offsetDate.getDate().toString().padStart(2, '0');
      const dateStr = year + '-' + month + '-' + day;
      result = result.replace(new RegExp(TemplateService.escapeRegex(entry.full), 'g'), dateStr);
    }

    return result;
  }

  private static escapeRegex(str: string): string {
    let escaped = '';
    for (let i = 0; i < str.length; i++) {
      const ch = str.charAt(i);
      if (ch === '{' || ch === '}' || ch === '+' || ch === '-' || ch === '|') {
        escaped = escaped + '\\' + ch;
      } else {
        escaped = escaped + ch;
      }
    }
    return escaped;
  }

  /**
   * 获取预置模板列表。
   */
  static getBuiltinTemplates(): TemplateInfo[] {
    const templates: TemplateInfo[] = [];
    const t1: TemplateInfo = {
      name: '日记',
      icon: 'calendar',
      content: '# {{date}} {{time}}\n\n- 今日计划\n- \n\n## 回顾\n- '
    };
    templates.push(t1);

    const t2: TemplateInfo = {
      name: '会议记录',
      icon: 'users',
      content: '# 会议: {{title}} — {{date}}\n\n- 参会人:\n- 议题:\n- \n\n## 结论\n- \n\n## 待办\n- TODO '
    };
    templates.push(t2);

    const t3: TemplateInfo = {
      name: '项目页面',
      icon: 'folder',
      content: 'tags:: project\nstatus:: active\n\n- 目标\n- \n\n## 任务\n- TODO '
    };
    templates.push(t3);

    const t4: TemplateInfo = {
      name: '周回顾',
      icon: 'refresh',
      content: '# 周回顾 — {{date:-7d}} ~ {{date}}\n\n## 完成\n- \n\n## 未完成\n- \n\n## 下周计划\n- '
    };
    templates.push(t4);

    return templates;
  }
}

interface DateOffsetMatch {
  full: string;
  sign: string;
  days: number;
}

export interface TemplateInfo {
  name: string;
  icon: string;
  content: string;
}
