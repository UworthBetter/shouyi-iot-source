import { HomePage } from '../view/HomePage';
import { RealtimeStatusPage } from '../view/RealtimeStatusPage';
import { ActivityReportPage } from '../view/ActivityReportPage';
import { AlertCenterPage } from '../view/AlertCenterPage';
import { MinePage } from '../view/MinePage';
import { PushMessage } from '../cloud/CloudTypes';
import { CareService } from '../service/CareService';
import { AppColor } from '../common/constants/ThemeColors';
import { Logger } from '../common/utils/Logger';

/**
 * 应用主框架 —— 五 Tab 容器。
 *
 * 这是 EntryAbility 启动后加载的第一个页面（`windowStage.loadContent('pages/Index')`）。
 * 职责很单一：承载五个业务页面并维护底部导航，自身不含任何业务逻辑。
 *
 * 五个 Tab 的分工（首页 → 四大模块）：
 *   首页      → 只回答"有没有待处理"，并给出四个模块入口
 *   实时状态  → 各传感器当前值与历史曲线
 *   活动报告  → 活动时段分布 / 频次趋势 / 周月报告
 *   预警中心  → 历史预警查询、详情与处置闭环
 *   设置与设备 → 家庭成员与角色、居家安全日志、演示与设置
 *
 * 设计取舍一：底部导航图标用 SymbolGlyph 系统符号库（sys.symbol.*）。
 * 本工程仍不引入位图图标素材 —— 版权边界不变；SymbolGlyph 是系统内置
 * 矢量符号，零素材文件、任意分辨率不失真，选中态随主题色联调。
 *
 * 设计取舍二：首页宫格不 push 新页面，而是切换 Tab。
 * 五个 Tab 已经把功能分完了，再叠一层"首页 → 二级页 → 返回"只会让层级变深，
 * 对老年人家属这类低频用户不友好。所以 HomePage 通过 onNavigate 回调直接切 Tab。
 */
@Entry
@Component
struct Index {
  private static readonly MODULE: string = 'Index';

  /** 预警中心的 Tab 下标（角标挂在这里） */
  private static readonly TAB_ALERT: number = 3;

  /** 当前选中的 Tab 下标 */
  @State currentIndex: number = 0;
  /** 待处置预警数，用于"预警中心"Tab 的角标 */
  @State pendingCount: number = 0;
  @StorageLink('alertRefreshTick') @Watch('onAlertsChanged') alertTick: number = 0;
  @State latestAlert: PushMessage | undefined = undefined;

  private service: CareService = new CareService();
  private tabsController: TabsController = new TabsController();

  aboutToAppear(): void {
    this.refreshBadge();
    this.service.subscribeAlerts((msg: PushMessage) => {
      this.latestAlert = msg;
      CareService.notifyAlertsChanged();
    });
  }

  aboutToDisappear(): void {
    this.service.unsubscribeAlerts();
  }

  onAlertsChanged(): void {
    this.refreshBadge();
  }

  /**
   * 刷新待处置角标。
   * 切到预警 Tab 或从详情页返回时都会调用，保证角标与实际状态一致。
   */
  async refreshBadge(): Promise<void> {
    try {
      this.pendingCount = await this.service.countPendingAlerts();
    } catch (err) {
      // 角标是辅助信息，取不到就不显示，不能因此影响主流程
      Logger.warn(Index.MODULE, `刷新待处置角标失败: ${(err as Error).message}`);
      this.pendingCount = 0;
    }
  }

  /** 首页宫格 → 切换对应 Tab */
  private goToTab(index: number): void {
    this.currentIndex = index;
    this.tabsController.changeIndex(index);
    if (index === Index.TAB_ALERT) {
      this.refreshBadge();
    }
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController }) {
      TabContent() {
        HomePage({
          latestAlert: this.latestAlert,
          onNavigate: (index: number) => {
            this.goToTab(index);
          }
        })
      }
      .tabBar(this.tabItem(0, '首页', $r('sys.symbol.house_fill')))

      TabContent() {
        RealtimeStatusPage({ active: this.currentIndex === 1 })
      }
      .tabBar(this.tabItem(1, '实时状态', $r('sys.symbol.heart_fill')))

      TabContent() {
        ActivityReportPage()
      }
      .tabBar(this.tabItem(2, '活动报告', $r('sys.symbol.doc_text')))

      TabContent() {
        AlertCenterPage()
      }
      .tabBar(this.tabItem(Index.TAB_ALERT, '预警中心', $r('sys.symbol.bell_fill')))

      TabContent() {
        MinePage()
      }
      .tabBar(this.tabItem(4, '设置与设备', $r('sys.symbol.gearshape_fill')))
    }
    .barMode(BarMode.Fixed)
    .barHeight(62)
    .barBackgroundColor(AppColor.CARD)
    .scrollable(true)
    .animationDuration(200)
    .onChange((index: number) => {
      this.currentIndex = index;
      // 进入预警页时刷新角标与列表：用户可能刚在详情页处置完，或在实时页模拟了告警
      if (index === Index.TAB_ALERT) {
        CareService.notifyAlertsChanged();
      }
    })
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.BG)
  }

  /**
   * 单个底部导航项：SymbolGlyph 图标 + 文字。
   * 选中态图标与文字同色（主色）加粗，未选中整体弱化为弱文本色；
   * 去掉了旧版的顶部指示条 —— 图标本身的颜色变化已足够表达选中态。
   *
   * 文字保持小字号：五个 Tab 里"设置与设备"是五个字，
   * 在 360dp 屏上要给图标让位，不能放大。
   */
  @Builder
  tabItem(index: number, title: string, icon: Resource) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(21)
        .fontColor([this.currentIndex === index ? AppColor.PRIMARY : AppColor.TEXT_3])

      Row() {
        Text(title)
          .fontSize(10)
          .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.currentIndex === index ? AppColor.PRIMARY : AppColor.TEXT_3)
          .margin({ top: 3 })
          .maxLines(1)

        // 仅"预警中心"Tab 显示待处置角标
        if (index === Index.TAB_ALERT && this.pendingCount > 0) {
          Text(this.pendingCount > 99 ? '99+' : `${this.pendingCount}`)
            .fontSize(9)
            .fontColor(AppColor.CARD)
            .backgroundColor(AppColor.DANGER)
            .borderRadius(9)
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .margin({ left: 3 })
        }
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
