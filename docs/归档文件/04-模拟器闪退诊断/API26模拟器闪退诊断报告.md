# API 26 模拟器不稳定与应用闪退 —— 诊断报告

**诊断对象**：HarmonyOS 7.0.0(26.0.0) 模拟器实例 `Pura 90 Pro Max`（API 26 / 7.0.0.106）
**应用**：Callaite `com.example.callaite`（targetSdkVersion 26.0.0）
**结论一句话**：闪退**不是应用代码缺陷**，而是**模拟器 express GPU 通路缺陷 + 宿主资源枯竭**共同导致：应用进入前台 → GPU ioctl 失败 → VSync 时间戳失效 → ArkUI 帧回调被排到 **2³² 毫秒之后** → 主线程永久阻塞 → 系统判定 `THREAD_BLOCK_6S` 杀进程。

---

## 一、闪退的直接机制（10/10 日志完全一致）

证据来自 `/data/log/faultlog/faultlogger/` 中 10 个 `appfreeze-com.example.callaite-*.log`。

| 项 | 值 |
|---|---|
| 冻结原因 | `Reason: THREAD_BLOCK_6S`（主线程阻塞 6 秒，系统杀进程） |
| 触发时机 | 每一次都在 `enters foreground` 之后 **170–200 ms** |
| 卡死任务 | `task name = vSyncTask`，`caller = event_queue.cpp(PostTaskForVsync:235)` |
| 进程内存 | RSS 稳定 **~203 MB**（无泄漏） |
| 客户机内存 | Total 4.0 GB，**Free 2.1 GB / Available 2.8 GB**（不是 OOM） |
| 主线程栈 | `libark_jsruntime` → `RTStub_CallRuntime`（ArkTS 运行时，非应用 JS 逻辑） |

### 关键量化事实：延迟恒等于 2³² 毫秒

`handle time − 入队时间`，10 个日志逐条计算：

```
2^32 ms = 4,294,967,296 ms = 49.710 天

file_time              enqueue_time      handle_time        delta_ms        delta/2^32
2026-09-19 13:51:03    13:50:47.856      次日06:53:35.150   4,294,967,294.0  1.000000
2026-09-19 13:52:57    13:52:41.812      次日06:55:29.106   4,294,967,294.0  1.000000
2026-09-19 13:55:45    13:55:29.534      次日06:58:16.828   4,294,967,294.0  1.000000
2026-09-19 13:57:27    13:57:11.404      次日06:59:58.698   4,294,967,294.0  1.000000
2026-09-19 14:57:21    14:57:06.301      次日07:59:53.595   4,294,967,294.0  1.000000
2026-09-19 15:00:14    14:59:59.205      次日08:02:46.499   4,294,967,294.0  1.000000
2026-09-19 15:01:05    15:00:49.883      次日08:03:37.177   4,294,967,294.0  1.000000
2026-09-19 15:06:47    15:06:31.594      次日08:09:18.888   4,294,967,294.0  1.000000
2026-09-19 15:11:26    15:11:11.021      次日08:13:58.315   4,294,967,294.0  1.000000
2026-09-19 16:12:33    16:12:17.669      次日09:15:04.963   4,294,967,294.0  1.000000
```

`4,294,967,294 = 0xFFFFFFFE = 2³² − 2`。**10 次完全相同**，说明不是调度抖动，而是 **32 位毫秒计数器溢出/错误哨兵值被当作延迟**：帧回调被排到 49.71 天之后，`completeTime` 永远为空，主线程再也不会被唤醒。

### 冻结前后的系统日志（同日志内嵌 hilog）

```
14:59:58.926  RS:      RSRenderServiceConnectHub call CreateConnection, needRefresh:[0]
14:59:58.927  WMSMain: VsyncStation: id 134552735449089 created
14:59:59.019  EntryAbility: Huawei account refreshed:
14:59:59.093  Ace:     ArkUI requests first Vsync.
14:59:59.205  WMSMain: VsyncCallbackInner: First vsync has come back   ← 回调延迟 112 ms（≈7 帧）
14:59:59.205  vSyncTask 入队 → handle time = 2026-11-08 08:02:46.499 ← 立即被污染成 2^32 ms
```

正常 VSync 应 ≤16 ms（60 Hz），这里首次 VSync 用了 **112 ms**，且随后时间戳直接失效——显示通路本身已处于异常状态。

---

## 二、为什么 VSync 会失效：express GPU 通路缺陷（已活体复现）

客户机内核持续报错：

```
[express_gpu_ioctl] command type [b] error!
```

### 历史会话（kernel.1.log）：错误分钟与冻结分钟重合

| 分钟 | ioctl 错误数 | 当分钟是否发生冻结 |
|---|---|---|
| 13:55 | 17 | **是** |
| 15:06 | 17 | **是** |
| 13:50 | 17 | 紧随 13:51 冻结 |
| 14:56 | 15 | 紧随 14:57 冻结 |
| 13:56 | 15 | 紧随 13:57 冻结 |
| 15:00 / 13:52 / 15:11 / 13:57 / 14:57 | 各 2 | **全部是** |

