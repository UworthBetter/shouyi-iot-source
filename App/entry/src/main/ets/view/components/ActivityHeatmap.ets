import { ActivityReport, HeatmapCell } from '../../model/ActivityRecord';
import { AppColor, AppSize } from '../../common/constants/ThemeColors';

/**
 * 活动时段分布热力图。
 *
 * 横轴 24 小时，纵轴日期，颜色深浅表示活动频次。
 * 一眼能看出老人的作息是否规律、有没有异常时段 —— 这是活动报告页的主视觉。
 *
 * 交互：点击任一格子，下方详情行给出「日期 + 时段 + 活动次数」。
 * 这样评委在现场点哪一格都能立刻得到解释，比只能"看个大概"更站得住。
 *
 * 用 Canvas 自绘，避免引入图表库依赖。
 */
@Component
export struct ActivityHeatmap {
  @Prop report: ActivityReport;
  @Prop chartWidth: number = 320;

  /** 当前选中的格子。组件内部自持，不交给外部同步 —— 避免父子双向同步的时序坑 */
  @State selected: HeatmapCell | undefined = undefined;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  /**
   * 单元格尺寸。
   *
   * 取值由宽度预算反推，不是随手定的：一屏内容宽度 375，去掉页面边距 32
   * 与卡片内边距 32 后可用 311；24 个小时列加上左侧日期标注必须塞进这个数。
   *   labelW 40 + 24 × (cellW 10 + gap 1) = 304 ≤ 311
   * 早先 cellW 12 / gap 2 / labelW 44 算下来是 380 —— 右侧 4 个小时列
   * 被直接裁在 Canvas 外，月报的 23 点那几天永远是缺的。
   */
  private readonly cellW: number = 10;
  private readonly cellH: number = 16;
  private readonly gap: number = 1;
  private readonly labelW: number = 40;
  private readonly topH: number = 18;

