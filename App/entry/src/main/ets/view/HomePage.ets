import { Device, Sensor } from '../model/Device';
import { Alert } from '../model/Alert';
import { FamilyMember } from '../model/FamilyMember';
import { DeviceListItem, PushMessage } from '../cloud/CloudTypes';
import { CareService } from '../service/CareService';
import { NetworkMonitor } from '../service/NetworkMonitor';
import { AppColor, AppSize } from '../common/constants/ThemeColors';
import { AlertLevel, AlertStatus } from '../common/constants/AppConstants';
import { DateUtil } from '../common/utils/DateUtil';
import { Logger } from '../common/utils/Logger';

/**
 * 首页宫格入口的展示模型。
 * ArkTS 的 @Builder 体内不能声明局部变量，派生值先算好放进来。
 */
class QuickEntry {
  key: string = '';
  title: string = '';
  hint: string = '';
  /** 图标：SymbolGlyph 系统符号（零素材文件），取代旧版单字 */
  icon: Resource = $r('sys.symbol.gearshape_fill');
  /** 主色：图标字与图标底色都从这里派生 */
  tint: string = '';
  /** 图标底色 */
  bg: string = '';
  /** 目标 Tab 下标 */
  target: number = 0;
}

/**
 * 首页。
 *
 * 只回答一个问题：**有没有待处理**。
 *
 * 设计取舍：把原来「总览」页里的设备卡、传感器网格、预警列表全部移走，
 * 首页只留"要不要现在动手"这一个判断。想看细节，走下方四个宫格入口。
 * 一屏里塞四类信息（状态 / 指标 / 传感器 / 预警）是上一版"看着乱"的根因。
 *
 * 导航：宫格不 push 新页面，而是切底部 Tab（由 Index 注入 onNavigate 回调），
 * 避免出现"首页 → 新页 → 返回"这种多余层级。
 */
@Component
export struct HomePage {
  private static readonly MODULE: string = 'HomePage';

  /** 切换底部 Tab 的回调，由 Index 注入 */
  onNavigate: (index: number) => void = () => {
  };

  @State device: Device | undefined = undefined;
  @State sensors: Sensor[] = [];
  /** 只存未处置的告警，首页不展示已闭环的历史 */
  @State pendingAlerts: Alert[] = [];
  @State memberCount: number = 0;
  @State online: boolean = true;
  @Prop @Watch('onLatestAlert') latestAlert: PushMessage | undefined = undefined;
  @StorageLink('alertRefreshTick') @Watch('onAlertsChanged') alertTick: number = 0;
  @State pushBanner: PushMessage | undefined = undefined;

  /** 演示场景切换后重新拉取，理由同 DeviceOverviewPage */
  @StorageLink('demoScenarioTick') @Watch('onDemoScenarioTick') demoTick: number = 0;

  private service: CareService = new CareService();

  onDemoScenarioTick(): void {
    this.load();
  }

  aboutToAppear(): void {
    NetworkMonitor.subscribe((online: boolean) => {
      this.online = online;
      if (online) {
        this.load();
      }
    });
    this.load();
  }

  onLatestAlert(): void {
    this.pushBanner = this.latestAlert;
  }

  onAlertsChanged(): void {
    this.load();
  }

  async load(): Promise<void> {
    try {
      const list: DeviceListItem[] = await this.service.loadDevices();
      if (list.length > 0) {
        this.device = list[0].device;
        this.sensors = list[0].sensors;
      }
      const alerts: Alert[] = await this.service.loadAlerts('', '', 7);
      this.pendingAlerts = alerts.filter((a: Alert) => a.isPending());
      const members: FamilyMember[] = await this.service.loadMembers();
      this.memberCount = members.length;
    } catch (err) {
      Logger.error(HomePage.MODULE, `加载失败: ${(err as Error).message}`);
    }
  }

  // ==================== 文案 ====================

  /** 主卡大字：直接回答"有没有待处理" */
  private pendingTitle(): string {
    if (this.pendingAlerts.length > 0) {
      return `有 ${this.pendingAlerts.length} 件待处理`;
    }
    return '没有待处理事项';
  }

