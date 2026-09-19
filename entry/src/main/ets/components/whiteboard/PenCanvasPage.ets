import { HandwriteComponent, HandwriteController, PenType, PenHspInfo, HiddenToolType, HiddenConfig } from '@kit.Penkit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0002;
const TAG = 'PenCanvasPage';

/**
 * PenCanvasPage —— 基于 Pen Kit 手写套件的原生手写白板。
 *
 * 设计取舍（对应"白板优先直接接入 Pen Kit，再进行 Canvas 适配"）：
 *   Pen Kit 手写套件由系统提供**原生笔迹渲染管线**（笔刷效果 / 笔迹编辑 / 报点预测 /
 *   一笔成形），并自动开启报点预测与一笔成形，无需自行实现，因此优先采用；
 *   仅在设备不支持 `SystemCapability.Stylus.Handwrite` 时，才回退到自研 Canvas 白板。
 *
 * 已覆盖的 Pen Kit 能力（API 均取自本地 SDK 声明 @hms.stylus.HandwriteComponent.d.ets）：
 *   · HandwriteComponent   : handwriteController / onInit / onScale / onDidScroll
 *                            defaultPenType / defaultPenInfo / widthRatio / heightRatio
 *                            maxCanvasHeight / scaleDisabled / hiddenTools(API 26)
 *   · HandwriteController  : save / load / onLoad / getContentRange / getThumbnail / scrollTo
 *   · 一笔成形             : InstantShapeGenerator（套件内自动启用）
 *   · 报点预测             : PointPredictor（套件内自动启用）
 */
@Component
export struct PenCanvasPage {
  /** 手写套件功能入口 */
  private controller: HandwriteController = new HandwriteController();
  /** 手写文件路径（.hw） */
  @State filePath: string = '';
  /** 当前缩放比 */
  @State zoomScale: number = 1.0;   // 注意：不可命名为 scale，与 CustomComponent 基类方法冲突
  /** 已加载完成 */
  @State loaded: boolean = false;
  /** 加载错误信息 */
  @State errorMsg: string = '';
  /** 保存中 */
  @State saving: boolean = false;
  /** 最近一次保存提示 */
  @State savedHint: string = '';
  /** 缩略图（getThumbnail 结果） */
  @State thumb: PixelMap | undefined = undefined;
  /** 长画布最大高度（vp）——6.1.0(23) 起支持 */
  private readonly maxCanvasHeight: number = 8000;
  /** 默认笔型与各笔刷宽度 —— 5.1.0(18) 起支持 */
  private readonly defaultPenType: PenType = PenType.PEN;
  private readonly penInfos: PenHspInfo[] = [
    { penType: PenType.PEN, penWidth: 3 },
    { penType: PenType.PENCIL, penWidth: 2 },
    { penType: PenType.MARKER, penWidth: 12 },
    { penType: PenType.HIGHLIGHTER_BRUSH, penWidth: 20 },
    { penType: PenType.RUBBER, penWidth: 16 }
  ];
  /**
   * 隐藏不需要的工具 —— API 26.0.0 新增能力。
   * 本例隐藏镭射笔与图形工具，保留书写类笔刷 + 套索，贴合笔记白板场景。
   */
  private readonly hiddenTools: HiddenConfig = {
    hiddenOptionalTools: [HiddenToolType.LASER, HiddenToolType.GRAPHICS_TOOLS],
    hiddenArcBox: false
  };

  aboutToAppear(): void {
    // 手写文件放在应用沙箱 filesDir 下（与官方示例一致）
    const ctx = this.getUIContext().getHostContext();
    const dir: string = ctx !== undefined ? ctx.filesDir : '';
    this.filePath = dir + '/callaite_whiteboard.hw';
    this.prepareFile();
    // 注册加载完成回调（回调参数为该手写内容页 id）
    this.controller.onLoad((err, pageId) => {
      if (err) {
        this.errorMsg = '加载手写内容失败: ' + err.message;
        hilog.error(DOMAIN, TAG, 'onLoad failed: %{public}s', err.message);
        return;
      }
      this.loaded = true;
      this.errorMsg = '';
      hilog.info(DOMAIN, TAG, 'handwrite loaded, pageId=%{public}s', pageId);
    });
    // load 会抛出 BusinessError 1010400001（load failed），必须显式捕获
    try {
      this.controller.load(this.filePath);
    } catch (e) {
      const err = e as BusinessError;
      this.errorMsg = '手写内容加载失败（' + err.code.toString() + '）';
      hilog.error(DOMAIN, TAG, 'controller.load failed: code=%{public}d msg=%{public}s', err.code, err.message);
    }
  }

