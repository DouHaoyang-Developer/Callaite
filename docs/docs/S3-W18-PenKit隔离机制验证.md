# S3-W18 —— Pen Kit「构建期隔离」机制验证（陷阱 3 独立复验）

- **窗口**：EXEC-SPRINT-03 · W18
- **日期**：2026-10-02
- **HEAD（开工/收工）**：`c73e9cb`
- **`git status --short`**：开工**空** ✓ → 收工**空** ✓（实验残留 = 0 ✓）
- **性质**：**查证 + 实验窗口**；**仓库业务代码零改动** ✓（所有注入均已回退，并已做清洁重建 + 重新装机 ✓）
- **本窗口不做的事** ✗：未创建任何第二个 product / 第二个 entry 模块 / sourceRoot（② 的结论已由 schema + 源码确定，无需再付实验代价）

---

## 0. 一页结论（TL;DR）

| # | 问题 | 结论 | 证据等级 |
|---|---|---|---|
| **1** | `@kit.Penkit` 是不是 HSP？ | **是**（HMS 系统 HSP：`com.huawei.hmos.hwstylusfeature/Penkit`） | **Ⓐ 实证**（SDK `@bundle` 标签 + 磁盘上真实 `Penkit.hsp`） |
| **2** | 无 HSP 设备是否 `SIGABRT` 于 `LoadJSPandaFile`？ | **是 —— 本窗口已独立复现，含逐字消息** | **Ⓐ 实证**（3 份 cppcrash，逐字相同） |
| **3** | `canIUse` 能否挡住？ | **不能** —— 且本窗口实测：它在**没有该 HSP** 的设备上仍返回 **`true`**（**假阳性**） | **Ⓐ 实证**（注入探针 + hilog） |
| **4** | 「`await import()` 被降级为 `require` ⇒ 无效」 | **被推翻** ✗ —— 动态 `import('@kit.Penkit')` **可编译、可解析、不崩**；而**静态 `import` 才会在模块实例化期硬 abort** | **Ⓐ 实证**（两种写法各自构建+装机+冷启动对照） |
| **5** | hvigor 的 `products` 能否差异化管理**依赖**？ | **不能** ✗（`products` schema **无** `dependencies` 字段） | **Ⓑ 文档/源码**（官方 JSON Schema + hvigor 源码） |
| **6** | 有没有「按 product 的**源集**」？ | **有** ✓ —— 但挂点是**模块 `targets[].source.sourceRoots`**，**不是** `products` | **Ⓑ 文档/源码** |
| **7** | 是否存在「按 syscap 的**安装门禁**」？ | **在 API 26 Stage 模型上没有找到** ✗ —— `reqCapabilities` 被 schema 拒绝；`requiredDeviceFeatures` 是**按设备形态**不是按 syscap | **Ⓐ 实证**（两次构建失败 + 一次 schema 通过后的 hvigor 内部异常） |
| **8** | 决策 ⇒ 白板该怎么做？ | **单 product + 静态 `import` + 无条件用原生**（理由见 §6） | **综合判断**（含 1 项**无法自证**的前提，见 §8） |

**一句话**：**陷阱 3 的「地基」是对的，但它的「结论」用错了地方** ——
崩溃**真实存在**（我被独立复现打脸式确认了），
但**「所以必须构建期隔离」这一步推不出来** ✗ —— 因为**动态 `import()` 是有效边界**（陷阱 3 说它无效，这条被推翻），
且**用户新定的红线要求「上架必须原生」**，而构建期隔离（按 product 摘掉 Pen Kit）**恰好与红线相反**。

---

## 1. 陷阱 3 逐条复验（**不引用归档结论，全部重新取证**）

> 纪律：**「行号/文字存在」≠「结论成立」**（AGENTS §7 陷阱 9）。
> 下面每条都给 **证据本身**，并标注**我在哪一步亲手验的**。

### 1.1 「`@kit.Penkit` 是 HSP 形式」⇒ **成立** ✓（Ⓐ 实证）

**证据 A（最强，SDK 自带、逐字）** —— `hms\ets\api\@hms.stylus.HandwriteComponent.d.ets:6`：

```
* @bundle com.huawei.hmos.hwstylusfeature/Penkit/ets/hsp/HandwritePaint 5.0.0(12)
```

- `@bundle` 标签的语法是 **`bundleName/moduleName/path`** ⇒
  **bundleName = `com.huawei.hmos.hwstylusfeature`**，**moduleName = `Penkit`**；
- 路径段含 **`/ets/hsp/`** ⇒ **HSP（共享包）形态**，不是普通 API；
- 与崩溃日志里的 `hsp name:com.huawei.hmos.hwstylusfeature/Penkit` **逐字吻合** ✓。

**证据 B（磁盘上真有这个 HSP 文件）**：

```
D:\Program Files\Huawei\DevEco Studio\sdk\default\hms\previewer\systemHsp\hmos\hwstylusfeature\Penkit.hsp
  492,160 bytes   （内部仅 ets/modules.abc —— previewer 用桩件）
```

同目录 `systemHsp\hmos\` 下另有 `hdscomponent` / `health` / `pic` / `walletkit` 等，**都是系统级能力** ✓ ——
该目录名 `systemHsp` 本身就是「系统预置共享包」的直证。

**证据 C（kit 聚合层）** —— `hms\ets\kits\@kit.Penkit.d.ts:12-20` 只是再导出：

```ts
import { HandwriteController, HandwriteComponent, PenHspInfo, PenType, HiddenToolType, HiddenConfig }
  from '@hms.stylus.HandwriteComponent';
