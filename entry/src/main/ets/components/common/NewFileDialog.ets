import { TablerIcon } from './Icons';
import { GlassSurface, GlassMode } from './GlassSurface';
import { MaterialRole } from '../../theme/MaterialTokens';
import { AppState } from '../../state/AppState';
import { WorkspaceService } from '../../services/WorkspaceService';
import { WhiteboardFileService } from '../../services/WhiteboardFileService';
import { FileService } from '../../services/FileService';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * NewFileDialog —— 新建文件三选项对话框（对齐 Obsidian 的新建入口）。
 *
 * 三个选项（不再默认直接创建大纲笔记）：
 *   1. 新建 Markdown 笔记 —— 文档式页面，写入页面属性 type:: markdown，首块为普通段落
 *   2. 新建白板           —— 生成新 .canvas 画布（旧画布自动归档后写入空画布），跳转白板页
 *   3. 新建大纲笔记       —— Logseq 式大纲块页（原默认行为）
 *
 * 打开方式：AppStorage 'callaite_newFileDialogOpen' = true（左栏「新建」、主页等入口共用）。
 */
@Component
export struct NewFileDialog {
  @StorageLink('callaite_newFileDialogOpen') open: boolean = false;
  @State hoveredKey: string = '';
  private seq: number = 0;

  private close(): void {
    AppStorage.setOrCreate('callaite_newFileDialogOpen', false);
  }

  /** 生成不重名的页面名 */
  private uniquePageName(base: string): string {
    const ws = WorkspaceService.getInstance();
    if (ws.getPageByName(base) === undefined) {
      return base;
    }
    let i = 2;
    while (ws.getPageByName(base + ' ' + i.toString()) !== undefined) {
      i++;
    }
    return base + ' ' + i.toString();
  }

  /** 选项 1：Markdown 笔记（文档式） */
  private createMarkdownNote(): void {
    const ws = WorkspaceService.getInstance();
    const name = this.uniquePageName('未命名笔记');
    ws.createPage(name);
    // 页面属性 type:: markdown（文档式渲染约定）
    const page = ws.getPageByName(name);
    if (page !== undefined) {
      page.properties.set('type', 'markdown');
    }
    AppState.setCurrentPage(name);
    this.close();
  }

  /** 选项 2：白板（.canvas） */
  private createWhiteboard(): void {
    const ctx = FileService.getContext();
    if (ctx === undefined) {
      this.close();
      return;
    }
    const dir = ctx.filesDir + '/whiteboards';
    const path = dir + '/default.canvas';
    const svc = WhiteboardFileService.getInstance();
    // 旧画布归档：default.canvas → default-<seq>.canvas（不丢用户数据）
    if (svc.loadRawCanvas(path) !== undefined) {
      this.seq = this.seq + 1;
      svc.saveRawCanvas(dir + '/default-' + Date.now().toString() + '.canvas',
        svc.loadRawCanvas(path) as string);
    }
    svc.saveCanvas(path, svc.createEmptyCanvas());
    hilog.info(0x0002, 'NewFileDialog', 'whiteboard created at %{public}s', path);
    AppState.setCurrentPage('Whiteboards');
    this.close();
  }

  /** 选项 3：大纲笔记（原默认行为） */
  private createOutlineNote(): void {
    const ws = WorkspaceService.getInstance();
    const name = this.uniquePageName('未命名');
    ws.createPage(name);
    AppState.setCurrentPage(name);
    this.close();
  }

  @Builder
  OptionRow(key: string, icon: string, title: string, desc: string, onTap: () => void) {
    Row({ space: 12 }) {
      Row() {
        TablerIcon(icon, 18, $r('app.color.primary'))
      }
      .width(40)
      .height(40)
      .borderRadius(10)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.surface2'))

      Column({ space: 2 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text'))
        Text(desc)
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(10)
    .stateStyles({
      normal: {
        .backgroundColor(this.hoveredKey === key ? $r('app.color.surface2') : Color.Transparent)
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onHover((isHover: boolean) => {
      this.hoveredKey = isHover ? key : '';
    })
    .onClick(() => {
      onTap();
    })
  }

  build() {
    if (this.open) {
      Stack({ alignContent: Alignment.Center }) {
        // 遮罩
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.4)')
          .onClick(() => {
            this.close();
          })

        // 对话框容器（自定义组件不支持链式属性，尺寸放外层容器）
        Column() {
          GlassSurface({
            radius: 14,
            fill: $r('app.color.surface1'),
            mode: GlassMode.EFFECT,
            materialRole: MaterialRole.MODAL
          }) {
            Column({ space: 6 }) {
              Row() {
                Text('新建')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text'))
                  .layoutWeight(1)
                Row() {
                  TablerIcon('x', 14, $r('app.color.muted_text'))
                }
                .width(24)
                .height(24)
                .justifyContent(FlexAlign.Center)
                .alignItems(VerticalAlign.Center)
                .borderRadius(4)
                .onClick(() => {
                  this.close();
                })
              }
              .width('100%')
              .margin({ bottom: 6 })

              this.OptionRow('md', 'file-description', '新建 Markdown 笔记',
                '文档式页面，适合连续撰写', (): void => {
                  this.createMarkdownNote();
                })
              this.OptionRow('wb', 'layout-grid', '新建白板',
                '无限画布，支持形状 / 连线 / 手写笔', (): void => {
                  this.createWhiteboard();
                })
              this.OptionRow('outline', 'list-details', '新建大纲笔记',
                'Logseq 式块大纲，适合逐条记录', (): void => {
                  this.createOutlineNote();
                })
            }
            .width('100%')
            .padding(16)
          }
        }
        .width('86%')
        .constraintSize({ maxWidth: 380 })
      }
      .width('100%')
      .height('100%')
    }
  }
}