  aboutToDisappear(): void {
    // 退出页面自动保存，避免笔迹丢失
    this.doSave(true);
  }

  /** 确保手写文件存在（Pen Kit 的 load 需要文件已存在或可创建） */
  private prepareFile(): void {
    try {
      if (!fs.accessSync(this.filePath)) {
        const f = fs.openSync(this.filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
        fs.closeSync(f);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'prepareFile failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 保存笔迹。silent=true 时用于退出自动保存，不展示提示 */
  private async doSave(silent: boolean): Promise<void> {
    if (this.saving) {
      return;
    }
    this.saving = true;
    try {
      await this.controller.save(this.filePath);
      if (!silent) {
        this.savedHint = '已保存';
      }
      hilog.info(DOMAIN, TAG, 'saved to %{public}s', this.filePath);
    } catch (e) {
      const msg: string = JSON.stringify(e);
      this.errorMsg = '保存失败: ' + msg;
      hilog.error(DOMAIN, TAG, 'save failed: %{public}s', msg);
    } finally {
      this.saving = false;
    }
  }

  /** 生成缩略图（6.0.0(20) 起支持） */
  private async makeThumbnail(): Promise<void> {
    try {
      const rect = this.controller.getContentRange();
      this.thumb = await this.controller.getThumbnail(rect);
      hilog.info(DOMAIN, TAG, 'thumbnail generated');
    } catch (e) {
      this.errorMsg = '缩略图生成失败';
      hilog.error(DOMAIN, TAG, 'getThumbnail failed: %{public}s', JSON.stringify(e));
    }
  }

  build() {
    Column() {
      // ─── 顶部工具条（应用侧，用于保存/缩略图/缩放显示）───
      Row({ space: 10 }) {
        Text('手写白板')
          .fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text'))
          .layoutWeight(1)

        if (this.thumb !== undefined) {
          Image(this.thumb)
            .width(36).height(24)
            .borderRadius(4)
            .objectFit(ImageFit.Cover)
        }

        Text(Math.round(this.zoomScale * 100).toString() + '%')
          .fontSize(12).fontColor($r('app.color.muted_text'))

        Button(this.saving ? '保存中…' : '保存')
          .fontSize(13)
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.primary'))
          .fontColor($r('app.color.on_primary'))
          .enabled(!this.saving)
          .onClick(() => {
            this.doSave(false);
          })

        Button('缩略图')
          .fontSize(13)
          .type(ButtonType.Capsule)
          .backgroundColor($r('app.color.surface2'))
          .fontColor($r('app.color.text'))
          .onClick(() => {
            this.makeThumbnail();
          })
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 12 })
      .backgroundColor($r('app.color.surface1'))
      .border({ width: { bottom: 0.5 }, color: $r('app.color.border') })

      if (this.errorMsg !== '') {
        Text(this.errorMsg)
          .fontSize(12)
          .fontColor($r('app.color.danger'))
          .width('100%')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      }

      // ─── 手写画布（Pen Kit 原生套件）───
      HandwriteComponent({
        handwriteController: this.controller,
        onInit: () => {
          hilog.info(DOMAIN, TAG, 'handwrite component initialized');
        },
        onScale: (scale: number) => {
          this.zoomScale = scale;
        },
        onDidScroll: (offset: number) => {
          hilog.debug(DOMAIN, TAG, 'canvas scrolled offset=%{public}d', offset);
        },
        defaultPenType: this.defaultPenType,
        defaultPenInfo: this.penInfos,
        widthRatio: 1,
        heightRatio: 1,
        maxCanvasHeight: this.maxCanvasHeight,
        scaleDisabled: false,
        // API 26：按应用场景裁剪工具集
        hiddenTools: this.hiddenTools
      })
        .layoutWeight(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface0'))
  }
}

/**
 * 设备是否具备手写套件能力。
 * 官方 SysCap：SystemCapability.Stylus.Handwrite（起始 5.0.0(12)）
 */
export function isPenKitSupported(): boolean {
  return canIUse('SystemCapability.Stylus.Handwrite');
}
