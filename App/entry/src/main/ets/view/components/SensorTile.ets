import { Sensor } from '../../model/Device';
import { AppColor, AppSize } from '../../common/constants/ThemeColors';
import { SensorType } from '../../common/constants/AppConstants';

/**
 * 传感器状态卡片 —— 全应用统一模板。
 *
 * 两行结构固定，六张卡片一律遵守，不再各自排版：
 *   第一行：左上角图标 + 主标题        右上角状态圆点
 *   第二行：监测信息，统一「标签：数值」
 *
 * 状态唯一来源是 Sensor.status()，颜色唯一来源是 AppColor.statusColor()：
 *   绿 = 正常 ／ 黄 = 待关注 ／ 红 = 高危 ／ 灰 = 设备离线
 *
 * 图标与文字在常态下保持深灰，只有异常才跟随状态色着色。
 * 这样静态页面足够低调，圆点成为屏幕上唯一的颜色信号，
 * 家属扫一眼就能定位到哪张卡片出了问题。
 */
@Component
export struct SensorTile {
  @Prop sensor: Sensor;

  build() {
    Column() {
      // ---------- 第一行：图标 + 主标题 + 状态圆点 ----------
      Row() {
        this.tileIcon()

        Text(this.sensor.name)
          .fontSize(AppSize.CAPTION_FONT)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.statusTextColor(this.sensor.status()))
          .margin({ left: 6 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        // 状态圆点：三色体系 + 离线灰
        Row()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(AppColor.statusColor(this.sensor.status()))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // ---------- 第二行：监测信息（标签：数值） ----------
      // 离线时由 Sensor.infoText() 统一给出【设备离线】，不留空白
      Text(this.sensor.infoText())
        .fontSize(AppSize.SMALL_FONT)
        .fontColor(this.infoColor())
        .margin({ top: 8 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(AppColor.CARD)
    .borderRadius(AppSize.SMALL_RADIUS)
    .border({ width: 1, color: AppColor.statusBorder(this.sensor.status()) })
  }

  /** 监测信息文字色：异常跟随状态色，常态保持次文本灰 */
  private infoColor(): string {
    return this.sensor.isAbnormal()
      ? AppColor.statusTextColor(this.sensor.status())
      : AppColor.TEXT_2;
  }

  /**
   * 卡片左上角图标。
   *
   * SOS 走细线线性小标：常态深灰、静态页面低调，
   * 只有真的按下求助（状态转红）时整块小标才变红。
   * 刻意不用大红感叹号那种"随时要炸"的图形 —— 一个长期挂在首页的
   * 强刺激符号，会让家属对真正的告警脱敏。
   */
  @Builder
  tileIcon() {
    if (this.sensor.sensorType === SensorType.SOS_BUTTON) {
      Text('SOS')
        .fontSize(9)
        .fontWeight(FontWeight.Medium)
        .letterSpacing(0.6)
        .fontColor(AppColor.statusIconColor(this.sensor.status()))
        .border({
          width: 1,
          color: AppColor.statusIconColor(this.sensor.status()),
          radius: 3
        })
        .padding({ left: 3, right: 3, top: 2, bottom: 2 })
    } else {
      Text(this.glyphOf(this.sensor.sensorType))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.statusIconColor(this.sensor.status()))
    }
  }

  /**
   * 传感器类型图标。
   * 沿用工程既有约定：用文字符号表达，不引入版权不明的位图素材。
   */
  private glyphOf(type: string): string {
    switch (type) {
      case SensorType.PIR:
        return '人';
      case SensorType.DOOR:
        return '门';
      case SensorType.TEMP_HUMIDITY:
        return '温';
      case SensorType.SMOKE:
        return '烟';
      case SensorType.GAS:
        return '气';
      case SensorType.HEART_RATE:
        return '心';
      default:
        return '感';
    }
  }
}
