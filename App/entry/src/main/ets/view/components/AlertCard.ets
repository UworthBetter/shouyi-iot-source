import { Alert } from '../../model/Alert';
import { DeviceConfig } from '../../model/Device';
import { CareService } from '../../service/CareService';
import { common } from '@kit.AbilityKit';
import { AppColor, AppSize } from '../../common/constants/ThemeColors';
import { AlertLevel, AlertStatus, HandleResult } from '../../common/constants/AppConstants';
import { DateUtil } from '../../common/utils/DateUtil';
import { Logger } from '../../common/utils/Logger';

/**
 * 预警卡片。
 *
 * 与活动报告页共用同一套视觉语言：白色圆角卡片、浅白底、左上标题 + 右上等级标签、
 * 正文一行、底部小字信息行、右下角"点击查看详情"。
 *
 * 视觉分级靠左侧色条 + 等级标签同色完成，都取 AppColor.levelColor ——
 * 不存在两处各画一套导致颜色不一致的可能。
 * 红色只留给 P0 紧急事件；P1 橙黄、P2 绿、P3 浅灰。
 *
 * 未处置的卡片额外带两个轻量快捷操作：
 *   联系老人 / 标记已处置
 * 一键闭环是高频动作，家属不该每次都点进详情页填一整套表单。
 */
@Component
export struct AlertCard {
  @Prop alert: Alert;
  onOpen: (alert: Alert) => void = () => {
  };
  /** 快捷操作完成后通知父级刷新列表，让按钮消失、「已处置」出现 */
  onChanged: (alert: Alert) => void = () => {
  };

  /** 老人联系电话，供「联系老人」拨号。取不到时给明确提示而不是静默失败 */
  @State elderPhone: string = '';
  /** 操作进行中。防止连点导致重复提交处置结果 */
  @State busy: boolean = false;
  /** 删除二次确认中。已闭环的卡片点「删除」后进入此态，防误触 */
  @State confirmingDelete: boolean = false;

  private service: CareService = new CareService();

  aboutToAppear(): void {
    this.loadElderPhone();
  }