  build() {
    Column() {
      // Stack 包裹 Canvas：点击坐标需要相对绘图区，
      // Canvas 自身不承载点击事件回调，挂在外层容器上最稳。
      Stack() {
        Canvas(this.ctx)
          .width(this.chartWidth)
          .height(this.canvasHeight())
          .backgroundColor(AppColor.SURFACE)
          .borderRadius(AppSize.SMALL_RADIUS)
          .onReady(() => {
            this.draw();
          })
      }
      .width(this.chartWidth)
      .onClick((event: ClickEvent) => {
        this.onTap(event.x, event.y);
      })

      this.readout()
    }
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 选格详情文案。未选中时给操作提示，选中时给「日期 + 时段 + 次数」。
   *
   * 抽成方法而不是写在 @Builder 里：@Builder 只允许 UI 组件语法，
   * 里面不能声明局部变量（本次改造第一个编译错误就是踩在这里）。
   */
  private readoutText(): string {
    const cell: HeatmapCell | undefined = this.selected;
    if (cell === undefined) {
      return '点击任意格子，查看当日该时段的活动次数';
    }
    return `${cell.date} ${cell.hour}:00 - ${cell.hour + 1}:00 · 活动 ${cell.count} 次`;
  }

  @Builder
  readout() {
    Text(this.readoutText())
      .fontSize(AppSize.SMALL_FONT)
      .fontColor(this.selected !== undefined ? AppColor.TEXT_2 : AppColor.TEXT_3)
      .margin({ top: 8 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width(this.chartWidth)
  }

  private canvasHeight(): number {
    const days: number = this.report.daily.length > 0 ? this.report.daily.length : 7;
    return this.topH + days * (this.cellH + this.gap) + 8;
  }

  /**
   * 点击命中判定：把组件坐标换算成（第几天，第几小时）。
   *
   * 只认绘图区内的落点：落在左侧日期标签列或顶部小时刻度上时忽略，
   * 否则点空白也会弹出一个"次数 0"，看起来像 bug。
   */
  private onTap(x: number, y: number): void {
    const dates: string[] = this.report.daily.map((d) => d.date);
    if (dates.length === 0) {
      return;
    }
    const innerX: number = x - this.labelW;
    const innerY: number = y - this.topH;
    if (innerX < 0 || innerY < 0) {
      this.selected = undefined;
      return;
    }
    const hour: number = Math.floor(innerX / (this.cellW + this.gap));
    const dayIndex: number = Math.floor(innerY / (this.cellH + this.gap));
    if (hour < 0 || hour > 23 || dayIndex < 0 || dayIndex >= dates.length) {
      this.selected = undefined;
      return;
    }
    const date: string = dates[dayIndex];
    let count: number = 0;
    for (const c of this.report.heatmap) {
      if (c.date === date && c.hour === hour) {
        count = c.count;
        break;
      }
    }
    this.selected = { date: date, hour: hour, count: count } as HeatmapCell;
  }

  private draw(): void {
    const w: number = this.chartWidth;
    const h: number = this.canvasHeight();
    this.ctx.clearRect(0, 0, w, h);

    const dates: string[] = this.report.daily.map((d) => d.date);
    if (dates.length === 0) {
      this.ctx.fillStyle = AppColor.TEXT_3;
      this.ctx.font = '12px sans-serif';
      this.ctx.textAlign = 'center';
      this.ctx.fillText('暂无活动数据', w / 2, h / 2);
      return;
    }

    // 建立 日期-小时 -> 次数 的索引
    const map: Map<string, number> = new Map<string, number>();
    for (const c of this.report.heatmap) {
      map.set(`${c.date}#${c.hour}`, c.count);
    }
    const maxCount: number = this.report.maxHeatmapCount > 0 ? this.report.maxHeatmapCount : 1;

    // 顶部小时刻度（每 3 小时标一次）
    this.ctx.fillStyle = AppColor.TEXT_3;
    this.ctx.font = '10px sans-serif';
    this.ctx.textAlign = 'center';
    for (let hour = 0; hour < 24; hour += 3) {
      const x: number = this.labelW + hour * (this.cellW + this.gap) + this.cellW / 2;
      this.ctx.fillText(`${hour}`, x, 12);
    }

    // 逐日绘制
    for (let i = 0; i < dates.length; i++) {
      const date: string = dates[i];
      const y: number = this.topH + i * (this.cellH + this.gap);

      // 左侧日期标签（只标首末与每 5 天，避免拥挤）
      if (i === 0 || i === dates.length - 1 || i % 5 === 0) {
        this.ctx.fillStyle = AppColor.TEXT_3;
        this.ctx.font = '10px sans-serif';
        this.ctx.textAlign = 'right';
        this.ctx.fillText(date.substring(5), this.labelW - 6, y + this.cellH / 2 + 3);
      }

      for (let hour = 0; hour < 24; hour++) {
        const count: number = map.get(`${date}#${hour}`) ?? 0;
        const x: number = this.labelW + hour * (this.cellW + this.gap);
        this.ctx.fillStyle = this.colorOf(count, maxCount);
        this.ctx.fillRect(x, y, this.cellW, this.cellH);
      }
    }

    this.drawSelection(dates);
  }

  /**
   * 选中格子的描边。
   *
   * 选中框必须在所有格子之后画：Canvas 没有图层概念，先画的会被后画的盖掉。
   * 用深色描边而非彩色 —— 格子本身已经是彩色强度编码，描边只负责"选中"这一件事。
   */
  private drawSelection(dates: string[]): void {
    const cell: HeatmapCell | undefined = this.selected;
    if (cell === undefined) {
      return;
    }
    const dayIndex: number = dates.indexOf(cell.date);
    if (dayIndex < 0) {
      return;
    }
    const x: number = this.labelW + cell.hour * (this.cellW + this.gap);
    const y: number = this.topH + dayIndex * (this.cellH + this.gap);
    this.ctx.strokeStyle = AppColor.TEXT;
    this.ctx.lineWidth = 2;
    this.ctx.strokeRect(x - 1, y - 1, this.cellW + 2, this.cellH + 2);
  }

  /**
   * 颜色映射：绿 → 深蓝四级梯度，活动越多越深。
   *
   * 为什么用绿而不继续用青：这一页的"正常"信号统一是绿色
   * （折线、基线圆点、偏离度文字都是绿），热力图若另用一个色相，
   * 同一块屏幕会出现两种"正常"，路演时讲解要多绕一句。
   * 最深一级压到深蓝，保证夜间密集时段在投屏上仍然压得住、看得清。
   */
  private colorOf(count: number, maxCount: number): string {
    if (count <= 0) {
      return 'rgba(26,29,33,0.05)';
    }
    const ratio: number = Math.min(1, count / maxCount);
    if (ratio < 0.25) {
      return 'rgba(46,125,50,0.30)';      // 浅绿
    }
    if (ratio < 0.5) {
      return 'rgba(46,125,50,0.58)';      // 绿
    }
    if (ratio < 0.75) {
      return 'rgba(35,110,95,0.78)';      // 绿蓝过渡
    }
    return 'rgba(31,58,95,0.94)';         // 深蓝
  }
}
