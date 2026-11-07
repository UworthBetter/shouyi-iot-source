import { TrendPoint } from '../../model/ActivityRecord';
import { Alert } from '../../model/Alert';
import { AppColor, AppSize } from '../../common/constants/ThemeColors';

/**
 * 通用趋势折线图。
 *
 * 展示一段时间内每日（或每小时）的数值，并标出均值基准线，
 * 让"在往坏的方向走"这件事在图上直接可见。
 * 首页活动报告、传感器详情页、实时状态页共用本组件。
 *
 * 额外支持把告警事件以红点画在图上（alerts + timeFrom/timeTo），
 * 点击红点通过 onAlertTap 回调给调用方弹详情。不传这三项时行为与原来完全一致。
 */
@Component
export struct TrendChart {
  // 数据变化后必须重绘：Canvas 的 onReady 只触发一次，
  // 不显式重绘的话切换时间范围会一直停在旧曲线上。
  @Prop @Watch('onPointsChanged') points: TrendPoint[];
  @Prop chartWidth: number = 320;
  @Prop chartHeight: number = 160;
  /** 折线颜色。活动报告用绿色（民生养老口的"健康"语义），默认沿用辅助青绿 */
  @Prop lineColor: string = AppColor.SECONDARY;
  /** 折线下方填充色。默认保持原有浅青，不影响既有调用方 */
  @Prop fillColor: string = 'rgba(46,125,107,0.12)';
  /**
   * 个性化基线值。传 0 时退化为"取本页数据均值"，
   * 兼容活动报告早期行为与实时状态页的传参。
   *
   * 语义区别：数据均值只描述"这段时间的平均"，
   * 个性化基线是老人自己的长期习惯，两者在图上的意义完全不同。
   */
  @Prop baseline: number = 0;
  /** 基线颜色。默认琥珀，活动报告按配色规范改用黄色 */
  @Prop baselineColor: string = 'rgba(224,138,0,0.55)';
  /** 是否在基线右端标注数值（如 "37.6"）。屏幕放不下时不必强标 */
  @Prop showBaselineLabel: boolean = false;
  /** 统计窗口起始时间戳。配合 timeTo 把告警时间映射到 X 轴 */
  @Prop timeFrom: number = 0;
  /** 统计窗口结束时间戳 */
  @Prop timeTo: number = 0;
  @Prop scaleToData: boolean = false;
  @Prop gapMs: number = 0;
  /** 窗口内的告警事件，以红点标记在图上 */
  @Prop alerts: Alert[] = [];
  /**
   * 点击红点的回调，由调用方负责弹详情。
   * 刻意不加 @Prop：ArkTS 的 @Prop 不能修饰函数型变量（API 23 起直接报错），
   * 与 AlertCard.onOpen 保持同样的普通成员写法。
   */
  onAlertTap: (alert: Alert) => void = () => {
  };

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  /** Canvas 是否已完成首次就绪。未就绪时 draw() 会被 onReady 兜住 */
  private canvasReady: boolean = false;

  private readonly padLeft: number = 34;
  private readonly padRight: number = 12;
  private readonly padTop: number = 14;
  private readonly padBottom: number = 22;

  /** points 变化时的回调：重绘 */
  onPointsChanged(): void {
    if (this.canvasReady) {
      this.draw();
    }
  }

  build() {
    // 圆角与底色移到 Stack 上：红点要覆盖在 Canvas 之上，
    // 若继续挂在 Canvas 上，红点会被裁到 Canvas 边界之外。
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.ctx)
        .width(this.chartWidth)
        .height(this.chartHeight)
        .onReady(() => {
          this.canvasReady = true;
          this.draw();
        })