第 10 次冻结（16:12:33）前 **0.3–0.6 秒** 正是 `16:12:32.697 / 16:12:32.751` 两条 ioctl 错误。

### 当前会话（本次诊断，实时读取 kernel.log）：前后台切换即触发

```
应用 onForeground 事件                     express_gpu_ioctl 错误
10:25:16.373  Ability onForeground   →    10:25:17.544 / 17.548
10:25:26.026  Ability onForeground   →    10:25:27.167 / 27.171
```

本次做了 6 轮「HOME → 重新唤起应用」，产生 **6 组** ioctl 错误（10:24→11 次、10:25→9 次），**每次前台切换后约 1.1–1.2 秒必然报错**。

### 模拟器启动期的 GPU 缺陷

```
express_gpu_render.c(static_value_prepare:532)] when creating static vaules 500
egl_context.c(d_eglCreateContext:50)] real share context is NULL          （×2）
express_display.c(opengl_paint_composer_layers:708)] not support transform_type 8
express_bridge.c(bridge_socket_listen:105)] can't bind on socket port 5555 100.
express_gpu_snapshot.c(save_native_samplers:749)] gl error 500!            （快照保存时）
```

即：**准虚拟化 GPU（express GPU）在此镜像上本身初始化不完整**（EGL 共享上下文为空、静态资源创建 500、不支持 transform_type 8），这是 VSync 时间戳失效的源头。

---

## 三、模拟器不稳定的独立原因（宿主侧）

| # | 问题 | 量化证据 |
|---|---|---|
| 1 | **宿主内存枯竭（主因）** | `crash_server.log` 共 **2922 次** `memory is low`；宿主总内存 15975 MB，**空闲最低 135 MB**，48 次低于 500 MB；Windows 页面文件峰值 **8037 MB**。启动时模拟器自己就警告 `The host computer's memory is ： 3032 ,which is less than …` |
| 2 | 内存预算本身不合理 | 宿主 15.6 GB vs 实例配置 `hw.ramSize=4096` + 560 dpi / 1308×2880 高分屏 + DevEco Studio JVM 同时运行 |
| 3 | **热启动快照通路不可靠** | (a) 10:21 启动：`WaitSnapshotLoadingFinish:184] wait load snapshot finish time out`（加载超时）；(b) 10:31 启动：`start check snapshot` → `Guest OS Boot Completed` 仅隔 **2 秒**，客户机 `uptime` 显示 **4:22**（远超模拟器进程年龄），应用进程 pid 19378 **跨重启存活** —— 证明是 RAM 快照恢复，**GPU/显示上下文与窗口状态都是陈旧的**；(c) 快照保存通路不稳：同样是**用户手动正常关闭**，9/19 报 `gl error 500`、10/31 却成功 |
| 4 | hdc/日志通路损坏 | `can't bind on socket port 5555`；启动期 `hdc is not connected, hdc not init`；`Emulator.log` 中 `excute hilog error` **每 45 秒一次**（15:46–16:12 全程），导致崩溃时 hilog 抓不下来 |
| 5 | 其它子系统故障 | 当前会话仍有 **619 次** `access_tokenid_ioctl: access tokenid magic fail`、19 次 binder transaction failed、QOS_CTRL 失败；`Kickdog:open /proc/sys/hguard/user_list fail` 101 次 |
| 6 | 宿主机设备环境不完整 | **无音频设备**（`dsound: Could not initialize DirectSoundCapture`）；存在虚拟显示器驱动 `OrayIddDriver Device` 与 `NVIDIA GeForce RTX 5060 Ti` 并存（GPU 选择风险）；`licenses/config.ini`、`system-image/config.ini` 缺失告警 |
| 7 | 启动期镜像签名校验慢 | 每次启动 `CheckSign system.img cost 20506~21990 ms`、`sys_prod.img cost 4737~4782 ms` —— 单是签名校验就占 25 s 以上（I/O 密集，不导致冻结但拖慢启动） |

### 修正说明：`curFree` 不是宿主磁盘

早前把 `HdcClient.cpp(GetFreeDisk)` 打印的 `curFree = 4725336` 误读为宿主 F: 盘剩余空间，据此怀疑「磁盘不足导致快照写入失败」。经核对：**该值是客户机 data 分区剩余空间**（配置 `disk.dataPartition.size=6g`，`userdata.img.qcow2` 实占 934 MB，余 ≈4.7 GB），与宿主无关；宿主 F: 实测空闲 **305.7 GB**。因此「宿主磁盘不足」不作为不稳定原因，已从结论中移除。

### 重要澄清：模拟器进程本身**从未崩溃**

