import { describe, it, expect } from '@ohos/hypium';
import { ContentRenderer, SegmentType } from '../../main/ets/utils/ContentRenderer';
import { TemplateService } from '../../main/ets/services/TemplateService';

/**
 * 设备端测试（含内容渲染与模板展开）。
 */
export default function abilityTest() {
  describe('Callaite 核心功能', () => {
    it('ContentRenderer 解析 markdown 链接', 0, () => {
      const segs = ContentRenderer.parse('[文本](https://example.com)');
      expect(segs.length === 1).assertTrue();
      expect(segs[0].type).assertEqual(SegmentType.LINK);
      expect(segs[0].text).assertEqual('https://example.com');
      expect(segs[0].extra).assertEqual('文本');
    });

    it('ContentRenderer 解析页面引用与加粗', 0, () => {
      const segs = ContentRenderer.parse('[[页面]] 与 **加粗**');
      expect(segs.length === 3).assertTrue();
      expect(segs[0].type).assertEqual(SegmentType.PAGE_REF);
      expect(segs[1].type).assertEqual(SegmentType.TEXT);
      expect(segs[2].type).assertEqual(SegmentType.BOLD);
    });

    it('ContentRenderer 解析块引用与代码', 0, () => {
      const segs = ContentRenderer.parse('```ts\nconst a = 1;\n```');
      expect(segs.length === 1).assertTrue();
      expect(segs[0].type).assertEqual(SegmentType.CODE);
    });

    it('TemplateService 展开变量', 0, () => {
      const result = TemplateService.expand('标题：{{title}}，日期：{{date}}', '我的页面');
      expect(result.indexOf('我的页面') >= 0).assertTrue();
      expect(result.indexOf('{{date}}') === -1).assertTrue();
      expect(result.indexOf('{{title}}') === -1).assertTrue();
    });
  });
}
