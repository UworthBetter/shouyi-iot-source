import { Device, Sensor } from '../model/Device';
import { Alert } from '../model/Alert';
import { DeviceListItem, PushMessage } from '../cloud/CloudTypes';
import { CareService } from '../service/CareService';
import { NetworkMonitor } from '../service/NetworkMonitor';
import { SensorTile } from './components/SensorTile';
import { AlertCard } from './components/AlertCard';
import { AppColor, AppSize } from '../common/constants/ThemeColors';
import { AlertLevel, HeartRateConst } from '../common/constants/AppConstants';
import { DateUtil } from '../common/utils/DateUtil';
import { Logger } from '../common/utils/Logger';

/**
 * 跳转传感器详情页的传参类型，必须与 SensorDetail 接收端保持一致。
 * ArkTS 不允许无类型对象字面量，两边都用显式 class。
 */
class SensorDetailParams {
  sensorType: string = '';

  constructor(sensorType: string) {
    this.sensorType = sensorType;
  }
}

/**
 * 首页 · 设备总览。
 *
 * 结构：设备状态卡 → 传感器网格 → 最新告警 → 快捷入口。
 * 目标是让子女打开 App 三秒内知道"家里现在正常吗"。
 */
@Component
export struct DeviceOverviewPage {
  private static readonly MODULE: string = 'DeviceOverviewPage';

  @State device: Device | undefined = undefined;
  @State sensors: Sensor[] = [];
  @State alerts: Alert[] = [];
  @State pendingCount: number = 0;
  @State online: boolean = true;
  @State loading: boolean = true;
  @State pushBanner: PushMessage | undefined = undefined;
  /**
   * 演示场景切换通知。
   * 「我的 → 设置」切换场景后写一个时间戳进来，这里收到变化就重新拉取，
   * 让首页三色圆点立刻反映新场景 —— Tabs 会保活页面，不会重走 aboutToAppear。
   */
  @StorageLink('demoScenarioTick') @Watch('onDemoScenarioTick') demoTick: number = 0;

  /** 演示场景变化：重新拉取设备与传感器状态 */
  onDemoScenarioTick(): void {
    this.load();
  }

  private service: CareService = new CareService();

  aboutToAppear(): void {
    NetworkMonitor.subscribe((online: boolean) => {
      this.online = online;
      if (online) {
        this.load();
      }
    });
    this.service.subscribeAlerts((msg: PushMessage) => {
      // 收到推送：顶部弹出横幅提醒
      this.pushBanner = msg;
      this.load();
    });
    this.load();
  }

  aboutToDisappear(): void {
    this.service.unsubscribeAlerts();
  }

  async load(): Promise<void> {
    this.loading = true;
    try {
      const list: DeviceListItem[] = await this.service.loadDevices();
      if (list.length > 0) {
        this.device = list[0].device;
        this.sensors = list[0].sensors;
        this.pendingCount = list[0].activeAlerts;
      }
      const alerts: Alert[] = await this.service.loadAlerts('', '', 7);
      this.alerts = alerts.slice(0, 3);
    } catch (err) {
      Logger.error(DeviceOverviewPage.MODULE, `加载失败: ${(err as Error).message}`);
    } finally {
      this.loading = false;
    }
  }

