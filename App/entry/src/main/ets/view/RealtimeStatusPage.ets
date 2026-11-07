import { Device, Sensor } from '../model/Device';
import { DeviceStatusResp, ReadingsResp, ReadingsPoint } from '../cloud/CloudTypes';
import { Alert, AlertHandle } from '../model/Alert';
import { CareService } from '../service/CareService';
import { TrendChart } from './components/TrendChart';
import { WatchVitalsCard } from './components/WatchVitalsCard';
import { ActivityReport, TrendPoint } from '../model/ActivityRecord';
import { AppColor, AppSize } from '../common/constants/ThemeColors';
import {
  SensorType, SensorStatus, AlertType, AlertLevel, AlertStatus
} from '../common/constants/AppConstants';
import { DateUtil } from '../common/utils/DateUtil';
import { Logger } from '../common/utils/Logger';

/** 时间范围下拉项。Select 需要显式类型，ArkTS 不接受无类型对象字面量 */
class SelectOption {
  value: string = '';
  label: string = '';
}

/**
 * 传感器行的展示模型。
 *
 * 之所以单独建一层 VM：ArkTS 的 @Builder 函数体内只允许写 UI 组件语法，
 * 不能声明局部变量。把颜色、文案这类派生值在 load() 时算好放进来，
 * 渲染时只做取值，@Builder 保持纯净。
 */
/**
 * 生命体征四连格里的单个指标格。
 * 三层结构：标签 / 数值 / 状态词，与「心率 72bpm 稳定」同构。
 */
class MetricCell {
  label: string = '';
  value: string = '';
  status: string = '';
  /** 数值与状态词共用的强调色 */
  color: string = '';
}

class SensorRowVM {
  sensor: Sensor = new Sensor();
  /** 状态色：绿 / 黄 / 红 / 灰 */
  color: string = '';
  border: string = '';
  bg: string = '';
  abnormal: boolean = false;
  /** 传感器类型图标：SymbolGlyph 系统符号 */
  icon: Resource = $r('sys.symbol.thermometer');
  data: string = '';
  insight: string = '';
}

/** 置顶求助按钮卡的展示模型。理由同 SensorRowVM */
class SosVM {
  sensor: Sensor = new Sensor();
  danger: boolean = false;
  offline: boolean = false;
  dot: string = '';
  accent: string = '';
  border: string = '';
  bg: string = '';
  statusLabel: string = '';
  footer: string = '';
  footerColor: string = '';
}

/** 跳转告警详情的传参。ArkTS 不接受无类型对象字面量，必须显式声明 */
class AlertDetailParams {
  alertId: string = '';

  constructor(alertId: string) {
    this.alertId = alertId;
  }
}

/**
 * 实时状态页。
 *
 * 比首页更细：逐个传感器给当前值、关键时间点，以及一句文字解读。
 * 赛题要求"帮助子女发现老人生活规律变化"，只给数字达不到这个要求 ——
 * 所以每张卡片第三行固定是判断而不是数据。
 *
 * 排列顺序（风险优先级 × 信息价值）：
 *   1. 紧急求助按钮  唯一响应级别最高的动作，固定置顶并用暖橙背景强调
 *   2. 人体活动      日常状态核心指标，额外给"与昨日对比"的变化解读
 *   3. 门窗状态
 *   4. 温湿度
 *   5. 烟雾          高危类，一旦异常直接转红
 *   6. 燃气          高危类，一旦异常直接转红
 *
 * 求助按钮只在置顶卡出现一次，不再在下方明细里重复占一行。
 */
@Component
export struct RealtimeStatusPage {
  private static readonly MODULE: string = 'RealtimeStatusPage';

  /**
   * 求助按钮除外的展示顺序。
   *
   * PIR（人体活动）已从明细列表移除：它的位置被「生命体征四连格」占用了，
   * 而活动数据并没有丢 —— 下方「历史监测数据」的「活动」标签仍可看曲线。
   * 保留 PIR 卡会造成"同一屏两个活动相关模块"，反而更乱。
   */
  private static readonly ORDER: string[] = [
    SensorType.DOOR, SensorType.TEMP_HUMIDITY,
    SensorType.SMOKE, SensorType.GAS
  ];

  @State rows: SensorRowVM[] = [];
  @State sosVm: SosVM | undefined = undefined;
  /** 监护主机。生命体征四连格的数据源 */
  @State device: Device | undefined = undefined;
  /** 生命体征四连格：心率 / 血氧 / 体温 / 步数 */
  @State vitalsCells: MetricCell[] = [];
  /** 四连格右上角的状态胶囊：正常 / 关注 / 无读数 */
  @State vitalsStatus: string = '';
  @State vitalsColor: string = '';
  /** 四连格下方的一句话解读 */
  @State vitalsInsight: string = '';
  /** 昨日活动次数，用于"与昨日对比"的解读 */
  @State yesterdayCount: number = 0;
  @State selectedType: string = SensorType.TEMP_HUMIDITY;
  @State trendPoints: TrendPoint[] = [];
  /** 统计条文案。@Builder 的值参数不具响应性，必须落成 @State 再经子组件 @Prop 传递 */
  @State statMax: string = '--';
  @State statMin: string = '--';
  @State statAvg: string = '--';
  @State statLast: string = '--';
  /** 短时原始采样与 24 小时汇总 */
  @State rangeKey: string = '5m';
  @State lastSampleText: string = '';
  private trendRequest: number = 0;
  /** 统计窗口内的告警。一物两用：图上红点 + 智能小结的安全信号 */
  @State alerts: Alert[] = [];
  @State alertPopup: Alert | undefined = undefined;
  @State summary: string = '';
  /** 小结用的辅助序列。与 trendPoints 分开存，避免切换标签时互相覆盖 */
  @State tempPoints: TrendPoint[] = [];
  @State activityPoints: TrendPoint[] = [];
  @State loading: boolean = true;
  @Prop @Watch('onActiveChanged') active: boolean = false;
  private liveTimer: number = -1;
  /** 下拉刷新指示。Refresh 组件用 $$ 双向绑定，load() 结束时置回 false 收起转圈 */
  @State refreshing: boolean = false;
  /** 演示场景切换通知：与首页一致，收到变化就重新拉取 */
  @StorageLink('demoScenarioTick') @Watch('onDemoScenarioTick') demoTick: number = 0;

