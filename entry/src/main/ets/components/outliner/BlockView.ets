import { BlockData } from '../../core/models/Block';
import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';
import { ContentRenderer, ContentSegment, SegmentType } from '../../utils/ContentRenderer';
import { MathRenderer } from '../extensions/MathRenderer';
import { MermaidRenderer } from '../extensions/MermaidRenderer';
import { WebEditor } from './WebEditor';

@Component
export struct BlockView {
  @Prop blockUuid: string = '';
  @Prop depth: number = 0;
  @State isEditing: boolean = false;
  @State editContent: string = '';
  @State showActions: boolean = false;
  @State displaySegments: ContentSegment[] = [];
  @State isHovered: boolean = false;
  @State bulletColor: string = '#A0A3A8';
  private blockData: BlockData | undefined;

  aboutToAppear(): void { this.refreshBlock(); }

  refreshBlock(): void {
    const ws = WorkspaceService.getInstance();
    this.blockData = ws.getBlock(this.blockUuid);
    if (this.blockData) this.displaySegments = ContentRenderer.parse(this.blockData.content);
  }

  build() {
    if (!this.blockData) { Row().width('100%').height(0) }
    else {
      Column() {
        Row() {
          if (this.depth > 0) {
            ForEach(this.buildGuideArray(), (idx: number) => {
              Row() {
                Column().width(1).height('100%').backgroundColor('#E8E9EA').margin({ left: 8 })
                Blank().width(15)
              }.width(24).height('100%')
            }, (idx: number) => idx.toString())
          }

          Row({ space: 8 }) {
            Circle({ width: 6, height: 6 }).fill(this.bulletColor).margin({ top: 5 })
              .animation({ duration: 150, curve: Curve.EaseOut })

            Row({ space: 4 }) {
              if (this.blockData.marker !== '') {
                Text(this.blockData.marker).fontSize(11).fontWeight(FontWeight.Medium)
                  .fontColor(this.getMarkerColor(this.blockData.marker))
                  .padding({ left: 4, right: 4, top: 2, bottom: 2 }).borderRadius(3)
                  .backgroundColor(this.getMarkerBg(this.blockData.marker))
                  .onClick(() => { EditorService.getInstance().setFocusedBlock(this.blockUuid); EditorService.getInstance().cycleMarker(); this.refreshBlock(); })
              }
              if (this.isEditing) {
                WebEditor({ blockUuid: this.blockUuid, initialContent: this.blockData.content, pageName: this.resolvePageName(),
                  onSave: () => { this.isEditing = false; this.refreshBlock(); },
                  onAction: (_a: string, _d: string) => { this.refreshBlock(); } }).layoutWeight(1)
              } else {
                Row({ space: 0 }) {
                  if (this.displaySegments.length === 0) {
                    Text(' ').fontSize(15).fontColor('#A0A3A8').height(28).onClick(() => { this.enterEdit(); })
                  } else {
                    ForEach(this.displaySegments, (seg: ContentSegment, idx: number) => {
                      if (seg.type === SegmentType.IMAGE) {
                        Image(seg.text).width(120).height(80).objectFit(ImageFit.Cover).borderRadius(4)
                      } else if (seg.type === SegmentType.MATH_BLOCK) {
                        MathRenderer({ formula: seg.text, displayMode: true })
                      } else if (seg.type === SegmentType.MATH_INLINE) {
                        MathRenderer({ formula: seg.text, displayMode: false })
                      } else if (seg.type === SegmentType.MERMAID) {
                        MermaidRenderer({ code: seg.text })
                      } else if (seg.type === SegmentType.BLOCKQUOTE) {
                        Row() { Column().width(3).height('100%').backgroundColor('#D1D5DB').margin({right:8}); Text(seg.text).fontSize(14).fontColor('#787B80').fontStyle(FontStyle.Italic).layoutWeight(1) }.width('100%').padding({left:4,top:2,bottom:2})
                      } else {
                        Text(seg.text).fontSize(15)
                          .fontColor(ContentRenderer.getSegmentColor(seg.type))
                          .fontWeight(seg.type === SegmentType.BOLD ? FontWeight.Bold : FontWeight.Normal)
                          .fontStyle(seg.type === SegmentType.ITALIC ? FontStyle.Italic : FontStyle.Normal)
                          .decoration({ type: seg.type === SegmentType.STRIKETHROUGH ? TextDecorationType.LineThrough : TextDecorationType.None, color: '#787B80' })
                          .backgroundColor(seg.type === SegmentType.HIGHLIGHT ? '#FFF9E6' : Color.Transparent)
                          .fontFamily(seg.type === SegmentType.CODE ? 'monospace' : '').height(28)
                          .onClick(() => { if (ContentRenderer.isClickable(seg.type)) ContentRenderer.handleClick(seg.type, seg.text); else this.enterEdit(); })
                      }
                    }, (seg: ContentSegment, idx: number) => idx.toString())
                  }
                }.layoutWeight(1)
              }
            }.layoutWeight(1)

            if (this.isHovered || this.showActions) {
              Row() { Text('···').fontSize(12).fontColor('#A0A3A8') }.width(20).height(20).onClick(()=>{this.showActions=!this.showActions;})
            }
          }.width('100%').padding({ top: 4, bottom: 4 })
        }.width('100%')
        .onHover((isHover: boolean) => { this.isHovered = isHover; this.bulletColor = isHover ? '#0458A6' : '#A0A3A8'; })
        .onClick(() => { if (!this.isEditing) EditorService.getInstance().setFocusedBlock(this.blockUuid); })
        .backgroundColor(this.isHovered ? '#F3F3F4' : Color.Transparent).borderRadius(4)

        if (this.showActions) {
          Row({ space: 4 }) {
            Button(){Text('→').fontSize(13).fontColor('#3A3A3A')}.width(26).height(26).type(ButtonType.Circle).backgroundColor('#EAEAEB').onClick(()=>{EditorService.getInstance().indentBlock();this.refreshBlock();this.showActions=false;})
            Button(){Text('←').fontSize(13).fontColor('#3A3A3A')}.width(26).height(26).type(ButtonType.Circle).backgroundColor('#EAEAEB').onClick(()=>{EditorService.getInstance().outdentBlock();this.refreshBlock();this.showActions=false;})
            Button(){Text('↑').fontSize(13).fontColor('#3A3A3A')}.width(26).height(26).type(ButtonType.Circle).backgroundColor('#EAEAEB').onClick(()=>{EditorService.getInstance().moveBlockUp();this.refreshBlock();this.showActions=false;})
            Button(){Text('↓').fontSize(13).fontColor('#3A3A3A')}.width(26).height(26).type(ButtonType.Circle).backgroundColor('#EAEAEB').onClick(()=>{EditorService.getInstance().moveBlockDown();this.refreshBlock();this.showActions=false;})
            Button(){Text('×').fontSize(15).fontColor('#DC2626')}.width(26).height(26).type(ButtonType.Circle).backgroundColor('#EAEAEB').onClick(()=>{WorkspaceService.getInstance().executeOp({type:'delete-block',uuid:this.blockUuid});this.refreshBlock();this.showActions=false;})
          }.width('100%').padding({left:24,right:8,bottom:4})
        }
        if (this.hasEmbedSegments()) this.EmbedBlocks()
      }.width('100%').padding({ left: 16, right: 16 })
    }
  }