  build() {
    Column() {
      // ---------- 顶部标题 ----------
      Column() {
        Row() {
          Column() {
            Text('守颐')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColor.CARD)
            Text('居家安全 · 实时守护')
              .fontSize(AppSize.SMALL_FONT)
              .fontColor('rgba(255,255,255,0.7)')
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.pendingCount > 0) {
            Column() {
              Text(`${this.pendingCount}`)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColor.CARD)
              Text('待处置')
                .fontSize(10)
                .fontColor('rgba(255,255,255,0.8)')
            }
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(AppColor.DANGER)
            .borderRadius(AppSize.SMALL_RADIUS)
          }
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .backgroundColor(AppColor.PRIMARY)
      .borderRadius({ bottomLeft: 16, bottomRight: 16 })

      // ---------- 离线提示 ----------
      if (!this.online) {
        Row() {
          Text('当前离线 · 展示的是最近一次同步的数据，设备端本地守护不受影响')
            .fontSize(AppSize.SMALL_FONT)
            .fontColor(AppColor.TEXT)
        }
        .width('100%')
        .padding(10)
        .backgroundColor('rgba(224,138,0,0.14)')
      }

      // ---------- 推送横幅 ----------
      if (this.pushBanner !== undefined) {
        Row() {
          Column() {
            Text(CareService.buildPushTitle(this.pushBanner))
              .fontSize(AppSize.CAPTION_FONT)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColor.CARD)
            Text(this.pushBanner.body)
              .fontSize(AppSize.SMALL_FONT)
              .fontColor('rgba(255,255,255,0.85)')
              .margin({ top: 4 })
              .maxLines(2)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text('关闭')
            .fontSize(AppSize.SMALL_FONT)
            .fontColor('rgba(255,255,255,0.8)')
            .onClick(() => {
              this.pushBanner = undefined;
            })
        }
        .width('100%')
        .padding(14)
        .backgroundColor(AppColor.levelColor(this.pushBanner.level))
      }

      Scroll() {
        Column() {
          // ---------- 设备状态卡 ----------
          if (this.device !== undefined) {
            Column() {
              Row() {
                Column() {
                  Text(this.device.deviceName)
                    .fontSize(AppSize.SUBTITLE_FONT)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(AppColor.TEXT)
                  // 固件版本属于底层开发信息，家属首页不需要看，已移至
                  // 「我的 → 设置 → 设备信息」。这里只保留家属真正会看的网络类型。
                  Text(this.networkLabel())
                    .fontSize(AppSize.SMALL_FONT)
                    .fontColor(AppColor.TEXT_3)
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Row() {
                  Row()
                    .width(8)
                    .height(8)
                    .borderRadius(4)
                    .backgroundColor(this.device.online ? AppColor.SUCCESS : AppColor.DANGER)
                  Text(this.device.online ? '在线' : '离线')
                    .fontSize(AppSize.SMALL_FONT)
                    .fontColor(this.device.online ? AppColor.SUCCESS : AppColor.DANGER)
                    .margin({ left: 6 })
                }
              }
              .width('100%')

              Row() {
                this.metric('最近上报', this.device.lastHeartbeat > 0
                  ? DateUtil.relative(this.device.lastHeartbeat) : '暂无上报', AppColor.TEXT)
              }
              .width('100%')
              .margin({ top: 14 })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(AppColor.CARD)
            .borderRadius(AppSize.CARD_RADIUS)
            .margin({ bottom: 12 })
          }

          // ---------- 传感器网格 ----------
          Text('传感器状态')
            .fontSize(AppSize.SUBTITLE_FONT)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.TEXT)
            .width('100%')
            .margin({ bottom: 10 })

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(this.sensors, (sensor: Sensor) => {
              Column() {
                SensorTile({ sensor: sensor })
              }
              .width('48%')
              .margin({ bottom: 10 })
              // 卡片可点：进入该传感器的详情页看长期趋势
              .hoverEffect(HoverEffect.Highlight)
              .stateStyles({
                pressed: { .opacity(0.6) },
                normal: { .opacity(1) }
              })
              .onClick(() => {
                this.openSensorDetail(sensor);
              })
            // key 含 displayValue：读数刷新后节点要重建
            }, (sensor: Sensor) => `${sensor.sensorId}_${sensor.displayValue}`)
          }
          .width('100%')

          // ---------- 最新告警 ----------
          Row() {
            Text('最新预警')
              .fontSize(AppSize.SUBTITLE_FONT)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColor.TEXT)
              .layoutWeight(1)
            Text(`近 7 天预警：${this.alerts.length} 条`)
              .fontSize(AppSize.SMALL_FONT)
              .fontColor(AppColor.TEXT_3)
          }
          .width('100%')
          .margin({ top: 8, bottom: 10 })

          if (this.alerts.length === 0) {
            Column() {
              Text('近 7 天没有预警记录')
                .fontSize(AppSize.CAPTION_FONT)
                .fontColor(AppColor.TEXT_3)
              Text('设备运行正常')
                .fontSize(AppSize.SMALL_FONT)
                .fontColor(AppColor.TEXT_3)
                .margin({ top: 6 })
            }
            .width('100%')
            .padding({ top: 30, bottom: 30 })
            .backgroundColor(AppColor.CARD)
            .borderRadius(AppSize.CARD_RADIUS)
          } else {
            ForEach(this.alerts, (alert: Alert) => {
              AlertCard({
                alert: alert,
                onChanged: () => {
                  // 卡片里一键标记已处置后重新拉列表：按钮要消失，文案要变成「已处置」
                  this.load();
                }
              })
                .margin({ bottom: 10 })
            }, (alert: Alert) => alert.alertId)
          }

          Blank().height(20)
        }
        .width('100%')
        .padding(AppSize.PAGE_PADDING)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.BG)
  }