      ForEach(this.alerts, (a: Alert) => {
        this.alertDot(a)
      }, (a: Alert) => a.alertId)
    }
    .width(this.chartWidth)
    .height(this.chartHeight)
    .backgroundColor(AppColor.SURFACE)
    .borderRadius(AppSize.SMALL_RADIUS)
  }

  /**
   * 告警事件红点。
   *
   * 两个设计取舍：
   * 1. 固定在绘图区顶部，而不是按 triggerValue 映射到 Y。事件型告警
   *    （SOS、长时间无活动）没有连续量，按值映射会落到基线附近几乎看不见；
   * 2. 命中区域做成 28×28 但只有中间 9px 是实心点，兼顾"看得见"与"点得中"。
   */
  @Builder
  alertDot(alert: Alert) {
    Row() {
      Row()
        .width(9)
        .height(9)
        .borderRadius(4.5)
        .backgroundColor(AppColor.DANGER)
        .shadow({ radius: 5, color: 'rgba(198,40,40,0.45)', offsetX: 0, offsetY: 1 })
    }
    .width(28)
    .height(28)
    .justifyContent(FlexAlign.Center)
    // Row 的 alignItems 只接受 VerticalAlign，写成 HorizontalAlign 会直接编译失败
    .alignItems(VerticalAlign.Center)
    .position({ x: this.alertX(alert) - 14, y: this.padTop - 5 })
    .onClick(() => {
      this.onAlertTap(alert);
    })
  }

  /** 告警时间 → 绘图区 X 坐标。窗口外的时间会被夹到边界内 */
  private alertX(alert: Alert): number {
    return this.xForTime(alert.timestamp);
  }

  private xForTime(timestamp: number): number {
    const span: number = this.timeTo - this.timeFrom;
    if (span <= 0) {
      return this.padLeft;
    }
    const t: number = Math.max(this.timeFrom, Math.min(this.timeTo, timestamp));
    const plotW: number = this.chartWidth - this.padLeft - this.padRight;
    return this.padLeft + ((t - this.timeFrom) / span) * plotW;
  }

  /**
   * X 轴标签。
   * 支持两种上游格式：'yyyy-MM-dd'（取 MM-dd）与 'HH:mm'（原样显示）。
   * 早先直接 substring(5) 会把小时制标签截成空串。
   */
  private xLabel(i: number): string {
    const d: string = this.points[i].date;
    return d.length === 10 ? d.substring(5) : d;
  }

  private draw(): void {
    const w: number = this.chartWidth;
    const h: number = this.chartHeight;
    this.ctx.clearRect(0, 0, w, h);

    const n: number = this.points.length;
    if (n === 0) {
      this.ctx.fillStyle = AppColor.TEXT_3;
      this.ctx.font = '12px sans-serif';
      this.ctx.textAlign = 'center';
      this.ctx.fillText('暂无趋势数据', w / 2, h / 2);
      return;
    }

    const plotW: number = w - this.padLeft - this.padRight;
    const plotH: number = h - this.padTop - this.padBottom;

    // Y 轴上限：取最大值上浮 15%，保证曲线不贴顶
    let minV: number = this.points[0].count;
    let maxV: number = minV;
    let sum: number = 0;
    for (const p of this.points) {
      maxV = Math.max(maxV, p.count);
      minV = Math.min(minV, p.count);
      sum += p.count;
    }
    if (this.scaleToData) {
      const pad: number = Math.max(0.2, (maxV - minV) * 0.15);
      minV -= pad;
      maxV += pad;
    } else {
      minV = Math.min(0, minV);
      maxV = Math.max(1, Math.ceil(maxV * 1.15));
    }
    const ySpan: number = maxV - minV;
    const avg: number = this.baseline > 0 ? this.baseline : sum / n;

    // Y 轴刻度
    this.ctx.fillStyle = AppColor.TEXT_3;
    this.ctx.font = '10px sans-serif';
    this.ctx.textAlign = 'right';
    for (let i = 0; i <= 4; i++) {
      const v: number = Math.round((minV + ySpan * i / 4) * 10) / 10;
      const y: number = this.padTop + plotH - (plotH * i / 4);
      this.ctx.fillText(`${v}`, this.padLeft - 6, y + 3);
      // 网格线
      this.ctx.strokeStyle = 'rgba(26,29,33,0.08)';
      this.ctx.lineWidth = 1;
      this.ctx.beginPath();
      this.ctx.moveTo(this.padLeft, y);
      this.ctx.lineTo(w - this.padRight, y);
      this.ctx.stroke();
    }

    // 基线基准线（虚线）
    // Y 轴上限要把基线一起纳入：个性化基线高于本页最高值时，
    // 不扩上限会把基线画到绘图区外，用户看到的图与"基线"二字对不上。
    const baseY: number = this.padTop + plotH - (Math.max(minV, Math.min(avg, maxV)) - minV) / ySpan * plotH;
    this.ctx.strokeStyle = this.baselineColor;
    this.ctx.lineWidth = 1;
    this.ctx.setLineDash([5, 4]);
    this.ctx.beginPath();
    this.ctx.moveTo(this.padLeft, baseY);
    this.ctx.lineTo(w - this.padRight, baseY);
    this.ctx.stroke();
    this.ctx.setLineDash([]);

    // 基线数值标注：贴右端内侧，避免被圆角裁掉
    if (this.showBaselineLabel) {
      this.ctx.fillStyle = this.baselineColor;
      this.ctx.font = '10px sans-serif';
      this.ctx.textAlign = 'right';
      this.ctx.fillText(`${Math.round(avg * 10) / 10}`, w - this.padRight - 2, baseY - 4);
    }

    // 折线路径
    const stepX: number = n > 1 ? plotW / (n - 1) : plotW;
    const xs: number[] = [];
    const ys: number[] = [];
    for (let i = 0; i < n; i++) {
      const timestamp = this.points[i].timestamp;
      xs.push(timestamp !== undefined && this.timeTo > this.timeFrom
        ? this.xForTime(timestamp)
        : this.padLeft + i * stepX);
      ys.push(this.padTop + plotH - ((this.points[i].count - minV) / ySpan) * plotH);
    }

    if (this.gapMs === 0) {
      const grad = this.ctx.createLinearGradient(0, this.padTop, 0, this.padTop + plotH);
      grad.addColorStop(0, this.fillColor);
      grad.addColorStop(1, 'rgba(255,255,255,0)');
      this.ctx.beginPath();
      this.ctx.moveTo(xs[0], this.padTop + plotH);
      for (let i: number = 0; i < n; i++) {
        this.ctx.lineTo(xs[i], ys[i]);
      }
      this.ctx.lineTo(xs[n - 1], this.padTop + plotH);
      this.ctx.closePath();
      this.ctx.fillStyle = grad;
      this.ctx.fill();
    }

    this.ctx.beginPath();
    this.ctx.moveTo(xs[0], ys[0]);
    for (let i: number = 1; i < n; i++) {
      const gap: number = (this.points[i].timestamp ?? 0) - (this.points[i - 1].timestamp ?? 0);
      if (this.gapMs > 0 && gap > this.gapMs) {
        this.ctx.moveTo(xs[i], ys[i]);
      } else {
        this.ctx.lineTo(xs[i], ys[i]);
      }
    }
    this.ctx.strokeStyle = this.lineColor;
    this.ctx.lineWidth = 2.5;
    this.ctx.lineJoin = 'round';
    this.ctx.lineCap = 'round';
    this.ctx.stroke();

    // 数据点：最后一个点带白环高亮，其余用小圆点
    for (let i = 0; i < n; i++) {
      const isLast: boolean = i === n - 1;
      this.ctx.beginPath();
      this.ctx.arc(xs[i], ys[i], isLast ? 4.5 : 2.6, 0, Math.PI * 2);
      this.ctx.fillStyle = isLast ? AppColor.PRIMARY : this.lineColor;
      this.ctx.fill();
      if (isLast) {
        this.ctx.strokeStyle = '#FFFFFF';
        this.ctx.lineWidth = 2;
        this.ctx.stroke();
      }
    }

    // 末值标注：贴最后一个点上方，数据"最后一刻是多少"一眼可见
    const lastVal: number = this.points[n - 1].count;
    let ly: number = ys[n - 1] - 10;
    if (ly < this.padTop + 10) {
      ly = ys[n - 1] + 18;
    }
    this.ctx.fillStyle = AppColor.PRIMARY;
    this.ctx.font = 'bold 11px sans-serif';
    this.ctx.textAlign = 'center';
    const lastLabel: string = this.scaleToData ? lastVal.toFixed(2) : `${Math.round(lastVal * 10) / 10}`;
    this.ctx.fillText(lastLabel, xs[n - 1], ly);

    // X 轴日期标签（只标首、中、末）
    this.ctx.fillStyle = AppColor.TEXT_3;
    this.ctx.font = '10px sans-serif';
    this.ctx.textAlign = 'center';
    const labelIdx: number[] = [0, Math.floor((n - 1) / 2), n - 1];
    for (const i of labelIdx) {
      if (i === 0 || xs[i] - xs[0] >= 45 && (i === n - 1 || xs[n - 1] - xs[i] >= 45)) {
        this.ctx.fillText(this.xLabel(i), xs[i], h - 6);
      }
    }
  }
}