  build() {
    Row() {
      Column() {
        // ---------- 第一行：标题 + 等级标签 ----------
        Row() {
          Text(this.alert.alertTypeName)
            .fontSize(AppSize.SUBTITLE_FONT)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.alert.isCritical() ? AppColor.DANGER : AppColor.TEXT)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(AlertLevel.labelOf(this.alert.level))
            .fontSize(AppSize.SMALL_FONT)
            .fontColor(AppColor.CARD)
            .backgroundColor(AppColor.levelColor(this.alert.level))
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(4)
            .margin({ left: 8 })
        }
        .width('100%')

        // ---------- 第二行：正文 ----------
        Text(this.alert.description)
          .fontSize(AppSize.CAPTION_FONT)
          .fontColor(AppColor.TEXT_2)
          .margin({ top: 6 })
          .lineHeight(19)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        // ---------- 第三行：来源 / 时间 / 处置状态（小标签，替代旧版分号连排） ----------
        Row({ space: 6 }) {
          Text(this.deviceLabel())
            .fontSize(AppSize.SMALL_FONT)
            .fontColor(AppColor.TEXT_2)
            .backgroundColor(AppColor.SURFACE)
            .borderRadius(6)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(DateUtil.relative(this.alert.timestamp))
            .fontSize(AppSize.SMALL_FONT)
            .fontColor(AppColor.TEXT_2)
            .backgroundColor(AppColor.SURFACE)
            .borderRadius(6)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          if (this.isHandled()) {
            Text(this.statusText())
              .fontSize(AppSize.SMALL_FONT)
              .fontColor(this.statusColor())
              .backgroundColor(this.statusColor() === AppColor.SUCCESS
                ? 'rgba(46,125,50,0.10)' : AppColor.SURFACE)
              .borderRadius(6)
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .margin({ top: 10 })

        // ---------- 第四行：右下角进入详情 ----------
        Row() {
          Blank()
          Text('点击查看详情 ›')
            .fontSize(AppSize.SMALL_FONT)
            .fontColor(AppColor.TEXT_3)
        }
        .width('100%')
        .margin({ top: 8 })

        // 未处置才给快捷操作；已闭环的给删除入口（两段确认，防误触）
        if (!this.isHandled()) {
          this.actions()
        } else if (!this.confirmingDelete) {
          Row() {
            this.action('删除', false, false, () => {
              this.confirmingDelete = true;
            })
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
          .margin({ top: 10 })
        } else {
          Row() {
            this.action('确认删除', true, false, () => this.removeAlert())
            this.action('取消', false, true, () => {
              this.confirmingDelete = false;
            })
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
          .margin({ top: 10 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      // 等级色条用左边框实现：高度自动贴合内容，不会把父容器撑开。
      .padding({ left: 12 })
      .border({
        width: { left: this.alert.isCritical() ? 6 : 4 },
        color: AppColor.levelColor(this.alert.level)
      })
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: 14, bottom: 14 })
    .backgroundColor(this.alert.isCritical() ? AppColor.levelBg(this.alert.level) : AppColor.CARD)
    .borderRadius(AppSize.CARD_RADIUS)
    // 只有 P0 紧急卡保留红描边（警示信号）；普通卡用阴影替代旧版灰边框
    .border({
      width: this.alert.isCritical() ? 1 : 0,
      color: AppColor.DANGER
    })
    .shadow({
      radius: AppSize.SHADOW_RADIUS,
      color: AppSize.SHADOW_COLOR,
      offsetY: AppSize.SHADOW_OFFSET_Y
    })
    .onClick(() => {
      this.onOpen(this.alert);
    })
  }

  /** 设备来源文案。取不到设备名时给明确占位，不留空 */
  private deviceLabel(): string {
    return this.alert.deviceName.length > 0 ? this.alert.deviceName : '未绑定设备';
  }

  /**
   * 右侧快捷操作。
   * 刻意做轻：小字号、纯色块、无图标 —— 预警列表信息密度高，
   * 操作按钮不该抢焦点，更不能被误认为是预警内容的一部分。
   */
  @Builder
  actions() {
    Row() {
      this.action('联系老人', false, false, () => this.contactElder())
      this.action('标记已处置', true, true, () => this.markHandled())
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .margin({ top: 10 })
  }

  @Builder
  action(label: string, primary: boolean, gapTop: boolean, act: () => void) {
    Text(label)
      .fontSize(AppSize.SMALL_FONT)
      .fontWeight(FontWeight.Medium)
      .fontColor(primary ? AppColor.CARD : AppColor.TEXT_2)
      .backgroundColor(primary ? AppColor.PRIMARY : AppColor.SURFACE)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(14)
      .margin({ left: gapTop ? 8 : 0 })
      .opacity(this.busy ? 0.5 : 1)
      .onClick(() => {
        // 操作中不再响应，避免重复提交处置结果
        if (!this.busy) {
          act();
        }
      })
  }

  // ==================== 状态与文案 ====================

  /** 已闭环（已处置 / 误报）后不再展示快捷操作 */
  private isHandled(): boolean {
    return this.alert.status === AlertStatus.HANDLED
      || this.alert.status === AlertStatus.FALSE_ALARM;
  }

  /** 处置状态文案。已处置带上处置人，便于家属追溯是谁处理的 */
  private statusText(): string {
    if (this.alert.status === AlertStatus.FALSE_ALARM) {
      return '误报';
    }
    if (this.alert.status === AlertStatus.HANDLED) {
      return this.alert.handle !== undefined
        ? `已处置 · ${this.alert.handle.handlerName}`
        : '已处置';
    }
    return AlertStatus.labelOf(this.alert.status);
  }

  private statusColor(): string {
    if (this.alert.status === AlertStatus.HANDLED) {
      return AppColor.SUCCESS;
    }
    if (this.alert.status === AlertStatus.FALSE_ALARM) {
      return AppColor.TEXT_3;
    }
    if (this.alert.status === AlertStatus.PENDING) {
      return AppColor.DANGER;
    }
    return AppColor.WARNING;
  }

  // ==================== 快捷操作 ====================

  /**
   * 联系老人。
   *
   * 直接调起系统拨号盘，把号码预填进去，由用户自己按拨出键。
   * 两个好处：
   *   1. 点一下就真的呼出，在预警列表里太容易误触；
   *   2. PLACE_CALL 是系统级权限，第三方应用拿不到，走拨号盘反而是唯一稳妥做法。
   */
  private contactElder(): void {
    const phone: string = this.elderPhone;
    if (phone.length === 0) {
      this.toast('尚未设置老人联系电话，请前往「我的 → 设置」补充');
      return;
    }
    this.toast(`正在打开拨号盘 · ${phone}`);
    this.dial(phone);
  }

  private dial(phone: string): void {
    try {
      // getContext 已废弃，自定义组件里用 getUIContext().getHostContext() 取宿主上下文
      const ctx: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.startAbility({
        action: 'ohos.want.action.DIAL',
        uri: `tel:${phone}`
      }).catch((e: Error) => {
        Logger.warn('AlertCard', `打开拨号盘失败: ${e.message}`);
        this.toast('未能打开拨号盘，请手动拨打');
      })
    } catch (e) {
      Logger.warn('AlertCard', '打开拨号盘异常');
      this.toast('未能打开拨号盘，请手动拨打');
    }
  }

  /**
   * 删除一条已闭环的告警（两段确认的第二段）。
   *
   * 只删 App 本地这条记录：居家安全日志、活动统计都不动。
   * 待确认的告警根本不会渲染出删除按钮（见 isHandled 分支），
   * 未处置的预警不能凭空消失。
   */
  private async removeAlert(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const ok: boolean = await this.service.deleteAlert(this.alert.alertId);
    this.busy = false;
    this.confirmingDelete = false;
    if (!ok) {
      this.toast('删除失败，请重试');
      return;
    }
    this.toast('已删除该条预警');
    // 与标记已处置同一条路：父级重新拉列表，本条消失
    this.onChanged(this.alert);
  }

  /**
   * 列表页一步标记已处置。
   *
   * 结果记 quick_marked 而不是"老人一切正常"这类带结论的值 ——
   * 安全类 App 不能替用户写结论。要填具体处置结果仍然走详情页。
   */
  private async markHandled(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    Logger.info('AlertCard', `markHandled 触发: ${this.alert.alertId}`);
    const ok: boolean = await this.service.handleAlert(
      this.alert.alertId, HandleResult.QUICK_MARKED, '在预警列表中快速标记已处置');
    this.busy = false;
    Logger.info('AlertCard', `markHandled 结果: ok=${ok}`);
    if (!ok) {
      this.toast('标记失败，请重试');
      return;
    }
    this.toast('已标记为已处置');
    // 交给父级重新拉列表：Alert 是 @Prop 单向传入，
    // 在这里改本地字段不会可靠地刷新视图。
    this.onChanged(this.alert);
  }

  private async loadElderPhone(): Promise<void> {
    try {
      const cfg: DeviceConfig | undefined = await this.service.fetchDeviceConfig();
      if (cfg !== undefined && cfg.elderPhone.length > 0) {
        this.elderPhone = cfg.elderPhone;
      }
    } catch (err) {
      // 联系方式取不到不影响主流程：点击时按钮会给出明确提示
      Logger.warn('AlertCard', `读取老人联系电话失败: ${(err as Error).message}`);
    }
  }

  private toast(message: string): void {
    try {
      // showToast 声明为可能抛异常，必须显式处理，否则编译告警
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (e) {
    }
  }
}