  @Builder
  metric(label: string, value: string, color: string) {
    Column() {
      Text(value)
        .fontSize(AppSize.CAPTION_FONT)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontSize(AppSize.SMALL_FONT)
        .fontColor(AppColor.TEXT_3)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  /** 打开某传感器的详情页，查看长期趋势与统计量 */
  private openSensorDetail(sensor: Sensor): void {
    const params: SensorDetailParams = new SensorDetailParams(sensor.sensorType);
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/SensorDetail',
      params: params
    }).catch((e: Error) => {
      Logger.warn(DeviceOverviewPage.MODULE, `跳转传感器详情失败: ${e.message}`);
    });
  }

  /**
   * 当前是否有可用心率读数。
   * 除设备自身条件（在线 / 读数有效 / 未过期）外，还要 App 本身在线 ——
   * 手机断网时看到的是缓存，同样不该当成实时心率展示。
   */
  private hasHeartRate(): boolean {
    const d: Device | undefined = this.device;
    if (!this.online || d === undefined) {
      return false;
    }
    return d.hasHeartRate();
  }

  /** 心率展示文案：有读数给数值，没有给 "-- 次/分钟" */
  private heartRateText(): string {
    const d: Device | undefined = this.device;
    const bpm: number = d !== undefined ? d.heartRate : 0;
    return HeartRateConst.display(bpm, this.hasHeartRate());
  }

  /**
   * 心率文字颜色。
   * 无读数 → 弱文本色（灰）；读数异常 → 砖红；正常 → 青绿（与全局"健康"语义一致）。
   * 刻意不复用告警红作为常态色，避免家属把"正常心率"误读成告警。
   */
  private heartRateColor(): string {
    const d: Device | undefined = this.device;
    if (!this.hasHeartRate() || d === undefined) {
      return AppColor.TEXT_3;
    }
    return d.isHeartRateNormal() ? AppColor.SECONDARY : AppColor.DANGER;
  }

  /** 心率条底色：无读数用中性浅底，异常时用对应等级的浅底 */
  private heartRateBg(): string {
    const d: Device | undefined = this.device;
    if (!this.hasHeartRate() || d === undefined) {
      return AppColor.SURFACE;
    }
    return d.isHeartRateNormal()
      ? 'rgba(46,125,107,0.08)'
      : AppColor.levelBg(AlertLevel.P1);
  }

  private networkLabel(): string {
    if (this.device === undefined) {
      return '';
    }
    switch (this.device.networkType) {
      case 'wifi':
        return 'Wi-Fi';
      case 'cellular':
        return '4G';
      case 'starflash':
        return '星闪';
      default:
        return this.device.networkType;
    }
  }
}