- 9/19 16:12 与 09/25 10:31 两次退出，日志均为**正常退出序列**（`StopMultiScreen` → `quit emulator` → `crash-service normal quit` → 线程收尾），实例目录下**没有 `Log\crash_report`**。
- 09/25 10:31 这次退出经确认为**用户手动停止模拟器**（正常关闭流程）。因此"退出序列干净 + 退出时快照保存成功"属于**预期行为**，不能当作任何故障或异常的证据。
- 结论：所谓「模拟器不稳定」的表现是**客户机内 GPU/VSync 故障、渲染 stall、快照加载超时、hdc/hilog 采集失败**，以及**应用被系统以 THREAD_BLOCK_6S 杀掉**；模拟器二进制本身没有崩溃记录。

---

## 四、已排除的可能原因（避免误判）

| 假设 | 排除依据 |
|---|---|
| 应用内存泄漏 / OOM | 进程 RSS 稳定 203 MB，客户机空闲 2.1 GB，无 OOM 记录 |
| 应用 JS 崩溃（jscrash/cppcrash） | faultlog 中**没有任何** jscrash/cppcrash，只有 appfreeze |
| 应用前台逻辑阻塞主线程 | `onForeground()` 仅打日志；重活（saveAll/云同步）在 `onBackground`，且卡死任务是系统的 `vSyncTask` |
| 客户机 lowmemorykiller 杀进程 | 内核日志无 OOM-kill 记录（仅 lowmemorykiller 路径配置告警） |
| 搜索面板/UI 残留状态 | 与本次无关（此前已确认为 warm start 现象） |
| 宿主 CPU 不足 | 14 核 Intel Ultra 5 245KF，非瓶颈 |

---

## 五、处理建议（按性价比排序）

### 立即可做（宿主侧，无需改代码）
1. **给模拟器腾内存**：运行前关闭 DevEco Studio、浏览器、其它虚拟机；目标是宿主**空闲内存 ≥8 GB**（本次诊断即为此状态，6 轮前后台切换未再冻结）。
2. **确认磁盘余量**：宿主 F: 空闲 305 GB（充裕，非问题）；客户机 data 分区 6 GB 中余 ≈4.7 GB，若后续灌入大量文件/应用需留意分区写满。
3. **关闭热启动快照（强烈建议）**：编辑实例 `config.ini` 将 `isHotBoot=false`（或删除实例目录下 `ram.img`/`ram.bin` 强制冷启动）。依据：快照加载一次超时、一次 2 秒成功；保存走的是**正常关机**流程，9/19 报 `gl error 500`、10/31 成功；且恢复后**客户机 uptime 4:22、应用进程跨重启存活**，说明 GPU/显示与窗口上下文全是陈旧状态——这正是 VSync 时间戳失效的可疑来源。用户数据在 `userdata.img.qcow2`，删快照不丢数据。
4. **降低显示负载**：改用低 dpi 实例（如 `MatePad Pro 13`）或降低 `hw.lcd.density`，减少快递 GPU 合成压力。
5. **GPU 驱动/设备**：运行模拟器时禁用 `OrayIddDriver` 虚拟显示器；RTX 5060 Ti 驱动（32.0.16.1692 / 2026-09-04）可尝试回退或更新。

### 应用侧加固（缓解，不治本）
6. 首帧减负：前台恢复时避免一次性重建整棵日志流；`EntryAbility` 已用 350 ms 延迟切换沉浸式（代码注释记录了同类渲染服务 IPC 阻塞史），可继续沿用该策略并把重活下移到 `setTimeout`/任务队列尾部。
7. 崩溃可观测性：`ErrorRecoveryService` 已有，可补一条「上次异常退出」标记落盘，便于下次启动提示——但注意 `THREAD_BLOCK_6S` 是系统直接杀进程，应用无法拦截。

### 上报华为
8. 这是一条**可复现的系统缺陷**，建议附带证据上报：
   - `PostTaskForVsync` 在 VSync 时间戳无效时把延迟算成 **2³²−2 ms**（应为兜底为下一帧或丢弃），10 次日志 delta 完全一致；
   - 同一镜像 `express_gpu_ioctl command type [b] error!` 每次前台渲染必现；
   - 启动期 `real share context is NULL` / `creating static vaules 500` / `not support transform_type 8`。

---

## 六、证据文件

| 文件 | 说明 |
|---|---|
| `callaite_freezelogs\appfreeze-com.example.callaite-*.log`（10 个） | 应用侧冻结日志，含主线程事件队列、栈、内嵌 hilog |
| `F:\DevEco Studio\sdk\Pura 90 Pro Max\Log\crash_server.log` | 2922 次宿主内存告急记录 |
| `...\Log\Emulator.log` | 启动配置、宿主内存监控、hilog 抓取失败 |
| `...\Log\qemu.log` | express GPU / EGL / 显示合成错误 |
| `...\Log\kernel.log` / `kernel.1.log` / `kernel.2.log` | 客户机内核：express_gpu_ioctl 错误、token/binder 故障 |
| `...\Log\memInfo.log` | 客户机内存分布 |
