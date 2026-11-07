# 守颐 · 赛题四项目交接文档

2026-11-05 更新。用户实测 RK2206 屏幕显示 `SLE:ON`，`OK` 持续增加，
确认 H2821 → H3863 → RK2206 本地数据链路已通。433 D0 迁到 PB0 后，
按按钮可直接触发本地报警，用户反馈响应更快。

2026-11-06：用户亲测"按报警按钮 → App 预警 → App 处置 → 主控自动消音"
闭环通过 ✅，演示视频镜头 4 的前置已解除。

烧录工具缺少 firmware 行的问题已修复。用户通过桌面「守颐主控烧录」
快捷方式重开后确认两行均在。正确固件已烧入并显示 SLE 状态行。
主控接线、历史故障与验证边界见 [本地桥接记录](LOCAL_BRIDGE.md)。

App 页面已开始修改。模拟模式保留演示告警，真实云模式下刷新只更新数据，
预警中心隐藏「模拟告警」入口。待在 App 上复验这两种模式的行为。

手表历史与最新体征卡片已接入守颐 App，并安装到模拟器。耆康云盾已收到
尾号 1265 手表重新上线后的定位报文，现有 929 条历史记录可供查询。
登录后显示实际读数及新测量上报仍待验收，见 §3.1。

剩余硬件验收包括关热点后的完整流程、板载按键消音、终端断电重连。
联网后实体 433 → App 预警已复验；App 处置 → 主控消音已于 11-06 亲测通过。

## 0. 项目是什么

