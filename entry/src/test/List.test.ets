import localUnitTest from './LocalUnit.test';
import markdownRoundTripTest from './MarkdownRoundTrip.test';
import outlinerCoreTest from './OutlinerCore.test';

/**
 * 本地单元测试入口（M0 安全网：纯逻辑、无 UI/上下文依赖）。
 *
 * 分组：
 *   LocalUnit.test       页面命名/路径清洗/UUID（既有）
 *   MarkdownRoundTrip    T1：md→树→md 往返不变式
 *   OutlinerCore         T2：BlockTree/Validator 操作 + 循环引用负例
 */
export default function testsuite() {
  localUnitTest();
  markdownRoundTripTest();
  outlinerCoreTest();
}
