# 星闪接入主控：本地通信版本

这份记录描述 H2821 → H3863 → RK2206 的本地数据通路。
2026-11-05 实测中，用户确认主控显示 `SLE:ON` 且 `OK` 持续增加。
433 D0 已迁至 PB0，按按钮可触发本地报警，用户反馈响应更快。
H3863 的 UART1 TX 接主控 PB6，两板共地。

烧录工具现在通过桌面「守颐主控烧录」启动，使用固定工作目录与
`D:\RKDevTool\images` 下的镜像绝对路径。用户确认重开后 LoaderToDDR
和 firmware 两行均在，烧入已校验的 e64a74c 版本后出现 SLE 状态行。

待验收项为明确关闭热点后的感应、报警与消音，以及终端掉线和恢复。
联网后的实体报警同步、App 处置回传也待复验。下文实测记录保留历史排障过程。

## 目标与规则

H2821 采集 HC-SR501，H3863 通过星闪接收后从串口输出，
RK2206 接收并更新人体活动状态。H3863 本地版本不启动 Wi-Fi 或 MQTT，
上电即可寻找星闪终端，RK2206 负责联网与上云。

按本次用户选择，正常人体活动不触发蜂鸣。
主控继续采用现有燃气连续超阈值与 SOS 报警规则；这两个规则在本地执行。
本次没有新增长时间无活动报警，也没有将人体活动冒充 SOS。

## 已实现的软件行为

接收端采用终端现有的逐行 JSON，字段为 `seq`、`dev`、`pir`、`pirReady`。

- 仅接收 `dev="sy-t-001"` 的完整、有效报文。
- 支持跨多次串口读取的报文，以及一次读取多条报文。
- 预热期间的 `pirReady=false` 不计入有效人体活动。
- 超过 10 秒没有新有效报文时，星闪链路标记离线，清除星闪活动状态。
- 离线不代表无人；本版本不依据离线状态执行无活动报警。
- 重复序号不延长在线时间；终端重启后的序号重置可以恢复接收。
- 格式错误、超长、缺字段、错误类型、嵌套数据或夹带 NUL 的报文被丢弃。
- 主控 `pir` 上报采用板载 PIR 与有效星闪 PIR 的逻辑或。
- 链路诊断见串口 `[sy nearlink]`；App 尚没有独立的星闪在线状态字段。
- 新增 LCD 状态版本：标题下显示 `SLE:ON P:0 RX:1234 OK:20`。
  `INIT` 表示接收任务尚未初始化，`ERR` 表示任务或 UART 初始化失败，
  `OFF` 表示当前没有新鲜有效报文，`WARM` 表示终端预热，`ON` 表示报文就绪。
  `P` 是星闪活动状态，`RX` 是串口接收字节数，`OK` 是有效终端报文数。
  正常活动仍不直接触发报警。

## 接线设计与实物核对

当前软件使用下列 GPIO。实际排针位置必须结合实物标识确认后再接线。
交接文档的旧排针编号与 SDK 原理图存在差异，不能混用。

| 信号 | 连接设计 | 注意事项 |
| --- | --- | --- |
| H3863 UART1 TX | GPIO15 → RK2206 GPIO0_PB6 / UART0 RX | 115200、8N1，3.3V 逻辑 |
| 地线 | H3863 GND → RK2206 GND | 两块板分别供电时仍要共地 |
| 433 接收器 D0 | 从 RK2206 GPIO0_PB6 迁到 GPIO0_PB0 | 必须与新固件同步迁线 |
| 门磁 | GPIO0_PB7，保持原功能 | UART 初始化后恢复为带上拉的 GPIO 输入 |
| UART0 TX | 不连接 | 本版本只接收，不发送 |

不能将 H3863 TX 和 433 D0 同时接到 PB6。
不要把两块板的 5V/3.3V 供电输出直接相连；本地通信仅需信号线与共地线。
GPIO0_PB0 在 SDK 原理图上标为扩展 SPI1 CS，本应用没有启用该 SPI1。
接线前确认没有额外扩展模块占用 PB0。

SU-03T 属于原理图中的板载电路，连接 UART2，并非没有调用语音功能就能
直接在同一根 RX 线上增加另一个输出。本方案保留 UART2。

## 文件与构建

代码与可重复执行的补丁保存在当前目录，应用前自动备份已有源码。

- `fw/local_bridge/nearlink_protocol.*`：平台无关的报文解析与有效期处理。
- `fw/local_bridge/nearlink_bridge.*`：RK2206 UART0 接收任务。
- `tools/patch_rk_local_bridge.py`：在 WSL 中更新 RK2206 应用。
- `tools/patch_c_local_bridge.py`：在 Windows SDK 中移除网关联网前置条件。
- `tools/build_local_gateway.py`：构建直接连接终端的本地网关版本。
- `tools/verify_local_bridge.sh`：验证报文解析、构建并归档 RK2206 固件。

