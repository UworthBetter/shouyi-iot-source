import { CloudApi } from './CloudApi';
import { MockCloudAdapter } from './MockCloudAdapter';
import { SeniorCloudAdapter } from './SeniorCloudAdapter';
import { IotDaCloudAdapter } from './IotDaCloudAdapter';
import { IotDaHttp } from './IotDaHttp';
import { IotDaAuth } from './IotDaAuth';
import { IotDaSigner } from './IotDaSigner';
import { AppConstants } from '../common/constants/AppConstants';
import { Logger } from '../common/utils/Logger';

/**
 * 云端适配器工厂 —— 全应用唯一决定"用哪个云端实现"的地方。
 *
 * 业务层与 UI 通过 AppConfig.getCloudApi() 获取 CloudApi 实例，
 * 永远不直接 new 具体实现，因此切换云端实现不需要改动业务代码。
 */
export class AppConfig {
  private static readonly MODULE: string = 'AppConfig';

  /**
   * 是否使用 Mock 云端。
   * true  → 本地模拟数据，接口文档未到时使用，App 可完整跑通
   * false → 对接学长云端服务器
   */
  static useMock: boolean = true;

  /**
   * 是否使用华为云 IoTDA。
   * 用静态可变字段而不是常量：编译器无法证明它为 false，
   * 分支才会被保留，IotDaCloudAdapter 才不会被当死代码摇掉。
   */
  static useIotDa: boolean = false;

  /** 华为云 IoTDA 参数（useIotDa = true 时生效） */
  static projectId: string = '';
  static deviceId: string = '';
  static familyId: string = 'fam_0001';
  static iamToken: string = '';

  /** 云端服务地址 */
  static baseUrl: string = AppConstants.CLOUD_BASE_URL;

  private static instance: CloudApi | undefined = undefined;
  private static seniorAdapter: SeniorCloudAdapter | undefined = undefined;

  /** 获取云端接口实例（单例） */
  static getCloudApi(): CloudApi {
    if (AppConfig.instance === undefined) {
      AppConfig.instance = AppConfig.create();
    }
    return AppConfig.instance;
  }

  private static create(): CloudApi {
    if (AppConfig.useIotDa) {
      Logger.info(AppConfig.MODULE, `云端实现：华为云 IoTDA ${AppConfig.baseUrl}`);
      const h: IotDaHttp = new IotDaHttp(AppConfig.baseUrl, AppConfig.projectId);
      h.setToken(AppConfig.iamToken);
      return new IotDaCloudAdapter(h, AppConfig.projectId, AppConfig.deviceId, AppConfig.familyId);
    }
    if (AppConfig.useMock) {
      Logger.info(AppConfig.MODULE, '云端实现：Mock（本地模拟数据）');
      return new MockCloudAdapter();
    }
    Logger.info(AppConfig.MODULE, `云端实现：学长云端服务器 ${AppConfig.baseUrl}`);
    AppConfig.seniorAdapter = new SeniorCloudAdapter(AppConfig.baseUrl);
    return AppConfig.seniorAdapter;
  }

  /** 切换到华为云 IoTDA */
  static switchToIotDa(baseUrl: string, projectId: string, deviceId: string,
                       familyId: string, iamToken: string): void {
    AppConfig.useIotDa = true;
    AppConfig.useMock = false;
    AppConfig.baseUrl = baseUrl;
    AppConfig.projectId = projectId;
    AppConfig.deviceId = deviceId;
    AppConfig.familyId = familyId;
    AppConfig.iamToken = iamToken;
    AppConfig.instance = undefined;
    Logger.info(AppConfig.MODULE, '已切换到华为云 IoTDA');
  }

  /**
   * 切换到华为云 IoTDA（AK/SK 签名，推荐）。
   *
   * 相比 IAM token：AK/SK 长期有效，签名在本地算，不依赖登录态，
   * 答辩现场不会因为 token 过期而全盘 401。
   *
   * @param baseUrl  应用侧接入域名，形如
   *                 https://2eb62113b2.st1.iotda-app.cn-north-4.myhuaweicloud.com
   * @param ak       Access Key Id
   * @param sk       Secret Access Key
   */
  static switchToIotDaAkSk(baseUrl: string, projectId: string, deviceId: string,
                           familyId: string, ak: string, sk: string): void {
    AppConfig.useIotDa = true;
    AppConfig.useMock = false;
    AppConfig.baseUrl = baseUrl;
    AppConfig.projectId = projectId;
    AppConfig.deviceId = deviceId;
    AppConfig.familyId = familyId;

    const signer: IotDaSigner = new IotDaSigner(ak, sk);
    const h: IotDaHttp = new IotDaHttp(baseUrl, projectId);
    h.setSigner(signer);
    AppConfig.instance = new IotDaCloudAdapter(h, projectId, deviceId, familyId);
    Logger.info(AppConfig.MODULE, '已切换到华为云 IoTDA（AK/SK 签名）');
  }

  /**
   * 切换到华为云 IoTDA（推荐）—— 用 IAM 账号密码自动取 token。
   *
   * 与 switchToIotDa 的区别：那个要手工贴 token，24 小时就过期；
   * 这个把账号密码交给 IotDaAuth，token 到期前自动续期。
   *
   * @param baseUrl     应用侧接入域名，从控制台「总览 → 接入信息」抄，形如
   *                    https://xxxx.iotda-app.cn-north-4.myhuaweicloud.com
   * @param region      区域，如 cn-north-4
   * @param domainName  华为云账号名（不是 IAM 用户名）
   * @param userName    IAM 用户名，主账号登录时通常与账号名相同
   */
  static switchToIotDaAuto(baseUrl: string, region: string, projectId: string,
                           deviceId: string, familyId: string, domainName: string,
                           userName: string, password: string): void {
    AppConfig.useIotDa = true;
    AppConfig.useMock = false;
    AppConfig.baseUrl = baseUrl;
    AppConfig.projectId = projectId;
    AppConfig.deviceId = deviceId;
    AppConfig.familyId = familyId;

    const auth: IotDaAuth = new IotDaAuth(region, domainName, userName, password, region);
    const h: IotDaHttp = new IotDaHttp(baseUrl, projectId);
    h.setAuth(auth);
    AppConfig.instance = new IotDaCloudAdapter(h, projectId, deviceId, familyId);
    Logger.info(AppConfig.MODULE, '已切换到华为云 IoTDA（IAM 自动续期）');
  }

  /**
   * 切换到真实云端。
   * 登录成功后调用，传入服务地址与访问令牌。
   */
  static switchToRealCloud(baseUrl: string, accessToken: string): void {
    AppConfig.useMock = false;
    AppConfig.baseUrl = baseUrl;
    const adapter: SeniorCloudAdapter = new SeniorCloudAdapter(baseUrl);
    adapter.setAccessToken(accessToken);
    AppConfig.seniorAdapter = adapter;
    AppConfig.instance = adapter;
    Logger.info(AppConfig.MODULE, '已切换到真实云端');
  }

  /** 切回 Mock（调试用） */
  static switchToMock(): void {
    AppConfig.useMock = true;
    AppConfig.instance = new MockCloudAdapter();
    Logger.info(AppConfig.MODULE, '已切换到 Mock 云端');
  }

  /** 当前是否使用 Mock */
  static isMock(): boolean {
    return AppConfig.useMock;
  }
}
