/**
 * LogicEngine — 自研迷你逻辑引擎。
 *
 * 支持 Datalog 风格的递归规则推导（半朴素评估算法）。
 *
 * 术语:
 *   Term   = 常量字符串 或 变量(以 ? 开头)
 *   Atom   = [谓词名, Term...]
 *   Fact   = 全常量 Atom（存储在事实库）
 *   Rule   = Head Atom ← Body Atom 列表
 *   Query  = 带变量的 Atom（求解满足的变量绑定）
 *
 * 示例:
 *   事实:  [parent, "A", "B"], [parent, "B", "C"]
 *   规则:  [ancestor, ?x, ?y] :- [parent, ?x, ?y]
 *          [ancestor, ?x, ?y] :- [parent, ?x, ?z], [ancestor, ?z, ?y]
 *   查询:  [ancestor, ?x, "C"] → [{?x: "A"}, {?x: "B"}]
 */
export class LogicEngine {
  private facts: string[][] = [];
  private rules: DatalogRule[] = [];
  private maxIterations: number = 50;

  /**
   * 添加一个事实。
   */
  addFact(predicate: string, ...args: string[]): LogicEngine {
    const atom: string[] = [];
    atom[0] = predicate;
    for (let i = 0; i < args.length; i++) atom[i + 1] = args[i];
    this.facts.push(atom);
    return this;
  }

  /**
   * 添加一条规则。
   * @param head 头部 Atom，含变量
   * @param body 体部 Atom 列表
   */
  addRule(head: string[], body: string[][]): LogicEngine {
    const rule: DatalogRule = { head: head, body: body };
    this.rules.push(rule);
    return this;
  }

  /**
   * 设置最大迭代次数（防止无限递归）。
   */
  setMaxIterations(n: number): LogicEngine {
    this.maxIterations = n;
    return this;
  }

  /**
   * 执行查询：找到所有满足查询 Atom 的变量绑定。
   * @returns 绑定列表，每个绑定是 {变量名: 值} 的 Map
   */
  query(queryAtom: string[]): Map<string, string>[] {
    // 先运行规则推导（补齐所有可推导的事实）
    this.evaluate();

    // 在事实库中匹配
    const results: Map<string, string>[] = [];
    for (let i = 0; i < this.facts.length; i++) {
      const bindings = LogicEngine.unify(queryAtom, this.facts[i]);
      if (bindings) {
        results.push(bindings);
      }
    }
    return results;
  }

  /**
   * 查询是否满足某个条件（存在性查询）。
   */
  exists(queryAtom: string[]): boolean {
    this.evaluate();
    for (let i = 0; i < this.facts.length; i++) {
      if (LogicEngine.unify(queryAtom, this.facts[i])) return true;
    }
    return false;
  }

  /**
   * 半朴素评估：迭代推导新事实直到不动点。
   */
  private evaluate(): void {
    for (let iter = 0; iter < this.maxIterations; iter++) {
      const newFacts: string[][] = [];

      for (let ri = 0; ri < this.rules.length; ri++) {
        const rule = this.rules[ri];
        // 对体部的每个 Atom 在事实库中匹配，累积绑定
        const bindingsList = LogicEngine.evaluateBody(rule.body, this.facts);
        for (let bi = 0; bi < bindingsList.length; bi++) {
          const headInstance = LogicEngine.substitute(rule.head, bindingsList[bi]);
          if (!LogicEngine.factExists(this.facts, headInstance)) {
            newFacts.push(headInstance);
          }
        }
      }

      if (newFacts.length === 0) break; // 不动点
      for (let i = 0; i < newFacts.length; i++) {
        this.facts.push(newFacts[i]);
      }
    }
  }

  // ─── 静态工具方法 ───

  /**
   * 变量统一：将常量 Atom 与带变量的 Atom 匹配。
   * @returns 变量绑定 Map，或 null（匹配失败）
   */
  static unify(pattern: string[], fact: string[]): Map<string, string> | undefined {
    if (pattern.length !== fact.length) return undefined;
    const bindings = new Map<string, string>();
    for (let i = 0; i < pattern.length; i++) {
      const pt = pattern[i];
      const ft = fact[i];
      if (LogicEngine.isVariable(pt)) {
        const existing = bindings.get(pt);
        if (existing) {
          if (existing !== ft) return undefined; // 绑定冲突
        } else {
          bindings.set(pt, ft);
        }
      } else {
        if (pt !== ft) return undefined; // 常量不匹配
      }
    }
    return bindings;
  }

  /**
   * 变量替换：将 Atom 中的变量替换为绑定值。
   */
  static substitute(atom: string[], bindings: Map<string, string>): string[] {
    const result: string[] = [];
    for (let i = 0; i < atom.length; i++) {
      if (LogicEngine.isVariable(atom[i])) {
        const val = bindings.get(atom[i]);
        result[i] = val ? val : atom[i];
      } else {
        result[i] = atom[i];
      }
    }
    return result;
  }

  /**
   * 合并两个绑定映射。
   */
  static mergeBindings(a: Map<string, string>, b: Map<string, string>): Map<string, string> | undefined {
    const result = new Map<string, string>();
    a.forEach((v: string, k: string) => { result.set(k, v); });
    let ok = true;
    b.forEach((v: string, k: string) => {
      const existing = result.get(k);
      if (existing && existing !== v) { ok = false; }
      else { result.set(k, v); }
    });
    return ok ? result : undefined;
  }

  /**
   * 评估规则体：找到所有满足所有体部原子的绑定组合。
   */
  static evaluateBody(body: string[][], facts: string[][]): Map<string, string>[] {
    if (body.length === 0) {
      const result: Map<string, string>[] = [];
      result.push(new Map<string, string>());
      return result;
    }

    let current: Map<string, string>[] = [];
    // 第一个原子的匹配
    for (let fi = 0; fi < facts.length; fi++) {
      const b = LogicEngine.unify(body[0], facts[fi]);
      if (b) current.push(b);
    }

    // 后续原子的连接
    for (let bi = 1; bi < body.length; bi++) {
      const next: Map<string, string>[] = [];
      for (let ci = 0; ci < current.length; ci++) {
        const substituted = LogicEngine.substitute(body[bi], current[ci]);
        for (let fi = 0; fi < facts.length; fi++) {
          const newB = LogicEngine.unify(substituted, facts[fi]);
          if (newB) {
            const merged = LogicEngine.mergeBindings(current[ci], newB);
            if (merged) next.push(merged);
          }
        }
      }
      current = next;
      if (current.length === 0) break;
    }

    return current;
  }

  static isVariable(term: string): boolean {
    return term.length > 0 && term.charAt(0) === '?';
  }

  static factExists(facts: string[][], target: string[]): boolean {
    for (let i = 0; i < facts.length; i++) {
      if (LogicEngine.atomEqual(facts[i], target)) return true;
    }
    return false;
  }

  static atomEqual(a: string[], b: string[]): boolean {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) return false;
    }
    return true;
  }
}

interface DatalogRule {
  head: string[];
  body: string[][];
}
