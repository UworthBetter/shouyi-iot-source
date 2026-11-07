import { router } from '@kit.ArkUI';
import { Alert } from '../model/Alert';
import { CareService } from '../service/CareService';
import { AlertCard } from './components/AlertCard';
import { AppColor, AppSize } from '../common/constants/ThemeColors';
import { AlertLevel, AlertStatus } from '../common/constants/AppConstants';
import { ReportExporter } from '../common/utils/ReportExporter';
import { Logger } from '../common/utils/Logger';
import { common } from '@kit.AbilityKit';

/** 筛选选项 */
class FilterOption {
  key: string = '';
  label: string = '';

  constructor(key: string, label: string) {
    this.key = key;
    this.label = label;
  }
}

/**
 * 跳转预警详情页的传参。
 * 必须显式声明为 class —— ArkTS 不允许无类型的对象字面量。
 */
class AlertDetailParams {
  alertId: string = '';

  constructor(alertId: string) {
    this.alertId = alertId;
  }
}

/**
 * 告警中心。
 *
 * 视觉上与活动报告页完全统一：浅白底、白色圆角卡片、左上标题 + 右上等级标签、
 * 右下角"点击查看详情"。
 *
 * 筛选分两行：
 *   第一行 处置状态（全部 / 待处置 / 已处置 / 误报）—— 深蓝实心选中
 *   第二行 告警等级（全部 / 紧急 / 高风险 / 需关注 / 提示）—— 各等级用自己的颜色描边，
 *           选中时填色。家属先选等级还是先选状态都顺手，两行互不干扰。
 *
 * 颜色语义与全 App 一致：红=紧急、橙黄=高风险、绿=需关注、浅灰=提示。
 */
@Component
export struct AlertCenterPage {
  private static readonly MODULE: string = 'AlertCenterPage';

  @State alerts: Alert[] = [];
  @State statusFilter: string = '';
  @State levelFilter: string = '';
  @State loading: boolean = true;
  /** 批量操作进行中，防止连点重复提交 */
  @State busy: boolean = false;
  /** 切到本页时 Index 会 +1，触发重新拉列表（页签缓存否则会停在旧数据） */
  @StorageLink('alertRefreshTick') @Watch('onAlertRefreshTick') alertTick: number = 0;

  private loadVersion: number = 0;
  private service: CareService = new CareService();

  aboutToAppear(): void {
    this.load();
  }

  /** Index 切到预警中心时 +1：重新拉列表，避免页签缓存显示旧数据 */
  onAlertRefreshTick(): void {
    this.load();
  }

  async load(): Promise<void> {
    const version: number = ++this.loadVersion;
    this.loading = true;
    try {
      const alerts: Alert[] = await this.service.loadAlerts(this.statusFilter, this.levelFilter, 60);
      if (version === this.loadVersion) {
        this.alerts = alerts;
      }
    } catch (err) {
      Logger.error(AlertCenterPage.MODULE, `加载告警失败: ${(err as Error).message}`);
    } finally {
      if (version === this.loadVersion) {
        this.loading = false;
      }
    }
  }

