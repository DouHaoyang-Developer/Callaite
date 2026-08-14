import { describe, it, expect } from '@ohos/hypium';
import { pageNameToFileName, extractNamespace, getShortPageName } from '../main/ets/core/models/Page';
import { UUID } from '../main/ets/utils/UUID';

/**
 * 本地单元测试（纯逻辑，无 UI/上下文依赖）。
 */
export default function localUnitTest() {
  describe('Callaite 核心纯逻辑', () => {
    it('pageNameToFileName 普通路径转换', 0, () => {
      expect(pageNameToFileName('a/b')).assertEqual('a_b.md');
      expect(pageNameToFileName('笔记')).assertEqual('笔记.md');
    });

    it('pageNameToFileName 清洗路径穿越', 0, () => {
      const result = pageNameToFileName('../../etc/passwd');
      expect(result.indexOf('/') === -1).assertTrue();
      expect(result.indexOf('..') === -1).assertTrue();
      expect(result.endsWith('.md')).assertTrue();
    });

    it('extractNamespace 提取命名空间', 0, () => {
      expect(extractNamespace('project/sub')).assertEqual('project');
      expect(extractNamespace('normal')).assertEqual('');
      expect(extractNamespace('/leading')).assertEqual('');
    });

    it('getShortPageName 提取短名', 0, () => {
      expect(getShortPageName('project/sub')).assertEqual('sub');
      expect(getShortPageName('normal')).assertEqual('normal');
    });

    it('UUID 生成合法格式', 0, () => {
      const id = UUID.generate();
      expect(UUID.isValid(id)).assertTrue();
      expect(id.length === 36).assertTrue();
    });
  });
}
