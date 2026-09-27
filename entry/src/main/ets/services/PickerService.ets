import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from './FileService';

/**
 * 系统文件选择结果。
 */
export interface PickResult {
  /** 是否拿到了有效结果（用户取消时为 false） */
  success: boolean;
  /** 选中的 URI 列表；取消时为空数组 */
  uris: string[];
  /** 失败原因（可直接展示给用户）；取消时为空串 */
  error: string;
}

/**
 * PickerService — 系统文件选择器（DocumentViewPicker）封装。
 *
 * 职责单一：只负责「拉起系统选择器 / 读写选择结果」，
 * 不负责拷贝入库、不负责解析、不负责导出格式。
 *
 * 失败处理约定：
 *  - 用户主动取消 → success=false + error=''，不写 hilog.error（非故障）；
 *  - 真实异常（拉起失败、无上下文、越权）→ hilog.error + error 可读文案（不静默吞掉）。
 */
export class PickerService {
  private static readonly DOMAIN: number = 0x0000;
  private static readonly TAG: string = 'PickerService';
  /** 用户取消选择时系统返回的错误码。 */
  private static readonly ERR_CANCEL: number = 13900020;

  /**
   * 拉起文档选择器，返回选中文件的 URI 列表。
   *
   * @param suffixFilters 后缀过滤，格式遵循 DocumentSelectOptions.fileSuffixFilters，
   *                      例如 ['.pdf'] 或 ['Markdown 文档|.md,.markdown']
   * @param maxCount 最多可选数量（<=0 时按 1 处理）
   */
  static async pickDocuments(suffixFilters: string[], maxCount: number): Promise<PickResult> {
    const options = new picker.DocumentSelectOptions();
    if (suffixFilters.length > 0) {
      options.fileSuffixFilters = suffixFilters;
    }
    let limit = maxCount;
    if (limit <= 0) {
      limit = 1;
    }
    options.maxSelectNumber = limit;

    const context = FileService.getContext();
    if (!context) {
      const msg = '应用上下文未就绪，无法拉起文件选择器';
      hilog.error(PickerService.DOMAIN, PickerService.TAG, 'pickDocuments: context is undefined');
      return PickerService.failure(msg);
    }

    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await documentPicker.select(options);
      if (!uris || uris.length === 0) {
        hilog.info(PickerService.DOMAIN, PickerService.TAG, 'pickDocuments: user cancelled');
        return PickerService.cancelled();
      }
      hilog.info(PickerService.DOMAIN, PickerService.TAG,
        'pickDocuments: %{public}d file(s) selected', uris.length);
      return PickerService.ok(uris);
    } catch (e) {
      const err = e as BusinessError;
      if (err !== undefined && err.code === PickerService.ERR_CANCEL) {
        hilog.info(PickerService.DOMAIN, PickerService.TAG, 'pickDocuments: user cancelled (code 13900020)');
        return PickerService.cancelled();
      }
      const msg = '打开文件选择器失败：' + PickerService.errText(err);
      hilog.error(PickerService.DOMAIN, PickerService.TAG, 'pickDocuments failed: %{public}s', msg);
      return PickerService.failure(msg);
    }
  }

  /**
   * 拉起文档保存选择器，返回保存目标 URI（用户取消时返回空串）。
   *
   * @param fileName 建议文件名（含后缀），用户可在系统页面修改
   * @param suffix 后缀，用于系统侧的类型提示，例如 '.md'
   */
  static async pickSaveTarget(fileName: string, suffix: string): Promise<string> {
    const options = new picker.DocumentSaveOptions();
    const names: string[] = [];
    names.push(fileName);
    options.newFileNames = names;
    if (suffix.length > 0) {
      const choices: string[] = [];
      choices.push(suffix);
      options.fileSuffixChoices = choices;
    }

    const context = FileService.getContext();
    if (!context) {
      hilog.error(PickerService.DOMAIN, PickerService.TAG, 'pickSaveTarget: context is undefined');
      return '';
    }

    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await documentPicker.save(options);
      if (!uris || uris.length === 0) {
        hilog.info(PickerService.DOMAIN, PickerService.TAG, 'pickSaveTarget: user cancelled');
        return '';
      }
      hilog.info(PickerService.DOMAIN, PickerService.TAG, 'pickSaveTarget: %{public}s', uris[0]);
      return uris[0];
    } catch (e) {
      const err = e as BusinessError;
      if (err !== undefined && err.code === PickerService.ERR_CANCEL) {
        hilog.info(PickerService.DOMAIN, PickerService.TAG, 'pickSaveTarget: user cancelled (code 13900020)');
        return '';
      }
      hilog.error(PickerService.DOMAIN, PickerService.TAG, 'pickSaveTarget failed: %{public}s',
        PickerService.errText(err));
      return '';
    }
  }

  /**
   * 把 Picker 返回的 URI 拷贝进应用沙箱。
   *
   * 拷贝而非直接使用 URI：沙箱路径可被既有服务（ImportService / ExportService /
   * WebView 资源加载）无差别使用，避免把「URI 是否可用」的差异扩散到业务层。
   *
   * @param uri 系统文件 URI
   * @param destPath 沙箱目标文件路径（父目录需已存在）
   * @returns 是否拷贝成功
   */
  static copyUriToSandbox(uri: string, destPath: string): boolean {
    try {
      // mode 默认 0 = 覆盖同名文件并截断多余部分（与「重新导出到同一位置」的预期一致）
      fs.copyFileSync(uri, destPath);
      hilog.info(PickerService.DOMAIN, PickerService.TAG, 'copied %{public}s -> %{public}s', uri, destPath);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(PickerService.DOMAIN, PickerService.TAG,
        'copyUriToSandbox failed: uri=%{public}s dest=%{public}s cause=%{public}s',
        uri, destPath, PickerService.errText(err));
      return false;
    }
  }

  /**
   * 把 URI 暂存到应用缓存目录，返回沙箱路径；失败返回空串。
   *
   * 文件名加时间戳前缀，避免同名文件互相覆盖；缓存的暂存文件由系统按需回收。
   */
  static stageUri(uri: string): string {
    const context = FileService.getContext();
    if (!context) {
      hilog.error(PickerService.DOMAIN, PickerService.TAG, 'stageUri: context is undefined');
      return '';
    }
    const fileName = PickerService.fileNameOf(uri);
    if (fileName.length === 0) {
      hilog.error(PickerService.DOMAIN, PickerService.TAG, 'stageUri: cannot resolve file name from uri');
      return '';
    }
    // Date.now() % 1000000 保持在安全整数区间，避免 toString() 出现科学计数法
    const stamp = Number(Date.now() % 1000000).toString();
    const dest = context.cacheDir + '/import_staging/' + stamp + '_' + fileName;
    try {
      fs.mkdirSync(context.cacheDir + '/import_staging', true);
    } catch (e) {
      const mkErr = e as BusinessError;
      // 目录已存在时 mkdirSync 也会抛错，此处降级为 info，真正的失败由 copyFileSync 暴露
      hilog.info(PickerService.DOMAIN, PickerService.TAG, 'stageUri mkdir: %{public}s',
        PickerService.errText(mkErr));
    }
    if (!PickerService.copyUriToSandbox(uri, dest)) {
      return '';
    }
    return dest;
  }

  /**
   * 从 URI 读取文本内容；失败返回空串（错误已 hilog.error 打点）。
   * 通过 fd 读取：readTextSync 只接受沙箱路径，openSync 自 API 9 起支持 URI。
   */
  static readTextFromUri(uri: string): string {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const content = fs.readTextSync(file.path);
      return content;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(PickerService.DOMAIN, PickerService.TAG, 'readTextFromUri failed: %{public}s',
        PickerService.errText(err));
      return '';
    } finally {
      if (file !== undefined) {
        try {
          fs.closeSync(file);
        } catch (closeErr) {
          hilog.warn(PickerService.DOMAIN, PickerService.TAG, 'close failed: %{public}s',
            PickerService.errText(closeErr as BusinessError));
        }
      }
    }
  }

  /**
   * 从 URI 解析文件名（含后缀）；解析不出返回空串。
   */
  static fileNameOf(uri: string): string {
    if (uri.length === 0) {
      return '';
    }
    const queryIdx = uri.indexOf('?');
    const trimmed = queryIdx >= 0 ? uri.substring(0, queryIdx) : uri;
    const slashIdx = trimmed.lastIndexOf('/');
    return slashIdx >= 0 ? trimmed.substring(slashIdx + 1) : trimmed;
  }

  // ─── 内部工具 ───

  private static ok(uris: string[]): PickResult {
    const r: PickResult = { success: true, uris: uris, error: '' };
    return r;
  }

  private static cancelled(): PickResult {
    const r: PickResult = { success: false, uris: [], error: '' };
    return r;
  }

  private static failure(message: string): PickResult {
    const r: PickResult = { success: false, uris: [], error: message };
    return r;
  }

  private static errText(err: BusinessError): string {
    if (err === undefined) {
      return '未知错误';
    }
    return 'code=' + err.code.toString() + ' ' + err.message;
  }
}
