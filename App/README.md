# 守颐 —— 独居老人居家安全监测与应急辅助系统

> 第三届河南省高等学校信息技术应用创新大赛（开源鸿蒙）赛题四 参赛作品
>
> **北向控制端**：基于 OpenHarmony / ArkTS 的鸿蒙 App
>
> 与设备端（开发板 + 传感器）和云端配合，构成"感知 → 判定 → 告警 → 处置 → 留痕"的完整守护链路。

---

## 一、这个工程是什么

本工程是赛题四的**北向控制端**（子女 / 监护人使用的鸿蒙 App），对应赛题要求中的：

| 赛题要求 | 本工程对应 |
|---|---|
| 北向数据展示：手机端查看传感器状态、设备在线与电量、活动规律报告、历史预警记录 | 首页 · 设备总览、状态 · 实时状态、报告 · 活动规律 |
| 事件闭环管理：确认预警 → 填写处置结果 → 形成居家安全日志 | 预警中心 + 预警详情（含处置时间线） |
| 数据统计分析：活动时段分布、每日活动频次趋势、周/月报告 | 活动报告页（热力图 + 趋势折线 + 智能研判） |
| `[创新]` 多终端协同：推送至子女、社区网格员、物业值班 | 角色权限体系 + 分级推送 |

**南向（开发板与传感器）与云端不在本工程内**，分别由设备端工程与云端服务承载。

---

## 二、当前状态：可直接运行（Mock 数据）

**重要**：云端接口文档尚未到位，本工程已内置 `MockCloudAdapter`，
**现在就能在 DevEco Studio 里跑起来**，全部页面与交互均可完整体验。

```
当前数据来源：Mock（本地模拟数据）
```

Mock 数据是**确定性生成**的（固定种子），并刻意贴合真实老人的作息规律：
6:30 起床、午休 12:00–13:30、晚间 19:00–21:30 活跃、22:00 后入睡。
最近 3 天活动量刻意降低 22%，因此"规律变化提示"能被触发，演示时效果完整。

### 如何跑起来

1. 用 DevEco Studio 5.0 打开本目录（`ShouYi` 为工程根目录）
2. 等待 hvigor 同步完成
3. `File → Project Structure → Signing Configs` 配置自动签名
4. 选手机或平板模拟器，运行

---

## 三、架构

### 3.1 四层分层

```
表现层 Presentation
  DeviceOverviewPage · RealtimeStatusPage · ActivityReportPage
  AlertCenterPage · AlertDetail · MinePage
  components: SensorTile / AlertCard / ActivityHeatmap / TrendChart
        ↓ 只向下调用，不跨层
业务层 Business
  CareService（业务门面）· ActivityAnalysisService（活动分析引擎）
  NetworkMonitor（网络状态）
        ↓
数据访问层 Data Access
  CloudApi（云端抽象接口）→ MockCloudAdapter / SeniorCloudAdapter
  CloudTypes（请求响应类型）
        ↓
存储与网络层
  HttpClient（统一 HTTP 封装）· Preferences · 内存缓存
```

### 3.2 核心设计：适配器模式隔离云端变化

**这是本工程最重要的架构决策。**

```
业务层与 UI
    ↓ 只依赖这一个接口
CloudApi（抽象接口，18 个方法）
    ├── MockCloudAdapter      ← 已实现，当前使用
    ├── SeniorCloudAdapter    ← 骨架已就位，接口文档到位后填空
    └── SelfHostedAdapter     ← 备选（若自建后端）
```

好处：
- 接口文档未到时，App 可用 Mock 完整跑通，**不阻塞开发进度**
- 接口文档到位后，**只改 `SeniorCloudAdapter` 一个文件**，业务层与 UI 一行不动
- 若最终改用自建后端，也只是换一个 adapter

切换方式（一处配置）：

```typescript
AppConfig.useMock = false;
AppConfig.baseUrl = 'https://实际地址/api/v1';
```

---

## 四、目录结构

