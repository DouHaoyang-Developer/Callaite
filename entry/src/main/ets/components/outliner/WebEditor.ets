import { webview } from '@kit.ArkWeb';
import { EditorService } from '../../services/EditorService';
import { WorkspaceService } from '../../services/WorkspaceService';
import { JournalService } from '../../services/JournalService';

/**
 * WebEditor — 基于 WebView 的 contenteditable 编辑器。
 *
 * 实现 Logseq 级别的键盘体验:
 *  - Enter → 创建新 Block
 *  - Shift+Enter → 块内换行
 *  - Tab → 缩进
 *  - Shift+Tab → 反缩进
 *  - Backspace(空行) → 删除并合并
 *  - Arrow up/down → 跨 Block 导航
 *
 * 通过 JavaScript Bridge 与 ArkTS 通信:
 *  - ArkTS → JS:  controller.runJavaScript(code)
 *  - JS → ArkTS: nativeProxy.onAction(action, data)
 */
@Component
export struct WebEditor {
  @Prop blockUuid: string = '';
  @Prop initialContent: string = '';
  @Prop pageName: string = '';
  onSave: () => void = () => {};
  onAction: (action: string, data: string) => void = (_a: string, _d: string) => {};

  private controller: webview.WebviewController = new webview.WebviewController();
  @State private htmlContent: string = '';
  private editorReady: boolean = false;
  private bridgeObj: NativeBridge = new NativeBridge(this);

  aboutToAppear(): void {
    const escaped = this.initialContent
      .replace(/\\/g, '\\\\').replace(/`/g, '\\`').replace(/\$/g, '\\$');
    this.htmlContent = WebEditorHTML
      .replace('__CONTENT__', escaped)
      .replace('__BLOCK_ID__', this.blockUuid);
  }

  build() {
    Web({
      src: this.htmlContent,
      controller: this.controller
    })
      .width('100%')
      .height(32)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .javaScriptProxy({
        object: this.bridgeObj,
        name: 'nativeProxy',
        methodList: ['onAction', 'getContent'],
        controller: this.controller
      })
      .onPageEnd(() => {
        this.editorReady = true;
      })
  }

  // Bridge registered via javaScriptProxy — NativeBridge 处理所有 JS 回调

  /**
   * 外部调用：设置焦点到编辑器。
   */
  focus(): void {
    if (this.editorReady) {
      try {
        this.controller.runJavaScript('focusEditor()');
      } catch (_e) { /* ignore */ }
    }
  }
}

/**
 * 自包含 HTML 编辑器页面。
 * 使用原生 contenteditable + keyboard event 拦截实现 Logseq 级键盘体验。
 */
/**
 * NativeBridge — JS 桥接对象。
 * 被 WebView JavaScript 调用，传递编辑器操作回 ArkTS。
 */
class NativeBridge {
  private parent: WebEditor;
  constructor(parent: WebEditor) { this.parent = parent; }

  onAction(action: string, data: string): void {
    const ws = WorkspaceService.getInstance();
    const editor = EditorService.getInstance();

    if (action === 'save') {
      editor.updateBlockContent(this.parent.blockUuid, data);
      this.parent.onSave();
    } else if (action === 'newBlock') {
      const page = ws.getPageByName(this.parent.pageName);
      if (page) {
        const newUuid = editor.createBlockBelow(page.uuid);
        this.parent.onAction('focusNew', newUuid);
      }
      editor.updateBlockContent(this.parent.blockUuid, data);
    } else if (action === 'indent') {
      editor.setFocusedBlock(this.parent.blockUuid);
      editor.indentBlock();
      editor.updateBlockContent(this.parent.blockUuid, data);
    } else if (action === 'outdent') {
      editor.setFocusedBlock(this.parent.blockUuid);
      editor.outdentBlock();
      editor.updateBlockContent(this.parent.blockUuid, data);
    } else if (action === 'delete') {
      editor.setFocusedBlock(this.parent.blockUuid);
      editor.deleteEmptyBlock();
      this.parent.onAction('focusPrev', '');
    } else if (action === 'focusPrev') {
      this.parent.onAction('focusPrev', '');
    } else if (action === 'focusNext') {
      this.parent.onAction('focusNext', '');
    }
  }