  build() {
    Column() {
      // ---------- 标题栏 ----------
      Row() {
        Text('预警中心')
          .fontSize(AppSize.TITLE_FONT)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColor.TEXT)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`共 ${this.alerts.length} 条预警记录`)
          .fontSize(AppSize.SMALL_FONT)
          .fontColor(AppColor.TEXT_3)
          .margin({ right: 10 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text('导出 PDF')
          .fontSize(AppSize.CAPTION_FONT)
          .fontColor(AppColor.CARD)
          .backgroundColor(AppColor.PRIMARY)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .onClick(() => {
            this.exportAlerts();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: AppSize.PAGE_PADDING, right: AppSize.PAGE_PADDING, top: AppSize.PAGE_PADDING })

      // 判定口径说明。放在标题下方而不是页面底部 ——
      // 家属第一眼就该知道这些提醒是怎么判出来的，否则只会当成噪音
      Text('系统依据老人个性化作息基线智能判定，区分紧急告警与健康关注提示，减少误报警扰。')
        .fontSize(AppSize.SMALL_FONT)
        .fontColor(AppColor.TEXT_3)
        .margin({ top: 8, bottom: 4 })
        .lineHeight(17)
        .padding({ left: AppSize.PAGE_PADDING, right: AppSize.PAGE_PADDING })

      // ---------- 第一行：处置状态 ----------
      Flex({ wrap: FlexWrap.Wrap }) {
        this.statusChip('', '全部')
        this.statusChip(AlertStatus.PENDING, '待处置')
        this.statusChip(AlertStatus.HANDLED, '已处置')
        this.statusChip(AlertStatus.FALSE_ALARM, '误报')
      }
      .width('100%')
      .padding({ left: AppSize.PAGE_PADDING, right: AppSize.PAGE_PADDING, top: 10, bottom: 6 })

      // ---------- 第二行：告警等级 ----------
      // 用 wrap 而不是横向滚动：5 个等级标签必须同时可见，
      // 滚动会让家属以为就只有前两个选项
      Flex({ wrap: FlexWrap.Wrap }) {
        this.levelChip('', '全部等级')
        this.levelChip(AlertLevel.P0, '紧急')
        this.levelChip(AlertLevel.P1, '高风险')
        this.levelChip(AlertLevel.P2, '需关注')
        this.levelChip(AlertLevel.P3, '提示')
      }
      .width('100%')
      .padding({ left: AppSize.PAGE_PADDING, right: AppSize.PAGE_PADDING, bottom: 12 })

      // ---------- 批量操作（仅待处置页签、且有数据时出现） ----------
      // 处置完的告警堆积是家属最头疼的点，所以给两个批量入口：
      //   批量标记已处置 —— 一键把待处置全部闭环（保留记录，可追溯）
      //   清空待处置     —— 直接删掉这批本地记录（弹二次确认，防误触）
      if (this.statusFilter === AlertStatus.PENDING && this.alerts.length > 0) {
        Row() {
          Text(`待处置 ${this.alerts.length} 条`)
            .fontSize(AppSize.SMALL_FONT)
            .fontColor(AppColor.TEXT_3)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text('批量标记已处置')
            .fontSize(AppSize.SMALL_FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.PRIMARY)
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(14)
            .backgroundColor(AppColor.PRIMARY_SOFT)
            .margin({ right: 8 })
            .opacity(this.busy ? 0.5 : 1)
            .onClick(() => {
              if (!this.busy) {
                this.doMarkAll();
              }
            })

          Text('清空待处置')
            .fontSize(AppSize.SMALL_FONT)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColor.DANGER)
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(14)
            .backgroundColor('rgba(198,40,40,0.08)')
            .opacity(this.busy ? 0.5 : 1)
            .onClick(() => {
              if (!this.busy) {
                this.confirmClearPending();
              }
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: AppSize.PAGE_PADDING, right: AppSize.PAGE_PADDING, bottom: 10 })
      }

      // ---------- 列表 ----------
      if (this.alerts.length === 0 && !this.loading) {
        Column() {
          Text('没有符合条件的预警记录')
            .fontSize(AppSize.BODY_FONT)
            .fontColor(AppColor.TEXT_3)
          Text('换个筛选条件试试')
            .fontSize(AppSize.CAPTION_FONT)
            .fontColor(AppColor.TEXT_3)
            .margin({ top: 8 })
        }
        .width('100%')
        .padding({ top: 80 })
        .layoutWeight(1)
      } else {
        List() {
          ForEach(this.alerts, (alert: Alert) => {
            ListItem() {
              AlertCard({
                alert: alert,
                onOpen: (a: Alert) => {
                  this.openDetail(a);
                },
                onChanged: () => {
                  // 与首页一致：一键标记已处置后刷新列表，按钮收起
                  this.load();
                }
              })
            }
            .margin({ bottom: 10 })
          // key 含 status/处置结果：标记已处置后 load() 重建数组，
          // 若只用 alertId，ForEach 会复用旧节点，状态徽标仍是"待处置"
          }, (alert: Alert) => `${alert.alertId}_${alert.status}_`
            + (alert.handle !== undefined ? alert.handle.resultName : ''))

          // ---------- 列表底部说明 ----------
          // 误报自学习是整套个性化基线能成立的关键，
          // 这句话必须出现在列表末端 —— 家属标记完误报往下滑就能看到
          ListItem() {
            Text('标记为【误报】的记录，系统会自动学习，动态更新老人基线，持续降低后续误报率。')
              .fontSize(AppSize.SMALL_FONT)
              .fontColor(AppColor.TEXT_3)
              .lineHeight(18)
              .width('100%')
              .padding({ top: 4, bottom: 12 })
          }

          ListItem() {
            // 列表尾留白。不能用 Blank —— 它只能嵌在 Row/Column/Flex 里，
            // 直接放在 ListItem 下会报 10905201。
            Row().width('100%').height(16)
          }
        }
        .layoutWeight(1)
        .padding({ left: AppSize.PAGE_PADDING, right: AppSize.PAGE_PADDING })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.BG)
  }

  /** 处置状态标签。深蓝实心=选中 */
  @Builder
  statusChip(key: string, label: string) {
    Text(label)
      .fontSize(AppSize.CAPTION_FONT)
      .fontColor(this.statusFilter === key ? AppColor.CARD : AppColor.TEXT_2)
      .backgroundColor(this.statusFilter === key ? AppColor.PRIMARY : AppColor.CARD)
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .margin({ right: 8, bottom: 8 })
      .border({ width: 1, color: this.statusFilter === key ? AppColor.PRIMARY : AppColor.LINE })
      .onClick(() => {
        this.statusFilter = key;
        this.load();
      })
  }

  /**
   * 等级标签。默认用等级自己的颜色描边 + 同色文字，选中才填色。
   *
   * 这样竖着一排看过去，五个等级的颜色本身就是图例；
   * 若默认全是灰底，家属还得逐个点开才知道哪个色对应哪个等级。
   *
   * 颜色与选中态都抽成独立方法：@Builder 里不能声明局部变量（10905209），
   * 派生值必须在方法里算好，渲染时只取值。
   */
  @Builder
  levelChip(key: string, label: string) {
    Text(label)
      .fontSize(AppSize.SMALL_FONT)
      .fontColor(this.levelFilter === key ? AppColor.CARD : this.levelChipTextColor(key))
      .backgroundColor(this.levelFilter === key ? this.levelChipColor(key) : AppColor.CARD)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(14)
      .margin({ right: 8, bottom: 8 })
      .border({ width: 1, color: this.levelChipColor(key) })
      .onClick(() => {
        this.levelFilter = key;
        this.load();
      })
  }

  /** 等级标签描边 / 选中底色。全部等级用中性灰，不参与颜色图例 */
  private levelChipColor(key: string): string {
    return key.length > 0 ? AppColor.levelColor(key) : 'rgba(26,29,33,0.45)';
  }

  /** 等级标签未选中时的文字色 */
  private levelChipTextColor(key: string): string {
    return key.length > 0 ? AppColor.levelColor(key) : AppColor.TEXT_2;
  }

  /**
   * 导出预警记录。
   *
   * 与活动报告同一口径：生成结构化文本 → 调起系统分享面板 → 选「打印」另存 PDF。
   * 原生 PDF 需要 @kit.PDFKit（依赖独立 ohos pdfkit npm 包），本工程未引入。
   */
  private exportAlerts(): void {
    if (this.alerts.length === 0) {
      this.toast('暂无可导出的预警记录');
      return;
    }
    try {
      // getContext 已废弃，自定义组件里用 getUIContext().getHostContext() 取宿主上下文
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      ReportExporter.shareAlerts(context, this.alerts, this.elderName());
    } catch (err) {
      Logger.error(AlertCenterPage.MODULE, `导出预警记录失败: ${(err as Error).message}`);
      this.toast('导出失败，请稍后重试');
    }
  }

  /** 被监护老人姓名。取不到时退回中性称呼，不留占位符 */
  private elderName(): string {
    return this.service.boundElderName() ?? '家中老人';
  }

  /**
   * 轻提示。
   * showToast 声明为可能抛异常，必须包 try —— 工程里既有约定，
   * 否则每次编译都留 warning 尾巴。
   */
  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      Logger.warn(AlertCenterPage.MODULE, `提示未弹出: ${(err as Error).message}`);
    }
  }

