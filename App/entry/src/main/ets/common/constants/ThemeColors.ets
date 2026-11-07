/**
 * 界面配色与尺寸。
 *
 * 视觉定位：安全、可信、克制。
 * 主色用深蓝（传达可靠），辅助色用青绿（健康），危险色用砖红（告警）。
 * 与"耆康云盾"的蓝绿盾牌视觉完全区分。
 */
export class AppColor {
  /** 主色 · 品牌蓝（比旧深蓝提亮，白字对比度仍达标） */
  static readonly PRIMARY: string = '#1A5FD6';
  /** 辅助色 · 青绿 */
  static readonly SECONDARY: string = '#2E7D6B';
  /** 危险色 · 砖红 */
  static readonly DANGER: string = '#C62828';
  /** 警示色 · 琥珀 */
  static readonly WARNING: string = '#E08A00';
  /** 正常色 · 绿 */
  static readonly SUCCESS: string = '#2E7D32';
  /** 协同角色色 · 浅蓝。
   *  只用于家庭成员里的社区网格员 / 物业值班标签。
   *  这两个角色是"外部协同方"，跟直系家属在权限上不同（看不到活动报告），
   *  用浅蓝而不是青绿，家属一眼能看出"这是外人，但收到了告警" */
  static readonly INFO: string = '#5B93C4';

  /** 页面底色 */
  static readonly BG: string = '#F4F6FA';
  /** 卡片底 */
  static readonly CARD: string = '#FFFFFF';
  /** 主文本 */
  static readonly TEXT: string = '#1A1D21';
  /** 次文本 */
  static readonly TEXT_2: string = 'rgba(26,29,33,0.66)';
  /** 弱文本 */
  static readonly TEXT_3: string = 'rgba(26,29,33,0.45)';
  /** 分割线 */
  static readonly LINE: string = 'rgba(26,29,33,0.12)';
  /** 浅底 */
  static readonly SURFACE: string = 'rgba(26,29,33,0.04)';

  // ==================== 视觉规范（2026-11 UI 翻新） ====================
  /** 头部渐变 · 顶端色。与 PRIMARY 同族、略亮，用于渐变头/横幅起点 */
  static readonly GRAD_TOP: string = '#2C6FE3';
  /** 头部渐变 · 底端色。渐变落点，白字对比度优先于亮度 */
  static readonly GRAD_BOT: string = '#173F9C';
  /** 主色浅底（次级按钮 / 图标底）。低透明品牌蓝，压在白卡上不显脏 */
  static readonly PRIMARY_SOFT: string = 'rgba(26,95,214,0.10)';

  /**
   * 告警等级色。
   *
   * 严重度阶梯：P0 红 → P1 橙黄 → P2 绿 → P3 灰。
   *
   * 这套配色与活动报告页、传感器卡片三色体系共用同一组色值语义：
   *   红 = 紧急高危（燃气 / 烟雾 / SOS，仅这一类用红）
   *   橙黄 = 高风险 → 同时是"健康关注"的口径色
   *   绿 = 正常 / 需关注
   *   灰 = 普通提示
   * 家属在任何一页看到颜色，含义都一样，不需要在脑子里做映射。
   *
   * 注意 P2 曾是黄色、现已改为绿色：预警中心页的配色规范明确
   * "绿色=需关注、橙黄=高风险"，两档必须分开。若 P2 保持黄，
   * 与 P1 的橙黄在投屏上几乎分不出等级差。
   */
  static levelColor(level: string): string {
    switch (level) {
      case 'P0':
        return AppColor.DANGER;      // 砖红 · 紧急
      case 'P1':
        return AppColor.WARNING;     // 橙黄 · 高风险
      case 'P2':
        return AppColor.SUCCESS;     // 绿 · 需关注
      default:
        return AppColor.TEXT_3;      // 浅灰 · 提示
    }
  }

  /** 告警等级浅底 */
  static levelBg(level: string): string {
    switch (level) {
      case 'P0':
        return 'rgba(198,40,40,0.06)';
      case 'P1':
        return 'rgba(224,138,0,0.08)';
      case 'P2':
        return 'rgba(46,125,50,0.08)';
      default:
        return AppColor.SURFACE;
    }
  }