```
ShouYi/
├── AppScope/
│   ├── app.json5                              # bundleName: com.shouyi.care
│   └── resources/base/element/string.json
├── entry/src/main/
│   ├── module.json5                           # 权限：INTERNET / GET_NETWORK_INFO / VIBRATE
│   ├── ets/
│   │   ├── entryability/EntryAbility.ets       # 入口，启动网络监听
│   │   ├── common/
│   │   │   ├── constants/AppConstants.ets      # 表名 / 枚举 / 阈值常量 ★
│   │   │   ├── constants/ThemeColors.ets       # 配色（深蓝主色，与同类作品区分）
│   │   │   └── utils/Logger.ets, DateUtil.ets
│   │   ├── model/                              # 数据模型
│   │   │   ├── Device.ets                      # 设备 / 传感器 / 读数 / 设备配置
│   │   │   ├── Alert.ets                       # 告警 / 处置 / 时间线 / 阈值建议 ★
│   │   │   ├── ActivityRecord.ets              # 活动聚合 / 报告 / 基线 ★
│   │   │   └── FamilyMember.ets                # 家庭成员与角色
│   │   ├── cloud/                              # ★ 云端抽象层
│   │   │   ├── CloudApi.ets                    # 抽象接口（18 个方法）
│   │   │   ├── CloudTypes.ets                  # 请求 / 响应类型
│   │   │   ├── HttpClient.ets                  # HTTP 封装（鉴权 / 幂等 / 错误码）
│   │   │   ├── MockCloudAdapter.ets            # Mock 实现（含确定性数据生成）
│   │   │   ├── SeniorCloudAdapter.ets          # 学长服务器对接（待接口文档）
│   │   │   └── CloudApiFactory.ets             # AppConfig：切换云端实现
│   │   ├── service/
│   │   │   ├── CareService.ets                 # 业务门面（离线缓存 + 组合 + 角色过滤）
│   │   │   ├── ActivityAnalysisService.ets     # ★ 活动规律分析引擎（纯函数）
│   │   │   └── NetworkMonitor.ets              # 网络状态监听
│   │   ├── view/
│   │   │   ├── components/
│   │   │   │   ├── SensorTile.ets              # 传感器状态卡片
│   │   │   │   ├── AlertCard.ets               # 告警卡片（等级视觉分级）
│   │   │   │   ├── ActivityHeatmap.ets         # ★ Canvas 活动热力图
│   │   │   │   └── TrendChart.ets              # ★ Canvas 趋势折线图
│   │   │   ├── DeviceOverviewPage.ets          # 首页 · 设备总览
│   │   │   ├── RealtimeStatusPage.ets          # 状态 · 实时状态
│   │   │   ├── ActivityReportPage.ets          # 报告 · 活动规律
│   │   │   ├── AlertCenterPage.ets             # 预警 · 告警中心
│   │   │   └── MinePage.ets                    # 我的 · 家庭成员与安全日志
│   │   └── pages/
│   │       ├── Index.ets                       # 五 Tab 主框架
│   │       └── AlertDetail.ets                 # 预警详情 + 事件闭环
│   └── resources/base/...                      # 字符串 / 颜色 / 页面路由
└── build-profile.json5 / oh-package.json5 / hvigorfile.ts
```

---

## 五、三个技术亮点（答辩重点）

### 5.1 活动规律分析：个人基线，而不是固定阈值

代码位置：`service/ActivityAnalysisService.ets`

**问题**：如果所有老人都用同一个"日均活动少于 X 次就告警"的阈值，
那么作息本来就安静的老人会被持续误报，子女很快就会关掉通知。

**做法**：以最近 14 天建立**这位老人自己**的活动基线（均值 + 标准差），
当前活动量偏离基线超过 2 个标准差才提示。

```typescript
deviation = (当前日均活动 - 个人基线均值) / 基线标准差
if (|deviation| >= 2) → 提示异常
```

同时计算趋势（本期 vs 上期）并**定位下降集中的时段**——
不只说"下降了 23%"，而说"下降主要集中在上午时段，建议关注老人日间状态"。

### 5.2 事件闭环：从触发到留痕的完整链路

代码位置：`pages/AlertDetail.ets`、`model/Alert.ets`

```
触发 → 上报 → 分级推送 → 确认 → 填写处置结果 → 写入安全日志
                                    ↓
                          若标记误报 → 生成阈值调整建议
```

**处置时间线**把全过程可视化，答辩时直观展示。

**误报反馈闭环**是加分点：用户标记误报后，系统统计近期同类误报次数，
达到 2 次以上才建议放宽阈值（避免单次偶然误报就调阈值），
让系统随使用逐步适配这位老人的习惯。

### 5.3 告警视觉分级：不能让"设备离线"和"燃气泄漏"长得一样

代码位置：`view/components/AlertCard.ets`、`common/constants/ThemeColors.ets`

| 等级 | 含义 | 视觉处理 |
|---|---|---|
| P0 | 紧急（求助按钮 / 燃气 / 烟雾） | 满底红 + 左侧 6px 粗条 + 顶部横幅 + 震动 |
| P1 | 高风险（长时间无活动） | 琥珀色卡片 + 左侧粗条 |
| P2 | 需关注（温湿度 / 门窗） | 普通卡片 + 彩色等级标签 |
| P3 | 提示（离线 / 低电量） | 普通卡片，弱化处理 |