第三届河南省高等学校信息技术应用创新大赛 · 开源鸿蒙 · **赛题四：独居老人居家安全监测与应急辅助系统**。
- 设计方案：《守颐》docx（副本在 `D:\jishe\sssss\.iot_design\`）
- 大赛通知：同目录 `competition_notice.pdf`
- **关键期限：作品提交 11-06（含演示视频+设计方案，硬期限）；路演 11-13/14**。报名已完成 ✅

## 1. 硬件与环境（全部就绪）

| 项 | 位置/值 |
| --- | --- |
| 开发板 | TX-Smart-R（RK2206，OpenHarmony 3.0 LiteOS-M） |
| 源码 | WSL(Ubuntu-24.04) `/root/txsmart`，分支 **shouyi-monitor**，已全部提交 |
| 编译 | **容器 `ohos` 已不存在（环境已在 WSL 宿主重建，见 §12）**：`wsl.exe -d Ubuntu-24.04 -u root bash /root/build_rk.sh`，增量约 6-8 秒 |
| 固件产物 | `/root/txsmart/out/rk2206/isoftstone-rk2206/images/Firmware.img` → 拷到 `D:\jishe\sssss\.iot_design\firmware\` |
| 烧录 | **D:\RKDevTool\RKDevTool.exe**。**注意：`D:\out\rk2206\TB-RK2206H0-A\images` 是指向固件目录的 junction（2026-11-01 建），删了它 RKDevTool 的镜像表会丢行** |
| 串口 | 115200 8N1，PowerShell 抓；脚本 `D:\jishe\sssss\.iot_design\serial_capture.ps1`（插拔后 COM 号会变，用 `[System.IO.Ports.SerialPort]::GetPortNames()` 查） |
| WiFi | 写死热点 "Redmi Turbo 3"/"xjcvbnmk"，仅 2.4G |
| 大坑 | LCD 中文查表渲染（lcd_font.h）；线程栈默认 2048 不够（smart_home 已 8192） |

## 2. 云端（全通，参数已逐项核对）

- 华为云 IoTDA 免费实例（北京四）：`2eb62113b2.st1.iotda-{device|app}.cn-north-4.myhuaweicloud.com`
- 设备：`6ad6dbb77f2e6c302fa4ef57_sy-rk2206-001`，在线、约 3-5 秒上报一次
- 物模型：服务 **monitor**（pir/door/temperature/humidity/smoke/gas/sos/battery/alarmActive/rssi + 4 健康占位）；命令服务 **control**（confirmAlert/handleAlert → 消音）
- App 认证：IAM 子用户 `shouyi-app`/`mmy262455`（账号 `hid_gk2lr21z__-uc0-`），X-Auth-Token
- **现成工具**：`D:\jishe\sssss\.iot_design\cloud_check.py`（WSL python3 跑）——查设备状态+影子（sos/alarmActive/温度等+时间戳），联调时代替串口看设备侧
- ⚠️ 安全收尾（**用户还没做**）：对话里出现过 3 把 AK/SK（hhh 一把、hid_ 两把），控制台「我的凭证→访问密钥」删掉

## 3. App（D:\jishe\js-work\ShouYi）——已真云跑通 ✅

- ArkTS，五页面 + cloud/ 适配层。`IotDaConfig.ets` 参数与实测一字不差，**零改动直连真云**
- DevEco Studio 26.0.0.851 装在 `D:\DevEco Studio`（SDK API 26 内置；工程按 API 12 构建，构建时按提示补装了 SDK）
- **模拟器跑通**：Mate 90 Pro HVD。真实云链路：SOS→App 预警中心出卡已验证 ✅
- ⚠️ **模拟器已迁移 D 盘（junction 方案，动过就坏）**：`C:\Users\admin\AppData\Local\Huawei\Sdk` 和 `...\Huawei\Emulator` 现在是**指向 `D:\DevEcoEmulator\` 的 junction**。IDE 配置（Roaming\Huawei\DevEcoStudio26.0\options\deviceManager.xml）每次启动会自己改回 C 盘路径——别去改它，junction 顶着就行。C 盘空余约 20G
- `subscribeAlerts` 每 4 秒轮询影子；App 处置 → confirmAlert/handleAlert 命令 → 板子消音

### 3.1 手表体征接入（2026-11-05）

守颐 App 通过耆康云盾现有的鉴权接口，只读查询尾号 1265 的手表
（耆康云盾设备编号 `9323`）。数据链路为手表 → 5C 平台 →
耆康云盾 → 守颐 App，与 RK2206 和星闪的环境监测链路并行。

| 指标 | 耆康云盾历史记录数 |
| --- | ---: |
| 心率 | 233 |
| 血氧 | 220 |
| 体温 | 233 |
| 血压 | 235 |
| 步数 | 8 |
| 合计 | 929 |

- 入口为「实时状态」中的「生命体征 · 手表」。使用有体征查看权限的
  耆康云盾账号登录后，卡片每 30 秒查询各项最近读数，也可手动刷新。
- 「查看手表历史」与体征卡片共用登录会话。历史页按指标分页，步数按日展示，
  其余指标显示后台记录时间。手表离线时仍可查询已保存的记录。
- App 已构建并安装到 Mate 90 Pro 模拟器。已验证体征卡片、历史页入口
  和生产验证码加载。相关源码为 App 工程中的 `WatchHistoryApi.ets`、
  `WatchHistory.ets` 和 `WatchVitalsCard.ets`。
- 后台在 11 月 5 日 23:35 收到上线报文，23:49 收到定位报文
  （均为洛杉矶时间）。最近一次心率、血氧、体温和血压入库仍是
  10 月 23 日 22:52（洛杉矶时间）。

验收时先登录并核对历史记录，再在表上手动测量一次心率，确认耆康云盾
收到新 `INFO` 报文并写入记录，最后在守颐刷新读数，核对数值与记录时间。

## 4. 当前进度（2026-11-01 会话末）

**已完成：**
1. 固件赛题四化全部提交（monitor 上报/燃气阈值报警/PIR/上键SOS/任意键消音/LCD 红底报警横幅）
2. 最新固件烧录 + 真机验证：SOS→蜂鸣+红灯+横幅→按键消音 ✅；云端影子确认 `sos:true` 上报、消音后持续上报 ✅
3. DevEco 安装 + 模拟器迁 D 盘 + **App 真云跑通，报警已收到** ✅

**已知遗留（不阻塞演示）：**
- **串口打印死**：第一次报警消音（IoTPwmStop→LzPwmStart(port,0,0) 假停止）之后，串口控制台永久变哑，但系统活着（LCD/上报/按键全正常）。已排查：代码路径无死循环、PWM HAL 无除零；根治方案候选=消音改 `IoTPwmDeinit+IoTPwmInit`（未试验，改后要重烧）
- 演示时调试盲→用 cloud_check.py 看影子

## 5. 下一步（按优先级）

1. ~~确认 App 处置→板子消音闭环~~ **✅ 2026-11-06 亲测通过**（按报警→App 预警→处置→主控自动消音），演示视频镜头 4 可拍
2. **演示视频**：拍摄脚本已写好 `D:\jishe\shouyi-iot\demo_video_script.md`（E-01~E-04 分镜+压缩命令），按脚本拍，11-06 硬期限
3. **设计方案更新**：选型改 TX-Smart-R 实际资源、补真机/云端实测数据（11-06 交）
4. PPT（路演 11-13/14）；外购门磁+433M 遥控按钮

## 6. 备忘/踩坑（新会话别再踩）

- Git-Bash 里向 wsl 传含 `\` 的命令会被转义坑 → 复杂改动写成 .py 放 `/mnt/d/...` 再 `bash -c "python3 -I /mnt/..."` 执行（**路径要包在 bash -c 的引号里**，裸传会被 MSYS 转成 D:/Git/mnt/...）
- zip 中文文件名 GBK：python `encode('cp437').decode('gbk')` 解
- IntelliJ 系 IDE 退出时会回写 options/*.xml——改配置必须先强杀进程（CloseMainWindow 不行），改完再启
- robocopy /MOVE 跨盘搬目录 + junction 是给 IDE 类工具"挪盘"的通用解法
- 上一会话 ID：`session_b4c27cbaf57f84ba16c5524a6038d852`

## 7. 星闪支线（11-01 夜新开，勿混入主线）

目标：星闪自组网补 Wi-Fi 覆盖盲区。三块新板：**T=H2821(终端)**、**G=H3863(网关)**、**R=H3863(中继，未验机)**。G 已烧入自编固件并启动成功 ✅

### 环境与路径（全部就绪）
- SDK：`D:\sdk\nearlink\fbb_ws63`（ws63，**直接在 src 内构建**）、`D:\sdk\nearlink\fbb_bs2x`（H2821，未构建）
- 编译：`bash D:\jishe\shouyi-iot\tools\build_ws63.sh ws63-liteos-app`（约 7 分钟首编，增量秒级）
- 烧录：`bash tools\flash_ws63.sh COM7 460800` → **30 秒内按 RST**。921600 会掉数据（CH340），**固定 460800**
- 验机：`powershell -File tools\read_serial.ps1 -Port COM7`（脚本在 tools/，DTR 开）
- 插件版 IDE：HiSpark Studio v26.9.1 已装，但侧边栏图标没显示过；**全流程走 CLI，不依赖 GUI**
- 工具链：VS Code 目录内 `tools\Windows\{cc_riscv32_musl_fp_win,gn,ninja}` + `tools\python`（内置 Python 3.11.4，pip/kconfiglib 已 --user 装好，python311._pth 已放开 import site）

### 大坑（已踩过，勿重踩）
1. **cmake 必须 3.20.5**（官方捆绑 wheel：`VS Code目录\resources\app\downloads\cmake-3.20.5-*.whl`，已装到用户 site）。4.x 会把 wpa_supplicant 超长命令行搞炸：`CreateProcess: No such file or directory`
2. **必须 `CMAKE_NINJA_FORCE_RESPONSE_FILE=1`**（build_ws63.sh 已带）
3. COM 号会漂：插拔后用 `Get-PnpDevice -Class Ports` 重扫；COM5=旧 RK2206 那套，别认错
4. BurnToolCmd 参数：`--burn -n ws63 -m serial COM 460800 0 0 -f xxx_all.fwpkg`（是 `--burn` 不是 `burn`）
5. 星闪 SDK 半开源：外设库为 .a，业务接口开放，够用

### 关键例程（现成的，别重造）
- ws63：`src/application/samples/bt/sle/sle_uart`（透传）、**`sle_sensor_report`**（温湿度定时上报+告警，架构=本项目）、`bt/sle_chba`（星闪组网+SLE↔WiFi 桥接，网关/中继底子）
- bs2x：`src/application/samples/products/sle_uart{client,server}`、`sle_multi_conn`
- 例程启用走 Kconfig（samples/Kconfig），怎么在 CLI 下切 sample 待研究

### 当前固件状态
- G 板跑默认固件：AT 框架已挂载（`at_recv`）、SLE MAC 已打印、RF 校准 OK。boot 日志若见 `version: bs21e`=H2821，`flashboot version: 1.10.102`=ws63 无应用（出厂态）
- 下一步：① CLI 下启用 sle_uart sample→G 烧透传服务端 ② T 板走 fbb_bs2x 编译链（可能要 WSL）烧透传客户端 ③ 点对点透传跑通 ④ 中继 ⑤ 网关连热点 "Redmi Turbo 3" + MQTT → IoTDA 新设备 `sy-nearlink-001`（复用 monitor 物模型，cloud_check.py 换设备 ID 验证）
- 期限倒逼：星闪链路 11-04 前必须可演示，只做温湿度上报，别扩scope

## 8. 星闪支线·阶段0收官（11-01 凌晨，接着干从这里开始）

**✅ 已达成：S↔C 点对点星闪建链成功，断线自动重连已验证**
- S 板（H3863，已贴标）= sle_uart **服务端**，广播 `uart_server`，等连接
- C 板（H3863，已贴标）= sle_uart **客户端**，扫描→连接→配对→服务发现→`=== bridge ready ===`
- C 串口日志实证：断链（reason 0x7）→ 自动重扫 → 自动重连 → 桥恢复。**这段日志就是视频"鲁棒性"镜头素材**
- 两板桥接的是 UART1（pin15/16, 115200），PC 调试口是 UART0——测真实数据流需要杜邦线跨接，未做

**板子/COM 现状（COM 号会漂，用日志特征认板，别信端口号；11-01 实测标签与固件曾对不上，以固件特征为准）**
| 板 | 物理特征 | 特征日志 | 固件 |
|---|---|---|---|
| T (H2821) | bs21e | `[sle uart server] ... local_name: sle_uart_server` + `data uart init bus=2` | sle_uart_server v2 ✅ `fw/bins/bs21e_sle_uart_server_all.fwpkg` |
| C (H3863) | **没焊排针**（11-01 确认） | `[sle uart client] scanning` / 静默=扫描中（客户端固件无心跳日志） | sle_uart_client ✅ `fw/bins/ws63_sle_uart_client_all.fwpkg`（11-01 重烧） |
| S (H3863) | 有排针 | `[sle uart server] waiting for connection` | sle_uart_server（待重烧为"客户端+上云"） |
| G (H3863) | — | `APP\|[SYS INFO] ... at_recv`（默认AT固件心跳） | 出厂默认 |

- **ws63 客户端固件静默≠没跑**：它在安静扫描，没有心跳日志；上电时若服务端不在场，扫不到不会自动重启扫描——**拔插重上电即可**（boot 时服务端在场就连上）
- **ws63 烧录 30 秒 RST 窗口容易错过**：用"循环重试 4 次 + 用户每 2-3 秒按一次 RST"的打法一次成功（tools/flash_ws63.sh 循环包一层）

**历史烧录经验（复位时机以 §10 为准）**
1. **烧录时电脑只连一块板**——两块 CH340 同挂会干扰（握手失败/传输中断），S 一次过、C 连挂三次都是这个原因
2. C 曾因两次中断烧录变砖（boot 循环 `upg verify: image ID error`）——**完整重烧即可救活**，不必慌
3. 波特率 460800 起步；某根线质量差会掉数据（换线解决），921600 必掉
4. sample 开关在 `build/config/target_config/ws63/menuconfig/acore/ws63_liteos_app.config`：改 SERVER↔CLIENT 就换 `CONFIG_SAMPLE_SUPPORT_SLE_UART_{SERVER,CLIENT}_SAMPLE=y`，**build_ws63.sh 已内置 touch CMakeLists 强制重配置**（不加这步 Kconfig 改动不生效，坑过）

**下一步优先级**
1. **T 板（H2821）编译链**：fbb_bs2x + 内置工具链（`VS Code目录\tools\Windows\` 里可能直接有 bs21 用的编译器，先查；不行走 WSL）→ 烧 sle_uart 客户端 → C 或 T 连 S
2. 数据通路验证：杜邦线把一侧 UART1 TX↔RX 环回，串口发数据看跨空回环
3. 真业务改造：终端周期上报 JSON（参考 `sle_sensor_report` 例程）→ S 收到打印
4. S 板加 Wi-Fi+MQTT 上云（IoTDA `sy-nearlink-001`，热点 Redmi Turbo 3）
5. 中继：chiba 例程或双角色桥，演示前摆位测试

## 9. 星闪支线·三板全点亮（11-01 晨，软件侧从这继续）

**✅ 硬件侧全部完成：三块板均烧入自编固件并验证启动**
| 板 | 芯片 | 当前固件 | 验证结果 |
|---|---|---|---|
| S (H3863) | ws63 | sle_uart **服务端** | 广播+接受连接 ✅ |
| C (H3863) | ws63 | sle_uart **客户端** | 扫描→建链→断线自动回网 ✅ |
| T (H2821) | bs21e | standard 标准固件 | `bs21e 1.0.19` 启动正常 ✅ |

固件三件套都在 `D:\jishe\shouyi-iot\fw\bins\`（ws63_server / ws63_client / bs21e_all_in_one）。

### T 板编译链（WSL 路线，Windows cmake 路线已放弃）
- **Windows 下 fbb_bs2x 编不了**：cmake configure 在闭源库兜底处拿空变量调 `cmake -E` 崩（`__null__`），死磕无意义
- **正确姿势：WSL Ubuntu-24.04**，SDK 已拷到 `/root/fbb_bs2x`（原生 fs，/mnt/d 编译慢到哭）
- WSL 依赖已装好：pip3(--break-system-packages) cmake==3.20.5 ninja kconfiglib **pycparser**（缺它 NV 打包会挂）
- 编译命令：`wsl -d Ubuntu-24.04 -u root bash -c "cd /root/fbb_bs2x/src && python3 build.py standard-bs21e-1100e"`
- **大坑：拷 SDK 千万别带上 output/ 目录**——里面 CMakeCache 记着旧路径（d:/...），cmake 直接罢工"cache directory different"
- 样例开关同 ws63 套路：改 `src/build/config/target_config/bs21e/menuconfig/acore/standard_bs21e_1100e.config`（bs2x 的 sle_uart 在 `application/samples/products/sle_uart/`，分 client/server 子目录）
- 产物：`output/bs21e/fwpkg/standard-bs21e-1100e/bs21e_all_in_one.fwpkg`

### T 板烧录（只能走 GUI，命令行走不通）
- `BurnToolCmd.exe`（-n 方式）**不支持 bs21e**：两个 3071 die 名都在 `m_seq:2 / Toggle I2C rate failed` 协议不匹配处死——别再试了
- **正道：`C:\Program Files\Microsoft VS Code\tools\cfbb\BurnTool\BurnTool.exe`（Qt GUI）**
- 已预置：`configure/config_chip_type.ini` → CurrentChipTypeId=12（BS2X）、`config_all_chip_type.ini` → BAUND_RATE11=750000
- GUI 流程：COM 选口 → **Select file** 选 `bs21e_all_in_one.fwpkg`（分区表自动填出）→ 勾 **Auto burn** → Disconnect → Connect → **按 T 的 RST** → 自动烧完自动复位
- T 板烧录实测多板同挂没问题（ws63 才有单板铁律）；COM 号天天漂，认板靠日志特征（见第 8 节表）

### 网关上云进度（11-03 凌晨，卡在最后一米）
**已完成：**
1. ✅ IoTDA 设备已用 API 建好：`6ad6dbb77f2e6c302fa4ef57_sy-nearlink-001`，secret=`shouyi-nl-2026`，复用主线程产品（monitor 物模型），脚本 `tools/cloud_mkdev.py`
2. ✅ **网关固件**（C 板，H3863 无排针那块）：`fw/bins/ws63_gateway_all.fwpkg` —— 在 sle_uart 客户端桥上加 Wi-Fi STA(热点 Redmi Turbo 3) + MQTT 上云。补丁链（幂等）：`patch_c_gateway.py`→`fix_c_gateway.py`→`fix_c_gw_scan.py`→`fix_c_gw_chscan.py`→`fix_c_gw_wifi_first.py`→`fix_c_gw_singlescan.py`→`fix_c_gw_mqtt_once.py`→`fix_c_gw_auth.py`（源文件备份 `.bak_pre_gw`）
3. ✅ **Wi-Fi 链路已验证通**：扫到热点→连接→DHCP 拿 IP（串口日志实证过）；SLE 侧 `gw_notify_publish` 挂钩在 notify 回调里，收到 T 的 JSON 就组 monitor 属性上报（rssi 实时值 + temperature/humidity 透传）
4. ✅ **三个关键修复**：
   - MQTT 域名：**`2eb62113b2.st1.iotda-device.cn-north-4.myhuaweicloud.com:1883`**（RK2206 同款端点；`iotda-mqtt` 是不存在的域名——NXDOMAIN 曾误导成"热点DNS问题"）
   - paho `MQTTClient_init()` 全局只调一次（每次调用泄漏 5 个 mutex，10s 重试循环打光 LOSCFG_BASE_IPC_MUX_LIMIT=20 的池子 → `client_mutex` init 失败）
   - **认证公式（11-03 反推+SDK样例双确认）**：`clientId={deviceId}_0_0_{ts}`、`password=HEX(HMAC-SHA256(key=ts字符串, msg=secret))`——SDK 自带样例 `ble_gateway/ble_gateway_client/src/ble_gateway_iotda.c` 注释写明官方 test vector 就是这个。固件 ts 硬编码 `2026110312`（RK2206 预证：它的 ts 是 10-23 的，11-01 仍在线，平台不严格查新鲜度）
5. ✅ 平台侧 `secure_access` 已改为 false（原 true 强制 TLS 会拒 1883 明文），API PUT 改的，无需控制台

**当前卡点（板子行为：WiFi 过了之后 MQTT 层静默，云端始终 INACTIVE）：**
- 待办 A（已在 §10 解决）：**开机看一次 boot 日志**（抓串口时按 RST），看 CONNECT 后 CONNACK rc 是多少——0=成功（剩下就是查热点），4=认证仍错，超时=端点问题
- 待办 B：**热点是最大环境变量**！小米热点"无设备连接自动关闭"会反复作妖（已多次坑：曾把"扫不到AP"误诊为板子问题）。演示当天用固定 WiFi 或关掉该开关
- 待办 C：MQTT 通了之后，插回 T 板（SLE 自动重连）→ T 的 JSON 会经 C 上云 → `cloud_check.py` 换 DEVICE ID 查 sy-nearlink-001 影子
- WSL 里测 MQTT 的路已通（`tools/mqtt_auth_bruteforce.py` 可改造成单发验证器；注意 PC 的 TUN 代理会 fake-ip 劫持 DNS，测之前用 `dns.google` WebFetch 拿真 IP）

**烧录铁律补充（11-03 血泪）：**
- 被取消的烧录循环会留下**僵尸 BurnToolCmd 占住 COM 口**，后续所有握手必然失败——烧录前先 `Get-Process | Where-Object {$_.ProcessName -like '*Burn*'} | Stop-Process -Force` 清场
- **USB 拔插不能当烧录复位用**（拔的瞬间串口句柄死掉，烧录工具永远慢一步），只有 RST 按键有效
- 烧录循环打法：`for i in 1..6; do flash_ws63.sh COM4 ...; done`（工具每次等 30s，用户每 2 秒按一次 RST 必撞上）

### T 板数据串口选型结论（11-01 定，别再翻）
- bs21e 总线：`UART_BUS_0`=L0（烧录口，codeloader 引脚 30/31）、`UART_BUS_1`=H0（**日志口**，`log_uart_init` 用 bus1 + CODELOADER 引脚 31/30，但 `uart_claim_pins` 会按 porting 表把 bus1 mux 到 17/18——实际物理归属有不确定性，**17/18 别动**）
- **数据串口选 `UART_BUS_2`(L1)**：porting 表引脚=PIN_NONE，claim_pins 不碰任何物理引脚，零冲突。样例 `uapi_uart_init` 传 17/18 仅为过参数校验
- 将来接实体传感器时：改 `uart_porting.c` 的 `g_pin_config_map[UART_BUS_2]` 换真实引脚（air_mouse 分支用的 17/18 是家族已知 L1 对，但要先确认与日志口不撞）
- 引脚复用枚举：`HAL_PIO_UART_L1_TXD=19 / L1_RXD=21`；PIN_NONE=32；`PIN_NONE`/S_MGPIO* 在 `platform_core.h`

## 10. 星闪稳定性修复与上云实测（2026-11-03）

本次已烧入两份修复固件，并验证 T→C→IoTDA 连续通信。
§9 的 MQTT 静默/未上线是历史状态；当前设备已在线。

### 修复内容与固件

本次修复两个由串口日志和 SDK 源码定位的问题，RK2206 程序未改动。

- T（H2821）：`SLEUartRptTask` 出现明确的 `stack overflow`，
  随后异常并导致星闪断线。将发报任务栈从 `0x800` 增至 `0x2000`。
  固件：`fw/bins/bs21e_sle_uart_server_stability_all.fwpkg`。
- C（H3863 网关）：同步 MQTT 客户端发送 QoS1 消息后未及时处理回执。
  SDK 的 LiteOS 适配在待确认队列满时直接返回失败。
  现增加 `MQTTClient_waitForCompletion(..., 5000)`，
  并在等待终端数据的空闲期间调用 `MQTTClient_yield()` 处理保活与断线。
  固件：`fw/bins/ws63_gateway_stability_all.fwpkg`。
- 可重复应用的补丁脚本：`tools/fix_sle_stability.py`。
  两端修改前的源文件保留 `.bak_pre_stability` 备份。

### 实测证据与边界

两份固件均编译通过并完整烧录成功，随后进行两分钟持续测试。

| 检查项 | 本次结果 |
| --- | --- |
| T 发报 | 60 条，序号连续至 72 |
| C 收到终端报文 | 60 条 |
| MQTT 云端回执 | 60 条 `publish completion rc=0` |
| 上报失败、栈溢出、运行异常 | 本次采集均为 0 |
| IoTDA 状态 | ONLINE，monitor 影子 rssi 更新 |

原始日志：
[网关两分钟日志](logs/20261103_045129_COM4_stability.log)、
[终端两分钟日志](logs/20261103_045129_COM15_stability.log)。
采集脚本为 `tools/capture_stability.ps1`，云端检查脚本为
`tools/check_cloud_stability.py`（复用现有本地认证助手，不复制凭据）。

T 仍每两秒发送 `seq/dev/ping` 测试报文，没有真实温湿度。
C 当前因此只上报自己的 Wi-Fi rssi；不能把这项结果当作终端传感器采集完成。
两分钟测试证明本次运行稳定，不代表完成长期运行或所有断网恢复测试。

### 烧录操作修正

你必须先看工具是否已经开始传输，再决定是否需要复位。
本次前几轮在出现进度后又按 RST，传输中断并出现反复 `boot`；
不再按 RST 后完整重烧成功，不能将前几次失败直接归因于线缆。

1. BS21 GUI 的 **Auto burn** 可能直接接上启动循环并开始写入。
   已有进度时不要按 RST、拔线或重新上电，等待
   `All images burnt successfully`。
2. 只有明确还在等待握手、尚未传输时，才短按一次 RST。
   WS63 命令行本次在 `Please reset the device` 时按一次即可。
3. 本次 BS21 使用独立副本 `tools/BurnTool_stability/BurnTool.exe`，
   BS2X 波特率配置为 115200；原安装目录配置未改动。
   WS63 使用 460800，命令行烧录结束后需要启动应用时，
   必须先确认 `Burned successfully`，退出烧录工具后才复位。

本次最终端口是 RK2206=COM12、C=COM4、T=COM15。
端口会随插拔变化，继续以固件日志识别板子。

### 下一步

保留当前已验证链路，下一阶段接入真实终端传感器，并补做长时间运行、
热点断开恢复及 RK2206 的 App 远程消音验证。

## 11. T 板接 HC-SR501（2026-11-05，本节是 PIR 的最新状态）

T 板=BearPi-Pico H2821E（SDK `vendor/BearPi-Pico_H2821E`，引脚图见 bearpi.cn）。

**引脚大坑：GPIO11 不能用。** 上一会话把 PIR 做在 GPIO11（排针脚3），
但 `flash_porting.c` 把 S_MGPIO11 映射为 SPI1_TXD —— 那是片上 flash 总线
（11=TXD/2=CS0/3=RXD/9=CLK），接传感器会互相打架。已挪到 **GPIO21（排针脚14）**。
避让清单：GPIO11-14=flash SPI 组、17/18=日志串口、0/1=晶振、9/10=NFC、
2-5/25/28-31=上电前不可拉高（否则不启动）、SWCLK/SWDIO 别碰。
GPIO21/22/15/16/26/27 是干净脚。

**固件**：`fw/bins/bs21e_pir_gpio21_all.fwpkg`（05:52 编译，源码改了
`sle_uart.c` 的 `SHOUYI_PIR_GPIO`，备份 `.bak_pre_pir21`）。PIR 任务每 2 秒
轮询 GPIO21，60 秒预热抑制，SLE 建链后随 JSON 发
`{"seq":N,"dev":"sy-t-001","pir":..,"pirReady":..}`；串口打 `[sy pir] GPIO21=0/1`。

**接线**：HC-SR501 VCC→脚1(3.3V)、GND→脚2、OUT→脚14(GPIO21)。
模组跳线拨 H（可重复触发），延时电位器拧到最小。先用 3.3V 供电保电平安全；
若模组 3.3V 不工作改 5V+分压再进 GPIO。演示前提前 1 分钟上电过预热。

**已知现象（11-05 两次烧录 2/2 复现）**：烧完第一次启动必看门狗崩溃
（panic id 36、pc=0x0、caller=app_main，日志 `logs/bs21_pir_first_run.log`
与 `bs21_pir_ie_selftest.log`），第二次启动起完全稳定。两个嫌疑：
① GPIO11/flash 争抢（GPIO21 固件可判别：还崩就排除了它）；
② all_in_one 每次重烧 NV 分区，全新 NV 首启初始化出问题（11-01/11-03
烧录没抓过启动段，无法对比）。烧 GPIO21 固件时**务必抓启动段日志**验证。

**网关侧待办**：C 板网关目前只透传 rssi/温湿度，pir 字段还没进 monitor 上报；
接线验证通了再补网关透传。

## 12. RK2206 接入 433 遥控 SOS + 门磁 + 构建环境重建（2026-11-05）

**达成：433 遥控 SOS 全链路真机验证 ✅**（按遥控→蜂鸣+红灯+LCD 红底横幅→影子
`sos:true`→App 预警卡，板载任意键消音兼容），两轮烧录实测（第二轮含延迟优化）。
构建链在 WSL 宿主重建完成，**§1 的"容器 ohos"编译条目作废**。

### 新硬件（11-04/05 到货，已按订单截图核对）
| 器件 | 用途 | 状态 |
| --- | --- | --- |
| 433 遥控 + 解码接收模块（自锁/互锁/点动三模式） | 随身 SOS | ✅ 已接入已验证；**跳线必须"点动"**（按住=高松开=低） |
| 干簧管 8×50mm 3 脚转换型 ×2 | 门磁 | RK2206 支**未接线（推迟 11-06）**：引脚太粗插不进杜邦母头，等网线到货剪芯绕线；第二支规划给星闪 T 板（路演） |
| HC-SR501 | 星闪终端 PIR | 已接 T 板，见 §11 |
| LD2410D-B 24G 存在雷达 | 存在感应升级 | 未接：单模块裸焊盘，免焊连接不可靠；等烙铁+2.54 排针，走 OUT 引脚方案，排路演 |
| N38 磁铁×10 / 防水盒×3 / 万能板×2 / 杜邦线 | 门磁安装辅料 | — |

### RK2206 新增引脚（原理图已核对：`docs/board/` 下有 PDF）
| GPIO | 物理位置 | 功能 |
| --- | --- | --- |
| GPIO0_PB6 | **J2 排针第 10 脚** | 433 解码 D0 输入 |
| GPIO0_PB7 | **J2 排针第 11 脚** | 门磁干簧管 NO（COM→GND；固件内部上拉，门开=高=door 1） |
| GPIO0_A4 | J1 第 14 脚 / J3 第 2 脚 | 仍空闲（下一个备用脚） |

3.3V=J1 第 3 脚；5V=J1/J2 第 1 脚；GND=J1-2、J2-2、J2-14。
引脚排除记录：PC7 没引到排针（老例程用它，别参考）；PB6/B7 在 HAL 表里是
EUART0_M0，但控制台实为 UART1_M1（PA6/PA7 经 CH340），EUART0 无人在用，安全；
PA0/PA1 被 EI2C0_M2（温湿度/光照）占用；板载已占：PA3=PIR、PA5=报警灯、
PC0-3/PA4=LCD、PB4/PB5/PD0=RGB、PWM5=蜂鸣器、PWM6=电机、UART2_M1=PB2/PB3 语音。
门磁判脚：磁铁靠近导通的一对=COM+NO；接到 NC 行为会反向，串口 door 翻转实测即可分辨。

### 固件改动（补丁 `tools/fix_rk2206_gpio433.py` 已应用；**源码改动未 git 提交**）
- `smart_home.c`：B6=433 D0 → 去抖上升沿 → `g_sos=true` 并**立即 `alarm_tick()`**
  （蜂鸣/红灯 ≤300ms，不等主循环）；B7=门磁，**PinctrlSet 上拉必须放在
  IoTGpioInit 之后**（放前面会被冲掉，实测踩过）；`iot_data.door` 改实读
  （替换 `iot_smart_home_example.c` 写死 0；1=门开，与 App 语义一致）
- 日志：电平变化即打 + 6 秒心跳 `[sy 433] B6=x door=x`、`[sy door] OPEN/CLOSED`
- `include/link.h`：SRAM_CODE 0x26000→**0x2C000**。原因：gcc13.2 的
  `.hdf.text` 达 170.8K，超旧 152K 预算（链接期 SRAM_CODE overflow 15KB）；
  SRAM_DATA 实测仅用 7.3K，挪界零风险。**board.ld 是 link.h 经 link.mk 生成的，别手改**

### 构建环境重建（全部在 WSL 宿主，入口 `bash /root/build_rk.sh`，增量 6-8 秒含 mkimage）
- `ln -s /root/txsmart /home/openharmony`——gn args 里的绝对路径依赖这个符号链接
- `/bin/sh`→bash——`mkimage.sh`/`copy.sh` 用 bash 语法，Ubuntu24 默认 dash 直接炸
- `/usr/local/bin/ccache` 透传垫片、`python`→python3 软链、
  `/usr/local/bin/hb` 包装器（`PYTHONPATH=/root/txsmart/build/lite` + `cd /root/txsmart`，
  mkimage.sh 里的 `hb env` 靠它）
- prompt_toolkit 桩包（dist-packages）：hb 的 cts 模块 import 用，构建链不真执行；
  pip 装 3.x 缺 `style_from_dict`/`Token` 等一串符号，装 2.x 也失败，桩最稳
- arm-none-eabi-gcc：ARM 官方 13.2.Rel1 解压在
  `/opt/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin`（build_rk.sh 已带 PATH）。
  **别走 apt 装 gcc-arm-none-eabi**——TUN 代理把 archive.ubuntu.com 弄成 502/fake-ip 死循环
- 踩坑：wsl.exe 单引号命令里的 `$VAR` 会被外层 Git-Bash 提前展开；Windows PATH 里的
  `(x86)` 会炸内层 bash 分词——复杂命令一律写 /root/*.sh 或 python heredoc 执行

### 已验证 / 遗留
- ✅ 433→SOS 全链路（用户实测两轮）。心跳判别：**新固件未接门磁时 door=1**
  （上拉生效），door=0 是上拉被冲掉的旧固件特征，可用来确认烧没烧对版本
- ⚠️ 门磁接线 11-06：网线芯绕引脚 8 圈（**钳子夹住引脚根部再绕，防裂管**），
  另一头绕排针 GND/B7；绕完桌面彩排看 door 翻转，再装盒贴门框
- 演示相关：遥控为点动行为 ✅；「模拟告警」按钮与下拉注入演示告警在真云模式
  下没隔离（下拉一次会凭空加 2 条假告警）——真云演示期间别碰，App 侧待修
- App 侧遗留（前会话已列）：设备列表钉死 sy-rk2206-001（fetchDeviceList 会把
  sy-nearlink-001 一并拉回，HomePage 取 list[0] 有穿帮风险）、alarmActive 现场
  状态显示、星闪设备卡片、死代码清理（DeviceOverviewPage/SensorTile/SensorDetail）
- 路演升级项：星闪门磁（reed#2 上 T + C 透传 door + App 卡片）、
  LD2410D OUT 接 RK2206、C 网关透传 pir（§11 遗留）

## 13. 星闪本地接入主控的实施记录（历史）

本次按用户确认的“人体活动更新状态，异常沿用现有规则”实现本地接收。
完整说明、源码补丁、固件位置、接线约束与验收步骤见
[本地桥接记录](LOCAL_BRIDGE.md)。

- H3863 新版本不启动应用 Wi-Fi/MQTT 任务，不再等待 Wi-Fi 才启星闪。
- RK2206 新增 UART0 接收任务：PB6 接收，PB7 恢复门磁输入，433 D0 迁到 PB0。
- 主控 `pir` 合并板载与有效星闪活动；预热与超过 10 秒的旧报文不计为星闪活动。
- 正常活动不直接报警；没有新增无活动超时规则。现有燃气/SOS 仍在本地处理。
- 两端编译通过，解析测试通过；固件尚未烧录，不能宣称三板本地链路已跑通。
- 实物识别以本次用户纠正为准：H3863 带排针，H2821 有带排针和不带排针的板子。
  历史 §8 对板型/排针的描述不能直接拿来指导接线。
- 三板均已识别：COM11=终端 PIR，COM4=RK2206（433 心跳日志），
  COM16=H3863 网关（热点扫描日志，经拓展坞接入）。
  用户随后确认实际连接四块板，而系统当前仅枚举上述三个串口。
  烧录暂缓，先识别第四块实物与 USB 连接；不要直接根据旧板型表烧录。
  后续用户改接三块，COM16 复读是中继日志，拟改为本地网关。
  首次烧录第一段成功后 Ymodem 握手失败，未完成；
  正等待只保留 H3863 后低速完整重烧，见 `LOCAL_BRIDGE.md`。
  **后续低速重烧成功**：只留 COM16，115200，日志明确 `Burned successfully.`。
  正采集启动日志并等待用户重接终端、复位；主控尚未烧录，板间尚未接线。
  **启动与星闪验证已完成**：本地网关 UART1 初始化、建链和服务发现成功，
  接收终端 seq=1..81，连续 81 条，其中 3 条是预热完成后的 `pir=true`。
  日志 `logs/ws63_local_bridge_startup.log`；没有应用 Wi-Fi 扫描、panic/栈溢出。
  启动前段有 `Flash Init Fail! ret = 0x80001341`，应用随后正常运行，未定位该提示。
  下一步对照 RK2206/H3863 排针照片确认物理位置、迁 433 D0、接 TX+GND，
  再烧主控并验证本地接收、断网 SOS。不要将当前结果说成已接入主控。
  **后续主控进度**：用户确认三项接线完成并自行烧录，正常显示温湿度。
  COM4 多次复位、K8 切主控后仍 0 字节；已添加屏幕 SLE 状态与 RX/OK 计数，
  构建与解析测试通过，sha256=`876fcead07bb592432ff59529ebca941bcae3143b0291ed4a0a79663b8a0209b`。
  当前等待用户重烧并反馈屏幕 SLE 行。不再依赖桌面操作；用户两次按 Esc 中止过桌面控制。
  现 COM3 已确认本地网关、COM4 主控、COM17 终端候选，勿沿用旧 COM16/COM11。
  **上述主控打包判断已更正**：Makefile ELF 目标缺少库依赖，静态库更新但
  ELF/BIN 保留 07:54 旧程序；包的时间和 hash 更新不代表应用更新。
  已补依赖并增加 ELF/BIN/镜像三层内容与逐字节包含校验，正确新包
  `e64a74c5991b06ed559e360bda0263ed4ee989b9824fe08b263c5d9fde9f24c4`。
  该正确包尚未放到 RKDevTool 路径，也未烧录。用户现正被要求先恢复 433→PB6，
  断开 H3863 数据线测试按钮。烧新包并确认 SLE 行后，才再次迁 433→PB0。
  **最新**：433 恢复 PB6 后用户确认按钮能报警。正确 e64a 包已放到 RKDevTool 原路径，
  已请求用户关重开工具后烧录，暂保持数据线断开/433 PB6；待确认 SLE 行后再断电迁线。
- SDK 原理图与 §12 的排针编号有差异。迁线前需用实物标识核对，
  不要根据旧编号把两个信号输出接在一起。
