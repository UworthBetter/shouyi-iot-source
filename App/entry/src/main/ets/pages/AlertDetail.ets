import { Alert, AlertTimelineNode, ThresholdSuggestion } from '../model/Alert';
import { CareService } from '../service/CareService';
import { AlertLevel, AlertStatus, AlertType, HandleResult } from '../common/constants/AppConstants';
import { AppColor, AppSize } from '../common/constants/ThemeColors';
import { DateUtil } from '../common/utils/DateUtil';
import { Logger } from '../common/utils/Logger';

/**
 * 跳转本页的传参类型，必须与 AlertCenterPage 里发送端保持一致。
 * ArkTS 不允许无类型对象字面量，所以两边都用显式 class。
 */
class AlertDetailParams {
  alertId: string = '';
}

/**
 * 预警详情 —— 事件闭环的落地页。
 *
 * 赛题原文要求："预警发生后，子女/监护人通过应用确认预警信息，填写处置结果
 * （如'已联系社区网格员上门查看''老人一切正常，误报'），形成居家安全日志。"
 *
 * 本页把这条链路做完整：
 *   触发 → 上报 → 分级推送 → 确认 → 填写处置结果 → 写入安全日志
 *                                        ↓
 *                              标记误报 → 生成阈值调整建议（误报反馈闭环）
 *
 * 入参：AlertCenterPage.openDetail() 通过 pushUrl 传入 { alertId }。
 */
@Entry
@Component
struct AlertDetail {
  private static readonly MODULE: string = 'AlertDetail';

  @State alert: Alert | undefined = undefined;
  @State timeline: AlertTimelineNode[] = [];
  @State loading: boolean = true;
  @State submitting: boolean = false;

  /** 处置表单 */
  @State selectedResult: string = '';
  @State note: string = '';
  /** 误报反馈闭环：阈值调整建议 */
  @State suggestion: ThresholdSuggestion | undefined = undefined;
  @State applyAdjust: boolean = false;

  private alertId: string = '';
  private service: CareService = new CareService();

  aboutToAppear(): void {
    try {
      const params = this.getUIContext().getRouter().getParams() as AlertDetailParams;
      if (params !== undefined && params !== null && params.alertId !== undefined) {
        this.alertId = params.alertId;
      }
    } catch (err) {
      Logger.error(AlertDetail.MODULE, `读取路由参数失败: ${(err as Error).message}`);
    }
    if (this.alertId.length === 0) {
      Logger.error(AlertDetail.MODULE, '未收到 alertId 参数，无法加载详情');
      this.loading = false;
      return;
    }
    this.load();
  }

  async load(): Promise<void> {
    this.loading = true;
    try {
      const resp = await this.service.loadAlertDetail(this.alertId);
      this.alert = resp.alert;
      this.timeline = resp.timeline;
      // 已处置过的告警：回显处置结果，避免用户重复填写
      if (resp.alert.handle !== undefined) {
        this.selectedResult = resp.alert.handle.result;
        this.note = resp.alert.handle.note;
      }
    } catch (err) {
      Logger.error(AlertDetail.MODULE, `加载告警详情失败: ${(err as Error).message}`);
      this.toast('加载失败，请返回重试');
    } finally {
      this.loading = false;
    }
  }

  /** 确认告警（状态：待确认 → 已确认） */
  async onConfirm(): Promise<void> {
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    const ok: boolean = await this.service.confirmAlert(this.alertId, '已确认，正在处理');
    this.submitting = false;
    if (ok) {
      this.toast('已确认');
      await this.load();
    } else {
      this.toast('确认失败，请检查网络');
    }
  }

  /** 选择处置结果；选到"误报"时拉取阈值调整建议 */
  async onPickResult(result: string): Promise<void> {
    this.selectedResult = result;
    if (result === HandleResult.FALSE_ALARM && this.alert !== undefined) {
      const s: ThresholdSuggestion | undefined =
        await this.service.buildThresholdSuggestion(this.alert.alertType);
      this.suggestion = s;
      // 有建议时默认勾选，减少一次点击 —— 安全场景下处置动作要快
      this.applyAdjust = s !== undefined;
    } else {
      this.suggestion = undefined;
      this.applyAdjust = false;
    }
  }