  enterEdit(): void { EditorService.getInstance().setFocusedBlock(this.blockUuid); this.isEditing = true; }
  resolvePageName(): string { const ws=WorkspaceService.getInstance(); const pid=ws.getPageUuidForBlock(this.blockUuid); if(pid){ const p=ws.getDataStore().getIndexStore().getPage(pid); if(p)return p.originalName; } return ''; }
  buildGuideArray(): number[] { const a:number[]=[]; for(let i=0;i<this.depth;i++)a.push(i); return a; }
  hasEmbedSegments(): boolean { for(let i=0;i<this.displaySegments.length;i++){ const t=this.displaySegments[i].type; if(t===SegmentType.BLOCK_EMBED||t===SegmentType.PAGE_EMBED)return true; } return false; }
  getEmbedUuids(): string[] { const u:string[]=[]; for(let i=0;i<this.displaySegments.length;i++){ if(this.displaySegments[i].type===SegmentType.BLOCK_EMBED)u.push(this.displaySegments[i].text); } return u; }
  @Builder EmbedBlocks() { Column({space:4}){ ForEach(this.getEmbedUuids(),(uuid:string)=>{ Column(){Text(this.getBlockContent(uuid)).fontSize(13).fontColor('#787B80').maxLines(3).textOverflow({overflow:TextOverflow.Ellipsis}).width('100%').padding({top:4,bottom:4,left:12,right:8})}.width('100%').backgroundColor('#F3F3F4').borderRadius(4).border({width:{left:2},color:'#0458A6'}).padding({left:24})},(uuid:string)=>uuid) }.width('100%') }
  getBlockContent(uuid: string): string { const ws=WorkspaceService.getInstance(); const b=ws.getBlock(uuid); if(b)return b.content.substring(0,120); return uuid.substring(0,8)+'...'; }
  getMarkerColor(m: string): ResourceColor { if(m==='DONE')return'#059669';if(m==='DOING')return'#0458A6';if(m==='TODO')return'#DC2626';if(m==='CANCELLED')return'#A0A3A8';return'#A0A3A8'; }
  getMarkerBg(m: string): ResourceColor { if(m==='DONE')return'#05966918';if(m==='DOING')return'#0458A618';if(m==='TODO')return'#DC262618';if(m==='CANCELLED')return'#787B8018';return Color.Transparent; }
}
