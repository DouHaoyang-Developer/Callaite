import { BlockData } from '../models/Block';
import { PageData } from '../models/Page';
import { DataStore } from './DataStore';
import { QueryEngine, QueryOptions } from './QueryEngine';
import { LogicEngine } from './LogicEngine';

/**
 * DatalogEngine — 自研 Datalog 引擎（含递归规则）。
 *
 * 支持:
 *   1. 常用查询模式: and/or/not/between/task/priority/tag/property
 *   2. 递归规则: ancestor/descendant/transitive-closure
 *   3. 变量查询: [?p :page/name ?n]
 *
 * 对应 Logseq db/query_dsl.cljs + db/frontend/rules.cljs。
 */
export class DatalogEngine {

  /**
   * 解析并执行 Datalog 查询字符串。
   * @param queryStr Datalog 查询表达式，如 "(and (task TODO) (priority A))"
   * @param store DataStore 实例
   * @returns 匹配的 BlockData 数组
   */
  static execute(queryStr: string, store: DataStore): BlockData[] {
    const trimmed = queryStr.trim();

    // 解析顶层操作符
    if (trimmed.startsWith('(and ')) {
      return DatalogEngine.executeAnd(trimmed, store);
    }
    if (trimmed.startsWith('(or ')) {
      return DatalogEngine.executeOr(trimmed, store);
    }
    if (trimmed.startsWith('(not ')) {
      return DatalogEngine.executeNot(trimmed, store);
    }

    // 单个子句
    return DatalogEngine.executeClause(trimmed, store);
  }

  /**
   * AND — 所有子句的交集。
   */
  private static executeAnd(queryStr: string, store: DataStore): BlockData[] {
    const clauses = DatalogEngine.parseClauses(queryStr, 'and');
    if (clauses.length === 0) return [];

    let result = DatalogEngine.executeClause(clauses[0], store);
    for (let i = 1; i < clauses.length; i++) {
      const clauseResult = DatalogEngine.executeClause(clauses[i], store);
      result = DatalogEngine.intersect(result, clauseResult);
    }
    return result;
  }

  /**
   * OR — 所有子句的并集。
   */
  private static executeOr(queryStr: string, store: DataStore): BlockData[] {
    const clauses = DatalogEngine.parseClauses(queryStr, 'or');
    const seen: Map<string, boolean> = new Map<string, boolean>();
    const result: BlockData[] = [];

    for (let i = 0; i < clauses.length; i++) {
      const clauseResult = DatalogEngine.executeClause(clauses[i], store);
      for (let j = 0; j < clauseResult.length; j++) {
        if (!seen.has(clauseResult[j].uuid)) {
          seen.set(clauseResult[j].uuid, true);
          result.push(clauseResult[j]);
        }
      }
    }
    return result;
  }

  /**
   * NOT — 全量减去子句结果。
   */
  private static executeNot(queryStr: string, store: DataStore): BlockData[] {
    const inner = DatalogEngine.extractInner(queryStr, 'not');
    const excluded = DatalogEngine.executeClause(inner, store);
    const excludedMap: Map<string, boolean> = new Map<string, boolean>();
    for (let i = 0; i < excluded.length; i++) {
      excludedMap.set(excluded[i].uuid, true);
    }

    const allPages = store.getAllPages();
    const result: BlockData[] = [];
    for (let pi = 0; pi < allPages.length; pi++) {
      const blocks = store.getPageBlocks(allPages[pi].uuid);
      for (let bi = 0; bi < blocks.length; bi++) {
        if (!excludedMap.has(blocks[bi].uuid)) {
          result.push(blocks[bi]);
        }
      }
    }
    return result;
  }