  getContent(): string {
    return '';
  }
}

const WebEditorHTML: string = `<!DOCTYPE html><html><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;font-size:15px;line-height:28px;color:#1a1a1a;background:transparent;padding:0 4px;}
#editor{outline:none;min-height:28px;word-break:break-word;white-space:pre-wrap;}
#editor:empty:before{content:attr(data-placeholder);color:#9ca3af;}
</style></head><body>
<div id="editor" contenteditable="true" data-placeholder="输入内容...">__CONTENT__</div>
<script>
const blockId='__BLOCK_ID__';
const editor=document.getElementById('editor');

// 初始化: 光标移到末尾
function focusEditor(){editor.focus();placeCaretAtEnd(editor);}
function placeCaretAtEnd(el){const range=document.createRange();range.selectNodeContents(el);range.collapse(false);const sel=window.getSelection();sel.removeAllRanges();sel.addRange(range);}

// 键盘拦截
editor.addEventListener('keydown',function(e){
  const text=editor.innerText||'';

  // Enter (无 Shift): 创建新 Block
  if(e.key==='Enter' && !e.shiftKey){
    e.preventDefault();
    // 分割光标前后的内容
    const sel=window.getSelection();
    if(sel.rangeCount>0){
      const range=sel.getRangeAt(0);
      const before=range.startContainer.textContent?.substring(0,range.startOffset)||'';
      const after=editor.innerText?.substring(range.startOffset)||'';
      // 更新当前 Block 为光标前的内容
      editor.innerText=before;
      // 通知 ArkTS 创建新 Block，内容为光标后
      if(window.nativeProxy){
        window.nativeProxy.onAction('newBlock',after||'');
      }
    }else{
      if(window.nativeProxy) window.nativeProxy.onAction('newBlock','');
    }
    return;
  }

  // Shift+Enter: 换行 (默认行为)
  if(e.key==='Enter' && e.shiftKey){return;}

  // Tab: 缩进
  if(e.key==='Tab' && !e.shiftKey){
    e.preventDefault();
    if(window.nativeProxy) window.nativeProxy.onAction('indent',editor.innerText||'');
    return;
  }

  // Shift+Tab: 反缩进
  if(e.key==='Tab' && e.shiftKey){
    e.preventDefault();
    if(window.nativeProxy) window.nativeProxy.onAction('outdent',editor.innerText||'');
    return;
  }

  // Backspace(空行): 删除并合并
  if(e.key==='Backspace' && (text===''||text==='\\n')){
    if(window.nativeProxy) window.nativeProxy.onAction('delete','');
    return;
  }

  // ArrowUp(光标在首行首位置): 焦点上移
  if(e.key==='ArrowUp'){
    const sel=window.getSelection();
    if(sel&&sel.rangeCount>0&&sel.getRangeAt(0).startOffset===0){
      // 检查是否在第一行
      const range=sel.getRangeAt(0);
      if(range.startContainer===editor||range.startContainer===editor.firstChild){
        if(window.nativeProxy) window.nativeProxy.onAction('focusPrev','');
        e.preventDefault();
        return;
      }
    }
  }

  // ArrowDown(光标在末行末位置): 焦点下移
  if(e.key==='ArrowDown'){
    const sel=window.getSelection();
    if(sel&&sel.rangeCount>0){
      const range=sel.getRangeAt(0);
      const lastChild=editor.lastChild;
      if(lastChild&&range.startContainer===lastChild){
        const textLen=lastChild.textContent?.length||0;
        if(range.startOffset>=textLen-1){
          if(window.nativeProxy) window.nativeProxy.onAction('focusNext','');
          e.preventDefault();
          return;
        }
      }
    }
  }
});

// 失焦时保存
editor.addEventListener('blur',function(){
  if(window.nativeProxy) window.nativeProxy.onAction('save',editor.innerText||'');
});

// 斜杠触发: 检测 / 开头的行
editor.addEventListener('keyup',function(e){
  if(e.key==='/'){
    const text=editor.innerText||'';
    const sel=window.getSelection();
    if(sel&&sel.rangeCount>0){
      const range=sel.getRangeAt(0);
      const node=range.startContainer;
      const offset=range.startOffset;
      if(node&&offset===1&&node.textContent?.charAt(0)==='/'){
        if(window.nativeProxy) window.nativeProxy.onAction('slashOpen','');
      }
    }
  }
});

// 初始化焦点
setTimeout(focusEditor,100);

// 监听来自 ArkTS 的调用
window.updateContent=function(content){
  editor.innerText=content;
  focusEditor();
};
</script></body></html>`;
