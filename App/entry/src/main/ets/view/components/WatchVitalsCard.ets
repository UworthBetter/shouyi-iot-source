import { WatchHistoryApi, WatchRecord } from '../../cloud/WatchHistoryApi';
import { AppColor, AppSize } from '../../common/constants/ThemeColors';

class VitalReading {
  label: string;
  value: string;
  time: string;

  constructor(label: string, value: string, time: string) {
    this.label = label;
    this.value = value;
    this.time = time;
  }
}

@Component
export struct WatchVitalsCard {
  @Prop @Watch('updatePolling') active: boolean = false;
  @StorageLink('watchSessionVersion') @Watch('updatePolling') sessionVersion: number = 0;
  @State private signedIn: boolean = false;
  @State private loading: boolean = false;
  @State private readings: VitalReading[] = [];
  private timer: number = -1;
  private generation: number = 0;

  aboutToAppear(): void {
    this.updatePolling();
  }

  aboutToDisappear(): void {
    this.stopPolling();
  }

  private stopPolling(): void {
    this.generation++;
    this.loading = false;
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private updatePolling(): void {
    this.stopPolling();
    this.signedIn = WatchHistoryApi.isSignedIn();
    this.readings = [];
    if (this.active && this.signedIn) {
      this.refresh();
      this.timer = setInterval(() => this.refresh(), 30000);
    }
  }

  private async refresh(): Promise<void> {
    if (this.loading) {
      return;
    }
    const generation = this.generation;
    this.loading = true;
    try {
      const readings = await Promise.all([
        this.readMetric('rate', '心率', ' 次/分'),
        this.readMetric('spo2', '血氧', '%'),
        this.readMetric('temp', '体温', ' °C'),
        this.readMetric('blood', '血压', ' mmHg'),
        this.readMetric('steps', '步数', ' 步')
      ]);
      if (generation === this.generation) {
        this.readings = readings;
      }
    } finally {
      if (generation === this.generation) {
        this.loading = false;
      }
    }
  }

  private async readMetric(metric: string, label: string, unit: string): Promise<VitalReading> {
    try {
      const result = await WatchHistoryApi.history(metric, 1, 1);
      if (result.rows.length === 0) {
        return new VitalReading(label, '—', '暂无记录');
      }
      const row: WatchRecord = result.rows[0];
      if (metric === 'steps') {
        const day = row.date ?? row.dateTime;
        const value = row.value != null ? `${row.value}${unit}` : '—';
        return new VitalReading(label, value, day ? day.slice(0, 10) : '日期未知');
      }
      let value = '—';
      if (metric === 'blood') {
        if (row.systolic != null && row.diastolic != null) {
          value = `${row.systolic}/${row.diastolic}${unit}`;
        }
      } else if (row.value != null) {
        value = `${row.value}${unit}`;
      }
      return new VitalReading(label, value, row.createTime ?? '记录时间未知');
    } catch (_) {
      return new VitalReading(label, '—', '读取失败或无权限');
    }
  }

  /** 指标 → SymbolGlyph 图标。与 RealtimeStatusPage 的体征语义保持一致 */
  private metricIcon(label: string): Resource {
    switch (label) {
      case '心率':
      case '血压':
        return $r('sys.symbol.heart_fill');
      case '血氧':
        return $r('sys.symbol.ohos_lungs');
      case '体温':
        return $r('sys.symbol.thermometer');
      case '步数':
        return $r('sys.symbol.figure_walk');
      default:
        return $r('sys.symbol.heart_fill');
    }
  }

  /** 指标强调色：只上在图标上，数值保持深色，避免整卡花掉 */
  private metricAccent(label: string): string {
    switch (label) {
      case '心率':
        return AppColor.DANGER;
      case '血氧':
        return AppColor.SECONDARY;
      case '体温':
        return AppColor.WARNING;
      case '血压':
        return AppColor.PRIMARY;
      case '步数':
        return AppColor.SUCCESS;
      default:
        return AppColor.PRIMARY;
    }
  }

  build() {
    Column({ space: 12 }) {
      // ---------- 标题行 ----------
      Column() {
        Text('生命体征 · 手表')
          .width('100%').fontSize(16).fontWeight(FontWeight.Bold).fontColor(AppColor.TEXT)
        Text('尾号 1265 · 最近一次上报的读数，每 30 秒自动刷新')
          .width('100%').fontSize(12).fontColor(AppColor.TEXT_2).margin({ top: 3 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // ---------- 指标格子（已登录） ----------
      if (this.signedIn) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.readings, (reading: VitalReading) => {
            Column() {
              Row({ space: 6 }) {
                SymbolGlyph(this.metricIcon(reading.label))
                  .fontSize(14)
                  .fontColor([this.metricAccent(reading.label)])
                Text(reading.label)
                  .fontSize(12)
                  .fontColor(AppColor.TEXT_2)
              }
              .alignItems(VerticalAlign.Center)

              Text(reading.value)
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColor.TEXT)
                .margin({ top: 7 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')

              Text(reading.time)
                .fontSize(10)
                .fontColor(AppColor.TEXT_3)
                .margin({ top: 4 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .padding(11)
            .backgroundColor(AppColor.SURFACE)
            .borderRadius(12)
            .width('48%')
            .margin({ bottom: 8 })
          }, (reading: VitalReading) => `${reading.label}/${reading.value}/${reading.time}`)
        }
        .width('100%')

        // ---------- 操作按钮 ----------
        Row({ space: 8 }) {
          Button(this.loading ? '读取中…' : '刷新读数')
            .layoutWeight(1)
            .height(36)
            .fontSize(13)
            .enabled(!this.loading)
            .backgroundColor(AppColor.PRIMARY)
            .fontColor(AppColor.CARD)
            .borderRadius(12)
            .onClick(() => this.refresh())
          Button('查看手表历史')
            .layoutWeight(1)
            .height(36)
            .fontSize(13)
            .backgroundColor(AppColor.PRIMARY_SOFT)
            .fontColor(AppColor.PRIMARY)
            .borderRadius(12)
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/WatchHistory' });
            })
        }
        .width('100%')
      } else {
        // 未登录：只给登录入口，格子区域不渲染空壳
        Button('登录耆康云盾查看读数')
          .width('100%')
          .height(38)
          .fontSize(13)
          .backgroundColor(AppColor.PRIMARY)
          .fontColor(AppColor.CARD)
          .borderRadius(12)
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/WatchHistory' });
          })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(AppColor.CARD)
    .borderRadius(AppSize.CARD_RADIUS)
    .shadow({
      radius: AppSize.SHADOW_RADIUS,
      color: AppSize.SHADOW_COLOR,
      offsetY: AppSize.SHADOW_OFFSET_Y
    })
  }
}