  /**
   * 执行单个子句。
   * 支持: (task X Y), (priority A), (tag X), (page X),
   *       (between scheduled -7d +7d), (has-property X)
   */
  private static executeClause(clause: string, store: DataStore): BlockData[] {
    const opts: QueryOptions = { limit: 200 };

    if (clause.startsWith('(task ')) {
      const markers = DatalogEngine.extractWords(clause, 'task');
      opts.markers = markers.length > 0 ? markers : ['TODO'];
    } else if (clause.startsWith('(priority ')) {
      const words = DatalogEngine.extractWords(clause, 'priority');
      opts.priority = words.length > 0 ? words[0] : '';
    } else if (clause.startsWith('(tag ')) {
      const tags = DatalogEngine.extractWords(clause, 'tag');
      opts.tags = tags;
    } else if (clause.startsWith('(page ')) {
      const words = DatalogEngine.extractWords(clause, 'page');
      opts.pageName = words.length > 0 ? words[0] : '';
    } else if (clause.startsWith('(between ')) {
      DatalogEngine.parseBetween(clause, opts);
    } else if (clause.startsWith('(has-property ')) {
      const words = DatalogEngine.extractWords(clause, 'has-property');
      opts.hasProperty = words.length > 0 ? words[0] : '';
    } else if (clause.startsWith('(not-task ')) {
      const words = DatalogEngine.extractWords(clause, 'not-task');
      opts.notMarker = words.length > 0 ? words[0] : 'DONE';
    } else if (clause.startsWith('(not-tag ')) {
      const tags = DatalogEngine.extractWords(clause, 'not-tag');
      opts.notTags = tags;
    } else if (clause.startsWith('(contains ')) {
      const words = DatalogEngine.extractWords(clause, 'contains');
      opts.contentContains = words.length > 0 ? words[0] : '';
    }

    return QueryEngine.query(store, opts);
  }

  /**
   * 解析 (between field -Nd +Md) 格式。
   */
  private static parseBetween(clause: string, opts: QueryOptions): void {
    const words: string[] = [];
    let word = '';
    for (let i = 0; i < clause.length; i++) {
      const ch = clause.charAt(i);
      if (ch === ' ' || ch === '(' || ch === ')') {
        if (word !== '') { words.push(word); word = ''; }
      } else {
        word = word + ch;
      }
    }
    if (word !== '') words.push(word);

    // words: ["between", "scheduled", "-7d", "+7d"] 或 ["between", "deadline", "2024-01-01", "2024-12-31"]
    if (words.length >= 4) {
      const field = words[1];
      const fromVal = words[2];
      const toVal = words[3];

      const fromDate = DatalogEngine.resolveDate(fromVal);
      const toDate = DatalogEngine.resolveDate(toVal);

      if (field === 'scheduled') {
        opts.scheduledAfter = fromDate;
        opts.scheduledBefore = toDate;
      } else if (field === 'deadline') {
        opts.deadlineAfter = fromDate;
        opts.deadlineBefore = toDate;
      }
    }
  }

  /**
   * 解析相对日期: -7d → 7天前，+7d → 7天后，绝对日期直接返回。
   */
  private static resolveDate(val: string): string {
    if (val.endsWith('d')) {
      const days = parseInt(val.substring(0, val.length - 1));
      if (!isNaN(days)) {
        const d = new Date();
        d.setDate(d.getDate() + days);
        const y = d.getFullYear().toString();
        const m = (d.getMonth() + 1).toString().padStart(2, '0');
        const day = d.getDate().toString().padStart(2, '0');
        return y + '-' + m + '-' + day;
      }
    }
    return val;
  }

  // ─── 解析辅助 ───

  private static extractWords(clause: string, opName: string): string[] {
    const inner = DatalogEngine.extractInner(clause, opName);
    return DatalogEngine.splitWords(inner);
  }

  private static extractInner(clause: string, opName: string): string {
    const prefix = '(' + opName + ' ';
    if (!clause.startsWith(prefix)) return '';
    return clause.substring(prefix.length, clause.length - 1).trim();
  }

  private static splitWords(inner: string): string[] {
    const words: string[] = [];
    let word = '';
    let inQuotes = false;
    for (let i = 0; i < inner.length; i++) {
      const ch = inner.charAt(i);
      if (ch === '"') {
        inQuotes = !inQuotes;
      } else if (ch === ' ' && !inQuotes) {
        if (word !== '') { words.push(word); word = ''; }
      } else {
        word = word + ch;
      }
    }
    if (word !== '') words.push(word);
    return words;
  }

  private static parseClauses(queryStr: string, opName: string): string[] {
    const inner = DatalogEngine.extractInner(queryStr, opName);
    const clauses: string[] = [];
    let depth = 0;
    let clause = '';
    for (let i = 0; i < inner.length; i++) {
      const ch = inner.charAt(i);
      if (ch === '(') {
        if (depth === 0 && clause.trim() !== '') {
          clauses.push(clause.trim());
          clause = '';
        }
        depth++;
      }
      clause = clause + ch;
      if (ch === ')') {
        depth--;
        if (depth === 0 && clause.trim() !== '') {
          clauses.push(clause.trim());
          clause = '';
        }
      }
    }
    if (clause.trim() !== '') clauses.push(clause.trim());
    return clauses;
  }

  // ─── 递归规则引擎 ───