```

⇒ `@kit.Penkit` 是**聚合入口**，真实实现全在 `@hms.stylus.*`（HMS 闭源）⇒ 与「HSP」一致 ✓

**⇒ 判定：成立** ✓（等级 **Ⓐ**：SDK 文件内容 + 磁盘文件实体，二者独立互证）

### 1.2 「无该 HSP 的设备启动即 SIGABRT，崩溃点在 `LoadJSPandaFile`」⇒ **成立** ✓（Ⓐ 实证，**本窗口独立复现**）

**这不是从归档抄的 —— 是我自己造出来的。** 做法（可回退、已回退）：

1. 在 `EntryAbility.ets` 的 `onCreate`（**普通方法体**，遵守 AGENTS §7 陷阱 44）注入探针；
2. **静态** 加入 `import { HandwriteComponent, PenType } from '@kit.Penkit';`
3. 构建 ⇒ **BUILD SUCCESSFUL**；装机 ⇒ 成功；`aa force-stop` + `aa start` 冷启动;
4. 结果：**进程消失，`pidof` 为空，`onCreate` 连一行日志都没打出来**。

**崩溃原文（3 份日志逐字相同）**：

```
Reason:Signal:SIGABRT(SI_TKILL)@0x01317b5200005f79 from:24441:20020050
LastFatalMessage:[default] [LoadJSPandaFile] load hsp failed,
                 hsp name:com.huawei.hmos.hwstylusfeature/Penkit,
                 errorMsg:Get shared HspPath failed, please check the module is correct
