import { Sensor } from '../model/Device';
import { Alert } from '../model/Alert';
import { DeviceStatusResp, ReadingsResp, ReadingsPoint } from '../cloud/CloudTypes';
import { CareService } from '../service/CareService';
import { TrendChart } from '../view/components/TrendChart';
import { TrendPoint } from '../model/ActivityRecord';
import { AppColor, AppSize } from '../common/constants/ThemeColors';
import { SensorType, SensorRisk, AlertType, AlertStatus } from '../common/constants/AppConstants';
import { DateUtil } from '../common/utils/DateUtil';
import { Logger } from '../common/utils/Logger';

/**
 * 跳转本页的传参类型，必须与发送端 DeviceOverviewPage 保持一致。
 * ArkTS 不允许无类型对象字面量，两边都用显式 class。
 */
class SensorDetailParams {
  sensorType: string = '';
}

/** 时间范围选项 */
class RangeOption {
  key: string = '';
  label: string = '';

  constructor(key: string, label: string) {
    this.key = key;
    this.label = label;
  }
}

/**
 * 传感器详情页 —— 单传感器的长期趋势。
 *
 * 从首页任意传感器卡片点击进入，回答一个问题：
 * "这个数字最近一直是这样吗，还是在往坏的方向走？"
 * 首页给的是当下，这一页给的是趋势，两者合起来才支撑"长期跟踪"。
 *
 * 入参：DeviceOverviewPage.openSensorDetail() 通过 pushUrl 传入 { sensorType }。
 */
@Entry
@Component
struct SensorDetail {
  private static readonly MODULE: string = 'SensorDetail';

  private static readonly RANGES: RangeOption[] = [
    new RangeOption('5m', '5 分钟'),
    new RangeOption('24h', '24 小时')
  ];

  @State sensorType: string = '';
  @State sensor: Sensor | undefined = undefined;
  @State points: TrendPoint[] = [];
  /** 事件型传感器（SOS）的触发记录，替代没有意义的连续趋势线 */
  @State events: Alert[] = [];
  @State rangeKey: string = '5m';
  @State chartEnd: number = 0;
  private trendTimer: number = -1;
  private trendRequest: number = 0;
  @State loading: boolean = true;

  private service: CareService = new CareService();

