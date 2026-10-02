import { describe, it, expect } from '@ohos/hypium';
import { MarkdownParser } from '../main/ets/core/parser/MarkdownParser';
import { MarkdownExporter } from '../main/ets/core/parser/MarkdownExporter';
import { BlockData } from '../main/ets/core/models/Block';
import { BlockTree } from '../main/ets/core/engine/BlockTree';

/**
 * T1（优化方案 v2 §七 任务卡）：Markdown 解析 ↔ 导出 **往返不变式**。
 *
 * 安全网价值：O4 整页编辑器与「应用并重建大纲」依赖
 *   parse(md) → BlockData[] → export(page, blocks) → md'
 * 这条链路。若往返不再收敛，重建会不断放大格式噪声（缩进漂移、marker 重复、
 * 引用丢失），而这类回归在 UI 上很难肉眼发现 —— 因此在此以断言固化。
 */

const SAMPLE: string = [
  '- 顶层块 A',
  '  - 子块 A1 #tag1',
  '  - TODO 子块 A2 [[页面引用]]',
  '- 顶层块 B',
  '',
  '  - 深层块 B1'
].join('\n');

export default function markdownRoundTripTest() {
  describe('MarkdownParser / MarkdownExporter 往返不变式', () => {

    it('解析：页面与块结构完整', 0, () => {
      const r = MarkdownParser.parse(SAMPLE, 'TestPage', 'TestPage.md');
      expect(r.page.name).assertEqual('TestPage');
      expect(r.blocks.length > 0).assertTrue();

      // 每个块都属于本页，且 uuid 唯一
      const seen: string[] = [];
      for (let i = 0; i < r.blocks.length; i++) {
        const b: BlockData = r.blocks[i];
        expect(b.pageId).assertEqual(r.page.uuid);
        expect(seen.indexOf(b.uuid) === -1).assertTrue();
        seen.push(b.uuid);
      }
    });

    it('解析：树结构自洽（父节点可达）', 0, () => {
      const r = MarkdownParser.parse(SAMPLE, 'TestPage', 'TestPage.md');
      const ids: string[] = [];
      for (let i = 0; i < r.blocks.length; i++) {
        ids.push(r.blocks[i].uuid);
      }
      for (let i = 0; i < r.blocks.length; i++) {
        const b: BlockData = r.blocks[i];
        // 顶层块的 parentId == pageId；非顶层块的父必须存在于本页
        const isTop: boolean = b.parentId === r.page.uuid;
        const parentExists: boolean = ids.indexOf(b.parentId) !== -1;
        expect(isTop || parentExists).assertTrue();
        expect(b.level >= 0).assertTrue();
      }
    });

    it('往返：一次规范化后收敛（幂等）', 0, () => {
      const r1 = MarkdownParser.parse(SAMPLE, 'TestPage', 'TestPage.md');
      const md1: string = MarkdownExporter.export(r1.page, r1.blocks);
      const r2 = MarkdownParser.parse(md1, 'TestPage', 'TestPage.md');
      const md2: string = MarkdownExporter.export(r2.page, r2.blocks);
      // 关键不变式：第二次往返必须与第一次完全一致（不再产生新噪声）
      expect(md2).assertEqual(md1);

      const r3 = MarkdownParser.parse(md2, 'TestPage', 'TestPage.md');
      const md3: string = MarkdownExporter.export(r3.page, r3.blocks);
      expect(md3).assertEqual(md1);
      // 块数量也不得漂移
      expect(r3.blocks.length).assertEqual(r1.blocks.length);
    });

    it('往返：正文与嵌套层级不丢失', 0, () => {
      const r1 = MarkdownParser.parse(SAMPLE, 'TestPage', 'TestPage.md');
      const md1: string = MarkdownExporter.export(r1.page, r1.blocks);
      expect(md1.indexOf('顶层块 A') !== -1).assertTrue();
      expect(md1.indexOf('子块 A1') !== -1).assertTrue();
      expect(md1.indexOf('深层块 B1') !== -1).assertTrue();

      const maxLevel: number = r1.blocks.reduce((acc: number, b: BlockData) => {
        return b.level > acc ? b.level : acc;
      }, 0);
      expect(maxLevel >= 1).assertTrue();
    });

    it('往返：TODO 标记保留为结构化字段', 0, () => {
      const r1 = MarkdownParser.parse(SAMPLE, 'TestPage', 'TestPage.md');
      let todoCount: number = 0;
      for (let i = 0; i < r1.blocks.length; i++) {
        if (r1.blocks[i].marker === 'TODO') {
          todoCount++;
        }
      }
      expect(todoCount).assertEqual(1);
      const md1: string = MarkdownExporter.export(r1.page, r1.blocks);
      expect(md1.indexOf('TODO') !== -1).assertTrue();
    });

    it('往返：页面引用与标签不丢失', 0, () => {
      const r1 = MarkdownParser.parse(SAMPLE, 'TestPage', 'TestPage.md');
      let hasRef: boolean = false;
      let hasTag: boolean = false;
      for (let i = 0; i < r1.blocks.length; i++) {
        const b: BlockData = r1.blocks[i];
        if (b.refs.indexOf('页面引用') !== -1) {
          hasRef = true;
        }
        if (b.tags.indexOf('tag1') !== -1) {
          hasTag = true;
        }
      }
      expect(hasRef).assertTrue();
      expect(hasTag).assertTrue();

      const md1: string = MarkdownExporter.export(r1.page, r1.blocks);
      expect(md1.indexOf('[[页面引用]]') !== -1).assertTrue();
      expect(md1.indexOf('#tag1') !== -1).assertTrue();
    });

    it('往返【回归】：同层多兄弟不得丢块（leftId 链完整）', 0, () => {
      // 缺陷回归用例：解析器曾漏写 block.leftId，导致导出器以 Map<leftId, block>
      // 建桶时同层兄弟互相覆盖 —— 保存后每层只剩最后一个块（静默数据丢失）。
      const r1 = MarkdownParser.parse(SAMPLE, 'TestPage', 'TestPage.md');
      const md1: string = MarkdownExporter.export(r1.page, r1.blocks);
      // SAMPLE 共 5 个块：顶层 A/B 与 A 的两个子块、B 的一个子块，一个都不能少
      const r2 = MarkdownParser.parse(md1, 'TestPage', 'TestPage.md');
      expect(r2.blocks.length).assertEqual(r1.blocks.length);
      expect(r1.blocks.length).assertEqual(5);
      // 每个解析出的块都必须有可用的 leftId 链（非首块 leftId 不得为空）
      let topCount: number = 0;
      let missingLeft: number = 0;
      for (let i = 0; i < r1.blocks.length; i++) {
        const b: BlockData = r1.blocks[i];
        const isFirstOfLevel: boolean = b.level === 0
          ? topCount === 0
          : false;
        if (b.level === 0) {
          topCount++;
        }
        if (!isFirstOfLevel && b.leftId === '' && b.level === 0) {
          missingLeft++;
        }
      }
      expect(missingLeft).assertEqual(0);
    });

    it('往返【回归·设备同路径】：parse → BlockTree → getPageBlocks → export 不丢块', 0, () => {
      // 复刻设备上的保存链路 DataStore.savePage()：
      //   MarkdownParser.parse → BlockTree.loadPageBlocks
      //   → blockTree.getPageBlocks(pageId) → MarkdownExporter.export
      const r1 = MarkdownParser.parse(SAMPLE, 'TestPage', 'TestPage.md');
      const tree: BlockTree = new BlockTree();
      tree.loadPageBlocks(r1.page.uuid, r1.blocks);

      const viaTree: BlockData[] = tree.getPageBlocks(r1.page.uuid);
      expect(viaTree.length).assertEqual(r1.blocks.length);

      const md: string = MarkdownExporter.export(r1.page, viaTree);
      expect(md.indexOf('顶层块 A') !== -1).assertTrue();
      expect(md.indexOf('子块 A1') !== -1).assertTrue();
      expect(md.indexOf('子块 A2') !== -1).assertTrue();
      expect(md.indexOf('顶层块 B') !== -1).assertTrue();
      expect(md.indexOf('深层块 B1') !== -1).assertTrue();

      // 顶层块数量必须仍为 2（若 leftId 链破损，这里会退化成 1）
      const topViaTree: BlockData[] = tree.getTopLevelBlocks(r1.page.uuid);
      expect(topViaTree.length).assertEqual(2);
      // 二次往返仍稳定
      const r2 = MarkdownParser.parse(md, 'TestPage', 'TestPage.md');
      const md2: string = MarkdownExporter.export(r2.page, r2.blocks);
      expect(md2).assertEqual(md);
    });

    it('契约【回归】：块前缀决定能否解析出块（无前缀 → 0 块）', 0, () => {
      // 该契约为「应用并重建」清空页面的间接成因之一：编辑器纯文本无 `- ` 前缀时
      // 解析出 0 个块。此处固化契约，防止后续改动悄悄放宽/收紧。
      const withPrefix = MarkdownParser.parse('- 内容行', 'P', 'P.md');
      const noPrefix = MarkdownParser.parse('内容行', 'P', 'P.md');
      const crlf = MarkdownParser.parse('- 内容行\r\n', 'P', 'P.md');
      expect(withPrefix.blocks.length).assertEqual(1);
      expect(noPrefix.blocks.length).assertEqual(0);
      expect(crlf.blocks.length).assertEqual(1);
    });

    it('边界：空文本不抛异常', 0, () => {
      const r = MarkdownParser.parse('', 'Empty', 'Empty.md');
      expect(r.page.name).assertEqual('Empty');
      const md: string = MarkdownExporter.export(r.page, r.blocks);
      expect(typeof md === 'string').assertTrue();
    });

    it('往返【回归·W1-8 静默丢块】：开头空块行不得被吞成「页面元数据」', 0, () => {
      // 缺陷：无 frontmatter 的元数据边界用 `trimmed.startsWith('- ')` 判定，而
      //   `'- '.trim()` === `'-'`（尾部空格被吃掉）⇒ **空块行不满足该判据**。
      //   于是「开头若干个空块」的文件会把整个文件并入元数据区 ⇒ 解析出 0 块 ⇒
      //   下一次落盘把页面写成 0 字节（实测离线复刻：32 行全 `- ` 时 95 B → 0 B）。
      //   应用内「添加」行反复建空块即可产生这种文件，故为真实数据丢失路径。
      const bare: string[] = [];
      for (let i = 0; i < 31; i++) {
        bare.push('- ');
      }
      bare.push('- 尾块内容');
      const src: string = bare.join('\n');

      const r1 = MarkdownParser.parse(src, 'P', 'P.md');
      // 1) 一个块都不能丢
      expect(r1.blocks.length).assertEqual(32);
      // 2) 空块内容为空、尾块内容保留
      expect(r1.blocks[0].content).assertEqual('');
      expect(r1.blocks[31].content).assertEqual('尾块内容');
      // 3) 落盘内容与磁盘原文逐字符相同（这是「不丢数据」的直接判据）
      const md1: string = MarkdownExporter.export(r1.page, r1.blocks);
      expect(md1).assertEqual(src);

      // 4) 二次往返仍稳定（幂等）
      const r2 = MarkdownParser.parse(md1, 'P', 'P.md');
      const md2: string = MarkdownExporter.export(r2.page, r2.blocks);
      expect(r2.blocks.length).assertEqual(32);
      expect(md2).assertEqual(src);
    });

    it('往返【回归·W1-8】：全空块文件不得被写成 0 字节', 0, () => {
      // 上一条的极端形态：文件里**一行块内容都没有**，全是空块。
      // 旧实现下 metadataEndIndex 会被推到 lines.length ⇒ 0 块 ⇒ 导出空串 ⇒ 页面清零。
      const bare: string[] = [];
      for (let i = 0; i < 20; i++) {
        bare.push('- ');
      }
      const src: string = bare.join('\n');

      const r = MarkdownParser.parse(src, 'P', 'P.md');
      expect(r.blocks.length).assertEqual(20);
      const md: string = MarkdownExporter.export(r.page, r.blocks);
      expect(md).assertEqual(src);
      expect(md.length > 0).assertTrue();
    });

    it('契约【回归】：元数据边界只吃「文件开头的属性行」，不吃正文', 0, () => {
      // 旧实现的第二条缺口：边界在**每一行**都推进，故「文件里一行块都没有」时
      //   也会得到 0 块。新实现把边界只推进到匹配 PROPERTY_REGEX 的连续属性行。
      const withProps = MarkdownParser.parse('title:: T\ntags:: a, b\n- x', 'P', 'P.md');
      expect(withProps.page.properties.get('title')).assertEqual('T');
      expect(withProps.blocks.length).assertEqual(1);
      expect(withProps.blocks[0].content).assertEqual('x');

      // 第一条非属性行即内容起点（此处为纯文本）——块数仍为 0（契约未放宽），
      // 但它**不再**被当作元数据吞掉：后续若接上块行，边界停在纯文本处。
      const strayThenBlock = MarkdownParser.parse('纯文本\n- x', 'P', 'P.md');
      expect(strayThenBlock.blocks.length).assertEqual(1);
      expect(strayThenBlock.blocks[0].content).assertEqual('x');

      // 纯属性行仍全部进页面属性（不回归成块）
      const onlyProps = MarkdownParser.parse('title:: T\nfoo:: bar', 'P', 'P.md');
      expect(onlyProps.page.properties.get('foo')).assertEqual('bar');
      expect(onlyProps.blocks.length).assertEqual(0);
    });

    it('辅助：countIndent 层级与块前缀判定', 0, () => {
      const l0 = MarkdownParser.countIndent('- 顶层');
      expect(l0.level).assertEqual(0);
      expect(l0.isBlock).assertTrue();
      const l1 = MarkdownParser.countIndent('  - 一级');
      expect(l1.level).assertEqual(1);
      expect(l1.isBlock).assertTrue();
      const l2 = MarkdownParser.countIndent('    - 二级');
      expect(l2.level).assertEqual(2);
      const plain = MarkdownParser.countIndent('纯文本');
      expect(plain.isBlock).assertFalse();
      expect(plain.level).assertEqual(0);
    });

    it('辅助：isJournalFileName 严格匹配 yyyy-MM-dd', 0, () => {
      expect(MarkdownParser.isJournalFileName('2026-09-25')).assertTrue();
      expect(MarkdownParser.isJournalFileName('2026-9-25')).assertFalse();
      expect(MarkdownParser.isJournalFileName('notes')).assertFalse();
      expect(MarkdownParser.isJournalFileName('2026-09-2X')).assertFalse();
    });

    it('辅助：引用/标签提取去重且排除嵌入', 0, () => {
      const refs = MarkdownParser.extractPageRefs('见 [[A]] 与 ![[B]] 与 [[A]]');
      expect(refs.length).assertEqual(1);
      expect(refs[0]).assertEqual('A');

      const tags = MarkdownParser.extractTags('#t1 正文 #标签 #t1');
      expect(tags.length).assertEqual(2);
      expect(tags[0]).assertEqual('t1');
      expect(tags[1]).assertEqual('标签');

      const blockRefs = MarkdownParser.extractBlockRefs('((123e4567-e89b-12d3-a456-426614174000))');
      expect(blockRefs.length).assertEqual(1);
      expect(MarkdownParser.extractBlockRefs('((太短))').length).assertEqual(0);
    });

    it('辅助：splitCommaSeparated 去空白与空项', 0, () => {
      const parts = MarkdownParser.splitCommaSeparated('a, b ,, c ');
      expect(parts.length).assertEqual(3);
      expect(parts[0]).assertEqual('a');
      expect(parts[1]).assertEqual('b');
      expect(parts[2]).assertEqual('c');
      expect(MarkdownParser.splitCommaSeparated('').length).assertEqual(0);
    });
  });
}
