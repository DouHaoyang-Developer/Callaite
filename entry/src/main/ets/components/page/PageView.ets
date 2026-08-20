import { BlockList } from '../outliner/BlockList';
import { JournalFeed } from './JournalFeed';
import { JournalService } from '../../services/JournalService';
import { SettingsPage } from '../settings/SettingsPage';
import { QueryBuilder } from '../query/QueryBuilder';
import { GraphView } from '../graph/GraphView';
import { Whiteboard } from '../whiteboard/Whiteboard';
import { FlashcardPage } from '../flashcard/FlashcardPage';
import { PdfPage } from '../extensions/PdfPage';
import { ProUpgradePage } from '../settings/ProUpgradePage';
import { WorkspaceService } from '../../services/WorkspaceService';
import { t } from '../../utils/i18n';
import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { PageData } from '../../core/models/Page';
import { bundleManager } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';

@Component
export struct PageView {
  @StorageLink('callaite_currentPage') @Watch('onPageChanged') currentPage: string = 'Journal';
  @State displayName: string = '';
  @State showProperties: boolean = false;
  @State pagePropKeys: string[] = [];
  @State pagePropValues: string[] = [];
  @State versionText: string = '';

  aboutToAppear(): void {
    this.resolvePage();
    // 从 bundle 读取真实版本号（不再硬编码）
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
      .then((info: bundleManager.BundleInfo) => {
        this.versionText = 'v' + info.versionName;
      })
      .catch(() => {
        this.versionText = '';
      });
  }

  /**
   * 显示标题：日志日期页（yyyy-MM-dd）显示本地化日期，其余显示页面名。
   * 注意：必须是普通方法 —— struct 上的 getter 会被 ArkTS 编译器静默丢弃。
   */
  getDisplayTitle(): string {
    if (/^\d{4}-\d{2}-\d{2}$/.test(this.displayName)) {
      return JournalService.formatJournalTitle(this.displayName);
    }
    return this.displayName;
  }

  /**
   * 响应式内容留白：窄屏（手机）20vp，宽屏（平板/2in1）48vp。
   * Logseq 桌面端内容区更宽，移动端更紧凑。
   */
  getContentPadding(): number {
    try {
      const d = display.getDefaultDisplaySync();
      if (d.width / d.densityPixels < 768) {
        return 20;
      }
    } catch (_e) {
      // 取不到显示信息时用窄屏值
    }
    return 48;
  }

  /**
   * currentPage 变更时重新解析页面名与属性。
   * 修复：此前仅在 aboutToAppear 调用 resolvePage，切换页面后标题/属性不刷新。
   */
  onPageChanged(): void {
    this.resolvePage();
  }

  resolvePage(): void {
    if (this.currentPage === 'Journal') {
      JournalService.ensureTodayJournal();
      this.displayName = JournalService.getTodayDateString();
    } else {
      this.displayName = this.currentPage;
    }
    this.loadProperties();
  }

