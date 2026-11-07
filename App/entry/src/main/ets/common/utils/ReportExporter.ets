import { ActivityReport } from '../../model/ActivityRecord';
import { Alert, SafetyLogEntry } from '../../model/Alert';
import { AlertLevel, AlertStatus } from '../constants/AppConstants';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DateUtil } from './DateUtil';
import { Logger } from './Logger';

/**
 * 报告导出。
 *
 * 场景：子女或社区要把一份老人活动报告留存交接 ——
 * 发微信、发邮件、存到文件管理，都是高频需求，路演时也是加分项。
 *
 * 实现选型（为什么不直接生成 PDF）：
 *   HarmonyOS 生成 PDF 需要 @kit.PDFKit，它依赖独立的 ohos pdfkit npm 包，
 *   本工程未引入该依赖。硬加一条与业务无关的供应链，对当前阶段收益不成比例。
 *   因此落地为：**生成一份结构化报告文本，调起系统分享面板**。
 *   在分享面板里选「打印」，即可由系统另存为 PDF —— 对纯文本这是最稳的路径。
 *
 * 两种用法：
 *   - ReportExporter.buildText()  只取文本（单元验证、后续接 PDF 都能复用）
 *   - ReportExporter.share()      直接拉起分享面板
 */
export class ReportExporter {
  private static readonly MODULE: string = 'ReportExporter';

  /** 周期 key → 报告名 */
  static titleOf(period: string): string {
    switch (period) {
      case 'day':
        return '活动日报';
      case 'month':
        return '活动月报';
      default:
        return '活动周报';
    }
  }

  /** 周期 key → 「统计周期」一行的说明 */
  static periodDesc(period: string): string {
    switch (period) {
      case 'day':
        return '本日 00:00 至当前';
      case 'month':
        return '近 30 个自然日';
      default:
        return '近 7 个自然日';
    }
  }

  /**
   * 生成完整报告文本。
   *
   * 段落顺序与界面一致：周期 → 活动总量 → 作息特征 → 智能研判 → 个人基线 → 口径说明。
   * 用纯文本、不用富文本标记，保证任何接收方（微信、邮件、笔记）都不会解析出乱码。
   */
  static buildText(report: ActivityReport, elderName: string): string {
    const title: string = ReportExporter.titleOf(report.period);
    const lines: string[] = [];

    lines.push('守颐 · 独居老人智能监护系统');
    lines.push(`${elderName} · ${title}`);
    lines.push('');
    lines.push('──────────────────────');
    lines.push(`统计周期：${ReportExporter.periodDesc(report.period)}`);
    lines.push(`报告生成：${DateUtil.format(DateUtil.now())}`);
    lines.push('');

    lines.push('一、活动总量');
    lines.push(`  活动总次数：${report.totalCount} 次`);
    lines.push(`  日均活动频次：${report.avgDailyCount} 次`);
    lines.push('');

    lines.push('二、作息特征');
    lines.push(`  活跃时段：${report.activeHours} 个`);
    lines.push(`  夜间活动：${report.nightActivityCount} 次`);
    lines.push(`  首次活动：${report.firstActivityTime.length > 0 ? report.firstActivityTime : '本期无活动记录'}`);
    lines.push(`  末次活动：${report.lastActivityTime.length > 0 ? report.lastActivityTime : '本期无活动记录'}`);
    lines.push('');

    lines.push('三、智能研判');
    lines.push(`  ${report.insight}`);
    lines.push('');

    if (report.baselineAvg > 0) {
      lines.push('四、个人基线');
      lines.push(`  基线日均：${report.baselineAvg} 次（波动 ±${report.baselineStdDev}）`);
      const sign: string = report.deviation > 0 ? '+' : '';
      lines.push(`  当前偏离：${sign}${report.deviation}σ`);
      lines.push('  基线说明：以最近 14 天数据建立，反映老人自身作息习惯，而非统一阈值。');
      lines.push('');
    }

    lines.push('──────────────────────');
    lines.push('口径说明：夜间活动统计区间为 22:00 - 06:00。');
    lines.push('报告中的"夜间活动偏多""活动量下降"等提示仅为健康参考，非紧急告警。');
    lines.push('如收到紧急告警，请以 App 预警中心与电话通知为准。');

    return lines.join('\n');
  }

