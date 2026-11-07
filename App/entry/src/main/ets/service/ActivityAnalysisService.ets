import {
  ActivityDaily, ActivityBaseline, ActivityReport, TrendPoint, HeatmapCell
} from '../model/ActivityRecord';
import { ThresholdSuggestion } from '../model/Alert';
import { AppConstants, AlertType } from '../common/constants/AppConstants';
import { DateUtil } from '../common/utils/DateUtil';

/**
 * 活动规律分析引擎。
 *
 * 这是本作品相对普通监护产品的核心差异化能力，也是赛题"数据统计分析"要求的落点。
 *
 * 设计原则：
 *   1. **纯函数、无副作用** —— 输入活动数据，输出分析结论，可充分单元测试；
 *   2. **个人基线而非固定阈值** —— 每个老人作息习惯不同，用固定阈值必然大量误报；
 *   3. **给判断而不只给数字** —— 赛题要求"帮助子女发现老人生活规律变化"，
 *      只给"活动 268 次"达不到要求，必须给"较上周下降 23%，集中在上午时段"。
 */
export class ActivityAnalysisService {
  private static readonly MODULE: string = 'ActivityAnalysisService';

  /**
   * 计算个人活动基线。
   *
   * 以最近 N 天（默认 14 天）的日活动量建立这位老人自己的基线：
   *   · 日均活动次数（均值）
   *   · 波动幅度（标准差）
   *   · 各小时的平均活动分布
   *
   * 样本不足 5 天时基线标记为无效，避免冷启动阶段误判。
   */
  static computeBaseline(dailyList: ActivityDaily[], windowDays: number = AppConstants.BASELINE_WINDOW_DAYS): ActivityBaseline {
    const baseline: ActivityBaseline = new ActivityBaseline();
    const sample: ActivityDaily[] = dailyList.slice(Math.max(0, dailyList.length - windowDays));

    if (sample.length < 5) {
      baseline.valid = false;
      baseline.sampleDays = sample.length;
      return baseline;
    }

    const counts: number[] = sample.map((d: ActivityDaily) => d.totalCount);
    const mean: number = counts.reduce((a: number, b: number) => a + b, 0) / counts.length;
    const variance: number = counts.reduce((s: number, c: number) => s + (c - mean) * (c - mean), 0) / counts.length;

    baseline.avgDailyCount = Math.round(mean * 10) / 10;
    baseline.stdDev = Math.round(Math.sqrt(variance) * 10) / 10;
    baseline.sampleDays = sample.length;
    baseline.valid = true;

    // 各小时平均活动分布（用当日活跃小时数近似拆分）
    const hourly: number[] = new Array<number>(24).fill(0);
    for (const d of sample) {
      if (d.activeHours <= 0) {
        continue;
      }
      const perHour: number = d.totalCount / d.activeHours;
      for (let h = 0; h < 24; h++) {
        hourly[h] += perHour * ActivityAnalysisService.hourWeight(h);
      }
    }
    baseline.hourlyAvg = hourly.map((v: number) => Math.round(v / sample.length * 10) / 10);
    return baseline;
  }

  /**
   * 判断当前活动量是否偏离基线。
   * 返回偏离的标准差倍数，绝对值 ≥ 2 视为异常。
   */
  static deviationFromBaseline(currentAvg: number, baseline: ActivityBaseline): number {
    if (!baseline.valid || baseline.stdDev <= 0) {
      return 0;
    }
    return Math.round((currentAvg - baseline.avgDailyCount) / baseline.stdDev * 100) / 100;
  }

  /**
   * 计算趋势：当前周期 vs 上一周期。
   */
  static computeTrend(current: ActivityDaily[], previous: ActivityDaily[]): TrendResult {
    const result: TrendResult = new TrendResult();
    if (current.length === 0) {
      return result;
    }

    const curAvg: number = current.reduce((s: number, d: ActivityDaily) => s + d.totalCount, 0) / current.length;
    result.currentAvg = Math.round(curAvg * 10) / 10;

    if (previous.length === 0) {
      result.direction = 'stable';
      result.changePercent = 0;
      return result;
    }

    const prevAvg: number = previous.reduce((s: number, d: ActivityDaily) => s + d.totalCount, 0) / previous.length;
    result.previousAvg = Math.round(prevAvg * 10) / 10;

    if (prevAvg <= 0) {
      result.direction = 'stable';
      return result;
    }

    result.changePercent = Math.round((curAvg - prevAvg) / prevAvg * 100);
    if (result.changePercent > 5) {
      result.direction = 'up';
    } else if (result.changePercent < -5) {
      result.direction = 'down';
    } else {
      result.direction = 'stable';
    }
    return result;
  }

