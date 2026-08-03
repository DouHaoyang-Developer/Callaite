import { WorkspaceService } from './WorkspaceService';

/**
 * FileService — 文件服务（兼容层）。
 *
 * 对应 Logseq frontend/fs.cljs + handler/repo.cljs。
 * 封装底层 FileRepository，提供给 EntryAbility 的初始化入口。
 */
export class FileService {
  private static context: Context | undefined;

  /**
   * 设置应用上下文（必须在 EntryAbility.onCreate 中调用）。
   */
  static setContext(ctx: Context): void {
    FileService.context = ctx;
  }

  static getContext(): Context | undefined {
    return FileService.context;
  }

  /**
   * 获取 Graph 根目录路径。
   * HarmonyOS 中默认使用应用的 files 目录。
   */
  static getDefaultGraphRoot(): string {
    if (!FileService.context) {
      return '/data/storage/el2/base/files/graph';
    }
    return FileService.context.filesDir + '/graph';
  }

  /**
   * 初始化文件服务并加载 Graph。
   */
  static initGraph(graphRoot?: string): void {
    const root = graphRoot ?? FileService.getDefaultGraphRoot();
    const ws = WorkspaceService.getInstance();

    // 确保目录存在
    ws.getDataStore().getFileRepo().ensureDir(root);

    // 加载所有 .md 文件
    ws.loadGraph(root);
  }
}