已有云端网关固件文件保持原样。本次新产物使用独立名称：
`fw/bins/ws63_local_bridge_all.fwpkg` 和
`fw/bins/rk2206_local_bridge/Firmware.img`。
SDK 当前源码已经改为本地版本，之后重新构建时必须注意版本选择。
回退源码使用各修改文件旁的 `.bak_pre_local_bridge`，不能直接恢复到 Git HEAD，
因为本次开始前已有尚未提交的 433 修改。

## 验收步骤

先核对三块板的型号、串口和实际排针，再按下列顺序验收。

1. 保存旧固件与接线照片，断电后迁移 433 D0 并连接 H3863 TX 与共地。
2. 烧入对应两份新固件，确认没有传输进度后再按需要复位。
3. 保持路由器/热点关闭，从断网上电开始检查星闪是否能够建链。
4. 等 HC-SR501 完成预热，走动与静止，观察终端 `pir` 与主控
   `[sy nearlink]` 是否对应变化。
5. 关闭 H2821 供电，确认主控 10 秒后报告 `online=0`，重新供电后恢复。
6. 断网按 433 遥控与板载 SOS，确认蜂鸣、报警灯、屏幕和本地消音仍有效。
7. 恢复联网，确认 RK2206 上报的 `pir` 能随星闪传感器更新。

本次不通过人为放气验证燃气报警；需要测试该规则时使用受控测试输入。
不得将正常走动不触发报警解释为链路故障。

## 实测记录

本节只记录已观察到的结果。

- COM11 已读取到 H2821 的 GPIO21 PIR 报文，`pirReady=true`。
- COM4 已通过 `[sy 433] B6=0 door=0` 日志确认为 RK2206。
- COM16 已通过 `[sle gw]` 与热点重扫日志确认为 H3863 网关。
- 用户确认 H3863 带排针；H2821 有带排针和不带排针的板子。
- 两份固件均已编译、打包并归档；RK2206 最终解析测试通过，
  测试启用内存和未定义行为检查，日志见 `logs/rk_local_bridge_verify.log`。
- H3863 构建日志见 `logs/ws63_local_bridge_build.log`。
- RK2206 首版固件 SHA256（保留为 `Firmware_before_lcd_status.img`）：
  `7b553ccc741af70fd61faa526adc7a5bcd7d45ec22f3c1b1c6a4a16b57ca3743`。
- H3863 固件 SHA256：
  `8118b4b24b26288127b75ed7eb521d83eca40d2ee4ee0cddf3a80a03766c8e1d`。
- 网关经拓展坞接入后新增 COM16，USB 与串口均已枚举正常。
- 下一步先烧 H3863 本地固件，需要用户配合短按 RST；
  RK2206 在迁移 433 接线并核对排针前不能烧入新版本。
- 尚未烧录本次固件，尚未验证板间串口和断网三板联动。
- 用户进一步确认实际连接四块板；Windows 设备列表、串口 API 与注册表
  当前均仅列出 COM4、COM11、COM16，未出现异常 USB 设备。
  烧录暂缓，先通过实物照片或逐块拔插确定第四块及实际板型。
- 用户随后改为只接三块板，复读确认 COM4=RK2206、COM11=PIR 终端，
  COM16 当前输出 `[sy relay] queue drop`，是运行中继版本的 WS63 板。
  COM 号与 USB 口关联，换板后不能沿用旧固件身份。
- BurnTool GUI 的下拉列表也确认只有 COM4、COM11、COM16。
- 对 COM16 尝试烧本地网关固件，用户按 RST 后第一段 loader 下载成功，
  后续 `Ymodem handshake failed`，整体 `Burned failed`。
  失败日志为 `logs/ws63_local_bridge_flash.log`。
  尚不能视为烧录成功；等待用户只保留 H3863，改用低速完整重烧。
- 只保留 COM16 后，使用 115200 完整重烧成功，工具明确返回
  `Burned successfully.`，日志见 `logs/ws63_local_bridge_flash_115200.log`。
  已进入网关启动日志采集，等待重新接终端并复位验证离线星闪链路。
  RK2206 本次固件仍未烧录，板间串口仍未接线。
- 用户重接 RK2206 与 H2821 并复位后，启动日志验证本地网关标记、
  UART1 TX=15 / RX=16 / 115200 初始化成功、星闪建链和服务发现成功。
- `logs/ws63_local_bridge_startup.log` 共记录终端序号 1 至 81，81 条连续无缺号。
  其中 63 条 `pirReady=true`，3 条同时 `pir=true`，验证真实活动字段传到网关。
  未出现应用 Wi-Fi 扫描日志、panic 或栈溢出。
- 启动早期有一条 `Flash Init Fail! ret = 0x80001341`，随后应用正常启动并持续接收；
  此提示未在本次定位，不能宣称启动日志完全无异常或长期稳定性已通过。
- 终端预热后的独立日志：`logs/terminal_local_gateway_ready.log`。
  下一步需要用户提供 RK2206 和 H3863 排针实物照片，确认物理位置后迁线、
  烧主控、验证板间接收和断网 SOS；正常活动按用户选择不直接触发报警。
