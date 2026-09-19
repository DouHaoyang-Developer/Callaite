import { common } from '@kit.AbilityKit';

/**
 * GlobalContext —— Pen Kit 手写套件要求的全局 Context 容器。
 *
 * 官方接入步骤（Pen Kit 手写套件接入手册）：
 *   1. 在 EntryAbility.onWindowStageCreate 中把 UIAbilityContext 存入全局容器
 *   2. 手写组件在初始化时从该容器读取 Context
 * 缺少此步骤时手写套件无法完成初始化。
 */
export default class GlobalContext {
  private static context: common.UIAbilityContext | undefined = undefined;

  static setContext(context: common.UIAbilityContext): void {
    GlobalContext.context = context;
  }

  static getContext(): common.UIAbilityContext | undefined {
    return GlobalContext.context;
  }
}
