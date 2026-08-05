import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { WorkspaceService } from '../services/WorkspaceService';
import { JournalService } from '../services/JournalService';
import { InsertBlockOp } from '../core/engine/OutlinerOps';
import { PageData } from '../core/models/Page';
import { BlockData } from '../core/models/Block';

/**
 * EntryFormAbility — 服务卡片 FormExtensionAbility。
 *
 * 职责：
 *  - onAddForm/onUpdateForm：根据 cardType 向卡片下发数据
 *  - 30 分钟定时刷新概览数据
 *  - onFormEvent：接收速记卡片提交的文本，调用 JournalService + WorkspaceService
 *                在今日日志页追加 Block
 */

interface OverviewData {
  title: string;
  pageCount: string;
  preview1: string;
  preview2: string;
  preview3: string;
}

interface CardFormData {
  title: string;
  pageCount: string;
  preview1: string;
  preview2: string;
  preview3: string;
  cardType: string;
  quickInput: string;
}

interface QuickNoteMessage {
  text: string;
}

const REFRESH_INTERVAL_MS: number = 30 * 60 * 1000;
const CARD_TYPE_OVERVIEW: string = 'overview';
const CARD_TYPE_QUICKNOTE: string = 'quicknote';
const PREVIEW_MAX_LENGTH: number = 50;
const PREVIEW_MAX_COUNT: number = 3;
const TOP_BLOCK_LEVEL: number = 0;

export default class EntryFormAbility extends FormExtensionAbility {
  private refreshTimerId: number = -1;

  onAddForm(want: Want): formBindingData.FormBindingData {
    const cardType: string = EntryFormAbility.parseCardType(want);
    const data: CardFormData = EntryFormAbility.buildCardData(cardType);
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    EntryFormAbility.refreshForm(formId, CARD_TYPE_OVERVIEW);
    this.scheduleNextRefresh(formId);
  }

  onCastTempForm(formId: string): void {
    EntryFormAbility.refreshForm(formId, CARD_TYPE_OVERVIEW);
  }

  onFormEvent(formId: string, message: string): void {
    console.info('[FormAbility] Event: ' + formId + ', msg: ' + message);
    EntryFormAbility.handleQuickNoteFromMessage(message);
    EntryFormAbility.refreshForm(formId, CARD_TYPE_OVERVIEW);
  }

  onRemoveForm(formId: string): void {
    if (this.refreshTimerId !== -1) {
      clearTimeout(this.refreshTimerId);
      this.refreshTimerId = -1;
    }
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  // ─── 定时刷新 ───

  /**
   * 30 分钟后再次刷新概览数据，并重新调度下一次刷新。
   * FormExtensionAbility 生命周期内有效；onRemoveForm 时清理定时器。
   */
  private scheduleNextRefresh(formId: string): void {
    this.refreshTimerId = setTimeout(() => {
      EntryFormAbility.refreshForm(formId, CARD_TYPE_OVERVIEW);
      this.scheduleNextRefresh(formId);
    }, REFRESH_INTERVAL_MS);
  }

  // ─── 数据获取 ───

  /**
   * 拉取概览卡片数据：页面总数 + 最近 3 条非空 Block 内容预览。
   */
  static fetchOverviewData(): OverviewData {
    const fallback: OverviewData = {
      title: 'Callaite',
      pageCount: '0',
      preview1: '',
      preview2: '',
      preview3: ''
    };
    try {
      const ws = WorkspaceService.getInstance();
      const pages: PageData[] = ws.getAllPages();
      const previews: string[] = [];
      let found = 0;
      for (let i = 0; i < pages.length && found < PREVIEW_MAX_COUNT; i++) {
        const blocks: BlockData[] = ws.getPageBlocks(pages[i].uuid);
        for (let j = 0; j < blocks.length && found < PREVIEW_MAX_COUNT; j++) {
          const content = blocks[j].content;
          if (content !== '') {
            previews.push(content.substring(0, PREVIEW_MAX_LENGTH));
            found++;
          }
        }
      }
      const result: OverviewData = {
        title: 'Callaite · 笔记',
        pageCount: pages.length.toString(),
        preview1: previews.length > 0 ? previews[0] : '',
        preview2: previews.length > 1 ? previews[1] : '',
        preview3: previews.length > 2 ? previews[2] : ''
      };
      return result;
    } catch (_e) {
      return fallback;
    }
  }

  /**
   * 组装卡片下发数据。
   */
  static buildCardData(cardType: string): CardFormData {
    const overview: OverviewData = EntryFormAbility.fetchOverviewData();
    const data: CardFormData = {
      title: overview.title,
      pageCount: overview.pageCount,
      preview1: overview.preview1,
      preview2: overview.preview2,
      preview3: overview.preview3,
      cardType: cardType,
      quickInput: ''
    };
    return data;
  }

  /**
   * 从 want.parameters 解析 cardType，缺省返回 overview。
   */
  static parseCardType(want: Want): string {
    try {
      const params = want.parameters;
      if (params !== undefined && params !== null) {
        const cardTypeObj: Object | undefined = params['cardType'];
        if (cardTypeObj !== undefined && cardTypeObj !== null) {
          const cardType: string = cardTypeObj.toString();
          if (cardType === CARD_TYPE_QUICKNOTE) {
            return CARD_TYPE_QUICKNOTE;
          }
        }
      }
    } catch (_e) { /* 静默 */ }
    return CARD_TYPE_OVERVIEW;
  }

  /**
   * 推送卡片数据到指定 formId。
   */
  static refreshForm(formId: string, cardType: string): void {
    try {
      const data: CardFormData = EntryFormAbility.buildCardData(cardType);
      const bindingData = formBindingData.createFormBindingData(data);
      formProvider.updateForm(formId, bindingData);
    } catch (_e) { /* 静默处理 */ }
  }

  // ─── 速记逻辑 ───

  /**
   * 从 onFormEvent 收到的 message 字符串中解析 text 字段并创建 Block。
   * message 期望为 JSON 字符串：{ "text": "..." }
   */
  static handleQuickNoteFromMessage(message: string): void {
    try {
      if (message === '') {
        return;
      }
      const parsed: QuickNoteMessage = JSON.parse(message) as QuickNoteMessage;
      if (parsed !== null && parsed !== undefined) {
        const text: string = parsed.text !== undefined ? parsed.text : '';
        if (text !== '') {
          EntryFormAbility.handleQuickNote(text);
        }
      }
    } catch (_e) { /* 静默 */ }
  }

  /**
   * 在今日日志页追加一条顶层 Block，内容为 text。
   * 若日志页不存在，JournalService.ensureTodayJournal 会自动创建。
   */
  static handleQuickNote(text: string): void {
    if (text === '') {
      return;
    }
    try {
      const dateStr: string = JournalService.ensureTodayJournal();
      const ws = WorkspaceService.getInstance();
      const page: PageData | undefined = ws.getJournalPage(dateStr);
      if (!page) {
        return;
      }
      const blocks: BlockData[] = ws.getPageBlocks(page.uuid);
      const lastBlock: BlockData | undefined = blocks.length > 0 ? blocks[blocks.length - 1] : undefined;
      const op: InsertBlockOp = {
        type: 'insert-block',
        content: text,
        pageId: page.uuid,
        parentId: page.uuid,
        leftId: lastBlock ? lastBlock.uuid : '',
        level: TOP_BLOCK_LEVEL
      };
      ws.executeOp(op);
      ws.savePage(page.uuid);
    } catch (_e) { /* 静默 */ }
  }
}