  /**
   * 拉系统分享面板导出活动报告。
   *
   * 单条 plain-text 记录 + SINGLE 选择模式：最稳妥的组合，
   * 任何支持接收文本的应用（微信、邮件、备忘录、文件管理）都能收到。
   */
  static share(context: common.UIAbilityContext, report: ActivityReport, elderName: string): void {
    const text: string = ReportExporter.buildText(report, elderName);
    const title: string = `${elderName} · ${ReportExporter.titleOf(report.period)}`;
    // SharedRecord 是接口、没有运行时实体，不能写成 systemShare.SharedRecord。
    // 直接传结构兼容的对象字面量即可 —— 这里刻意不写类型标注，
    // 免得为一个只用一次的接口再引入一层 import。
    const data: systemShare.SharedData = new systemShare.SharedData({
      utd: 'general.plain-text',
      title: title,
      description: `统计周期：${ReportExporter.periodDesc(report.period)}`,
      content: text
    });
    const controller: systemShare.ShareController = new systemShare.ShareController(data);
    controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    }).then(() => {
      // 面板关闭：分享成功与用户主动取消都会走到这里，无需区分
    }).catch((err: BusinessError) => {
      // 401 参数错误 / 1003702001 类型不支持 / 1003702002 IPC 超限（200KB）
      // 纯文本报告远小于 200KB，实际只可能是设备不具备分享能力
      Logger.error(ReportExporter.MODULE, `系统分享失败 ${err.code}: ${err.message}`);
    });
  }

  // ==================== 预警记录导出 ====================

  /**
   * 生成预警记录文本。
   *
   * 与活动报告同一套排版口径（破折号分隔、两级序号、结尾口径说明），
   * 保证同一次交接发出去的几份文件看起来是同一个系统产出的。
   *
   * 排序按等级权重再按时间：最紧急的排最前，接收方打开就能看到该先看哪条。
   */
  static buildAlertsText(alerts: Alert[], elderName: string): string {
    const lines: string[] = [];

    lines.push('守颐 · 独居老人智能监护系统');
    lines.push(`${elderName} · 预警记录`);
    lines.push('');
    lines.push('──────────────────────');
    lines.push(`记录条数：${alerts.length} 条`);
    lines.push(`导出时间：${DateUtil.format(DateUtil.now())}`);
    lines.push('');

    if (alerts.length === 0) {
      lines.push('当前没有符合条件的预警记录。');
      lines.push('');
    } else {
      for (let i = 0; i < alerts.length; i++) {
        const a: Alert = alerts[i];
        lines.push(`${i + 1}. 【${AlertLevel.labelOf(a.level)}】${a.alertTypeName}`);
        lines.push(`   触发时间：${DateUtil.format(a.timestamp)}`);
        lines.push(`   设备来源：${a.deviceName.length > 0 ? a.deviceName : '未绑定设备'}`);
        lines.push(`   触发描述：${a.description}`);
        lines.push(`   实测值：${a.triggerValue}（判定阈值 ${a.threshold}）`);
        const state: string = ReportExporter.alertState(a);
        lines.push(`   处置状态：${state}`);
        if (a.handle !== undefined) {
          lines.push(`   处置记录：${a.handle.resultName} · ${a.handle.handlerName}`
            + ` · ${DateUtil.format(a.handle.handledAt)}`);
          if (a.handle.note.length > 0) {
            lines.push(`   处置说明：${a.handle.note}`);
          }
        }
        lines.push('');
      }
    }

    lines.push('──────────────────────');
    lines.push('判定说明：系统依据老人个性化作息基线智能判定，'
      + '区分紧急告警与健康关注提示，以减少误报警扰。');
    lines.push('标记为「误报」的记录，系统会自动学习并动态更新老人基线，'
      + '持续降低后续误报率。');
    lines.push('本记录仅供家属与社区留存交接使用，'
      + '收到紧急告警请以 App 预警推送与电话通知为准。');

    return lines.join('\n');
  }

  /** 单条告警的状态文案 */
  private static alertState(a: Alert): string {
    switch (a.status) {
      case AlertStatus.HANDLED:
        return a.handle !== undefined ? `已处置 · ${a.handle.handlerName}` : '已处置';
      case AlertStatus.FALSE_ALARM:
        return a.handle !== undefined ? `误报 · ${a.handle.handlerName}` : '误报';
      case AlertStatus.CONFIRMED:
        return '已确认待处置';
      default:
        return '待处置';
    }
  }

  /** 预警记录分享标题 */
  static alertsTitleOf(elderName: string): string {
    return `${elderName} · 预警记录`;
  }

  // ==================== 居家安全日志导出 ====================

  /**
   * 生成居家安全日志文本。
   *
   * 日志与预警记录的分工：预警记录是"发生了什么"，
   * 日志是"处置结果与结论"。因此每条日志必须带上处置人与结论，
   * 否则交接方拿到一堆时间点却不知道后来怎么样了。
   */
  static buildLogsText(logs: SafetyLogEntry[], elderName: string): string {
    const lines: string[] = [];

    lines.push('守颐 · 独居老人智能监护系统');
    lines.push(`${elderName} · 居家安全日志`);
    lines.push('');
    lines.push('──────────────────────');
    lines.push(`日志条数：${logs.length} 条（近 60 天已处置记录）`);
    lines.push(`导出时间：${DateUtil.format(DateUtil.now())}`);
    lines.push('');

    if (logs.length === 0) {
      lines.push('当前没有已处置的预警记录。');
      lines.push('');
    } else {
      for (let i = 0; i < logs.length; i++) {
        const l: SafetyLogEntry = logs[i];
        lines.push(`${i + 1}. 【${AlertLevel.labelOf(l.level)}】${l.alertTypeName}`);
        lines.push(`   发生时间：${DateUtil.format(l.triggeredAt)}`);
        lines.push(`   处置时间：${DateUtil.format(l.handledAt)}`);
        lines.push(`   处置人：${l.handlerName}`);
        lines.push(`   处置结论：${l.resultName}`);
        if (l.note.length > 0) {
          lines.push(`   备注：${l.note}`);
        }
        lines.push('');
      }
    }

    lines.push('──────────────────────');
    lines.push('日志由已处置预警自动归档生成，用于长期追踪老人居家状态变化。');
    lines.push('标记为「误报」的记录，系统会自动学习并动态更新老人基线，'
      + '持续降低后续误报率。');

    return lines.join('\n');
  }

  /** 日志分享标题 */
  static logsTitleOf(elderName: string): string {
    return `${elderName} · 居家安全日志`;
  }

  /**
   * 拉系统分享面板导出居家安全日志。
   * 传参与 ReportExporter.share 一致的兜底策略。
   */
  static shareLogs(context: common.UIAbilityContext, logs: SafetyLogEntry[], elderName: string): void {
    const text: string = ReportExporter.buildLogsText(logs, elderName);
    const data: systemShare.SharedData = new systemShare.SharedData({
      utd: 'general.plain-text',
      title: ReportExporter.logsTitleOf(elderName),
      description: `日志条数：${logs.length} 条`,
      content: text
    });
    const controller: systemShare.ShareController = new systemShare.ShareController(data);
    controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    }).then(() => {
      // 面板关闭：分享成功与用户主动取消都会走到这里，无需区分
    }).catch((err: BusinessError) => {
      Logger.error(ReportExporter.MODULE, `系统分享失败 ${err.code}: ${err.message}`);
    });
  }

  /**
   * 拉系统分享面板导出预警记录。
   * 传参与 ReportExporter.share 一致的兜底策略。
   */
  static shareAlerts(context: common.UIAbilityContext, alerts: Alert[], elderName: string): void {
    const text: string = ReportExporter.buildAlertsText(alerts, elderName);
    const data: systemShare.SharedData = new systemShare.SharedData({
      utd: 'general.plain-text',
      title: ReportExporter.alertsTitleOf(elderName),
      description: `记录条数：${alerts.length} 条`,
      content: text
    });
    const controller: systemShare.ShareController = new systemShare.ShareController(data);
    controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    }).then(() => {
      // 面板关闭：分享成功与用户主动取消都会走到这里，无需区分
    }).catch((err: BusinessError) => {
      Logger.error(ReportExporter.MODULE, `系统分享失败 ${err.code}: ${err.message}`);
    });
  }
}
