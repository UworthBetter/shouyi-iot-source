import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { NetworkMonitor } from '../service/NetworkMonitor';
import { AppConfig } from '../cloud/CloudApiFactory';
import { IotDaCloudAdapter } from '../cloud/IotDaCloudAdapter';
import { IotDaConfig } from '../cloud/IotDaConfig';
import { Logger } from '../common/utils/Logger';

/**
 * 应用入口 Ability。
 *
 * 启动编排：
 *   1. 启动网络监听（为离线降级做准备）
 *   2. 加载首页
 *
 * 与赛题一不同：本作品不在启动时做本地数据库预置，
 * 因为设备与告警数据都来自云端，本地只做轻量缓存。
 */
export default class EntryAbility extends UIAbility {
  private static readonly MODULE: string = 'EntryAbility';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Logger.info(EntryAbility.MODULE, 'Ability onCreate');

    // 1) 切到华为云 IoTDA（IAM 子用户，token 自动续期）
    AppConfig.switchToIotDaAuto(
      IotDaConfig.ENDPOINT, IotDaConfig.REGION, IotDaConfig.PROJECT_ID,
      IotDaConfig.DEVICE_ID, IotDaConfig.FAMILY_ID,
      IotDaConfig.DOMAIN_NAME, IotDaConfig.USER_NAME, IotDaConfig.PASSWORD);

    // 2) 把沙箱目录注入适配器，开启告警 / 安全日志 / 活动统计的本地持久化。
    //    平台不提供这些业务数据，必须落在 App 端。
    const api = AppConfig.getCloudApi();
    if (api instanceof IotDaCloudAdapter) {
      (api as IotDaCloudAdapter).initStore(this.context.filesDir);
    }
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    Logger.info(EntryAbility.MODULE, '窗口创建，开始初始化');

    // 网络监听：网络恢复后由各页面自行触发刷新
    NetworkMonitor.start();
    await NetworkMonitor.refresh();

    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        Logger.error(EntryAbility.MODULE, `加载首页失败: ${err.code} ${err.message}`);
        return;
      }
      Logger.info(EntryAbility.MODULE, '首页加载完成');
    });
  }

  onDestroy(): void {
    Logger.info(EntryAbility.MODULE, 'Ability onDestroy');
  }

  onForeground(): void {
    Logger.info(EntryAbility.MODULE, '应用进入前台');
  }

  onBackground(): void {
    Logger.info(EntryAbility.MODULE, '应用进入后台');
  }
}