  loadProperties(): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.displayName);
    const keys: string[] = [];
    const values: string[] = [];
    if (page) {
      page.properties.forEach((key: string, value: string) => {
        keys.push(key);
        values.push(value);
      });
    }
    this.pagePropKeys = keys;
    this.pagePropValues = values;
  }

  build() {
    if (this.currentPage === 'Settings') {
      SettingsPage()
    } else if (this.currentPage === 'Journal') {
      // 日志首页 = 时间流 feed（Logseq all-journals）
      JournalFeed()
    } else if (this.currentPage === 'Graph') {
      GraphView()
    } else if (this.currentPage === 'Whiteboards') {
      Whiteboard()
    } else if (this.currentPage === 'Flashcards') {
      FlashcardPage()
    } else if (this.currentPage === 'Pdf') {
      PdfPage()
    } else if (this.currentPage === 'ProUpgrade') {
      ProUpgradePage()
    } else if (this.currentPage === 'AllPages') {
      this.AllPagesView()
    } else if (this.currentPage === 'Recycle') {
      this.RecycleView()
    } else if (this.currentPage === 'About') {
      this.AboutView()
    } else {
      // 外层容器：内容列限宽 960vp 并水平居中（--ls-main-content-max-width）
      Column({ space: 0 }) {
        Column({ space: 0 }) {
        // 页面标题（Logseq 风格: 大号粗体；日志日期页显示本地化日期）
        Text(this.getDisplayTitle())
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
          .width('100%')
          .padding({ top: 20, bottom: 8 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // ─── 属性区：logseq 内联 key:: value 风格（仅页面有属性时显示）───
        if (this.pagePropKeys.length > 0) {
          Row({ space: 6 }) {
            Text(this.showProperties ? '−' : '+')
              .fontSize(14)
              .fontColor($r('app.color.muted_text'))
              .width(14)
            Text(t('properties').toUpperCase())
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.muted_text'))
              .letterSpacing(0.8)
            Text('· ' + this.pagePropKeys.length.toString())
              .fontSize(11)
              .fontColor($r('app.color.muted_text'))
              .opacity(0.7)
          }
          .width('100%')
          .padding({ top: 12, bottom: 6, left: 4, right: 4 })
          .onClick(() => { this.showProperties = !this.showProperties; })

          if (this.showProperties) {
            Column({ space: 2 }) {
              ForEach(this.pagePropKeys, (key: string, idx: number) => {
                // logseq 内联属性渲染：key 用主色 + :: 分隔符 + value
                Row({ space: 0 }) {
                  Text(key)
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.primary'))
                  Text('::')
                    .fontSize(13)
                    .fontColor($r('app.color.muted_text'))
                    .padding({ left: 4, right: 6 })
                  Text(this.pagePropValues[idx])
                    .fontSize(13)
                    .fontColor($r('app.color.text'))
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .padding({ top: 2, bottom: 2, left: 20 })
              }, (key: string) => key)
            }
            .width('100%')
            .padding({ top: 4, bottom: 8 })
          }
        }

        // Block 列表
        Scroll() {
          BlockList({ pageName: this.displayName })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)

        Blank()
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: 960 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.getContentPadding(), right: this.getContentPadding() })
    .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  QueryView() {
    Column({ space: 16 }) {
      Text('图谱 / 查询').fontSize(32).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        .width('100%').padding({ top: 24, bottom: 8 })
      Scroll() { QueryBuilder() }.width('100%').layoutWeight(1)
      Blank()
    }
    .width('100%').height('100%').padding({ left: 24, right: 24 }).alignItems(HorizontalAlign.Start)
  }

  /**
   * 所有页面视图 — 对应 logseq all_pages.cljs。
   * 修复：此前 LeftSidebar 点击"所有页面"会跳到不存在的 AllPages 页面。
   */
  @Builder
  AllPagesView() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Text(t('nav_all_pages'))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 24, bottom: 16 })

      Scroll() {
        Column({ space: 0 }) {
          ForEach(WorkspaceService.getInstance().getAllPages(), (page: PageData) => {
            Row({ space: 12 }) {
              TablerIcon(page.journalDay !== '' ? 'calendar' : 'file', 16, $r('app.color.muted_text'))
              Column({ space: 2 }) {
                Text(page.originalName)
                  .fontSize(15)
                  .fontColor($r('app.color.text'))
                if (page.tags.length > 0) {
                  Text(page.tags.join(', '))
                    .fontSize(11)
                    .fontColor($r('app.color.muted_text'))
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text(new Date(page.updatedAt).toLocaleDateString())
                .fontSize(11)
                .fontColor($r('app.color.muted_text'))
            }
            .width('100%')
            .height(48)
            .padding({ left: 12, right: 12 })
            .borderRadius(6)
            .onClick(() => { AppState.setCurrentPage(page.originalName); })
          }, (page: PageData) => page.uuid)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 48, right: 48 })
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 回收站视图 — 对应 logseq recycle.cljs。
   */
  @Builder
  RecycleView() {
    Column({ space: 0 }) {
      Text(t('nav_recycle'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text'))
        .width('100%')
        .padding({ top: 24, bottom: 16 })

      Column({ space: 12 }) {
        TablerIcon('trash', 40, $r('app.color.muted_text'))
        Text('回收站暂无内容')
          .fontSize(14)
          .fontColor($r('app.color.muted_text'))
      }
      .width('100%')
      .padding({ top: 60 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 48, right: 48 })
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 关于视图 — 对应 logseq about 页面。
   */
  @Builder
  AboutView() {
    Column({ space: 16 }) {
      Text(t('nav_about'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text'))
        .width('100%')
        .padding({ top: 24, bottom: 16 })

      Column({ space: 8 }) {
        TablerIcon('bolt', 48, $r('app.color.primary'))
        Text(t('app_name'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
        if (this.versionText !== '') {
          Text(this.versionText)
            .fontSize(13)
            .fontColor($r('app.color.muted_text'))
        }
        Text(t('onboarding_desc'))
          .fontSize(13)
          .fontColor($r('app.color.muted_text'))
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ top: 40 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 48, right: 48 })
    .alignItems(HorizontalAlign.Start)
  }
}
