/**
 * 活动数据模型。
 * 原始数据是 PIR 触发事件，聚合为小时级与日级，供报告与热力图使用。
 */

/** 小时级活动聚合 */
export class ActivityHourly {
  deviceId: string = '';
  /** 日期，yyyy-MM-dd */
  date: string = '';
  /** 小时 0-23 */
  hour: number = 0;
  /** 该小时触发次数 */
  count: number = 0;
  /** 该小时首次触发时间戳 */
  firstTriggered: number = 0;
  /** 该小时末次触发时间戳 */
  lastTriggered: number = 0;
}

/** 日级活动聚合 */
export class ActivityDaily {
  deviceId: string = '';
  /** 日期，yyyy-MM-dd */
  date: string = '';
  /** 当日时间戳（零点） */
  dayStart: number = 0;
  /** 当日总活动次数 */
  totalCount: number = 0;
  /** 活跃时段数（有活动的不同小时数） */
  activeHours: number = 0;
  /** 首次活动时间戳 */
  firstActivity: number = 0;
  /** 末次活动时间戳 */
  lastActivity: number = 0;
  /** 夜间活动次数（22:00-06:00） */
  nightCount: number = 0;
}

/** 热力图单元格 */
export class HeatmapCell {
  date: string = '';
  hour: number = 0;
  count: number = 0;
}

/** 趋势数据点 */
export class TrendPoint {
  timestamp?: number;
  date: string = '';
  count: number = 0;
}

/**
 * 活动规律报告。
 * 这是赛题"数据统计分析"要求的核心产物。
 */
export class ActivityReport {
  /** 周期：day / week / month */
  period: string = 'week';
  from: number = 0;
  to: number = 0;

  // ---------- 汇总 ----------
  totalCount: number = 0;
  avgDailyCount: number = 0;
  activeHours: number = 0;
  firstActivityTime: string = '';
  lastActivityTime: string = '';
  nightActivityCount: number = 0;

  // ---------- 趋势 ----------
  /** 方向：up / down / stable */
  trendDirection: string = 'stable';
  /** 变化百分比，负数表示下降 */
  changePercent: number = 0;
  /** 对比对象描述，如"上周" */
  compareWith: string = '';
  /**
   * 自然语言判断。
   * 关键设计：不只给数字，要给出判断 —— 赛题要求"帮助子女发现老人生活规律变化"，
   * 只给数字达不到这个要求。
   */
  insight: string = '';

  // ---------- 图表数据 ----------
  daily: TrendPoint[] = [];
  hourlyDistribution: number[] = new Array<number>(24).fill(0);
  heatmap: HeatmapCell[] = [];
  maxHeatmapCount: number = 1;

  // ---------- 个人基线 ----------
  baselineAvg: number = 0;
  baselineStdDev: number = 0;
  /** 偏离的标准差倍数，负值表示低于基线 */
  deviation: number = 0;
  /** 是否偏离基线异常 */
  baselineAbnormal: boolean = false;
}

/**
 * 个人活动基线。
 *
 * 设计要点：以最近 N 天建立**这位老人自己**的活动基线，
 * 而不是用固定阈值。每个老人作息习惯不同，固定阈值必然大量误报。
 */
export class ActivityBaseline {
  /** 基线日均活动次数 */
  avgDailyCount: number = 0;
  /** 标准差 */
  stdDev: number = 0;
  /** 各小时的平均活动次数（24 项） */
  hourlyAvg: number[] = new Array<number>(24).fill(0);
  /** 参与计算的样本天数 */
  sampleDays: number = 0;
  /** 基线是否有效（样本不足时无效） */
  valid: boolean = false;
}