Fault thread info:
#07 ... panda::ecmascript::SourceTextModule::Instantiate(...)
#10 ... panda::JSNApi::ExecuteModuleBufferSecure(...)
```

| 日志文件 | 时刻 | Process life time |
|---|---|---|
| `cppcrash-...-20261002225818927.log` | 22:58:18 | **4 s** |
| `cppcrash-...-20261002225838506.log` | 22:58:38 | **21 s** |
| `cppcrash-...-20261002225941405.log` | 22:59:41 | **65 s** |

> ⚠️ **一条新增的实测细节（归档没有）** ✗✓：**abort 的时机不确定**（4 / 21 / 65 s 三种）。
> 但 **`LastFatalMessage` 与 `Reason` 三次逐字相同** ⇒ 是**同一个确定性缺陷**，
> 只是**触发点被推迟**（栈顶为 `SourceTextModule::Instantiate` ⇒ 发生在**该模块被实例化**时，而非进程入口）。
> ⇒ **「启动即崩」应更准确地表述为「该模块被实例化的那一刻崩」** ✓（对本决策无影响，但影响今后复现的判据写法）

**⇒ 判定：成立** ✓（等级 **Ⓐ**：我亲手构建/装机/冷启动，拿到 3 份 cppcrash 原文）

### 1.3 「早于任何 `canIUse` 守卫」⇒ **成立** ✓（Ⓐ 实证）

- **代码级**：`canIUse` 是**运行时全局函数**（SDK `global.d.ts`：`export declare function canIUse(syscap: string): boolean;`，`@since 8`），
  它只在**被调用的那一刻**求值；而崩溃栈是 **`SourceTextModule::Instantiate`**（模块实例化期）。
- **实测级（决定性）**：探针的第 1 行就是 `hilog.info(... 'penkit-canIUse=...')`，
  而静态 import 版冷启动后 **`onCreate` 一行都没输出**（日志里连 `Ability onCreate` 都没有）⇒
  **`onCreate` 根本没机会执行** ⇒ 守卫在物理上不可能先跑 ✓✓

**⇒ 判定：成立** ✓（等级 **Ⓐ**）

### 1.4 「`await import()` 也会被降级为 `require` 而无效」⇒ **被推翻** ✗（Ⓐ 实证）

**这是本窗口最反直觉、也最重要的一条 —— 我专门为它做了一组对照实验。**

| 实验 | 写法 | 构建 | 装机+冷启动 | 结果 |
|---|---|---|---|---|
| **L** | **仅动态**：`import('@kit.Penkit').then(...).catch(...)` | SUCCESSFUL | ✓ | **不崩** ✓，`penkit-import=OK`，app 存活 |
| **S** | **静态**：`import { HandwriteComponent, PenType } from '@kit.Penkit';` | SUCCESSFUL | ✓ | **SIGABRT（`LoadJSPandaFile`）** ✗ |

**实验 L 的原始 hilog（22:57:20）**：

```
I A00001/W18PROBE: penkit-canIUse=true
I A00001/W18PROBE: penkit-import=OK handwriteComponent="undefined"
```

**实验 S 的原始 hilog（22:57:47）**：**什么都没有** —— 只有 `aa start` 返回成功，进程随即消失。

**⇒ 三条事实**：

1. **`await import()` / `import().then()` 在 ArkTS 里是官方支持的合法写法**，
   且**没有被降级成 `require`** ⇒ 陷阱 3 的这条**机制描述是错的** ✗；
2. **动态 import 是一条真实的「不崩」边界** ✓ —— 这与陷阱 3 的结论**正好相反**；
3. 但 **`handwriteComponent` 读出 `"undefined"`** ⇒ 在**没有该 HSP 的模拟器上**，
   动态 import 虽然**不抛错**，也**拿不到真实现**（一个**静默半吊子**：不崩，但也没有原生能力）✗✓

**官方文档佐证（ArkTS 语言指南《Dynamic Import》，本地知识库）**：

- `arkts-dynamic-import.md:10`：「Dynamic imports support conditional loading and partial reflection…
  **It allows loading HSP modules**, HAR modules, ohpm packages, and native libraries.」
- `:17`：「The imported module **does not exist at load time** and needs to be fetched asynchronously.」
  ⇒ **官方把「模块在加载期不存在」列为动态导入的适用场景** ✓✓
- `:129-133`：明确给出 `let ns: ESObject = await import('myhar');`
- `:304`：**唯一**的限制在**变量表达式**：
  「static imports and dynamic imports with **constant expressions** can be identified and parsed by
  rollup and its plug-ins… **can be added to the dependency tree, participate in the build process**」
  ⇒ **常量写法的动态 import 仍会进依赖树**（会被编译进去），
  要**运行时才决定**必须用**变量写法** + `buildOption.arkOptions.runtimeOnly` ✓

> **我实测的是「常量写法」**（`import('@kit.Penkit')`）⇒ 它**进了依赖树但仍不崩**。
> **「变量写法」（`const s = '@kit.Penkit'; import(s)`）我没有实测** ✗ —— 见 §8 无法自证项。

**⇒ 判定：这一条被推翻** ✗（等级 **Ⓐ**：双向对照实验）

### 1.5 陷阱 3 总结论 —— **部分成立**（**地基对、推论错**）

| 子断言 | 判定 | 等级 |
|---|---|---|
| `@kit.Penkit` 是 HSP | **成立** ✓ | Ⓐ |
| 无 HSP ⇒ `LoadJSPandaFile` 处 abort | **成立** ✓（已独立复现） | Ⓐ |
| 早于任何 `canIUse` 守卫 | **成立** ✓ | Ⓐ |
| **`await import()` 被降级为 `require` ⇒ 无效** | **被推翻** ✗ | Ⓐ |
| **「因此必须用构建期隔离」** | **推不出来** ✗ | 见 §6 |

---

## 2. 核心问题：hvigor 的 product 能否差异化管理依赖？

### 2.1 `products` 能配什么（**官方 JSON Schema，逐字段**）—— Ⓑ

文件：`tools\hvigor\hvigor-ohos-plugin\res\schemas\ohos-project-build-profile-schema.json`
（`app.products[]` 的 `propertyNames.enum`）：

```
name · signingConfig · bundleName · buildOption · runtimeOS ·
compileSdkVersion · compatibleSdkVersion · compatibleSdkVersionStage ·
targetSdkVersion · bundleType · label · icon · versionCode · versionName ·
buildVersion · resource · output · arkTSVersion · vendor
```

- **没有 `dependencies`** ✗ ⇒ **product 不能差异化管理依赖**（**这是核心问题的答案**）
- **没有 `sourceRoots` / `sourceSets`** ✗（只有 `resource.directories`，那是**资源**不是**源码**）
- 本仓现存配置（`Callaite\build-profile.json5`）与之一致：只用了 `name/signingConfig/targetSdkVersion/compatibleSdkVersion/runtimeOS/buildOption` ✓

### 2.2 那「按 product 差异」靠什么？—— 模块 **`targets`** ✓ Ⓑ

**项目级** `modules[].targets[]`（同一 schema）只允许两个字段：

```
name · applyToProducts
```

`applyToProducts` 的官方描述（逐字）：
> 「Describes which products the target is used for, which means that **different products can contain different targets**.」

**运行时语义（hvigor 源码，Ⓑ，非推断）** ——
`src\tasks\service\module-task-service.js`：

```js
function getProducts(t,e,r,o){
  if(r===CommonConst.OHOS_TEST) return [o];
  const s = t?.getTargetApplyProducts(e.getName(), r);
  return s ?? ["default"];              // ← 未声明 applyToProducts ⇒ 默认 ["default"]
}
function checkHasTargetApplyProduct(t,e,r){
  if(t.isHarModule() || getAlignTarget()) return true;
  const o=t.getParentProject(), s=getProducts(o,t,e,r), a=o.getProductNames();
  if(s.some(x=>!a.includes(x))) printErrorExit("INVALID_PRODUCT_FOR_TARGET", ...);
  return s.includes(r);                 // ← 命中即「该 target 属于该 product」
}
```

⇒ **`applyToProducts` 确实能按 product 门控「某个模块的某个 target」** ✓（**这是最硬的证据**）

### 2.3 但 **`applyToProducts` 不能做到「依赖差异」** ✗ —— 关键区别 Ⓑ

`applyToProducts` 门控的是**「该模块的构建任务是否产出」**，
**不是「该模块是否出现在依赖图里」** ✗ ⇒
它**无法**阻止主 HAP 仍静态 `import` 那个模块并把它打进包 ✓✓

> ⇒ **上级裁决里的那句判断是对的** ✓：
> 「**把 Pen Kit 代码放进一个独立模块本身不构成隔离** —— 只要主应用在依赖图里依赖了它，它仍会被加载」✓
> 本窗口把它**从断言升级为「源码级 + schema 级」双证据** ✓

⇒ **所以：`products` 差异化管理依赖 = 不行** ✗（**A 的原始形态不成立**）

### 2.4 「按 product 的**源集**」—— **存在** ✓，但挂点不同 Ⓑ

**模块级** `build-profile.json5` 的 `targets[]`（`ohos-module-build-profile-schema.json`）
允许字段：`name · runtimeOS · config · source · resource · output`
其中 **`source`** 允许：`abilities · pages · **sourceRoots**`

`sourceRoots` 官方描述（逐字）：
> 「In StageMode, specifies **the extended source directories** of the ability selected by the target.」

⇒ **这是真正的「同名接口 + 两个实现」形态** ✓
⇒ **但**：它挂在**模块的 target** 上，且 **`sourceRoots` 是「扩展目录」（additive）**，
**不是「替换 `src/main`」** ⇒ 用它做「有/无 Pen Kit 的两份实现」需要**谨慎验证覆盖语义**（本窗口未实测 ✗，见 §8）

### 2.5 机制清单与证据等级汇总

| # | 机制 | 能否达成目标 | 证据等级 |
|---|---|---|---|
| M1 | `products[].dependencies` | **不存在（schema 无此字段）** ✗ | **Ⓑ** schema |
| M2 | `products[].sourceRoots` / `sourceSets` | **不存在** ✗ | **Ⓑ** schema |
| M3 | `products[].resource.directories` | 只影响**资源**，不影响依赖 ✗ | **Ⓑ** schema |
| M4 | `modules[].targets[].applyToProducts` | 能按 product 门控**模块 target 的构建** ✓，**但不能改变依赖图** ✗ | **Ⓑ** schema + **源码** |
| M5 | 模块 `targets[].source.sourceRoots` | 能做**按 target 的扩展源集** ✓（additive 语义待实测 ⚠️） | **Ⓑ** schema |
| M6 | 两个 entry 模块 + `applyToProducts` 分流 | **能**做到「产物级」隔离 ✓（两个 HAP） | **Ⓒ 推断**（未实测；机制 M4 已证，组合未证）|
| M7 | `buildOption.arkOptions.runtimeOnly` | 让**变量表达式**动态导入进包 ✓ | **Ⓑ** 官方文档 |
| M8 | `module.requiredDeviceFeatures` | **按设备形态**（`phone`/`2in1`/`wearable`）声明特性，**不是按 syscap** ✗ | **Ⓐ** 实测（见 §3.4）|

> **⚠️ 我做的实验（如实登记）**：本窗口**没有**去造第二个 product / 第二个 entry 模块做端到端实验 ✗。
> 理由：**核心问题（M1：`products` 能否差异化管理依赖）已被 schema 直接否决** ✓ ——
> 对一个「字段根本不存在」的问题再付一次全量构建+装机，边际信息量低。
> **上级原任务书要求「若无法从文档确定 ⇒ 做实验」** ✓ —— 本条**已能从文档确定**，故未做；
> 但我把**没做**这件事明确写在这里，**不冒充已做** ✗✓。
> （M6 的**组合**我也只给了 Ⓒ 推断，未实测。）

---

## 3. 现状核查（决定「现在到底会不会崩」）

### 3.1 谁 import 了 `@kit.Penkit` —— **全仓仅 1 处** ✓

```
entry/src/main/ets/components/whiteboard/PenCanvasPage.ets:1
  import { HandwriteComponent, HandwriteController, PenType, PenHspInfo, HiddenToolType, HiddenConfig } from '@kit.Penkit';