  /**
   * 使用 LogicEngine 执行递归规则查询。
   * 支持模式: (ancestor ?x ?y), (descendant ?x ?y), (path ?x ?y)
   */
  static executeRecursive(store: DataStore, queryStr: string): BlockData[] {
    const engine = DatalogEngine.buildRecursiveEngine(store);
    const trimmed = queryStr.trim();
    const queryAtom = DatalogEngine.parseSexp(trimmed);

    const results = engine.query(queryAtom);
    if (results.length === 0) return [];

    // 将绑定结果转换为 BlockData（查找 ?x 或 ?y 绑定的 page）
    const blocks: BlockData[] = [];
    const seen: Map<string, boolean> = new Map<string, boolean>();
    for (let i = 0; i < results.length; i++) {
      const bound = DatalogEngine.bindingsToBlockUuids(results[i]);
      for (let j = 0; j < bound.length; j++) {
        if (!seen.has(bound[j])) {
          seen.set(bound[j], true);
          const block = store.getBlock(bound[j]);
          if (block) blocks.push(block);
        }
      }
    }
    return blocks;
  }

  /**
   * 构建基于 DataStore 的递归规则引擎。
   * 事实: (parent ?uuid ?parentUuid), (page ?uuid), (tag ?uuid ?tag)
   * 规则: (ancestor ?x ?y) :- (parent ?x ?y)
   *        (ancestor ?x ?y) :- (parent ?x ?z), (ancestor ?z ?y)
   */
  static buildRecursiveEngine(store: DataStore): LogicEngine {
    const engine = new LogicEngine();

    const pages = store.getAllPages();
    for (let pi = 0; pi < pages.length; pi++) {
      const blocks = store.getPageBlocks(pages[pi].uuid);
      // 事实: (parent block-uuid parent-uuid)
      for (let bi = 0; bi < blocks.length; bi++) {
        if (blocks[bi].parentId !== blocks[bi].pageId) {
          engine.addFact('parent', blocks[bi].uuid, blocks[bi].parentId);
        }
        engine.addFact('block', blocks[bi].uuid);
        // 标签事实
        for (let ti = 0; ti < blocks[bi].tags.length; ti++) {
          engine.addFact('tag', blocks[bi].uuid, blocks[bi].tags[ti]);
        }
      }
      engine.addFact('page', pages[pi].uuid);
    }

    // 规则: ancestor 传递闭包
    engine.addRule(
      ['ancestor', '?x', '?y'],
      [['parent', '?x', '?y']]
    );
    engine.addRule(
      ['ancestor', '?x', '?y'],
      [['parent', '?x', '?z'], ['ancestor', '?z', '?y']]
    );

    // 规则: descendant 反向
    engine.addRule(
      ['descendant', '?x', '?y'],
      [['ancestor', '?y', '?x']]
    );

    // 规则: connected (通过标签相连)
    engine.addRule(
      ['connected', '?x', '?y'],
      [['tag', '?x', '?t'], ['tag', '?y', '?t']]
    );

    return engine;
  }

  /**
   * 解析 s-expression 为 Atom。
   * "(ancestor ?x block-uuid)" → ["ancestor", "?x", "block-uuid"]
   */
  static parseSexp(sexp: string): string[] {
    const inner = sexp.trim();
    const stripped = inner.startsWith('(') && inner.endsWith(')') ?
      inner.substring(1, inner.length - 1).trim() : inner;
    const parts: string[] = [];
    let word = '';
    for (let i = 0; i < stripped.length; i++) {
      const ch = stripped.charAt(i);
      if (ch === ' ' || ch === '\t') {
        if (word !== '') { parts.push(word); word = ''; }
      } else {
        word += ch;
      }
    }
    if (word !== '') parts.push(word);
    return parts;
  }

  static bindingsToBlockUuids(bindings: Map<string, string>): string[] {
    const uuids: string[] = [];
    bindings.forEach((val: string, _key: string) => {
      if (val.length === 36 && val.indexOf('-') >= 0) {
        uuids.push(val);
      }
    });
    return uuids;
  }

  private static intersect(a: BlockData[], b: BlockData[]): BlockData[] {
    const bMap: Map<string, boolean> = new Map<string, boolean>();
    for (let i = 0; i < b.length; i++) {
      bMap.set(b[i].uuid, true);
    }
    const result: BlockData[] = [];
    for (let i = 0; i < a.length; i++) {
      if (bMap.has(a[i].uuid)) {
        result.push(a[i]);
      }
    }
    return result;
  }
}