  private service: CareService = new CareService();

  /**
   * 刷新重入保护。
   * 点右上「下拉刷新」会把 refreshing 置 true，从而再次触发 Refresh.onRefreshing，
   * 造成一次刷新执行两遍。用这个标志挡住第二次。
   */
  private refreshingGuard: boolean = false;

  /** 时间范围下拉的取值与文案，两处共用一套避免写岔 */
  private static readonly RANGES: string[][] = [
    ['5m', '近 5 分钟'],
    ['24h', '近 24 小时']
  ];

  onDemoScenarioTick(): void {
    this.load();
  }

  aboutToAppear(): void {
    this.onActiveChanged();
  }

  aboutToDisappear(): void {
    this.stopLiveTimer();
  }

  onActiveChanged(): void {
    this.stopLiveTimer();
    if (this.active) {
      this.refreshStatus();
      this.liveTimer = setInterval(() => {
        this.refreshStatus(false);
      }, 4000);
    }
  }

  private stopLiveTimer(): void {
    if (this.liveTimer >= 0) {
      clearInterval(this.liveTimer);
      this.liveTimer = -1;
    }
  }

  async load(): Promise<void> {
    this.loading = true;
    try {
      let all: Sensor[] = [];
      const resp: DeviceStatusResp | undefined = await this.service.loadDeviceStatus('');
      if (resp !== undefined) {
        all = resp.sensors;
        this.device = resp.device;
      }
      // 生命体征四连格来自 device，与传感器列表无关，单独算一次
      this.buildVitals();
      // 昨日活动要先拿到，活动卡的解读文案依赖它
      await this.loadYesterday();
      await this.loadTrendAndSummary();

      const sos: Sensor | undefined =
        all.find((s: Sensor) => s.sensorType === SensorType.SOS_BUTTON);
      this.sosVm = sos !== undefined ? RealtimeStatusPage.buildSos(sos) : undefined;

      // 求助按钮只以置顶卡形式出现一次，明细列表里剔掉，避免重复
      const rest: Sensor[] =
        all.filter((s: Sensor) => s.sensorType !== SensorType.SOS_BUTTON);
      this.rows = [];
      for (const s of this.sort(rest)) {
        this.rows.push(this.buildRow(s));
      }
    } catch (err) {
      Logger.error(RealtimeStatusPage.MODULE, `加载失败: ${(err as Error).message}`);
    } finally {
      this.loading = false;
      // 无论成功失败都要收起下拉刷新的转圈，否则它会一直转
      this.refreshing = false;
    }
  }

  /** 刷新实时状态。 */
  private async refreshStatus(showSpinner: boolean = true): Promise<void> {
    if (this.refreshingGuard) {
      return;
    }
    this.refreshingGuard = true;
    this.refreshing = showSpinner;
    try {
      await this.load();
    } finally {
      this.refreshing = false;
      this.refreshingGuard = false;
    }
  }

  /** 按固定顺序排。列表里没出现的类型追加在末尾，避免新增传感器被吞掉 */
  private sort(list: Sensor[]): Sensor[] {
    const sorted: Sensor[] = [];
    for (const type of RealtimeStatusPage.ORDER) {
      const hit: Sensor | undefined = list.find((s: Sensor) => s.sensorType === type);
      if (hit !== undefined) {
        sorted.push(hit);
      }
    }
    for (const s of list) {
      if (RealtimeStatusPage.ORDER.indexOf(s.sensorType) < 0) {
        sorted.push(s);
      }
    }
    return sorted;
  }

  /** 昨日总活动次数。取不到就给 0，解读自动降级为不带对比的表述 */
  private async loadYesterday(): Promise<void> {
    try {
      const report: ActivityReport | undefined = await this.service.loadActivityReport('week');
      const yesterday: string = DateUtil.formatDate(DateUtil.daysAgo(1));
      this.yesterdayCount = report?.daily.find((point: TrendPoint) => point.date === yesterday)?.count ?? 0;
    } catch (err) {
      Logger.warn(RealtimeStatusPage.MODULE, `读取昨日活动失败: ${(err as Error).message}`);
    }
  }

  /** 拉取所选传感器在时间范围内的读数，转成折线图数据 */
  private async fetchSeries(type: string, from: number, to: number, iv: string): Promise<TrendPoint[]> {
    const resp: ReadingsResp | undefined = await this.service.loadReadings(type, from, to, iv);
    if (resp === undefined) {
      return [];
    }
    const out: TrendPoint[] = [];
    for (const p of resp.points) {
      const date: string = iv === 'raw' ? DateUtil.formatSampleTime(p.timestamp) : DateUtil.formatTime(p.timestamp);
      out.push({ date: date, count: p.value, timestamp: p.timestamp } as TrendPoint);
    }
    return out;
  }

  /**
   * 拉取三组序列 + 告警，并生成智能分析小结。
   *
   * 小结不是写死的文案，全部由当前窗口的真实数据算出 ——
   * 这是"智能分析"和"贴一句话"的区别，也是赛题上真正能拉开差距的地方。
   */
  private async loadTrendAndSummary(): Promise<void> {
    const now: number = DateUtil.now();
    const from: number = this.rangeFrom(now);
    const iv: string = this.rangeInterval();

    const request: number = ++this.trendRequest;
    const points: TrendPoint[] = await this.fetchSeries(this.selectedType, from, now, iv);
    if (request !== this.trendRequest) {
      return;
    }
    this.trendPoints = points;
    const last = points[points.length - 1];
    this.lastSampleText = last?.timestamp === undefined
      ? '暂无采样 · App 打开并连通设备后开始记录'
      : `图中 ${points.length} 个点 · 最后采样 ${DateUtil.formatSampleTime(last.timestamp)}`;
    this.statMax = this.statText('max');
    this.statMin = this.statText('min');
    this.statAvg = this.statText('avg');
    this.statLast = this.statText('last');
    Logger.info(RealtimeStatusPage.MODULE,
      `统计: type=${this.selectedType} pts=${this.trendPoints.length} max=${this.statMax}`);
    // 温度/活动两组是小结的依据，与当前选中标签无关，始终要拉
    this.tempPoints = this.selectedType === SensorType.TEMP_HUMIDITY
      ? this.trendPoints
      : await this.fetchSeries(SensorType.TEMP_HUMIDITY, from, now, iv);
    this.activityPoints = this.selectedType === SensorType.PIR
      ? this.trendPoints
      : await this.fetchSeries(SensorType.PIR, from, now, iv);

    this.alerts = await this.service.loadAlerts('', '', 1);
    // 只保留窗口内的，避免服务端按"天"取整时把窗口外的算进来
    this.alerts = this.alerts.filter((a: Alert) => a.timestamp >= from && a.timestamp <= now);

    this.summary = this.buildSummary();
  }