```

### 3.2 它在启动路径上吗 —— **不在：它是「零引用」文件** ✓✓（**这就是本机不崩的唯一原因**）

- `PenCanvasPage` 在全仓**只出现在**：
  - 它自己的定义（`PenCanvasPage.ets:7/10/26/254`）
  - `Whiteboard.ets:80` 的**一行注释**（「经 PenCanvasPage 按需模块接入」）
- 严格 `from '…PenCanvasPage'` 检索：**0 命中** ✗ ⇒ **没有任何 `.ets` 真的 import 它**

**反向硬证据（产物级）** —— 把当前构建的 HAP 解开，在 `ets/modules.abc` 里搜字符串：

```
Penkit = 0 | hwstylusfeature = 0 | HandwriteComponent = 0 | HandwriteController = 0 | stylus = 0
```

⇒ **它根本没进编译产物** ✓✓ ⇒ **不崩不是因为有守卫，而是因为它压根没被编译进去** ✓

> ⚠️ 这与 AGENTS §7 陷阱「零引用 ≠ 死代码」同族，但**结论相反**：
> 这里「零引用」正是**当前不崩的原因**，而**白板要上原生就必然要接线** ⇒ **一接线就会崩** ✗✓

### 3.3 本机模拟器有没有该 HSP —— **没有** ✗（Ⓐ 实证，多路互证）

| 检查 | 结果 |
|---|---|
| `bm dump -a`（全部 bundle 列表） | **52 个，无 `com.huawei.hmos.hwstylusfeature`** ✗ |
| `bm dump -n com.huawei.hmos.hwstylusfeature` | `error: failed to get information` ✗ |
| `ls /system/hsp` | `No such file or directory` ✗ |
| `find /system -name '*.hsp'` | 空 ✗ |
| `const.product.model` | **`emulator`**（不是真机型号）|
| `const.ohos.fullname` | **`OpenHarmony-7.0.0.105`** ← **关键** |
| `const.ohos.apiversion` | 26 |
| `const.product.devicetype` | `2in1` |

> **⇒ 性质判定：本机是「OpenHarmony 模拟器镜像」，不是 HarmonyOS 真机** ✓
> ⇒ 它**天然不含 HMS 系统 HSP**（`hwstylusfeature` 是 HMS 能力）✓
> ⇒ **不能用它来推断真机有没有** ✗ —— 这一点**极其重要**，见 §4.1 与 §8

### 3.4 🔴 本窗口最重要的**新发现**：`canIUse` 在**没有该 HSP** 的设备上返回 `true` ✗

**实测（注入探针 + 冷启动 + hilog）**：

```
I A00001/W18PROBE: penkit-canIUse=true          ← 设备上根本没有这个 HSP！
```

**为什么**（源码级追因，Ⓑ）：
1. `Callaite\build-profile.json5` 的 product 设了 **`runtimeOS: "HarmonyOS"`**；
2. hvigor 的 `abstract-syscap-transform.js` 的 `doTaskAction()` **第一行就是**：

   ```js
   async doTaskAction(){ if(this.targetData.isHarmonyOS()) return; ... }
   ```

   ⇒ **HarmonyOS 目标下，整个 SysCap 变换任务直接 return（跳过）** ✓
3. ⇒ `canIUse` 的答案**不是来自运行时探测**，而是来自**编译期注入的 SysCap 集合**；
4. 而 SDK 的 **HarmonyOS 设备档**（`hms\ets\api\device-define\*-hmos.json`）**全部**包含：

   | 档 | 条目数 | 是否含 `SystemCapability.Stylus.Handwrite` |
   |---|---|---|
   | `2in1-hmos.json` | 115 | **✓** |
   | `tablet-hmos.json` | 124 | **✓** |
   | `phone-hmos.json` | 127 | **✓** |
   | `2in1.json`（OpenHarmony） | 254 | **✗** |
   | `tablet.json`（OpenHarmony） | 247 | **✗** |
   | `phone.json`（OpenHarmony） | 251 | **✗** |

**⇒ 三条结论**：

1. **`canIUse('SystemCapability.Stylus.Handwrite')` 不是「设备有没有 Pen Kit」的判据** ✗ ——
   它在**没有 HSP** 的模拟器上照样 `true` ⇒ **假阳性** ✓✓
2. ⇒ `Whiteboard.ets:84` 的注释「**官方 SysCap 运行时探测**」**与实测不符** ✗
   （它是**编译期 profile 查询**，不是运行时探测）；
3. ⇒ **`WhiteboardBrushPanel` / `WhiteboardStatusBar` 现在会在本机显示「Pen Kit 原生」** ✗
   （因为 `handwriteCapable=true`），而实际渲染走的是 Canvas ⇒ **UI 在说谎** ✓
   > 这是一条**独立的现状缺陷**（不是 W18 引入），建议登记。

### 3.5 本仓现有的 Pen Kit 相关构建期开关 —— **一个都没有** ✗

- `build-profile.json5`：**只有 1 个 product（`default`）**，无 `dependencies` / 无 `sourceRoots`
- `entry\build-profile.json5`：`targets` 只有 `default` + `ohosTest`，**无 `source.sourceRoots`**
- `entry\src\main\module.json5`：**无** `requiredDeviceFeatures` / 无 `syscap` 声明
- 无 `entry\src\main\syscap.json`（hvigor 支持的**可选** SysCap 定制入口）✓ 确认不存在
- `hvigorfile.ts`（根/entry）：都是内置 `appTasks`/`hapTasks`，**无自定义插件**

---

## 4. `@kit.Penkit` 的**供给形态**（本窗口被升级为第一优先级的问题）

### 4.1 能不能从本机确定「所有目标设备都有」—— **不能** ✗（**必须如实说**）

| 想用的证据 | 为什么**不成立** |
|---|---|
| 本机模拟器有/没有 | 本机是 **OpenHarmony 镜像**，**不是** HarmonyOS 真机 ✗ ⇒ 无外推力 |
| `canIUse(...)` | **实测是假阳性**（§3.4）✗ ⇒ **零证据力** |
| SDK `*-hmos.json` 含该 syscap | 它只证明「**HarmonyOS 设备档声明支持该能力**」，**不等于「每台设备都预置了这个 HSP」** ⚠️ ⇒ 只是**间接**支持 |
| SDK 里有 `Penkit.hsp`（previewer 桩） | 那是 **DevEco 预览器**用的，**不是设备镜像** ✗ |
| 崩溃消息里写的是系统 HSP 名 | 证明它是**系统级 HSP**，**不等于「一定预置」** ⚠️ |

**⇒ 诚实结论**：
**「`@kit.Penkit` 在 API 26 / HarmonyOS 7 的所有目标设备上都预置」这一条，本窗口无法自证** ✗✓。
我能给到的最强陈述是 **Ⓑ 级**：**HarmonyOS 设备档（phone/tablet/2in1）在 SDK 中都被声明为支持
`SystemCapability.Stylus.Handwrite`** ⇒ **它在 HarmonyOS 侧是「声明性必备能力」，不是「可选加分项」** ✓
—— 这与「**它在 OpenHarmony 侧完全不存在**」（§3.4 表）形成鲜明对照 ✓✓

> **⚠️ 取真机的正确办法**（建议列入 R0 批次，**本窗口不做**）：
> `hdc shell bm dump -n com.huawei.hmos.hwstylusfeature`（真机上应能返回 bundle 信息）
> 或在真机上跑一次 §5 的**静态 import 冒烟包** ⇒ 不崩 = 该机有该 HSP ✓
> **这是唯一能一次问清的实验**，且**代价极小**（现成探针已写好，见 §5.2）。

### 4.2 有没有「按 syscap 的安装门禁」—— **没找到** ✗（Ⓐ 实证）

上级在 §22.20 的设想是「**把原生能力声明为必需依赖 ⇒ 不支持的设备根本装不到**」。
我**尝试把它做出来，结果失败**：

| 尝试 | 写法 | 结果 |
|---|---|---|
| ① | `module.reqCapabilities: ["SystemCapability.Stylus.Handwrite"]` | **构建失败** ✗ —— Stage 模型 schema **拒绝该字段** |
| ② | `module.requiredDeviceFeatures: ["..."]` | **构建失败** ✗ —— `must be object` |
| ③ | `module.requiredDeviceFeatures: { "2in1": ["zzq"] }` | schema **通过**，但 hvigor 抛 `Cannot read properties of undefined (reading '0')` ✗ |

**schema 报错原文（①）** 直接给出了 Stage 模型 `module` 的**全部合法字段**：

```
allowedValues: [ name, type, srcEntrance, srcEntry, abilitySrcEntryDelegator,
  abilityStageSrcEntryDelegator, description, process, mainElement, deviceTypes,
  requiredDeviceFeatures, deliveryWithInstall, installationFree, virtualMachine,
  uiSyntax, pages, systemTheme, metadata, abilities, extensionAbilities,
  requestPermissions, definePermissions, testRunner, dependencies, libIsolation,
  compressNativeLibs, extractNativeLibs, atomicService, generateBuildHash,
  isolationMode, proxyData, crossAppSharedConfig, fileContextMenu, querySchemes,
  routerMap, appEnvironments, appStartup, formWidgetModule, hnpPackages, easyGo,
  shareFiles, skillProfiles, executableBinaryPaths ]
