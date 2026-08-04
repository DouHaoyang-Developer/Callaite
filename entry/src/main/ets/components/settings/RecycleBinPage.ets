import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { WorkspaceService } from '../../services/WorkspaceService';
import { PageData } from '../../core/models/Page';

/**
 * RecycleBinPage — 回收站页面。
 * 显示可恢复的已删除页面（基于文件系统）。
 */
@Component
export struct RecycleBinPage {
  @State deletedPages: PageData[] = [];

  aboutToAppear(): void {
    // 回收站目前为空（DataStore.deletePage 直接删除文件）
    // 后续可改造为软删除（移动到回收站目录）
  }

  build() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Row() { TablerIcon('arrow-left', 18, $r('app.color.text')) }
        .width(36).height(36)
        .onClick(() => { AppState.setCurrentPage('Settings'); })

        Text('回收站')
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
      }
      .width('100%').padding({ top: 24, bottom: 12 })

      if (this.deletedPages.length === 0) {
        Column({ space: 12 }) {
          TablerIcon('trash', 40, '#D1D5DB')
          Text('回收站为空')
            .fontSize(16).fontColor($r('app.color.muted_text'))
          Text('删除的页面会出现在这里')
            .fontSize(13).fontColor($r('app.color.muted_text'))
        }
        .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 60 })
      } else {
        ForEach(this.deletedPages, (page: PageData) => {
          Row({ space: 8 }) {
            TablerIcon('file', 16, $r('app.color.muted_text'))
            Text(page.originalName).fontSize(14).fontColor($r('app.color.text')).layoutWeight(1)
            Text('恢复').fontSize(13).fontColor($r('app.color.primary'))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(4).backgroundColor($r('app.color.surface2'))
          }
          .width('100%').height(40).padding({ left: 12, right: 12 })
        }, (page: PageData) => page.uuid)
      }
      Blank()
    }
    .width('100%').height('100%').padding({ left: 24, right: 24 }).alignItems(HorizontalAlign.Start)
  }
}