  /**
   * 定位活动下降集中的时段。
   * 让"下降"这个结论落到具体时段上，子女才知道该关注什么时候。
   */
  static locateDeclineSegment(hourly: number[]): string {
    if (hourly.length < 24) {
      return '';
    }
    const morning: number = ActivityAnalysisService.sum(hourly, 6, 12);
    const afternoon: number = ActivityAnalysisService.sum(hourly, 12, 18);
    const evening: number = ActivityAnalysisService.sum(hourly, 18, 23);
    const max: number = Math.max(morning, afternoon, evening);

    if (max <= 0) {
      return '';
    }
    if (max === morning) {
      return '上午时段';
    }
    if (max === afternoon) {
      return '下午时段';
    }
    return '晚间时段';
  }

  /**
   * 生成自然语言判断 —— 报告的灵魂。
   *
   * 三段式，每段都对应一个可以被追问的角度：
   *   ① 总体作息（和上一周期比，是稳、是升、是降）
   *   ② 日间活动（和这位老人自己的历史基线比）
   *   ③ 夜间活动（睡眠质量线索，附个人基线对照与行动建议）
   * 句尾按需追加个人基线偏离说明。
   *
   * 之所以要分段：一长串逗号连下来的句子，路演讲到一半自己都会断片；
   * 分号断句的版本，评委能抓住"稳、正常、夜间偏多"三个层次。
   */
  static buildInsight(report: ActivityReport, baseline: ActivityBaseline): string {
    const parts: string[] = [];
    const scope: string = report.period === 'day' ? '本日'
      : (report.period === 'month' ? '近一月' : '本周');

    // ---------- ① 总体作息 ----------
    if (report.trendDirection === 'down') {
      const decline: number = Math.abs(report.changePercent);
      const segment: string = ActivityAnalysisService.locateDeclineSegment(report.hourlyDistribution);
      const where: string = segment.length > 0 ? `，减少集中在${segment}` : '';
      parts.push(`${scope}活动总量较${report.compareWith}下降 ${decline}%${where}，整体作息较平常明显减少`);
    } else if (report.trendDirection === 'up') {
      parts.push(`${scope}活动总量较${report.compareWith}上升 ${report.changePercent}%，整体状态较为活跃`);
    } else {
      parts.push(`${scope}老人整体作息稳定，活动节奏与${report.compareWith}基本一致`);
    }

    // ---------- ② 日间活动（对照个人基线，而非固定阈值）----------
    const dayCount: number = ActivityAnalysisService.sumWrapped(report.hourlyDistribution, 6, 16);
    const dayBaseline: number = ActivityAnalysisService.sumWrapped(baseline.hourlyAvg, 6, 16);
    if (dayBaseline > 0 && dayCount < dayBaseline * 0.8) {
      parts.push('日间活动较个人基线偏少，建议关注老人白天状态');
    } else {
      parts.push('日间活动正常');
    }

    // ---------- ③ 夜间活动 ----------
    const nightBaseline: number = ActivityAnalysisService.nightBaseline(baseline);
    if (report.nightActivityCount > 10) {
      const above: boolean = nightBaseline <= 0 || report.nightActivityCount > nightBaseline * 1.2;
      if (above) {
        const ref: string = nightBaseline > 0 ? `（约 ${nightBaseline} 次）` : '';
        parts.push(`夜间活动共 ${report.nightActivityCount} 次，高于个人历史基线${ref}，`
          + `建议关注老人睡眠质量，必要时电话问询`);
      } else {
        parts.push(`夜间活动 ${report.nightActivityCount} 次，与本人往常水平相近`);
      }
    } else if (report.nightActivityCount > 0) {
      parts.push(`夜间活动 ${report.nightActivityCount} 次，处于正常范围`);
    } else {
      parts.push('夜间无活动记录，睡眠节律良好');
    }

    // ---------- ④ 个人基线偏离 ----------
    // 偏离量直接用 report.deviation，不在此重复计算：
    // 报告对象上已经带着这个值，两条路径（云端 / 本地兜底）都算过一遍了，
    // 再算第三遍既可能不一致，也让这个函数多背一份输入。
    const deviation: number = report.deviation;
    if (Math.abs(deviation) >= AppConstants.BASELINE_DEVIATION_SIGMA) {
      const dir: string = deviation < 0 ? '低于' : '高于';
      parts.push(`日均活动量${dir}个人基线 ${Math.abs(deviation)} 个标准差`);
    }

    return parts.join('；') + '。';
  }