  /** 主卡副文案：有告警给最紧急那条，没有就给设备状态 */
  private pendingSub(): string {
    if (this.pendingAlerts.length > 0) {
      const top: Alert | undefined = this.pendingAlerts[0];
      if (top === undefined) {
        return '';
      }
      return `${top.alertTypeName} · ${DateUtil.relative(top.timestamp)}`;
    }
    if (this.device === undefined) {
      return '正在同步设备状态…';
    }
    return this.device.online
      ? '主控在线'
      : '主控离线，暂无法获取实时读数';
  }

  /** 主卡右上角的状态胶囊 */
  private statusPillText(): string {
    return this.pendingAlerts.length > 0 ? '需要你处理' : '无待处置预警';
  }

  private statusPillColor(): string {
    return this.pendingAlerts.length > 0 ? AppColor.DANGER : AppColor.SUCCESS;
  }

  private statusPillBg(): string {
    return this.pendingAlerts.length > 0 ? 'rgba(198,40,40,0.10)' : 'rgba(46,125,50,0.10)';
  }

  /** 四个宫格入口。顺序按"使用频率 × 紧急度"排 */
  private quickEntries(): QuickEntry[] {
    const list: QuickEntry[] = [];

    const status: QuickEntry = new QuickEntry();
    status.key = 'status';
    status.title = '实时状态';
    status.hint = `${this.sensors.length} 个传感器`;
    status.icon = $r('sys.symbol.heart_fill');
    status.tint = AppColor.SECONDARY;
    status.bg = 'rgba(46,125,107,0.10)';
    status.target = 1;
    list.push(status);

    const report: QuickEntry = new QuickEntry();
    report.key = 'report';
    report.title = '活动报告';
    report.hint = '日报 · 周报 · 月报';
    report.icon = $r('sys.symbol.doc_text');
    report.tint = AppColor.INFO;
    report.bg = 'rgba(91,147,196,0.12)';
    report.target = 2;
    list.push(report);

    const alert: QuickEntry = new QuickEntry();
    alert.key = 'alert';
    alert.title = '预警中心';
    alert.hint = this.pendingAlerts.length > 0 ? `${this.pendingAlerts.length} 条待处置` : '历史记录';
    alert.icon = $r('sys.symbol.bell_fill');
    alert.tint = this.pendingAlerts.length > 0 ? AppColor.DANGER : AppColor.WARNING;
    alert.bg = this.pendingAlerts.length > 0 ? 'rgba(198,40,40,0.10)' : 'rgba(224,138,0,0.12)';
    alert.target = 3;
    list.push(alert);

    const family: QuickEntry = new QuickEntry();
    family.key = 'family';
    family.title = '家庭成员';
    family.hint = this.memberCount > 0 ? `${this.memberCount} 位成员` : '角色与权限';
    family.icon = $r('sys.symbol.person_fill');
    family.tint = AppColor.PRIMARY;
    family.bg = AppColor.PRIMARY_SOFT;
    family.target = 4;
    list.push(family);

    return list;
  }