  // ==================== 批量操作 ====================

  /**
   * 批量标记：一键把当前全部「待处置」闭环为「已处置」。
   * 保留记录可追溯，处置结果同时写入安全日志。
   */
  private async doMarkAll(): Promise<void> {
    this.busy = true;
    try {
      const n: number = await this.service.markAllPendingHandled();
      if (n > 0) {
        this.toast(`已将 ${n} 条标记为已处置`);
      } else {
        this.toast('没有待处置的预警');
      }
      await this.load();
    } finally {
      this.busy = false;
    }
  }

  /**
   * 「清空待处置」的二次确认弹窗。
   *
   * 删除不可撤销，且是整批操作 —— 必须先让家属再确认一次，
   * 避免误触把上百条待处置一次清空。这是唯一的强制确认环节。
   */
  private confirmClearPending(): void {
    const count: number = this.alerts.length;
    try {
      this.getUIContext().showAlertDialog({
        title: '清空待处置预警？',
        message: `将删除全部 ${count} 条待处置预警。\n\n只删 App 本地记录，不影响日报、活动统计与安全日志；删除后不可恢复。`,
        autoCancel: true,
        primaryButton: {
          value: '取消',
          action: () => {
          }
        },
        secondaryButton: {
          value: '确认清空',
          fontColor: AppColor.DANGER,
          action: () => {
            this.doClearPending();
          }
        }
      });
    } catch (err) {
      Logger.warn(AlertCenterPage.MODULE, `清空确认弹窗未弹出: ${(err as Error).message}`);
    }
  }

  /** 执行清空（仅在二次确认后调用）。 */
  private async doClearPending(): Promise<void> {
    this.busy = true;
    try {
      const n: number = await this.service.clearPendingAlerts();
      if (n > 0) {
        this.toast(`已清空 ${n} 条待处置预警`);
      } else {
        this.toast('没有待处置的预警');
      }
      await this.load();
    } finally {
      this.busy = false;
    }
  }

  private openDetail(alert: Alert): void {
    const params: AlertDetailParams = new AlertDetailParams(alert.alertId);
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/AlertDetail',
      params: params
    }).catch((e: Error) => {
      Logger.warn(AlertCenterPage.MODULE, `跳转告警详情失败: ${e.message}`);
    });
  }
}