- 用户已明确确认三项接线全部完成：H3863 UART1_TX→RK PB6、GND 共地，
  433 D0 从 PB6 迁到 PB0；尚未通过日志验证接线是否正确。
- RK2206 旧固件备份为 `fw/bins/rk2206_before_local_bridge/Firmware.img`，
  SHA256 `3e6c6816b399d37ecb222edff5b2fd95256f0323f7cf0b9a77d542e63a15b126`。
  已把新固件复制到 RKDevTool 原来使用的 `D:\out\rk2206\TB-RK2206H0-A\images`
  junction 目标位置，校验与已归档新固件一致。主控还没开始烧录。
- RKDevTool 必须以 `D:\RKDevTool` 为工作目录启动，否则相对配置找不到、
  窗口仅出现空白 Loader 行。已用正确工作目录重开并验证两行配置恢复。
  原始配置备份为 `fw/configs/rkdevtool_before_local_bridge.cfg`。
  当前等待用户将 RK2206 接烧录 USB 并按 BOOT+RST，窗口显示没有发现设备。
- 用户随后报告已自行完成首版主控烧录；RKDevTool 日志在 09:49:10 开始
  下载 Firmware、09:49:20 结束。用户确认主控屏幕正常显示温湿度/智慧家居。
- `logs/rk_local_bridge_first_run.log`、`logs/rk_local_bridge_boot.log`、
  `logs/rk_local_bridge_console_check.log` 均采集到 0 字节；
  用户已将 K8 拨到主控侧并复位，仍无串口数据。原因未定位。
  不能据此宣称板间 UART 已通或接线错误。
- 重新接回三板后的串口：COM4=RK2206，COM3=本地网关，COM17=终端候选。
  COM3 已实读 `bridge ready` 与终端 PIR 报文，见
  `logs/reconnected_COM3_identify.log`。端口会变化，继续以日志认板。
- 已新增 LCD 状态行，解析测试与 RK2206 重新构建均通过，日志为
  `logs/rk_local_bridge_lcd_verify.log`；新固件 SHA256：
  `876fcead07bb592432ff59529ebca941bcae3143b0291ed4a0a79663b8a0209b`。
  新文件已复制到烧录工具原路径，原 433 固件备份保持不变。
  当前等待用户按上次方法重烧并回报屏幕 SLE 状态；不需要改接线。

### 打包缺陷与修复：此前主控固件无效

用户报告没有新增 SLE 行，随后报告迁走 433 后按钮不响、H3863 上电反而报警。
检查发现静态库已更新到 09:57，但 `liteos.elf` 仍停留在 07:54。
SDK `Makefile` 的 ELF 目标没有任何依赖，增量构建只重新打包旧 BIN。
此前 `7b553...`、`876fce...` 两份主控包均未包含新主程序；
旧主程序仍将 PB6 当作 433 输入。`e64a...` 是修复后首次通过内容校验的包。

已采取下列修复与保护：

- `tools/fix_rk_link_dependencies.py` 为 ELF 目标补齐全部静态库、链接脚本、
  Makefile 依赖，保留 SDK 原 Makefile 备份。
- `tools/verify_rk_image.py` 在归档之前检查 ELF、BIN、Firmware.img 三者
  均含新接收程序、PB0 遥控日志和 SLE 屏幕标记，时间不早于应用静态库。
- 再确认新 BIN 在打包镜像偏移 131072 处逐字节完整匹配。
- `tools/verify_local_bridge.sh` 已调用上述修复与验证；任一检查失败就停止归档。
- 已确认旧主控镜像缺少全部新标记，见 `logs/rk_packaging_regression.json`。

正确重链接固件 SHA256：
`e64a74c5991b06ed559e360bda0263ed4ee989b9824fe08b263c5d9fde9f24c4`。
完整日志为 `logs/rk_local_bridge_relink_verify.log`，归档文件仍为
`fw/bins/rk2206_local_bridge/Firmware.img`。**尚未将这份正确镜像复制到
RKDevTool 原路径，也尚未烧录。**

安全恢复顺序为：先断电，断开 H3863 数据线，将 433 D0 恢复原 PB6 并确认
按钮可报警；之后在星闪数据线保持断开的情况下烧正确版本，确认 SLE 屏幕行
出现，再断电迁 433 到 PB0、接回 H3863 TX→PB6、重新验证。
在上述步骤完成前，不能说主控已接入星闪。

### 恢复 433 后的最新操作

用户已回复“已恢复接线，按钮能报警”，证实旧 PB6 遥控通路恢复。
已将经内容校验的 `e64a74c...` 镜像复制到
`D:\jishe\sssss\.iot_design\firmware\Firmware.img`，并核对 SHA256 一致。
用户被要求关闭重开 RKDevTool（正确工作目录 `D:\RKDevTool`），确认 LoaderToDDR
与 firmware 两行，再烧新版本。此时保持 H3863 数据线断开、433 暂留 PB6，
先确认 SLE 屏幕行；新程序的遥控输入已改 PB0，因此确认并迁线前不测试 433。
之后断电迁 433→PB0、H3863 TX→PB6，再测试按钮与终端数据。