---

## 六、对接学长云端服务器（待接口文档）

### 6.1 需要做什么

`cloud/SeniorCloudAdapter.ets` 已写好完整骨架，含 18 个方法的请求构造。
拿到接口文档后按以下步骤填空：

1. 对照 `02_云端接口/云端接口设计草案.md` 最后一节的**对接字段映射表**，逐条填写实际路径
2. 若字段名不一致，在 adapter 内做转换（**不要改动 CloudTypes 与业务层**）
3. 若鉴权方式不同，改 `buildOptions()` 方法
4. 若推送不是 WebSocket，改 `subscribeAlerts()` 实现
5. 把 `AppConfig.useMock` 置为 `false`

### 6.2 推送通道的三种方案

| 方案 | 实时性 | 说明 |
|---|---|---|
| WebSocket 长连接 | 高（秒级） | App 在前台时首选 |
| 厂商推送（Push Kit） | 高 | App 在后台 / 被杀时使用 |
| 定时轮询 | 低（分钟级） | **保底方案**，前两者不可用时降级 |

`SeniorCloudAdapter.subscribeAlerts()` 中已预留轮询降级逻辑。

### 6.3 需要向学长确认的接口问题

1. 鉴权方式：设备端和 App 端分别怎么鉴权？令牌有效期？
2. 上报频率限制：有没有 QPS 或每日配额？
3. 推送通道：支持哪些方式？有没有现成 SDK？
4. **配置下发**：阈值能不能存云端下发？（决定改阈值要不要重新烧录固件）
5. **服务端聚合**：查询接口支不支持按小时 / 按天聚合？（决定报告查询拉多少数据）
6. 角色与权限：支不支持多角色（子女 / 网格员 / 物业）？

> 第 4、5 条最关键，答案不同工程量和体验差距很大。

---

## 七、自测清单

在 Mock 模式下可验证：

- [ ] 首页展示设备在线状态、电量、信号、最后心跳
- [ ] 六个传感器卡片全部正常渲染（人体活动 / 门窗 / 温湿度 / 烟雾 / 燃气 / 求助按钮）
- [ ] 首页展示最近 3 条预警
- [ ] 状态页展示每个传感器的当前值与最后触发时间
- [ ] 状态页可切换传感器类型，历史曲线随之刷新
- [ ] 报告页切换日报 / 周报 / 月报，数据正确刷新
- [ ] 报告页"智能研判"给出自然语言结论（应提示"下降 22%"之类）
- [ ] 报告页热力图渲染出 24 小时 × N 天的网格
- [ ] 报告页趋势折线含均值虚线
- [ ] 报告页个人基线显示偏离 σ 值
- [ ] 预警中心可按状态 / 等级筛选
- [ ] P0 告警与 P3 告警的卡片视觉明显不同
- [ ] 点进预警详情，看到完整处置时间线
- [ ] 选择"误报"时出现阈值调整建议勾选框
- [ ] 提交处置结果后，状态变为"已处置"
- [ ] 我的页展示三类角色及其权限差异
- [ ] 我的页展示居家安全日志时间线
- [ ] 我的页切换角色为"网格员"后，报告页显示隐私边界提示

---

## 八、与设备端、云端的接口约定

| 方向 | 内容 |
|---|---|
| 设备端 → 云端 | 心跳、传感器读数批量上报、告警上报、配置拉取 |
| 云端 → App | 设备列表与状态、历史读数、告警列表与详情、活动报告、安全日志、家庭成员 |
| App → 云端 | 确认告警、提交处置结果（含阈值调整） |

完整接口定义见 `02_云端接口/云端接口设计草案.md`，
代码侧对应 `cloud/CloudApi.ets` 与 `cloud/CloudTypes.ets`。

---

## 九、后续待办

| 优先级 | 事项 | 依赖 |
|---|---|---|
| 高 | 对接学长云端接口 | 接口文档 |
| 高 | 设备端工程（开发板 + 传感器采集 + 阈值判定 + 声光报警） | 硬件到货 |
| 高 | 轻量后端（若学长接口不可用） | 按接口草案自建 |
| 中 | Push Kit 接入（后台告警推送） | 华为开发者账号 |
| 中 | 本地缓存持久化（当前为内存缓存） | — |
| 低 | 平板分栏适配（List-Detail） | — |
| 低 | 深色模式适配 | — |
