import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { WorkspaceService } from '../services/WorkspaceService';

export default class EntryFormAbility extends FormExtensionAbility {

  onAddForm(want: Want): formBindingData.FormBindingData {
    const data: Record<string, string> = EntryFormAbility.buildCardData();
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    try {
      const data: Record<string, string> = EntryFormAbility.buildCardData();
      const bindingData = formBindingData.createFormBindingData(data);
      formProvider.updateForm(formId, bindingData);
    } catch (_e) { /* 静默处理 */ }
  }

  onFormEvent(formId: string, message: string): void {
    console.info('[FormAbility] Event: ' + formId + ', msg: ' + message);
  }

  onRemoveForm(_formId: string): void {}

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  static buildCardData(): Record<string, string> {
    const result: Record<string, string> = {};
    try {
      const ws = WorkspaceService.getInstance();
      const pages = ws.getAllPages();
      result['title'] = 'Callaite · 笔记';
      result['pageCount'] = pages.length.toString();
      let found = 0;
      const previews: string[] = [];
      for (let i = 0; i < pages.length && found < 3; i++) {
        const blocks = ws.getPageBlocks(pages[i].uuid);
        for (let j = 0; j < blocks.length && found < 3; j++) {
          if (blocks[j].content !== '') {
            previews.push(blocks[j].content.substring(0, 50));
            found++;
          }
        }
      }
      result['preview1'] = previews.length > 0 ? previews[0] : '';
      result['preview2'] = previews.length > 1 ? previews[1] : '';
      result['preview3'] = previews.length > 2 ? previews[2] : '';
    } catch (_e) {
      result['title'] = 'Callaite';
    }
    return result;
  }
}