  build() {
    Column() {
      // ---------- 顶部标题 ----------
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

        if (this.pendingAlerts.length > 0) {
          Column() {
            Text(`${this.pendingAlerts.length}`)
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
      .padding(20)
      .linearGradient({
        angle: 150,
        colors: [[AppColor.GRAD_TOP, 0.0], [AppColor.GRAD_BOT, 1.0]]
      })
      .borderRadius({ bottomLeft: 20, bottomRight: 20 })

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
          // ---------- 主卡：有没有待处理 ----------
          this.statusCard()

          // ---------- 宫格入口 ----------
          Text('常用功能')
            .fontSize(AppSize.SUBTITLE_FONT)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.TEXT)
            .width('100%')
            .margin({ top: 18, bottom: 10 })

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(this.quickEntries(), (entry: QuickEntry) => {
              Column() {
                this.entryTile(entry)
              }
              .width('48%')
              .margin({ bottom: 10 })
            }, (entry: QuickEntry) => `${entry.key}_${entry.hint}`)
          }
          .width('100%')

          // ---------- 最近预警 ----------
          Row() {
            Text('最近预警')
              .fontSize(AppSize.SUBTITLE_FONT)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColor.TEXT)
              .layoutWeight(1)
            Text('查看全部 ›')
              .fontSize(AppSize.SMALL_FONT)
              .fontColor(AppColor.TEXT_3)
              .onClick(() => {
                this.onNavigate(3);
              })
          }
          .width('100%')
          .margin({ top: 12, bottom: 10 })

          if (this.pendingAlerts.length === 0) {
            Column() {
              Text('暂无待处置预警')
                .fontSize(AppSize.CAPTION_FONT)
                .fontColor(AppColor.TEXT_3)
            }
            .width('100%')
            .padding({ top: 26, bottom: 26 })
            .backgroundColor(AppColor.CARD)
            .borderRadius(AppSize.CARD_RADIUS)
          } else {
            // 首页只给最近两条，避免把首页又做成第二个预警中心
            ForEach(this.pendingAlerts.slice(0, 2), (alert: Alert) => {
              this.alertLine(alert)
            // key 含 status/处置结果：与预警中心同理，标记已处置后列表状态要刷新
            }, (alert: Alert) => `${alert.alertId}_${alert.status}_`
              + (alert.handle !== undefined ? alert.handle.resultName : ''))
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

  /** 主卡：一句话回答"有没有待处理" */
  @Builder
  statusCard() {
    Column() {
      Row() {
        Text('有没有待处理')
          .fontSize(AppSize.SMALL_FONT)
          .fontColor(AppColor.TEXT_3)
          .layoutWeight(1)
        Text(this.statusPillText())
          .fontSize(10)
          .fontColor(this.statusPillColor())
          .backgroundColor(this.statusPillBg())
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(9)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.pendingTitle())
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pendingAlerts.length > 0 ? AppColor.DANGER : AppColor.TEXT)
        .margin({ top: 10 })
        .width('100%')

      Text(this.pendingSub())
        .fontSize(AppSize.CAPTION_FONT)
        .fontColor(AppColor.TEXT_2)
        .lineHeight(20)
        .margin({ top: 8 })
        .width('100%')

      if (this.pendingAlerts.length > 0) {
        Text('去处置 →')
          .fontSize(AppSize.CAPTION_FONT)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.CARD)
          .backgroundColor(AppColor.DANGER)
          .padding({ left: 18, right: 18, top: 9, bottom: 9 })
          .borderRadius(18)
          .margin({ top: 14 })
          .onClick(() => {
            this.onNavigate(3);
          })
      }
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
  }

  /** 宫格入口卡片 */
  @Builder
  entryTile(entry: QuickEntry) {
    Column() {
      Row() {
        Row() {
          SymbolGlyph(entry.icon)
            .fontSize(17)
            .fontColor([entry.tint])
        }
        .width(34)
        .height(34)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(entry.bg)
        .borderRadius(10)

        Blank()

        Text('›')
          .fontSize(16)
          .fontColor(AppColor.TEXT_3)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(entry.title)
        .fontSize(AppSize.BODY_FONT)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.TEXT)
        .margin({ top: 10 })
        .width('100%')

      Text(entry.hint)
        .fontSize(AppSize.SMALL_FONT)
        .fontColor(AppColor.TEXT_3)
        .margin({ top: 3 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
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
    .onClick(() => {
      this.onNavigate(entry.target);
    })
  }

  /** 最近预警的单行展示。点任意一条都去预警中心，不在首页展开处置表单 */
  @Builder
  alertLine(alert: Alert) {
    Row() {
      Row()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(AppColor.levelColor(alert.level))
        .margin({ right: 10 })

      Column() {
        Text(alert.alertTypeName)
          .fontSize(AppSize.CAPTION_FONT)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(`${DateUtil.relative(alert.timestamp)} · ${AlertStatus.labelOf(alert.status)}`)
          .fontSize(10)
          .fontColor(AppColor.TEXT_3)
          .margin({ top: 3 })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(AlertLevel.labelOf(alert.level))
        .fontSize(10)
        .fontColor(AppColor.levelColor(alert.level))
        .backgroundColor(AppColor.levelBg(alert.level))
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(4)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(12)
    .backgroundColor(AppColor.CARD)
    .borderRadius(12)
    .shadow({
      radius: AppSize.SHADOW_RADIUS,
      color: AppSize.SHADOW_COLOR,
      offsetY: AppSize.SHADOW_OFFSET_Y
    })
    .margin({ bottom: 8 })
    .onClick(() => {
      this.onNavigate(3);
    })
  }
}