  // ==================== 时间范围 ====================

  private rangeFrom(now: number): number {
    return now - (this.rangeKey === '5m' ? 300000 : 86400000);
  }

  private rangeInterval(): string {
    return this.rangeKey === '5m' ? 'raw' : '5m';
  }

  private rangeLabel(): string {
    for (const r of RealtimeStatusPage.RANGES) {
      if (r[0] === this.rangeKey) {
        return r[1];
      }
    }
    return '近 5 分钟';
  }

  private rangeOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (const r of RealtimeStatusPage.RANGES) {
      opts.push({ value: r[0], label: r[1] } as SelectOption);
    }
    return opts;
  }

  // ==================== 历史统计 / 告警跳转 ====================

  /**
   * 统计条文案：最高 / 最低 / 平均 / 当前。
   *
   * 直接从当前 trendPoints 派生（与图表同源），而不是另存一份 @State ——
   * 实测踩坑：另存的 @State 与图表更新不同步，会出现"图上有数据、统计条却是 --"。
   * 在 build 里调用本方法，trendPoints 一变就会随之重算。
   */
  private statText(kind: string): string {
    const pts: TrendPoint[] = this.trendPoints;
    if (pts.length === 0) {
      return '--';
    }
    let max: number = pts[0].count;
    let min: number = pts[0].count;
    let sum: number = 0;
    for (const p of pts) {
      max = Math.max(max, p.count);
      min = Math.min(min, p.count);
      sum += p.count;
    }
    const unit: string = this.unitOf(this.selectedType);
    if (kind === 'max') {
      return `${this.fmtStat(max)}${unit}`;
    }
    if (kind === 'min') {
      return `${this.fmtStat(min)}${unit}`;
    }
    if (kind === 'avg') {
      return `${this.fmtStat(sum / pts.length)}${unit}`;
    }
    return `${this.fmtStat(pts[pts.length - 1].count)}${unit}`;
  }

  /** 单位：温度 ℃、活动 次、烟雾/燃气 ppm，其余不带单位 */
  private unitOf(type: string): string {
    if (type === SensorType.TEMP_HUMIDITY) {
      return '℃';
    }
    if (type === SensorType.PIR) {
      return '';
    }
    if (type === SensorType.SMOKE || type === SensorType.GAS) {
      return 'ppm';
    }
    return '';
  }

  /** 统计值格式化：整数原样，小数保留 1 位 */
  private fmtStat(v: number): string {
    return this.selectedType === SensorType.TEMP_HUMIDITY ? v.toFixed(2) : `${Math.round(v * 10) / 10}`;
  }

  /** 打开某条告警的完整详情页（时间线 + 处置） */
  private openAlertDetail(alert: Alert): void {
    this.alertPopup = undefined;
    const params: AlertDetailParams = new AlertDetailParams(alert.alertId);
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/AlertDetail',
      params: params
    }).catch((e: Error) => {
      Logger.warn(RealtimeStatusPage.MODULE, `跳转告警详情失败: ${e.message}`);
    });
  }

  /** 告警条目副文案：时间 + 等级 + 处置状态 */
  private alertMeta(alert: Alert): string {
    return `${DateUtil.format(alert.timestamp)} · ${AlertLevel.labelOf(alert.level)} · `
      + `${AlertStatus.labelOf(alert.status)}`;
  }

  // ==================== VM 构建 ====================

  private buildRow(sensor: Sensor): SensorRowVM {
    const vm: SensorRowVM = new SensorRowVM();
    vm.sensor = sensor;
    const st: string = sensor.status();
    vm.color = AppColor.statusColor(st);
    vm.abnormal = sensor.isAbnormal();
    vm.border = st === SensorStatus.OFFLINE ? AppColor.LINE : vm.color;
    vm.bg = this.rowBg(st);
    vm.icon = this.iconOf(sensor.sensorType);
    vm.data = this.dataText(sensor);
    vm.insight = this.insightText(sensor);
    return vm;
  }

  // ==================== 生命体征四连格 ====================

  /**
   * 生成生命体征四连格：心率 / 血氧 / 体温 / 步数。
   *
   * 数据来自监护主机（device），不是挂在下方的传感器节点 —— 这四项由
   * 雷达 / PPG 模组采集，随心跳一并上报。所以它渲染在「传感器明细」最上方，
   * 与下面的门窗、温湿度、烟雾、燃气区分开：上面看"人"，下面看"环境"。
   *
   * 每格都给状态词而不是只丢数字：76 bpm 本身说明不了好坏，
   * "稳定"两个字才是家属真正要看的。
   */
  private buildVitals(): void {
    const d: Device | undefined = this.device;
    const cells: MetricCell[] = [];

    if (d === undefined) {
      // 设备未就绪时也渲染四连格的"空壳"（四个 -- 格）。
      // 如果这里给空数组，外层 `if (cells.length > 0)` 会让整个区块消失，
      // 用户看到"生命体征"标题下是一片空白，会当成页面 bug。
      this.vitalsCells = [
        this.metric('心率', '--', '同步中', AppColor.TEXT_3),
        this.metric('血氧', '--', '同步中', AppColor.TEXT_3),
        this.metric('体温', '--', '同步中', AppColor.TEXT_3),
        this.metric('步数', '--', '同步中', AppColor.TEXT_3)
      ];
      this.vitalsStatus = '同步中';
      this.vitalsColor = AppColor.TEXT_3;
      this.vitalsInsight = '正在同步监护主机的生命体征数据…';
      return;
    }

    const valid: boolean = d.hasVitals();

    // ① 心率：主机标配项，独立判定（有心率但血氧缺失时不能一起变灰）
    const hrOk: boolean = valid && d.heartRate > 0 && d.isHeartRateNormal();
    cells.push(this.metric('心率',
      valid && d.heartRate > 0 ? `${d.heartRate} bpm` : '--',
      valid && d.heartRate > 0 ? (hrOk ? '稳定' : '异常') : '无读数',
      valid && d.heartRate > 0 ? (hrOk ? AppColor.SUCCESS : AppColor.DANGER) : AppColor.TEXT_3));

    // ② 血氧：部分主机未配血氧传感器，0 表示"该主机没有这项"，不是 0%
    const spo2Ok: boolean = valid && d.spo2 > 0 && d.isSpo2Normal();
    cells.push(this.metric('血氧',
      valid && d.spo2 > 0 ? `${d.spo2}%` : '--',
      valid && d.spo2 > 0 ? (spo2Ok ? '稳定' : '偏低') : '无读数',
      valid && d.spo2 > 0 ? (spo2Ok ? AppColor.SUCCESS : AppColor.WARNING) : AppColor.TEXT_3));

    // ③ 体温：同上，0 表示未配置
    const tempOk: boolean = valid && d.bodyTemp > 0 && d.isBodyTempNormal();
    cells.push(this.metric('体温',
      valid && d.bodyTemp > 0 ? `${d.bodyTemp.toFixed(1)}°C` : '--',
      valid && d.bodyTemp > 0 ? (tempOk ? '稳定' : '关注') : '无读数',
      valid && d.bodyTemp > 0 ? (tempOk ? AppColor.SUCCESS : AppColor.WARNING) : AppColor.TEXT_3));

    // ④ 步数：没有"正常值"一说，只看当天是否采集到（采集到 0 步也算有效）
    const stepsOk: boolean = valid && d.steps > 0;
    cells.push(this.metric('步数',
      valid && d.steps > 0 ? `${d.steps}` : '--',
      valid && d.steps > 0 ? '稳定' : '无读数',
      valid && d.steps > 0 ? AppColor.SUCCESS : AppColor.TEXT_3));

    this.vitalsCells = cells;

    // 整体状态：只在"有读数且不在区间"时标关注，全绿才算"正常"；
    // 某项无读数不算异常，避免主机功能差异被误判成健康问题
    const allOk: boolean = valid && hrOk && spo2Ok && tempOk;
    const hasAbnormal: boolean =
      (valid && d.heartRate > 0 && !hrOk)
      || (valid && d.spo2 > 0 && !d.isSpo2Normal())
      || (valid && d.bodyTemp > 0 && !d.isBodyTempNormal());
    this.vitalsStatus = valid ? (hasAbnormal ? '关注' : (allOk ? '正常' : '无读数')) : '无读数';
    this.vitalsColor = valid ? (hasAbnormal ? AppColor.WARNING : AppColor.TEXT_3) : AppColor.TEXT_3;
    this.vitalsInsight = this.vitalsInsightText(d, valid, hasAbnormal);
  }

  /** 生命体征的一句话解读：先说结论，再给依据 */
  private vitalsInsightText(d: Device, valid: boolean, abnormal: boolean): string {
    if (!d.online) {
      return '监护主机离线，暂无法读取生命体征数据';
    }
    if (!valid) {
      return '监护主机暂未上报生命体征，可能是刚上电或信号中断';
    }
    if (abnormal) {
      if (d.bodyTemp > 0 && !d.isBodyTempNormal()) {
        return `体温 ${d.bodyTemp.toFixed(1)}°C 高于 37.2℃，建议复测并留意是否有发热症状`;
      }
      if (d.spo2 > 0 && !d.isSpo2Normal()) {
        return `血氧 ${d.spo2}% 低于 95%，建议静息后复测，持续偏低需就医`;
      }
      return `心率 ${d.heartRate} bpm 偏离静息区间 60–100，建议安静休息后复测`;
    }
    // 正常态：点名实际有读数的项，没有的项说明非主机功能缺失而是设备能力
    const parts: string[] = [];
    if (d.heartRate > 0) {
      parts.push(`心率 ${d.heartRate} bpm`);
    }
    if (d.spo2 > 0) {
      parts.push(`血氧 ${d.spo2}%`);
    }
    if (d.bodyTemp > 0) {
      parts.push(`体温 ${d.bodyTemp.toFixed(1)}°C`);
    }
    if (d.steps > 0) {
      parts.push(`今日 ${d.steps} 步`);
    }
    if (parts.length === 0) {
      return '监护主机生命体征未采集，请确认佩戴设备是否开机';
    }
    return `${parts.join(' · ')} · ${DateUtil.relative(d.vitalsAt)}更新`;
  }

  /** 构造一个指标格。ArkTS 不允许无类型对象字面量，统一走这里 */
  private metric(label: string, value: string, status: string, color: string): MetricCell {
    const c: MetricCell = new MetricCell();
    c.label = label;
    c.value = value;
    c.status = status;
    c.color = color;
    return c;
  }

  private static buildSos(sos: Sensor): SosVM {
    const vm: SosVM = new SosVM();
    vm.sensor = sos;
    vm.danger = sos.status() === SensorStatus.DANGER;
    vm.offline = !sos.online;
    vm.dot = vm.offline ? AppColor.TEXT_3 : AppColor.statusColor(sos.status());
    vm.accent = vm.danger ? AppColor.DANGER : '#C77A17';
    vm.border = vm.danger ? AppColor.DANGER : '#EFCB96';
    vm.bg = vm.danger ? AppColor.levelBg('P0') : '#FBEFDE';
    vm.statusLabel = vm.offline ? '云端未收到状态' : (vm.danger ? '求助已触发' : '当前无求助');
    if (vm.offline) {
      vm.footer = '本地求助仍可触发声光报警。主控联网后，App 才能收到上报。';
      vm.footerColor = AppColor.TEXT_3;
    } else if (sos.battery >= 0) {
      vm.footer = `电量 ${sos.battery}%`;
      vm.footerColor = sos.battery < 20 ? AppColor.WARNING : AppColor.TEXT_3;
    }
    return vm;
  }

  /** 卡片底色：按状态给极浅的染色，让颜色信号不只在一条边框上 */
  private rowBg(status: string): string {
    switch (status) {
      case SensorStatus.NORMAL:
        return 'rgba(46,125,50,0.05)';
      case SensorStatus.WARNING:
        return 'rgba(224,162,0,0.08)';
      case SensorStatus.DANGER:
        return 'rgba(198,40,40,0.07)';
      default:
        return AppColor.CARD;
    }
  }

  // ==================== 智能分析小结 ====================

  /**
   * 生成小结文案。
   *
   * 三段式：活动节律 + 温湿度 + 危险信号。全部由当前窗口的读数算出，
   * 不写死。这才是"智能分析"和"贴一句话"的区别。
   */
  private buildSummary(): string {
    const a: string = this.activityBrief();
    const t: string = this.tempBrief();
    const s: string = this.safetyBrief();
    return `${this.rangeLabel()}，${a}；${t}；${s}。`;
  }

  private activityBrief(): string {
    if (this.activityPoints.length === 0) {
      return '该时段暂无 PIR 采样';
    }
    return this.activityPoints.some((point: TrendPoint) => point.count > 0)
      ? '已采到 PIR 活动信号'
      : '已采样时刻均未检测到 PIR 活动';
  }

  /** 温度：给出实测区间与越界判断 */
  private tempBrief(): string {
    const pts: TrendPoint[] = this.tempPoints;
    if (pts.length === 0) {
      return '无温度数据';
    }
    let lo: number = pts[0].count;
    let hi: number = pts[0].count;
    for (const p of pts) {
      lo = Math.min(lo, p.count);
      hi = Math.max(hi, p.count);
    }
    const span: string = `${this.round1(lo)}℃ ~ ${this.round1(hi)}℃`;
    if (hi > 28) {
      return `室内温度偏高（${span}），留意老人中暑风险`;
    }
    if (lo < 18) {
      return `室内温度偏低（${span}），留意老人着凉风险`;
    }
    return `室内温度波动正常（${span}）`;
  }

  /** 危险信号：只数高危类告警，不给任何"大概没问题"的模糊表述 */
  private safetyBrief(): string {
    const risky: Alert[] = this.alerts.filter((a: Alert) =>
      a.alertType === AlertType.SMOKE_DETECTED
      || a.alertType === AlertType.GAS_LEAK
      || a.alertType === AlertType.SOS_PRESSED);
    if (risky.length === 0) {
      return '该时段暂无危险信号记录';
    }
    let gas: number = 0;
    let smoke: number = 0;
    let sos: number = 0;
    for (const a of risky) {
      if (a.alertType === AlertType.GAS_LEAK) {
        gas++;
      } else if (a.alertType === AlertType.SMOKE_DETECTED) {
        smoke++;
      } else {
        sos++;
      }
    }
    const parts: string[] = [];
    if (gas > 0) {
      parts.push(`燃气 ${gas} 次`);
    }
    if (smoke > 0) {
      parts.push(`烟雾 ${smoke} 次`);
    }
    if (sos > 0) {
      parts.push(`求助 ${sos} 次`);
    }
    return `检测到危险信号：${parts.join('、')}，请在预警中心逐条确认处置`;
  }

  private round1(v: number): string {
    return `${Math.round(v * 10) / 10}`;
  }

  // ==================== 红点详情弹窗 ====================

  /** 当时实测值。事件型告警没有连续量，给 -- 而不是编一个数 */
  private triggerText(alert: Alert): string {
    if (alert.triggerValue <= 0) {
      return '--';
    }
    return alert.alertType === AlertType.TEMP_HUMIDITY_ABNORMAL
      ? `${alert.triggerValue}℃`
      : `${alert.triggerValue}`;
  }

  /** 处置记录。未处置就明说，不用"无"糊过去 */
  private handleText(alert: Alert): string {
    const h: AlertHandle | undefined = alert.handle;
    if (h === undefined) {
      return '尚未处置';
    }
    const when: string = h.handledAt > 0 ? `（${DateUtil.format(h.handledAt)}）` : '';
    const note: string = h.note.length > 0 ? ` · ${h.note}` : '';
    return `${h.resultName}${when}${note}`;
  }

  @Builder
  popupLine(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(AppSize.SMALL_FONT)
        .fontColor(AppColor.TEXT_3)
        .width(64)
      Text(value)
        .fontSize(AppSize.SMALL_FONT)
        .fontColor(AppColor.TEXT_2)
        .layoutWeight(1)
        .lineHeight(18)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: 10 })
  }

  @Builder
  alertPopupCard(alert: Alert) {
    Stack({ alignContent: Alignment.Center }) {
      // 遮罩：点空白处关闭
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(16,22,34,0.5)')
      .onClick(() => {
        this.alertPopup = undefined;
      })

      Column() {
        Row() {
          Text(alert.alertTypeName)
            .fontSize(AppSize.SUBTITLE_FONT)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.TEXT)
            .layoutWeight(1)
          Text(AlertLevel.labelOf(alert.level))
            .fontSize(10)
            .fontColor(AppColor.CARD)
            .backgroundColor(AppColor.levelColor(alert.level))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
        }
        .width('100%')

        this.popupLine('告警时间', DateUtil.format(alert.timestamp))
        this.popupLine('告警类型', alert.alertTypeName)
        this.popupLine('当时数值', this.triggerText(alert))
        this.popupLine('处置状态', AlertStatus.labelOf(alert.status))
        this.popupLine('处置记录', this.handleText(alert))

        Row() {
          Text('关闭')
            .fontSize(AppSize.CAPTION_FONT)
            .fontColor(AppColor.TEXT_2)
            .backgroundColor(AppColor.SURFACE)
            .border({ width: 1, color: AppColor.LINE })
            .padding({ top: 10, bottom: 10 })
            .borderRadius(AppSize.SMALL_RADIUS)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.alertPopup = undefined;
            })

          Text('查看详情 ›')
            .fontSize(AppSize.CAPTION_FONT)
            .fontColor(AppColor.CARD)
            .backgroundColor(AppColor.PRIMARY)
            .padding({ top: 10, bottom: 10 })
            .borderRadius(AppSize.SMALL_RADIUS)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .margin({ left: 10 })
            .onClick(() => {
              this.openAlertDetail(alert);
            })
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width(280)
      .backgroundColor(AppColor.CARD)
      .borderRadius(AppSize.CARD_RADIUS)
      .padding(18)
      .shadow({
        radius: 24,
        color: 'rgba(10,25,60,0.25)',
        offsetY: 8
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 文案 ====================

  /** 第二行：关键数据。不同传感器关心的时间维度不同 */
  private dataText(sensor: Sensor): string {
    if (!sensor.online) {
      return sensor.displayValue || '暂无实时读数';
    }
    switch (sensor.sensorType) {
      case SensorType.PIR:
        return `${sensor.displayValue} · 今日触发 ${sensor.todayCount} 次`;
      case SensorType.DOOR:
        return sensor.lastChanged > 0
          ? `${sensor.displayValue} · 最后变化 ${DateUtil.relative(sensor.lastChanged)}`
          : sensor.displayValue;
      default:
        return sensor.displayValue;
    }
  }

  /**
   * 第三行：文字解读。
   * 赛题要求"帮助子女发现老人生活规律变化"，只给数字不够，必须给判断。
   * 活动量这一类还额外做真实的前后对比，而不是写死一句"正常"。
   */
  private insightText(sensor: Sensor): string {
    if (!sensor.online) {
      return '';
    }
    switch (sensor.sensorType) {
      case SensorType.PIR:
        return this.activityInsight(sensor);
      case SensorType.DOOR:
        return sensor.value > 0
          ? '门窗处于打开状态，请确认老人是否安全'
          : '门窗长时间关闭，居家环境稳定';
      case SensorType.TEMP_HUMIDITY:
        return this.tempInsight(sensor.value);
      case SensorType.SMOKE:
      case SensorType.GAS:
        return sensor.isAbnormal()
          ? 'MQ-2 读数偏高或主控报警中'
          : 'MQ-2 读数在设定阈值内';
      default:
        return '';
    }
  }

  /** 活动解读：与昨日做真实对比。±10% 以内算持平 */
  private activityInsight(sensor: Sensor): string {
    if (this.yesterdayCount <= 0 || sensor.todayCount <= 0) {
      return sensor.todayCount > 0
        ? `App 今日记录活动 ${sensor.todayCount} 次`
        : 'App 今日暂无活动记录';
    }
    const diff: number = sensor.todayCount - this.yesterdayCount;
    const tolerance: number = Math.max(1, Math.round(this.yesterdayCount * 0.1));
    if (Math.abs(diff) <= tolerance) {
      return `App 记录的活动频次与昨日接近（昨日 ${this.yesterdayCount} 次）`;
    }
    return diff > 0
      ? `今日活动 ${sensor.todayCount} 次，比昨日多 ${diff} 次`
      : `今日活动 ${sensor.todayCount} 次，比昨日少 ${-diff} 次`;
  }

  private tempInsight(temp: number): string {
    if (temp > 28) {
      return '室内偏热，留意老人中暑风险';
    }
    if (temp < 18) {
      return '室内偏凉，留意老人着凉风险';
    }
    return '室内温湿度舒适';
  }

  /** 传感器类型图标。SymbolGlyph 系统符号库，不引入位图素材 */
  private iconOf(type: string): Resource {
    switch (type) {
      case SensorType.PIR:
        return $r('sys.symbol.person_fill');
      case SensorType.DOOR:
        return $r('sys.symbol.ohos_lock');
      case SensorType.TEMP_HUMIDITY:
        return $r('sys.symbol.thermometer');
      case SensorType.SMOKE:
        return $r('sys.symbol.smoke_fill');
      case SensorType.GAS:
        return $r('sys.symbol.flame_fill');
      case SensorType.HEART_RATE:
        return $r('sys.symbol.heart_fill');
      default:
        return $r('sys.symbol.warning');
    }
  }

  // ==================== 界面 ====================

  build() {
    Stack() {
      // ---------- 页面主体 ----------
      Column() {
        Row() {
          Text('实时状态')
            .fontSize(AppSize.TITLE_FONT)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.TEXT)
            .layoutWeight(1)
          Text(this.refreshing ? '刷新中…' : '下拉刷新')
            .fontSize(AppSize.SMALL_FONT)
            .fontColor(this.refreshing ? AppColor.PRIMARY : AppColor.TEXT_3)
            .onClick(() => {
              if (this.refreshing) {
                return;
              }
              this.refreshStatus();
            })
        }
        .width('100%')
        .padding(AppSize.PAGE_PADDING)

        // 手势下拉刷新：在内容区按住往下拉，松手重新拉取。
        // refreshing 用 $$ 双向绑定给 Refresh；load() 的 finally 里置回 false。
        Refresh({ refreshing: $$this.refreshing }) {
          Scroll() {
            Column() {
              // ---------- 置顶：紧急求助按钮 ----------
              if (this.sosVm !== undefined) {
                this.sosCard(this.sosVm)
              }

            if (this.vitalsStatus !== '无读数' && this.vitalsStatus !== '同步中'
              && this.vitalsCells.length > 0) {
              this.vitalsBox()
            }

            WatchVitalsCard({ active: this.active })
              .margin({ bottom: 12 })

            // ---------- 环境与安全传感器（看"环境"） ----------
            Text('环境与安全')
              .fontSize(AppSize.SUBTITLE_FONT)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColor.TEXT)
              .width('100%')
              .margin({ top: 8, bottom: 10 })

            // key 含 data/insight：与四连格同理，否则节点复用后读数不刷新
            ForEach(this.rows, (vm: SensorRowVM) => {
              this.sensorRow(vm)
            }, (vm: SensorRowVM) => `${vm.sensor.sensorId}_${vm.data}_${vm.insight}`)

            // ---------- 历史监测数据（独立分区） ----------
            // 与上方"传感器明细"分开起标题：上面看当下，下面看趋势，
            // 两件事的信息密度差别很大，挤在一个卡片里会互相干扰。
            Row() {
              Text('历史监测数据')
                .fontSize(AppSize.SUBTITLE_FONT)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColor.TEXT)
                .layoutWeight(1)

              Select(this.rangeOptions())
                .value(this.rangeKey)
                .font({ size: AppSize.SMALL_FONT, weight: FontWeight.Normal })
                .fontColor(AppColor.TEXT_3)
                .selectedOptionFontColor(AppColor.PRIMARY)
                .optionFont({ size: AppSize.SMALL_FONT })
                .optionFontColor(AppColor.TEXT_2)
                .onSelect((index: number) => {
                  const r: string[] = RealtimeStatusPage.RANGES[index];
                  if (r !== undefined && r[0] !== this.rangeKey) {
                    this.rangeKey = r[0];
                    this.load();
                  }
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 4, bottom: 10 })

            Column() {
              // 传感器类型切换
              Row() {
                this.typeChip(SensorType.TEMP_HUMIDITY, '温度')
                this.typeChip(SensorType.GAS, '燃气')
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 统计条：最高 / 最低 / 平均 / 当前 —— 让曲线之外还有可读的硬指标
              Row() {
                StatCell({ label: '最高', value: this.statMax, color: AppColor.DANGER }).layoutWeight(1)
                StatCell({ label: '最低', value: this.statMin, color: AppColor.SECONDARY }).layoutWeight(1)
                StatCell({ label: '平均', value: this.statAvg, color: AppColor.TEXT_2 }).layoutWeight(1)
                StatCell({ label: '末点', value: this.statLast, color: AppColor.PRIMARY }).layoutWeight(1)
              }
              .width('100%')
              .padding({ top: 4, bottom: 10 })

              // 折线图 + 告警红点
              TrendChart({
                points: this.trendPoints,
                chartWidth: 336,
                chartHeight: 190,
                timeFrom: this.rangeFrom(DateUtil.now()),
                timeTo: DateUtil.now(),
                scaleToData: true,
                gapMs: this.rangeKey === '5m' ? 30000 : 600000,
                alerts: this.alerts,
                onAlertTap: (a: Alert) => {
                  this.alertPopup = a;
                }
              })

              Text(this.lastSampleText)
                .fontSize(AppSize.SMALL_FONT)
                .fontColor(AppColor.TEXT_2)
                .width('100%')
                .margin({ top: 8 })
              Text(this.rangeKey === '5m' ? '原始采样 · 缺测时段留空' : '每 5 分钟汇总 · 取已采样读数的平均值')
                .fontSize(AppSize.SMALL_FONT)
                .fontColor(AppColor.TEXT_3)
                .width('100%')
                .margin({ top: 4 })

              // 红点说明
              Row() {
                Row()
                  .width(8)
                  .height(8)
                  .borderRadius(4)
                  .backgroundColor(AppColor.DANGER)
                  .margin({ right: 5 })
                Text('红色圆点为该时段的历史告警事件，点击查看处置记录')
                  .fontSize(10)
                  .fontColor(AppColor.TEXT_3)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ top: 10 })

              // ---------- 本时段告警（可点击直达详情） ----------
              if (this.alerts.length > 0) {
                Column() {
                  Row() {
                    Text(`本时段告警 ${this.alerts.length} 条`)
                      .fontSize(AppSize.SMALL_FONT)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(AppColor.TEXT_2)
                      .layoutWeight(1)
                    Text('点击查看详情 ›')
                      .fontSize(10)
                      .fontColor(AppColor.TEXT_3)
                  }
                  .width('100%')
                  .margin({ bottom: 4 })

                  ForEach(this.alerts.slice(0, 4), (a: Alert) => {
                    Row() {
                      Row()
                        .width(7)
                        .height(7)
                        .borderRadius(3.5)
                        .backgroundColor(AppColor.levelColor(a.level))
                        .margin({ right: 8 })
                      Column() {
                        Text(a.alertTypeName)
                          .fontSize(AppSize.SMALL_FONT)
                          .fontColor(AppColor.TEXT)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(this.alertMeta(a))
                          .fontSize(10)
                          .fontColor(AppColor.TEXT_3)
                          .margin({ top: 2 })
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                      Text('›')
                        .fontSize(18)
                        .fontColor(AppColor.TEXT_3)
                        .margin({ left: 6 })
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)
                    .padding({ top: 9, bottom: 9 })
                    .border({ width: { bottom: 1 }, color: AppColor.LINE })
                    .onClick(() => {
                      this.openAlertDetail(a);
                    })
                  }, (a: Alert) => `${a.alertId}_${a.status}`)
                }
                .width('100%')
                .margin({ top: 12 })
                .padding(12)
                .backgroundColor(AppColor.SURFACE)
                .borderRadius(AppSize.SMALL_RADIUS)
              }

              // ---------- 智能分析小结 ----------
              Column() {
                Row() {
                  Text('智能分析小结')
                    .fontSize(AppSize.CAPTION_FONT)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(AppColor.PRIMARY)
                    .layoutWeight(1)
                }
                .width('100%')

                Text(this.summary.length > 0 ? this.summary : '正在分析…')
                  .fontSize(AppSize.SMALL_FONT)
                  .fontColor(AppColor.TEXT_2)
                  .lineHeight(20)
                  .margin({ top: 8 })
                  .width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(12)
              .backgroundColor(AppColor.SURFACE)
              .borderRadius(AppSize.SMALL_RADIUS)
              .margin({ top: 12 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(16)
            .backgroundColor(AppColor.CARD)
            .borderRadius(AppSize.CARD_RADIUS)
            .shadow({
              radius: AppSize.SHADOW_RADIUS,
              color: AppSize.SHADOW_COLOR,
              offsetY: AppSize.SHADOW_OFFSET_Y
            })
            .margin({ top: 4 })

            Blank().height(20)
          }
          .width('100%')
          .padding({ left: AppSize.PAGE_PADDING, right: AppSize.PAGE_PADDING })
        }
        .scrollBar(BarState.Off)
      }
      .layoutWeight(1)
      .onRefreshing(() => {
        this.refreshStatus();
      })
      }
      .width('100%')
      .height('100%')

      // ---------- 告警红点详情弹窗 ----------
      if (this.alertPopup !== undefined) {
        this.alertPopupCard(this.alertPopup)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.BG)
  }

  /**
   * 置顶的紧急求助按钮卡片。
   *
   * 用暖橙背景而不是告警红：它挂在最顶部，长期可见。
   * 用红色会与"燃气泄漏"这类真告警抢语义，也会让家属对告警脱敏。
   * 只有真的按下求助（状态转高危）时才整体变红。
   */
  @Builder
  sosCard(vm: SosVM) {
    Column() {
      Row() {
        Text('SOS')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(vm.accent)
          .border({ width: 1, color: vm.border, radius: 4 })
          .padding({ left: 6, right: 6, top: 3, bottom: 3 })
          .letterSpacing(1)

        Text('紧急求助按钮')
          .fontSize(AppSize.SUBTITLE_FONT)
          .fontWeight(FontWeight.Bold)
          .fontColor(vm.danger ? AppColor.DANGER : AppColor.TEXT)
          .margin({ left: 10 })

        Blank()

        Row() {
          Row()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(vm.dot)
          Text(vm.statusLabel)
            .fontSize(AppSize.SMALL_FONT)
            .fontColor(vm.dot)
            .margin({ left: 6 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('可通过主控按键或 433 遥控发起求助')
        .fontSize(AppSize.SMALL_FONT)
        .fontColor(AppColor.TEXT_2)
        .margin({ top: 8 })
        .width('100%')

      Text(vm.footer)
        .fontSize(AppSize.SMALL_FONT)
        .fontColor(vm.footerColor)
        .margin({ top: 6 })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(vm.bg)
    .borderRadius(AppSize.CARD_RADIUS)
    .shadow({
      radius: AppSize.SHADOW_RADIUS,
      color: AppSize.SHADOW_COLOR,
      offsetY: AppSize.SHADOW_OFFSET_Y
    })
    .margin({ bottom: 12 })
  }

  /**
   * 生命体征四连格。
   *
   * 一个浅灰底容器里并排四格，每格三层（标签 / 数值 / 状态词），
   * 格子之间用细竖线分隔。方框下方补一句解读 —— 数字之外还要给判断，
   * 否则家属只看到 "37.7°C" 也不知道这算不算发烧。
   *
   * 容器标题用「当前快照」而不是「生命体征」：后者已经是外层分区标题，
   * 里外重复会让层级看起来比实际更平。
   */
  @Builder
  vitalsBox() {
    Column() {
      // 标题行：左侧说明，右侧整体状态胶囊
      Row() {
        Text('当前快照')
          .fontSize(AppSize.CAPTION_FONT)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.TEXT)
          .layoutWeight(1)
        Row() {
          Row()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.vitalsColor)
            .margin({ right: 5 })
          Text(this.vitalsStatus)
            .fontSize(10)
            .fontColor(this.vitalsColor)
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 四连格
      // key 必须包含数值与状态：若只用 label，ArkUI 会判定"同一条目"复用节点，
      // itemGenerator 不再执行，界面保留旧数字（实测：洞察文案已更新、四格不动）。
      Row() {
        ForEach(this.vitalsCells, (c: MetricCell, idx: number) => {
          this.metricCell(c, idx > 0)
        }, (c: MetricCell) => `${c.label}_${c.value}_${c.status}`)
      }
      .width('100%')
      .margin({ top: 12 })

      // 解读：数字之外给判断
      Text(this.vitalsInsight)
        .fontSize(AppSize.SMALL_FONT)
        .fontColor(AppColor.TEXT_3)
        .lineHeight(18)
        .margin({ top: 12 })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(AppColor.CARD)
    .borderRadius(AppSize.CARD_RADIUS)
    .shadow({
      radius: AppSize.SHADOW_RADIUS,
      color: AppSize.SHADOW_COLOR,
      offsetY: AppSize.SHADOW_OFFSET_Y
    })
    .margin({ bottom: 10 })
  }

  /** 单个指标格。withDivider 为真时在左侧画细竖线，做出四连格的分隔感 */
  @Builder
  metricCell(c: MetricCell, withDivider: boolean) {
    Row() {
      if (withDivider) {
        Divider()
          .vertical(true)
          .height(34)
          .strokeWidth(1)
          .color(AppColor.LINE)
          .margin({ right: 2 })
      }
      Column() {
        Text(c.label)
          .fontSize(10)
          .fontColor(AppColor.TEXT_3)
          .maxLines(1)
        Text(c.value)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(c.color)
          .margin({ top: 5 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(c.status)
          .fontSize(10)
          .fontColor(c.color)
          .margin({ top: 4 })
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 普通传感器明细行。
   * 三色状态直接反映在边框、圆点与解读文字上：
   * 正常绿 / 待关注黄 / 高危红 / 离线灰。
   */

  @Builder
  sensorRow(vm: SensorRowVM) {
    Column() {
      Row() {
        SymbolGlyph(vm.icon)
          .fontSize(20)
          .fontColor([vm.color])
        Text(vm.sensor.name)
          .fontSize(AppSize.BODY_FONT)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.TEXT)
          .margin({ left: 10 })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(vm.color)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(vm.data)
        .fontSize(AppSize.CAPTION_FONT)
        .fontColor(AppColor.TEXT_2)
        .margin({ top: 8 })
        .width('100%')

      Text(vm.insight)
        .fontSize(AppSize.SMALL_FONT)
        .fontColor(vm.abnormal ? vm.color : AppColor.TEXT_3)
        .margin({ top: 6 })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(vm.bg)
    .borderRadius(AppSize.CARD_RADIUS)
    .border({ width: 1, color: vm.border })
    .margin({ bottom: 10 })
  }

  @Builder
  typeChip(type: string, label: string) {
    Text(label)
      .fontSize(AppSize.SMALL_FONT)
      .fontColor(this.selectedType === type ? AppColor.CARD : AppColor.TEXT_2)
      .backgroundColor(this.selectedType === type ? AppColor.PRIMARY : AppColor.SURFACE)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .margin({ right: 8 })
      .onClick(() => {
        this.selectedType = type;
        this.loadTrendAndSummary();
      })
  }
}

/**
 * 历史统计条的单格。
 *
 * 独立成 @Component 而不是 @Builder：ArkUI 局部更新下 @Builder 的值参数
 * 不具响应性，@State 变化不会刷新（实测统计条一直停在 --）；
 * @Prop 则是标准响应式通道，父级 statMax 一变即刷新。
 */
@Component
struct StatCell {
  @Prop label: string = '';
  @Prop value: string = '--';
  @Prop color: string = '';

  build() {
    Column() {
      Text(this.value)
        .fontSize(AppSize.CAPTION_FONT)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.color)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.label)
        .fontSize(10)
        .fontColor(AppColor.TEXT_3)
        .margin({ top: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