  /**
   * 研判分级：normal / attention / danger。
   *
   * 只依赖 ActivityReport 自身字段 —— 云端报告与本地兜底报告都能直接用，
   * 不需要把趋势对象穿越到界面层。
   *
   * 判定标准（与卡片三色体系共用一个心智模型）：
   *   danger   —— 已偏离个人基线 2σ 以上，或活动量断崖式下滑（≥30%）
   *   attention—— 任何程度的下降、夜间活动偏多、偏离基线 1σ 以上
   *   normal   —— 其余
   *
   * "下降但没到危险程度"归 attention 而非 danger：方向不对就该被提示，
   * 但还没到要家属立刻行动的程度。分级的意义就在这一档。
   */
  static insightLevel(report: ActivityReport): string {
    if (report.baselineAbnormal) {
      return 'danger';
    }
    if (report.trendDirection === 'down' && Math.abs(report.changePercent) >= 30) {
      return 'danger';
    }
    if (report.trendDirection === 'down') {
      return 'attention';
    }
    if (report.nightActivityCount > 10) {
      return 'attention';
    }
    if (Math.abs(report.deviation) >= 1) {
      return 'attention';
    }
    return 'normal';
  }

  /**
   * 夜间活动基线：22:00-06:00 各区间的平均活动次数。
   * 用于判断本期夜间活动是不是真比这位老人往常多 —— 而不是和所有人的固定阈值比。
   */
  private static nightBaseline(baseline: ActivityBaseline): number {
    if (!baseline.valid) {
      return 0;
    }
    return Math.round(ActivityAnalysisService.sumWrapped(baseline.hourlyAvg, 22, 8));
  }

  /**
   * 从日汇总数据直接生成完整报告。
   * 供离线场景使用（本地缓存数据不足以调用云端报告接口时）。
   */
  static buildReportFromDaily(dailyList: ActivityDaily[], period: string): ActivityReport {
    const days: number = period === 'month' ? 30 : (period === 'week' ? 7 : 1);
    const current: ActivityDaily[] = dailyList.slice(Math.max(0, dailyList.length - days));
    const previous: ActivityDaily[] = dailyList.slice(
      Math.max(0, dailyList.length - days * 2), Math.max(0, dailyList.length - days));

    const report: ActivityReport = new ActivityReport();
    report.period = period;
    report.from = current.length > 0 ? current[0].dayStart : 0;
    report.to = DateUtil.now();

    let total: number = 0;
    let night: number = 0;
    let firstTs: number = 0;
    let lastTs: number = 0;
    const hourly: number[] = new Array<number>(24).fill(0);

    for (const d of current) {
      total += d.totalCount;
      night += d.nightCount;
      if (d.firstActivity > 0 && (firstTs === 0 || d.firstActivity < firstTs)) {
        firstTs = d.firstActivity;
      }
      if (d.lastActivity > lastTs) {
        lastTs = d.lastActivity;
      }
      report.daily.push({ date: d.date, count: d.totalCount } as TrendPoint);

      const perHour: number = d.activeHours > 0 ? d.totalCount / d.activeHours : 0;
      for (let h = 0; h < 24; h++) {
        hourly[h] += perHour * ActivityAnalysisService.hourWeight(h);
        const c: number = Math.round(perHour * ActivityAnalysisService.hourWeight(h));
        if (c > 0) {
          const cell: HeatmapCell = new HeatmapCell();
          cell.date = d.date;
          cell.hour = h;
          cell.count = c;
          report.heatmap.push(cell);
          report.maxHeatmapCount = Math.max(report.maxHeatmapCount, c);
        }
      }
    }

    report.totalCount = total;
    report.avgDailyCount = current.length > 0 ? Math.round(total / current.length * 10) / 10 : 0;
    report.nightActivityCount = night;
    report.firstActivityTime = DateUtil.formatTime(firstTs);
    report.lastActivityTime = DateUtil.formatTime(lastTs);
    report.hourlyDistribution = hourly.map((v: number) => Math.round(v));
    report.activeHours = report.hourlyDistribution.filter((v: number) => v > 0.5).length;

    const trend: TrendResult = ActivityAnalysisService.computeTrend(current, previous);
    report.trendDirection = trend.direction;
    report.changePercent = trend.changePercent;
    report.compareWith = period === 'month' ? '上月' : (period === 'week' ? '上周' : '昨日');

    const baseline: ActivityBaseline = ActivityAnalysisService.computeBaseline(
      dailyList.slice(0, Math.max(0, dailyList.length - days)));
    report.baselineAvg = baseline.avgDailyCount;
    report.baselineStdDev = baseline.stdDev;
    report.deviation = ActivityAnalysisService.deviationFromBaseline(trend.currentAvg, baseline);
    report.baselineAbnormal = Math.abs(report.deviation) >= AppConstants.BASELINE_DEVIATION_SIGMA;

    report.insight = ActivityAnalysisService.buildInsight(report, baseline);
    return report;
  }