```

**schema 报错原文（③ 的上一轮）** 揭示了 `requiredDeviceFeatures` 的真实形状：

```
instancePath: 'module.requiredDeviceFeatures',
keyword: 'enum', params: { allowedValues: [ 'phone', '2in1', 'wearable' ] },
message: 'must be equal to one of the allowed values'
```

⇒ **`requiredDeviceFeatures` 是「按设备形态声明特性」，不是「按 syscap 声明能力」** ✗
⇒ **API 26 Stage 模型上，我没有找到任何「按 syscap 的安装门禁」机制** ✗✓
（`reqCapabilities` 只存在于 **FA 模型** 的 `config.json`：SDK 里 `configSchema_rich.json` 有它，
   而 Stage 的 `module.json5` 没有 ✓ —— 这是一条**模型差异**，不是我的配置写错）

> **⇒ 这条对上级的 §22.20 有直接影响** ✗✓：
> 「**声明为必需依赖，让不支持的设备装不上**」在 **Stage 模型 / API 26 上买不到** ✗ ——
> 至少**不是**通过 `module.json5` 买的。若仍要这个效果，只能靠
> **AppGallery 上架时的「支持设备集」/ syscap 勾选**（**发布期交付物，非代码**）
> —— 而那是**发布侧**的事，**本窗口无法在本地验证** ✗✓（已登记为 §8 无法自证项）

---

## 5. 实验清单（**可回退、残留 = 0**）

### 5.1 已执行（全部已回退 ✓）

| # | 实验 | 做法 | 结果 | 产物/证据 |
|---|---|---|---|---|
| E1 | 产物基线 | 解 HAP，搜 `Penkit`/`hwstylusfeature` | **0 命中** ⇒ 模块未进编译图 | `modules.abc` 字符串计数 |
| E2 | **`canIUse` 值** | `EntryAbility.onCreate` 注入 1 行 hilog | **`true`**（设备无该 HSP）⇒ **假阳性** | hilog `W18PROBE` |
| E3 | **动态 `import()`** | `import('@kit.Penkit').then().catch()` | **OK，不崩**，`HandwriteComponent=undefined` | hilog + `pidof` 存活 |
| E4 | **静态 `import`** | `import { HandwriteComponent, PenType } from '@kit.Penkit'` | **SIGABRT / `LoadJSPandaFile`** | 3 份 cppcrash |
| E5 | 安装门禁 ① | `module.reqCapabilities` | **schema 拒绝** | 构建报错（含合法字段全表） |
| E6 | 安装门禁 ②③ | `module.requiredDeviceFeatures` 两种形状 | ② 类型错；③ schema 过、hvigor 内部崩 | 构建报错 |

**回退与复原**：
1. `edit` 回退 `EntryAbility.ets`（探针 + 静态 import 全部移除）⇒ 断言 `W18PROBE` 计数 = **0** ✓
2. `edit` 回退 `module.json5` ⇒ 断言 `requiredDeviceFeatures`/`reqCapabilities` 计数 = **0** ✓
3. **清洁重建**（删 `entry\build` + `.hvigor\cache`）⇒ **BUILD SUCCESSFUL** ✓（AGENTS §7 陷阱 41）
4. 重新装机 + 冷启动 ⇒ **app 存活（pid `2727`）** ✓
5. 最终产物纯度断言：`W18PROBE=0 · Penkit=0 · requiredDeviceFeatures=0` ✓✓
6. `git status --short` = **空** ✓；`git grep W18PROBE|requiredDeviceFeatures|reqCapabilities` = **0** ✓

### 5.2 建议交 R0 批次（**真机必做，一次性问清**）

现成探针（**已验证可编译、可运行**，只需在真机上跑一次）：

```ts
// 临时加在 EntryAbility.ets 顶部（静态 import —— 这是判据本身）
import { HandwriteComponent, PenType } from '@kit.Penkit';
```
- 真机**不崩** ⇒ 该机**有**该 HSP ⇒ **静态 import 可用** ✓
- 真机**崩**（`LoadJSPandaFile`）⇒ 该机**没有** ⇒ **必须**走 §6 的动态方案

**判据**：`aa force-stop` + `aa start` 后 30 s，`pidof com.example.callaite` 非空 = 通过 ✓
**同时取证**：`hdc shell bm dump -n com.huawei.hmos.hwstylusfeature` 应返回 bundle 信息 ✓

---

## 6. 裁决：白板该怎么做（**面向用户的红线，不是面向我的 A/B**）

### 6.1 先把框架摆正（**上级的新框架是对的，我确认** ✓）

- 用户红线（AGENTS §0.0）：**上架的产品里白板必须有 HarmonyOS 原生体验**；
- ⇒ **「按 product 把 Pen Kit 摘掉」= 与红线相反** ✗ ⇒ **原 A1 方向作废** ✓；
- ⇒ 真正要回答的是：**「怎么保证上架产品有原生白板，同时在没有 Pen Kit 的设备上不崩」** ✓

### 6.2 我的建议：**单 product + 静态 `import` + 无条件用原生** ✓（**首选**）

**形态（具体到文件与字段）**：

| 文件 | 改动 | 说明 |
|---|---|---|
| `entry\src\main\ets\components\whiteboard\PenCanvasPage.ets` | **保持** 文件顶部 `import ... from '@kit.Penkit'` | **不动** ✓ |
| `entry\src\main\ets\components\whiteboard\Whiteboard.ets` | 接线：在满足原生条件时渲染 `PenCanvasPage` | **本次不实现**，仅登记为 S4 工作面 |
| `build-profile.json5` | **不加** product、**不加** `sourceRoots` | **保持单一 product** ✓ |
| `module.json5` | **不改** | 无可用安装门禁（§4.2）✗ |

**为什么首选它**：

1. **它才满足红线** ✓ —— 上架包**只含原生实现**，没有「非原生降级」分支 ✓；
2. **本窗口已证：静态 import 的崩溃只发生在「设备真的没有该 HSP」时** ✓；
   而 **HarmonyOS 设备档被 SDK 声明为支持该能力**（§3.4 表）⇒ **目标设备集内应当都有** ✓；
3. **成本最低**：**0 个新模块、0 个新 product、1 份产物** ✓；对现有 **136 个 `.ets`** 的改动面
   **仅 1 个文件的接线**（`Whiteboard.ets`）+ 可能删除 1 处误导性注释 ✓；
4. **不需要 `canIUse` 守卫** ✓（它本来就是假阳性，留着只会骗人）。

**⚠️ 它的前提（必须由真机确认，见 §4.1）**：
**所有上架目标设备都预置 `com.huawei.hmos.hwstylusfeature`**。
**若真机实测发现有设备没有 ⇒ 6.2 作废，转 6.3。**

### 6.3 备选方案（**仅当 6.2 的前提被真机否掉时**）

**形态：单 product + 变量表达式动态 `import()` + 原生/兜底二选一**

```ts
// 变量写法 ⇒ 编译期不进依赖树（需 runtimeOnly 声明，官方文档 §1.4）
const modName: string = '@kit.Penkit';
try {
  const ns: ESObject = await import(modName);
  if (ns.HandwriteComponent !== undefined) { /* 走原生 */ }
} catch (e) { /* 该设备无 Pen Kit */ }
```
配合 `entry\build-profile.json5`：
```json5
"buildOption": { "arkOptions": { "runtimeOnly": { "packages": ["@kit.Penkit"] } } }
```

- ✅ **不崩**（E3 已证：即使 HSP 缺失也不 abort）✓
- ✅ 有该 HSP 的设备**仍拿到原生体验** ⇒ **对红线无害** ✓
- ⚠️ **代价**：引入一条「无则兜底」分支 ⇒ **与红线「不得降级」的字面口径有张力** ✗✓
  ⇒ **必须由用户/产品拍板**：红线是「**关键能力（白板/笔）用原生**」还是「**全栈原生、且不许有降级分支**」
  ⇒ **这正是 §22.20 的 IMMEDIATE CONSEQUENCE #2 那条开放问题** ✓
- ⚠️ **未实测项**：**变量写法**我没实测 ✗（E3 测的是常量写法）⇒ 落地前须先跑一次 §7b 式验证

### 6.4 明确不推荐 ✗

| 方案 | 为什么不推荐 |
|---|---|
| **A2 / B：两个 entry 模块 + 按 product 分流** | **不满足红线** ✗（它的目的是「产出一个不含 Pen Kit 的包」）；且要维护**两套产物/两次构建**；且本窗口已证 `products` **无法**差异化依赖（§2.1），只能靠模块级分流 ⇒ **复杂度换不到红线要求的收益** ✗ |
| **`sourceRoots` 双实现** | 同为「摘掉 Pen Kit」思路 ⇒ 同样**与红线相反** ✗；且 `sourceRoots` 是 **additive** 语义，**未实测** ⚠️ |
| **`canIUse` 守卫** | **实测假阳性**（§3.4）⇒ **给出了虚假的安全感** ✗✗ |
| **靠 `reqCapabilities` 安装门禁** | **API 26 Stage 模型上不存在**（§4.2，Ⓐ 实证）✗ |

### 6.5 顺带该清的现状债务（**建议单独登记，非本窗口**）

1. `Whiteboard.ets:78-84` 注释称 `canIUse` 为「**官方 SysCap 运行时探测**」✗ ⇒ **与实测不符**，应改口径；
2. `WhiteboardBrushPanel.ets:33` / `WhiteboardStatusBar.ets:18` 的引擎名会在本机显示
   **「Pen Kit 原生」**，而实际走 Canvas ⇒ **UI 说谎** ✗；
3. `EntryAbility.ets:77-78` 的注释说「Pen Kit 手写套件要求：把 UIAbilityContext 暴露到全局容器」
   ⇒ 该 `setContext` 目前**只为 Pen Kit 服务**，但 Pen Kit 尚未接线 ⇒ **接线时再核** ⚠️；
4. `PenCanvasPage.ets` 是**零引用死文件**，而**它携带唯一的 `@kit.Penkit` import**
   ⇒ **S4 接线的那一刻就是「会不会崩」的判决时刻** ✗✓ ⇒ **建议在 S4 开工前先跑 §5.2 真机冒烟** ✓

---

## 7. 成本与风险（对 6.2 首选方案）

| 项 | 量 |
|---|---|
| 新增模块 | **0** ✓ |
| 新增 product | **0** ✓ |
| 产物数 | **1**（现状不变）✓ |
| 构建次数 | **1**（现状不变）✓ |
| 对现有 136 个 `.ets` 的改动面 | **接线 1 个文件**（`Whiteboard.ets`）+ 建议清理 2–3 处注释/文案 ✓ |
| 新增依赖 | **0**（`@kit.Penkit` 是 SDK 自带，`oh-package.json5` **无需改**）✓ 已核：本仓 `dependencies` 为空 |

**风险**：

| 风险 | 等级 | 缓解 |
|---|---|---|
| **目标设备里有一台没有该 HSP ⇒ 装上即崩** | **高**（后果是「应用打不开」）| **§5.2 真机冒烟**必须在 S4 接线前跑 ✓ |
| 上架审核对「硬依赖 HMS 能力」的要求未知 | 中 | 属**发布期**事项 ⇒ 交用户/产品 ✓ |
| `canIUse` 假阳性导致「以为有守卫」 | **高**（认知风险）| **§6.5-1/2 明确改口径** ✓ |
| 变量写法（6.3）未实测 | 中 | 落地前补一次 §7b 式验证 ✓ |

---

## 8. 我**无法自证**的项（**如实标注** ✗✓）

1. 🔴 **真机（用户的设备）到底有没有 `com.huawei.hmos.hwstylusfeature`** ✗✓
   —— **本窗口无法回答**：本机是 **OpenHarmony 模拟器镜像**（`OpenHarmony-7.0.0.105`），
   **结构上就不含 HMS 系统 HSP** ⇒ **对本问题零证据力** ✓
   ⇒ **这是整个决策的唯一关键未知** ✓ —— 我给的最强证据只是 Ⓑ（SDK 设备档声明）✓
2. **「变量表达式动态 `import()` + `runtimeOnly`」未实测** ✗ —— E3 测的是**常量写法**；
   两者在「是否进依赖树」上**文档说不同**（§1.4），我**没有**亲手验常量/变量的行为差异 ⚠️
3. **`sourceRoots` 的覆盖语义未实测** ✗（schema 说 "extended"，我未验证「同名文件谁赢」）⚠️
4. **`applyToProducts` 门控模块依赖的端到端行为未实测** ✗ ——
   我只证到「源码级：它决定 target 是否属于 product」，**没有**造第二个 entry 模块跑通 ⚠️
5. **上架侧（AppGallery）能否按 syscap 限制支持设备集** ✗ —— 发布期事项，本地无从验证 ✓
6. **`PenCanvasPage` 一旦接线后的运行时行为**（除「有没有 HSP」外的所有行为）✗ ——
   本窗口**未接线**（且接线会崩，故刻意不接）✓
7. **3 份 cppcrash 的 `Process life time` 为何是 4/21/65 s** ⚠️ ——
   现象已登记，**机制未归因** ✓（栈顶都指向 `SourceTextModule::Instantiate`，但触发时机不同）

---

## 9. 交还状态

| 项 | 状态 |
|---|---|
| HEAD | `c73e9cb`（未提交任何改动 ✓）|
| `git status --short` | **开工空 → 收工空** ✓✓ |
| 实验残留 | **0** ✓（源码 + 产物双重断言）|
| 清洁重建 | 已做 ✓（`BUILD SUCCESSFUL`）|
| 设备已装包 | **纯净版**（`W18PROBE=0 · Penkit=0`）✓ |
| 实例状态 | `127.0.0.1:5555` **在线** ✓；`com.example.callaite` **存活**（pid `2727`）✓ |
| 本窗口改动 | **仅本文件 + `EXEC-PLAN.md §22.21`**（均在 `Callaite-工作文档\docs\`，**不在 git 内**）✓ |

**⚠️ 交还时设备上残留的崩溃日志**（**只读，未删** ✓）：
`/data/log/faultlog/faultlogger/` 下 3 份 `cppcrash-com.example.callaite-2026100222{5818,5838,5941}*.log`
—— 这是**本窗口 E4 实验的证据留档**，**故意保留** ✓（如需清理请告知，我未擅自删除设备日志）
