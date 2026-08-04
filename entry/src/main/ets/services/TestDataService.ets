import { WorkspaceService } from './WorkspaceService';
import { JournalService } from './JournalService';

/**
 * TestDataService — 测试数据生成器。
 * 在 Graph 为空时自动插入示例页面和 Block，便于 UI 测试。
 */
export class TestDataService {

  /**
   * 如果 Graph 为空，生成示例数据。
   */
  static seedIfEmpty(): void {
    const ws = WorkspaceService.getInstance();
    const pages = ws.getAllPages();
    if (pages.length > 0) return; // 已有数据，跳过

    console.info('[TestData] Seeding demo graph...');

    // 1. 今天日志页
    const today = JournalService.ensureTodayJournal();
    const ws1 = WorkspaceService.getInstance();
    let page = ws1.getPageByName(today);
    if (page) {
      ws1.executeOp({ type: 'insert-block', content: '今日日志', pageId: page.uuid, parentId: page.uuid, leftId: '', level: 0 });

      TestDataService.insertBlock(ws1, page.uuid, page.uuid, '', 0, 'TODO 完成项目文档 [[项目文档]]');
      TestDataService.insertBlock(ws1, page.uuid, page.uuid, '', 0, 'DOING 学习 HarmonyOS ArkTS 开发');
      TestDataService.insertBlock(ws1, page.uuid, page.uuid, '', 0, 'LATER 整理 **重要笔记**');
      TestDataService.insertBlock(ws1, page.uuid, page.uuid, '', 0, 'DONE 代码审查 #dev');
      TestDataService.insertBlock(ws1, page.uuid, page.uuid, '', 0, '这是一段 ==高亮文本== 和 `code` 示例');

      // 嵌入示例
      TestDataService.insertBlock(ws1, page.uuid, page.uuid, '', 0, '嵌入测试 !((00000000-0000-0000-0000-000000000001))');
    }

    // 2. 项目页面
    const projPage = ws1.createPage('项目文档');
    TestDataService.insertBlock(ws1, projPage.uuid, projPage.uuid, '', 0, 'tags:: project, important');
    TestDataService.insertBlock(ws1, projPage.uuid, projPage.uuid, '', 0, 'TODO 完成需求分析 [[日志]]');
    TestDataService.insertBlock(ws1, projPage.uuid, projPage.uuid, '', 0, 'SCHEDULED: <' + today + '>');
    TestDataService.insertBlock(ws1, projPage.uuid, projPage.uuid, '', 0, 'DOING 编写技术方案');
    TestDataService.insertBlock(ws1, projPage.uuid, projPage.uuid, '', 0, 'DEADLINE: <' + JournalService.getDateAfter(7) + '>');
    TestDataService.insertBlock(ws1, projPage.uuid, projPage.uuid, '', 0, '参考: [[HarmonyOS开发指南]]');
    // 子 Block
    TestDataService.insertBlock(ws1, projPage.uuid, projPage.uuid, '', 0, '任务拆解');
    const parentBlocks = ws1.getPageBlocks(projPage.uuid);
    let lastParent = '';
    for (let i = 0; i < parentBlocks.length; i++) {
      if (parentBlocks[i].content === '任务拆解') { lastParent = parentBlocks[i].uuid; break; }
    }
    if (lastParent) {
      TestDataService.insertBlock(ws1, projPage.uuid, lastParent, '', 1, '前端 ArkUI 组件开发');
      TestDataService.insertBlock(ws1, projPage.uuid, lastParent, '', 1, '后端服务对接');
      TestDataService.insertBlock(ws1, projPage.uuid, lastParent, '', 1, '测试用例编写');
    }

    // 保存项目页面以触发引用索引
    ws1.savePage(projPage.uuid);

    // 3. 命名空间页面
    const nsPage = ws1.createPage('dev/鸿蒙开发笔记');
    TestDataService.insertBlock(ws1, nsPage.uuid, nsPage.uuid, '', 0, 'tags:: dev, harmonyos');
    TestDataService.insertBlock(ws1, nsPage.uuid, nsPage.uuid, '', 0, '## ArkUI 声明式 UI');
    TestDataService.insertBlock(ws1, nsPage.uuid, nsPage.uuid, '', 0, '@State 用于组件内状态管理');
    TestDataService.insertBlock(ws1, nsPage.uuid, nsPage.uuid, '', 0, '## 组件通信');
    TestDataService.insertBlock(ws1, nsPage.uuid, nsPage.uuid, '', 0, '@Prop 父→子单向传递');
    TestDataService.insertBlock(ws1, nsPage.uuid, nsPage.uuid, '', 0, '@Link 父子双向同步');
    ws1.savePage(nsPage.uuid);

    // 4. 带引用和属性的页面
    const hmosPage = ws1.createPage('HarmonyOS开发指南');
    TestDataService.insertBlock(ws1, hmosPage.uuid, hmosPage.uuid, '', 0, 'alias:: HOS开发, 鸿蒙指南');
    TestDataService.insertBlock(ws1, hmosPage.uuid, hmosPage.uuid, '', 0, '## 环境搭建');
    TestDataService.insertBlock(ws1, hmosPage.uuid, hmosPage.uuid, '', 0, '1. 安装 DevEco Studio');
    TestDataService.insertBlock(ws1, hmosPage.uuid, hmosPage.uuid, '', 0, '2. 配置 SDK 6.1.1(24)');
    TestDataService.insertBlock(ws1, hmosPage.uuid, hmosPage.uuid, '', 0, '## 项目结构');
    TestDataService.insertBlock(ws1, hmosPage.uuid, hmosPage.uuid, '', 0, 'entry/src/main/ets/ 为主代码目录');
    ws1.savePage(hmosPage.uuid);

    // 5. 全部保存以确保引用索引完整
    ws1.saveAll();

    console.info('[TestData] Demo graph seeded with ' + ws1.getAllPages().length + ' pages.');
  }

  private static insertBlock(ws: WorkspaceService, pageId: string, parentId: string, leftId: string, level: number, content: string): void {
    const blocks = ws.getPageBlocks(pageId);
    let lastSiblingId = leftId;
    if (lastSiblingId === '') {
      // 找到同 parent 下最后一个
      for (let i = blocks.length - 1; i >= 0; i--) {
        if (blocks[i].parentId === parentId && blocks[i].level === level) {
          lastSiblingId = blocks[i].uuid;
          break;
        }
      }
    }
    ws.executeOp({ type: 'insert-block', content: content, pageId: pageId, parentId: parentId, leftId: lastSiblingId, level: level });
  }
}