  /**
   * 是否事件型传感器。
   * SOS 按钮是"按一下触发一次"的事件，没有连续量可言 ——
   * 给它画折线会得到一条恒零直线，那比不画更糟。
   */
  private isEventType(): boolean {
    return this.sensorType === SensorType.SOS_BUTTON;
  }

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as SensorDetailParams;
    if (params !== undefined && params.sensorType !== undefined && params.sensorType.length > 0) {
      this.sensorType = params.sensorType;
    }
    if (this.isEventType()) {
      this.rangeKey = '24h';
    } else {
      this.trendTimer = setInterval(() => {
        this.loadTrend();
      }, 4000);
    }
    this.load();
  }

  aboutToDisappear(): void {
    if (this.trendTimer >= 0) {
      clearInterval(this.trendTimer);
      this.trendTimer = -1;
    }
  }

  async load(): Promise<void> {
    this.loading = true;
    try {
      const resp: DeviceStatusResp | undefined = await this.service.loadDeviceStatus('');
      if (resp !== undefined) {
        this.sensor = resp.sensors.find((s: Sensor) => s.sensorType === this.sensorType);
      }
      if (this.isEventType()) {
        await this.loadEvents();
      } else {
        await this.loadTrend();
      }
    } catch (err) {
      Logger.error(SensorDetail.MODULE, `加载失败: ${(err as Error).message}`);
    } finally {
      this.loading = false;
    }
  }

  /**
   * 拉取最近 30 天的求助触发记录。
   * 对事件型传感器而言，触发记录才是真正的"历史数据"。
   */
  async loadEvents(): Promise<void> {
    try {
      const all: Alert[] = await this.service.loadAlerts('', '', 30);
      this.events = all.filter((a: Alert) => a.alertType === AlertType.SOS_PRESSED);
    } catch (err) {
      Logger.error(SensorDetail.MODULE, `加载触发记录失败: ${(err as Error).message}`);
      this.events = [];
    }
  }

  /** 按所选时间范围拉取读数，转成折线图数据 */
  async loadTrend(): Promise<void> {
    const now: number = DateUtil.now();
    const request: number = ++this.trendRequest;
    const raw: boolean = this.rangeKey === '5m';
    const resp: ReadingsResp | undefined = await this.service.loadReadings(
      this.sensorType, this.rangeFrom(now), now, this.rangeInterval());
    if (request !== this.trendRequest) {
      return;
    }
    this.chartEnd = now;
    if (resp === undefined) {
      this.points = [];
      return;
    }
    this.points = resp.points.map((p: ReadingsPoint) => {
      const label: string = raw ? DateUtil.formatSampleTime(p.timestamp) : DateUtil.formatTime(p.timestamp);
      return { date: label, count: p.value, timestamp: p.timestamp } as TrendPoint;
    });
  }

  build() {
    Column() {
      // ---------- 顶部导航 ----------
      Row() {
        Text('‹')
          .fontSize(26)
          .fontColor(AppColor.TEXT)
          .width(32)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        Text(this.titleOf(this.sensorType))
          .fontSize(AppSize.TITLE_FONT)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.TEXT)
          .layoutWeight(1)
        if (this.sensor !== undefined) {
          Text(this.sensor.statusLabel())
            .fontSize(AppSize.SMALL_FONT)
            .fontColor(AppColor.statusColor(this.sensor.status()))
            .border({ width: 1, color: AppColor.statusBorder(this.sensor.status()) })
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding(AppSize.PAGE_PADDING)

      Scroll() {
        Column() {
          // ---------- 当前值 ----------
          Column() {
            Text('当前读数')
              .fontSize(AppSize.SMALL_FONT)
              .fontColor(AppColor.TEXT_3)
              .width('100%')

            Row() {
              Text(this.currentValueText())
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.sensor !== undefined
                  ? AppColor.statusTextColor(this.sensor.status()) : AppColor.TEXT_3)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)

              Row()
                .width(10)
                .height(10)
                .borderRadius(5)
                .backgroundColor(this.sensor !== undefined
                  ? AppColor.statusColor(this.sensor.status()) : AppColor.TEXT_3)
                .margin({ left: 10 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 8 })

            Text(this.updateText())
              .fontSize(AppSize.SMALL_FONT)
              .fontColor(AppColor.TEXT_3)
              .margin({ top: 8 })
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor(AppColor.CARD)
          .borderRadius(AppSize.CARD_RADIUS)
          .margin({ bottom: 12 })

          // ---------- 历史数据 ----------
          // 连续量传感器给趋势线与统计量；事件型传感器（SOS）给触发记录。
          if (!this.isEventType()) {
            Column() {
              Row() {
                Text('采样趋势')
                  .fontSize(AppSize.SUBTITLE_FONT)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColor.TEXT)
                  .layoutWeight(1)
                Text(this.rangeLabel())
                  .fontSize(AppSize.SMALL_FONT)
                  .fontColor(AppColor.TEXT_3)
              }
              .width('100%')
              .margin({ bottom: 12 })

              Row() {
                ForEach(SensorDetail.RANGES, (r: RangeOption) => {
                  this.rangeChip(r)
                }, (r: RangeOption) => r.key)
              }
              .width('100%')
              .margin({ bottom: 14 })

              TrendChart({
                points: this.points,
                chartWidth: 296,
                chartHeight: 168,
                timeFrom: this.rangeFrom(this.chartEnd),
                timeTo: this.chartEnd,
                scaleToData: this.sensorType === SensorType.TEMP_HUMIDITY || this.sensorType === SensorType.GAS
                  || this.sensorType === SensorType.ILLUMINATION,
                gapMs: this.rangeKey === '5m' ? 30000 : 600000
              })
              Text(this.rangeKey === '5m' ? '原始采样 · 缺测时段留空' : '每 5 分钟汇总 · 缺测时段留空')
                .fontSize(AppSize.SMALL_FONT)
                .fontColor(AppColor.TEXT_3)

              // ---------- 统计量 ----------
              Row() {
                this.stat('平均', this.avgText())
                this.stat('最高', this.maxText())
                this.stat('最低', this.minText())
              }
              .width('100%')
              .margin({ top: 14 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(16)
            .backgroundColor(AppColor.CARD)
            .borderRadius(AppSize.CARD_RADIUS)
            .margin({ bottom: 12 })
          } else {
            this.eventCard()
          }

          // ---------- 说明 ----------
          Column() {
            Text('关于这项监测')
              .fontSize(AppSize.SUBTITLE_FONT)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColor.TEXT)
              .width('100%')
            Text(this.descOf(this.sensorType))
              .fontSize(AppSize.SMALL_FONT)
              .fontColor(AppColor.TEXT_3)
              .lineHeight(20)
              .margin({ top: 8 })
              .width('100%')
            Text(this.riskNote())
              .fontSize(AppSize.SMALL_FONT)
              .fontColor(SensorRisk.isHighRisk(this.sensorType) ? AppColor.DANGER : AppColor.TEXT_2)
              .lineHeight(20)
              .margin({ top: 8 })
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor(AppColor.CARD)
          .borderRadius(AppSize.CARD_RADIUS)

          Blank().height(20)
        }
        .width('100%')
        .padding({ left: AppSize.PAGE_PADDING, right: AppSize.PAGE_PADDING })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.BG)
  }

  @Builder
  rangeChip(r: RangeOption) {
    Text(r.label)
      .fontSize(AppSize.SMALL_FONT)
      .fontColor(this.rangeKey === r.key ? AppColor.CARD : AppColor.TEXT_2)
      .backgroundColor(this.rangeKey === r.key ? AppColor.PRIMARY : AppColor.SURFACE)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(14)
      .margin({ right: 8 })
      .onClick(() => {
        if (this.rangeKey !== r.key) {
          this.rangeKey = r.key;
          this.loadTrend();
        }
      })
  }

  /**
   * 事件型传感器的历史数据卡 —— 触发记录。
   *
   * SOS 按钮是事件，没有连续量：硬画折线只会得到一条恒零直线，
   * 那比不画更糟 —— 家属会以为页面坏了。列出每一次触发的时间与状态
   * 才是真正有用的历史数据。
   * 没有触发时也要给明确空状态：家属需要的是"没事"这个确定答案，
   * 而不是一片空白。
   */
  @Builder
  eventCard() {
    Column() {
      Row() {
        Text('触发记录')
          .fontSize(AppSize.SUBTITLE_FONT)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.TEXT)
          .layoutWeight(1)
        Text('近 30 天')
          .fontSize(AppSize.SMALL_FONT)
          .fontColor(AppColor.TEXT_3)
      }
      .width('100%')
      .margin({ bottom: 4 })

      if (this.events.length === 0) {
        Text('近 30 天没有求助触发记录 · 老人未按下求助按钮')
          .fontSize(AppSize.SMALL_FONT)
          .fontColor(AppColor.TEXT_3)
          .lineHeight(20)
          .padding({ top: 24, bottom: 24 })
          .width('100%')
      } else {
        ForEach(this.events, (a: Alert) => {
          Column() {
            Row() {
              Text(a.description.length > 0 ? a.description : '老人按下紧急求助按钮')
                .fontSize(AppSize.CAPTION_FONT)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColor.TEXT)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              // SOS 一律按最高优先级处理，状态块固定用告警红
              Text(AlertStatus.labelOf(a.status))
                .fontSize(10)
                .fontColor(AppColor.DANGER)
                .border({ width: 1, color: AppColor.DANGER })
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .borderRadius(3)
                .margin({ left: 8 })
            }
            .width('100%')

            Text(DateUtil.format(a.timestamp))
              .fontSize(AppSize.SMALL_FONT)
              .fontColor(AppColor.TEXT_3)
              .margin({ top: 4 })
              .width('100%')
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .border({ width: { bottom: 1 }, color: AppColor.LINE })
        }, (a: Alert) => a.alertId)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(AppColor.CARD)
    .borderRadius(AppSize.CARD_RADIUS)
    .margin({ bottom: 12 })
  }

  @Builder
  stat(label: string, value: string) {
    Column() {
      Text(value)
        .fontSize(AppSize.CAPTION_FONT)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.TEXT)
      Text(label)
        .fontSize(AppSize.SMALL_FONT)
        .fontColor(AppColor.TEXT_3)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  // ==================== 取值辅助 ====================

  private rangeFrom(now: number): number {
    return now - (this.rangeKey === '5m' ? 300000 : 86400000);
  }

  private rangeInterval(): string {
    return this.rangeKey === '5m' ? 'raw' : '5m';
  }

  private rangeLabel(): string {
    return this.rangeKey === '5m' ? '最近 5 分钟' : '最近 24 小时';
  }

  private currentValueText(): string {
    if (this.sensor === undefined) {
      return '--';
    }
    // 离线时同样给 "--"，不展示不可信的缓存值
    if (!this.sensor.online) {
      return '--';
    }
    return this.sensor.displayValue.length > 0 ? this.sensor.displayValue : '--';
  }

  private updateText(): string {
    if (this.sensor === undefined) {
      return '暂无数据';
    }
    if (!this.sensor.online) {
      return '设备离线，暂无实时读数';
    }
    const t: number = this.sensor.updatedAt > 0 ? this.sensor.updatedAt : this.sensor.lastChanged;
    return t > 0 ? `最后更新：${DateUtil.relative(t)}` : '最后更新：刚刚';
  }

  private avgText(): string {
    if (this.points.length === 0) {
      return '--';
    }
    let sum: number = 0;
    for (const p of this.points) {
      sum += p.count;
    }
    return this.withUnit(Math.round(sum / this.points.length * 10) / 10);
  }

  private maxText(): string {
    if (this.points.length === 0) {
      return '--';
    }
    let m: number = this.points[0].count;
    for (const p of this.points) {
      m = Math.max(m, p.count);
    }
    return this.withUnit(Math.round(m * 10) / 10);
  }

  private minText(): string {
    if (this.points.length === 0) {
      return '--';
    }
    let m: number = this.points[0].count;
    for (const p of this.points) {
      m = Math.min(m, p.count);
    }
    return this.withUnit(Math.round(m * 10) / 10);
  }

  private withUnit(v: number): string {
    const u: string = this.unitOf(this.sensorType);
    return u.length > 0 ? `${v}${u}` : `${v}`;
  }

  private unitOf(type: string): string {
    switch (type) {
      case SensorType.TEMP_HUMIDITY:
        return '℃';
      case SensorType.PIR:
        return ' 次';
      case SensorType.SMOKE:
      case SensorType.GAS:
        return ' ppm';
      default:
        return '';
    }
  }

  private titleOf(type: string): string {
    switch (type) {
      case SensorType.PIR:
        return '人体活动';
      case SensorType.DOOR:
        return '门窗状态';
      case SensorType.TEMP_HUMIDITY:
        return '温湿度';
      case SensorType.SMOKE:
        return '烟雾监测';
      case SensorType.GAS:
        return '燃气监测';
      case SensorType.SOS_BUTTON:
        return '紧急求助按钮';
      case SensorType.HEART_RATE:
        return '心率';
      default:
        return '传感器详情';
    }
  }

  private descOf(type: string): string {
    switch (type) {
      case SensorType.PIR:
        return '红外人体感应，记录老人在家的活动频次。白天长时间无活动、'
          + '或夜间超过阈值没有活动，会触发预警。';
      case SensorType.DOOR:
        return '门窗磁感应，记录开合状态与持续时长。长时间敞开会被判为待关注，'
          + '提醒家属确认老人是否安全。';
      case SensorType.TEMP_HUMIDITY:
        return '室内温湿度监测。超出舒适区间会先给黄色提醒，'
          + '用于预防中暑与着凉，不直接升级为高危。';
      case SensorType.SMOKE:
        return '烟雾浓度监测。属于高危类传感器，一旦超过阈值直接进入红色告警，'
          + '并以最高优先级推送给全部家属。';
      case SensorType.GAS:
        return '可燃气体浓度监测。属于高危类传感器，一旦超过阈值直接进入红色告警，'
          + '同时触发设备端语音播报与声光报警。';
      case SensorType.SOS_BUTTON:
        return '可通过主控按键或 433 遥控发起求助。主控触发本地声光报警，联网时上报求助状态。';
      case SensorType.HEART_RATE:
        return '由监护主机的毫米波雷达/PPG 采集的实时心率。'
          + '超出静息正常区间会提示关注。';
      default:
        return '该传感器的历史读数与趋势。';
    }
  }

  private riskNote(): string {
    if (SensorRisk.isHighRisk(this.sensorType)) {
      return `风险分级：高危 —— 异常直接进红色告警，走最高优先级推送。`;
    }
    return '风险分级：普通监测 —— 异常先给黄色提醒，由家属判断是否升级。';
  }
}