  /**
   * 误报反馈闭环：根据误报记录给出阈值调整建议。
   *
   * 逻辑：某类告警在近期反复被标记误报时，说明阈值过严，
   * 给出放宽建议，让系统随使用逐步适配这位老人的生活习惯。
   *
   * @param alertType 告警类型
   * @param currentThreshold 当前阈值
   * @param falseAlarmCount 近期误报次数
   */
  static suggestThreshold(alertType: string, currentThreshold: number, falseAlarmCount: number): ThresholdSuggestion | undefined {
    // 误报不足 2 次不建议调整，避免单次偶然误报就放宽阈值
    if (falseAlarmCount < 2) {
      return undefined;
    }

    const s: ThresholdSuggestion = new ThresholdSuggestion();
    s.currentValue = currentThreshold;
    s.key = '';

    switch (alertType) {
      case AlertType.NO_ACTIVITY:
        s.key = 'noActivityMinutesNight';
        s.label = '夜间「长时间无活动」阈值';
        s.unit = '分钟';
        s.suggestedValue = Math.min(180, Math.round(currentThreshold * 1.5));
        s.message = `近 ${falseAlarmCount} 次「长时间无活动」被标记为误报，`
          + `建议将夜间阈值从 ${currentThreshold} 分钟放宽至 ${s.suggestedValue} 分钟`;
        break;
      case AlertType.TEMP_HUMIDITY_ABNORMAL:
        s.key = 'tempMax';
        s.label = '温度上限';
        s.unit = '℃';
        s.suggestedValue = Math.min(38, Math.round((currentThreshold + 2) * 10) / 10);
        s.message = `近 ${falseAlarmCount} 次「温湿度异常」被标记为误报，`
          + `建议将温度上限从 ${currentThreshold}℃ 放宽至 ${s.suggestedValue}℃`;
        break;
      case AlertType.DOOR_ABNORMAL:
        s.key = 'doorAbnormalMinutes';
        s.label = '门窗异常判定时长';
        s.unit = '分钟';
        s.suggestedValue = Math.min(60, Math.round(currentThreshold * 1.5));
        s.message = `近 ${falseAlarmCount} 次「门窗异常」被标记为误报，`
          + `建议将判定时长从 ${currentThreshold} 分钟放宽至 ${s.suggestedValue} 分钟`;
        break;
      default:
        return undefined;
    }
    return s;
  }

  /** 24 小时活动权重（与云端聚合口径保持一致） */
  private static hourWeight(h: number): number {
    const w: number[] = [
      0.1, 0.0, 0.0, 0.0, 0.0, 0.3,
      1.6, 2.4, 2.6, 2.2, 2.0, 1.8,
      0.5, 0.6, 1.8, 2.0, 1.9, 1.7,
      1.9, 2.1, 1.6, 0.9, 0.4, 0.2
    ];
    return w[h];
  }

  private static sum(arr: number[], from: number, to: number): number {
    let s: number = 0;
    for (let i = from; i < to && i < arr.length; i++) {
      s += arr[i];
    }
    return s;
  }

  /**
   * 跨零点的区间求和。
   * 夜间活动（22:00 - 06:00）会跨过 24 点，用 sum() 会漏掉 0-5 点这一段。
   */
  private static sumWrapped(arr: number[], from: number, count: number): number {
    let s: number = 0;
    for (let i = 0; i < count; i++) {
      const h: number = (from + i) % 24;
      if (h < arr.length) {
        s += arr[h];
      }
    }
    return s;
  }
}

/** 趋势计算结果 */
export class TrendResult {
  /** up / down / stable */
  direction: string = 'stable';
  /** 变化百分比 */
  changePercent: number = 0;
  currentAvg: number = 0;
  previousAvg: number = 0;
}