  /** 提交处置结果，完成事件闭环 */
  async onSubmit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    if (this.selectedResult.length === 0) {
      this.toast('请先选择处置结果');
      return;
    }
    this.submitting = true;

    let adjustKey: string = '';
    let adjustValue: number = 0;
    if (this.applyAdjust && this.suggestion !== undefined) {
      adjustKey = this.suggestion.key;
      adjustValue = this.suggestion.suggestedValue;
    }

    const ok: boolean = await this.service.handleAlert(
      this.alertId, this.selectedResult, this.note, adjustKey, adjustValue);
    this.submitting = false;

    if (ok) {
      this.toast(adjustKey.length > 0 ? '已处置，阈值已调整' : '已处置');
      this.back();
    } else {
      this.toast('提交失败，请检查网络');
    }
  }

  private toast(message: string): void {
    // showToast 声明为可能抛异常，必须显式处理，否则编译告警
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      Logger.warn(AlertDetail.MODULE, `弹出提示失败: ${(err as Error).message}`);
    }
  }

  private back(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (err) {
      Logger.warn(AlertDetail.MODULE, `返回失败: ${(err as Error).message}`);
    }
  }

  build() {
    Column() {
      this.topBar()

      if (this.loading) {
        Column() {
          LoadingProgress().width(40).height(40).color(AppColor.PRIMARY)
          Text('加载中…')
            .fontSize(AppSize.CAPTION_FONT)
            .fontColor(AppColor.TEXT_3)
            .margin({ top: 10 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.alert === undefined) {
        Column() {
          Text('未找到该预警记录')
            .fontSize(AppSize.BODY_FONT)
            .fontColor(AppColor.TEXT_3)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            this.alertCard(this.alert)
            this.timelineCard()
            if (this.alert.isPending()) {
              this.handleSection()
            } else {
              this.handledSummary(this.alert)
            }
            // 底部留白（Scroll 内不用 Blank，避免依赖父容器确定高度）
            Column().width('100%').height(24)
          }
          .width('100%')
          .padding({ left: AppSize.PAGE_PADDING, right: AppSize.PAGE_PADDING })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.BG)
  }

  // ==================== 顶部栏 ====================

  @Builder
  topBar() {
    Row() {
      Text('‹ 返回')
        .fontSize(AppSize.BODY_FONT)
        .fontColor(AppColor.CARD)
        .onClick(() => {
          this.back();
        })
      Text('预警详情')
        .fontSize(AppSize.SUBTITLE_FONT)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.CARD)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      // 右侧占位，保证标题居中
      Text('返回').fontSize(AppSize.BODY_FONT).fontColor(Color.Transparent)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .linearGradient({
      angle: 150,
      colors: [[AppColor.GRAD_TOP, 0.0], [AppColor.GRAD_BOT, 1.0]]
    })
  }

  // ==================== 告警信息卡 ====================

  @Builder
  alertCard(alert: Alert) {
    Column() {
      // P0 紧急告警：顶部满宽红色横幅，视觉上与普通告警彻底区分
      if (alert.isCritical()) {
        Row() {
          Text('紧急事件 · 请立即处理')
            .fontSize(AppSize.CAPTION_FONT)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.CARD)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .backgroundColor(AppColor.DANGER)
        .borderRadius({ topLeft: AppSize.CARD_RADIUS, topRight: AppSize.CARD_RADIUS })
      }

      Column() {
        Row() {
          Text(alert.alertTypeName)
            .fontSize(AppSize.TITLE_FONT)
            .fontWeight(FontWeight.Bold)
            .fontColor(alert.isCritical() ? AppColor.DANGER : AppColor.TEXT)
            .layoutWeight(1)
          Text(AlertLevel.labelOf(alert.level))
            .fontSize(AppSize.SMALL_FONT)
            .fontColor(AppColor.CARD)
            .backgroundColor(AppColor.levelColor(alert.level))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(4)
        }
        .width('100%')

        Text(alert.description)
          .fontSize(AppSize.BODY_FONT)
          .fontColor(AppColor.TEXT_2)
          .margin({ top: 10 })
          .width('100%')

        Divider().color(AppColor.LINE).margin({ top: 14, bottom: 12 })

        this.infoRow('设备', alert.deviceName)
        this.infoRow('触发时间', DateUtil.format(alert.timestamp))
        if (alert.triggerValue > 0) {
          this.infoRow('实测值', `${alert.triggerValue}`)
        }
        if (alert.threshold > 0) {
          this.infoRow('触发阈值', `${alert.threshold}`)
        }
        this.infoRow('当前状态', AlertStatus.labelOf(alert.status))
        if (alert.notifiedRoles.length > 0) {
          this.infoRow('已推送至', alert.notifiedRoles.map((r: string) => {
            return this.roleLabel(r);
          }).join('、'))
        }
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .backgroundColor(AppColor.CARD)
    .borderRadius(AppSize.CARD_RADIUS)
    .border({
      width: alert.isCritical() ? 1 : 0,
      color: AppColor.DANGER
    })
    .shadow({
      radius: AppSize.SHADOW_RADIUS,
      color: AppSize.SHADOW_COLOR,
      offsetY: AppSize.SHADOW_OFFSET_Y
    })
    .clip(true)
    .margin({ top: 14 })
  }

  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(AppSize.CAPTION_FONT)
        .fontColor(AppColor.TEXT_3)
        .width(76)
      Text(value)
        .fontSize(AppSize.CAPTION_FONT)
        .fontColor(AppColor.TEXT)
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ bottom: 7 })
  }

  private roleLabel(role: string): string {
    switch (role) {
      case 'child':
        return '子女';
      case 'grid_worker':
        return '社区网格员';
      case 'property':
        return '物业值班';
      case 'maintainer':
        return '维护人员';
      default:
        return role;
    }
  }

  // ==================== 处置时间线 ====================

  @Builder
  timelineCard() {
    Column() {
      Text('处置时间线')
        .fontSize(AppSize.SUBTITLE_FONT)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.TEXT)
        .width('100%')
        .margin({ bottom: 12 })

      if (this.timeline.length === 0) {
        Text('暂无记录')
          .fontSize(AppSize.CAPTION_FONT)
          .fontColor(AppColor.TEXT_3)
      } else {
        ForEach(this.timeline, (node: AlertTimelineNode, index: number) => {
          Row() {
            // 左侧节点圆点（不画连接线：Row 内无法可靠地撑满高度）
            Column()
              .width(10)
              .height(10)
              .borderRadius(5)
              .backgroundColor(index === this.timeline.length - 1
                ? AppColor.PRIMARY : AppColor.SECONDARY)
              .margin({ top: 4 })

            Column() {
              Row() {
                Text(AlertTimelineNode.eventLabel(node.event))
                  .fontSize(AppSize.SMALL_FONT)
                  .fontColor(AppColor.CARD)
                  .backgroundColor(AppColor.PRIMARY)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
                Text(DateUtil.formatTime(node.time))
                  .fontSize(AppSize.SMALL_FONT)
                  .fontColor(AppColor.TEXT_3)
                  .margin({ left: 8 })
              }
              .width('100%')

              Text(node.text)
                .fontSize(AppSize.CAPTION_FONT)
                .fontColor(AppColor.TEXT_2)
                .margin({ top: 6 })
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .padding({ bottom: 16 })
            .margin({ left: 10 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (node: AlertTimelineNode, index: number) => `${index}_${node.event}_${node.time}`)
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
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 12 })
  }

  // ==================== 处置表单 ====================

  @Builder
  handleSection() {
    Column() {
      Text('处置')
        .fontSize(AppSize.SUBTITLE_FONT)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColor.TEXT)
        .width('100%')
        .margin({ bottom: 4 })

      // 待确认时先提供"确认"动作，与赛题的状态机一致
      if (this.alert !== undefined && this.alert.status === AlertStatus.PENDING) {
        Button('确认收到该预警')
          .width('100%')
          .height(42)
          .fontSize(AppSize.BODY_FONT)
          .backgroundColor(AppColor.PRIMARY_SOFT)
          .fontColor(AppColor.PRIMARY)
          .borderRadius(12)
          .enabled(!this.submitting)
          .margin({ top: 12 })
          .onClick(() => {
            this.onConfirm();
          })
      }

      Text('处置结果')
        .fontSize(AppSize.CAPTION_FONT)
        .fontColor(AppColor.TEXT_3)
        .width('100%')
        .margin({ top: 16, bottom: 8 })

      // 预设选项：安全场景下处置动作要快，不让用户手打
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(HandleResult.all(), (result: string) => {
          Text(HandleResult.labelOf(result))
            .fontSize(AppSize.CAPTION_FONT)
            .fontColor(this.selectedResult === result ? AppColor.CARD : AppColor.TEXT_2)
            .backgroundColor(this.selectedResult === result ? AppColor.PRIMARY : AppColor.SURFACE)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(16)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.onPickResult(result);
            })
        }, (result: string) => result)
      }
      .width('100%')

      TextArea({ text: this.note, placeholder: '补充说明（选填）' })
        .width('100%')
        .height(72)
        .fontSize(AppSize.CAPTION_FONT)
        .backgroundColor(AppColor.SURFACE)
        .borderRadius(AppSize.SMALL_RADIUS)
        .margin({ top: 4 })
        .onChange((value: string) => {
          this.note = value;
        })

      // 误报反馈闭环：标记误报后提示是否放宽阈值
      if (this.suggestion !== undefined) {
        Row() {
          Column() {
            Text('建议调整阈值')
              .fontSize(AppSize.CAPTION_FONT)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppColor.WARNING)
            Text(this.suggestion.message)
              .fontSize(AppSize.SMALL_FONT)
              .fontColor(AppColor.TEXT_2)
              .margin({ top: 4 })
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Toggle({ type: ToggleType.Checkbox, isOn: this.applyAdjust })
            .selectedColor(AppColor.PRIMARY)
            .onChange((isOn: boolean) => {
              this.applyAdjust = isOn;
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor('rgba(224,138,0,0.10)')
        .borderRadius(AppSize.SMALL_RADIUS)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 10 })
      }

      Button(this.submitting ? '提交中…' : '提交处置结果')
        .width('100%')
        .height(46)
        .fontSize(AppSize.BODY_FONT)
        .fontWeight(FontWeight.Bold)
        .backgroundColor(this.selectedResult.length > 0 ? AppColor.PRIMARY : AppColor.TEXT_3)
        .borderRadius(AppSize.SMALL_RADIUS)
        .enabled(this.selectedResult.length > 0 && !this.submitting)
        .margin({ top: 16 })
        .onClick(() => {
          this.onSubmit();
        })
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
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 12 })
  }

  // ==================== 已处置回显 ====================

  @Builder
  handledSummary(alert: Alert) {
    Column() {
      Row() {
        Text('已处置')
          .fontSize(AppSize.SMALL_FONT)
          .fontColor(AppColor.CARD)
          .backgroundColor(AppColor.SUCCESS)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(4)
        Text(alert.status === AlertStatus.FALSE_ALARM ? '该条已标记为误报' : '事件已闭环')
          .fontSize(AppSize.CAPTION_FONT)
          .fontColor(AppColor.TEXT_2)
          .margin({ left: 8 })
      }
      .width('100%')

      if (alert.handle !== undefined) {
        Divider().color(AppColor.LINE).margin({ top: 12, bottom: 12 })
        this.infoRow('处置人', alert.handle.handlerName)
        this.infoRow('处置结果', alert.handle.resultName)
        if (alert.handle.note.length > 0) {
          this.infoRow('补充说明', alert.handle.note)
        }
        this.infoRow('处置时间', DateUtil.format(alert.handle.handledAt))
        if (alert.handle.thresholdAdjusted) {
          this.infoRow('阈值调整', '已按建议放宽阈值')
        }
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
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 12 })
  }
}