  /**
   * 传感器状态 → 圆点颜色（三色体系 + 离线灰）。
   * 绿=正常、黄=待关注、红=高危、灰=离线。
   */
  static statusColor(status: string): string {
    switch (status) {
      case 'normal':
        return AppColor.SUCCESS;
      case 'warning':
        return AppColor.WARNING;
      case 'danger':
        return AppColor.DANGER;
      default:
        return AppColor.TEXT_3;
    }
  }

  /** 传感器状态 → 卡片描边色。正常与离线都用中性分割线，避免整屏花掉 */
  static statusBorder(status: string): string {
    switch (status) {
      case 'warning':
        return 'rgba(224,138,0,0.45)';
      case 'danger':
        return AppColor.DANGER;
      default:
        return AppColor.LINE;
    }
  }

  /** 传感器状态 → 图标与数值文字色。常态深灰，只有异常才着色 */
  static statusTextColor(status: string): string {
    switch (status) {
      case 'normal':
        return AppColor.TEXT;
      case 'warning':
        return AppColor.WARNING;
      case 'danger':
        return AppColor.DANGER;
      default:
        return AppColor.TEXT_3;
    }
  }

  /**
   * 传感器状态 → 图标色。常态深灰保持页面低调，异常才跟随状态色
   */
  static statusIconColor(status: string): string {
    switch (status) {
      case 'normal':
        return AppColor.TEXT_2;
      case 'warning':
        return AppColor.WARNING;
      case 'danger':
        return AppColor.DANGER;
      default:
        return AppColor.TEXT_3;
    }
  }

  // ==================== 智能研判分级 ====================
  // 三档：正常（绿）/ 关注（浅橙）/ 异常告警（红）。
  // 「关注」档刻意不用红：老人夜间活动偏多、活动量波动这类事
  // 属于"建议留意"，不是"危险"。把提示也刷成红，整页会没有信息层级，
  // 家属很快对所有红色脱敏 —— 那才是真的危险。
  /** 研判分级 · 正常 */
  static readonly INSIGHT_NORMAL: string = 'normal';
  /** 研判分级 · 关注 */
  static readonly INSIGHT_ATTENTION: string = 'attention';
  /** 研判分级 · 异常告警 */
  static readonly INSIGHT_DANGER: string = 'danger';

  /** 研判分级 → 标签底色 */
  static insightBg(level: string): string {
    switch (level) {
      case AppColor.INSIGHT_ATTENTION:
        return 'rgba(224,138,0,0.14)';   // 浅橙
      case AppColor.INSIGHT_DANGER:
        return 'rgba(198,40,40,0.10)';   // 浅红
      default:
        return 'rgba(46,125,50,0.12)';   // 浅绿
    }
  }

  /** 研判分级 → 标签文字色 */
  static insightText(level: string): string {
    switch (level) {
      case AppColor.INSIGHT_ATTENTION:
        return '#B26A00';                // 深橙：浅橙底上要压得住
      case AppColor.INSIGHT_DANGER:
        return AppColor.DANGER;
      default:
        return '#2C7A38';                // 深绿：同理
    }
  }

  /** 研判分级 → 卡片描边色 */
  static insightBorder(level: string): string {
    switch (level) {
      case AppColor.INSIGHT_ATTENTION:
        return 'rgba(224,138,0,0.45)';
      case AppColor.INSIGHT_DANGER:
        return 'rgba(198,40,40,0.40)';
      default:
        return 'rgba(46,125,50,0.32)';
    }
  }
}

export class AppSize {
  static readonly PAGE_PADDING: number = 16;
  static readonly CARD_RADIUS: number = 16;
  static readonly SMALL_RADIUS: number = 8;
  /** 卡片阴影半径 */
  static readonly SHADOW_RADIUS: number = 14;
  /** 卡片阴影色。主色族低透明，冷调投影，与灰边框比更"轻" */
  static readonly SHADOW_COLOR: string = 'rgba(23,63,156,0.08)';
  /** 卡片阴影纵向偏移 */
  static readonly SHADOW_OFFSET_Y: number = 3;
  static readonly TITLE_FONT: number = 22;
  static readonly SUBTITLE_FONT: number = 16;
  static readonly BODY_FONT: number = 15;
  static readonly CAPTION_FONT: number = 13;
  static readonly SMALL_FONT: number = 11;
}
