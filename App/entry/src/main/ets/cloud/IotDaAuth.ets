/**
 * @file    IotDaAuth.ets
 * @brief   华为云 IAM 令牌获取与自动续期
 *
 * 为什么需要它：
 *   IoTDA 应用侧所有 REST 都要带 `X-Auth-Token`，而这个 token 要从 IAM 换。
 *   手抄一个 token 贴进代码只能撑 24 小时，答辩现场一过期全盘 401。
 *   所以做成：首次调用自动获取 + 到期前自动续期。
 *
 * 调用链：
 *   POST https://iam.{region}.myhuaweicloud.com/v3/auth/tokens
 *   响应 **头** `X-Subject-Token` 里才是 token（不在 body 里，这点最容易搞错）
 *
 * 权限前提：
 *   用的 IAM 用户需要有 IoTDA 的读取权限。主账号默认有；
 *   子账号要额外授予 `IoTDA ReadOnlyAccess` 或更高。
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/utils/Logger';

// ============================================================================
// IAM 请求体结构（ArkTS 不允许裸对象字面量，必须逐层声明）
// ============================================================================

class IamDomain {
  name: string = '';
}

class IamUser {
  domain: IamDomain = new IamDomain();
  name: string = '';
  password: string = '';
}

class IamPassword {
  user: IamUser = new IamUser();
}

class IamIdentity {
  methods: string[] = ['password'];
  password: IamPassword = new IamPassword();
}

class IamProject {
  name: string = '';
}

class IamScope {
  project: IamProject = new IamProject();
}

class IamAuth {
  identity: IamIdentity = new IamIdentity();
  scope: IamScope = new IamScope();
}

class IamTokenReq {
  auth: IamAuth = new IamAuth();
}

/** 令牌结果 */
export class IamToken {
  token: string = '';
  /** 过期时间戳（毫秒）。IAM 默认 24 小时 */
  expiresAt: number = 0;
}

// ============================================================================

export class IotDaAuth {
  private static readonly MODULE: string = 'IotDaAuth';

  /** 提前 10 分钟续期，避免边界时刻 401 */
  private static readonly REFRESH_AHEAD_MS: number = 10 * 60 * 1000;

  private iamHost: string = '';
  private domainName: string = '';
  private userName: string = '';
  private password: string = '';
  private projectName: string = '';

  private cached: IamToken | undefined = undefined;

  /**
   * @param region      区域，如 cn-north-4
   * @param domainName  华为云账号名（不是 IAM 用户名）
   * @param userName    IAM 用户名；主账号登录时通常与账号名相同
   * @param password    密码
   * @param projectName 项目名，通常与 region 同名，如 cn-north-4
   */
  constructor(region: string, domainName: string, userName: string,
              password: string, projectName: string) {
    this.iamHost = `https://iam.${region}.myhuaweicloud.com`;
    this.domainName = domainName;
    this.userName = userName;
    this.password = password;
    this.projectName = projectName;
  }

  /** 是否已配置账号密码 */
  isConfigured(): boolean {
    return this.userName.length > 0 && this.password.length > 0;
  }

  /**
   * 取可用 token。缓存有效直接返回，过期或首次则去 IAM 换。
   */
  async getToken(): Promise<string> {
    const now: number = Date.now();
    if (this.cached !== undefined
      && this.cached.token.length > 0
      && this.cached.expiresAt - IotDaAuth.REFRESH_AHEAD_MS > now) {
      return this.cached.token;
    }
    return await this.fetch();
  }

  /** 强制丢弃缓存（比如收到 401 时调用） */
  invalidate(): void {
    this.cached = undefined;
  }

  private buildBody(): IamTokenReq {
    const req: IamTokenReq = new IamTokenReq();
    req.auth.identity.methods = ['password'];
    req.auth.identity.password.user.domain.name = this.domainName;
    req.auth.identity.password.user.name = this.userName;
    req.auth.identity.password.user.password = this.password;
    req.auth.scope.project.name = this.projectName;
    return req;
  }

  private async fetch(): Promise<string> {
    if (!this.isConfigured()) {
      throw new Error('IAM 账号未配置，无法获取 token');
    }

    const url: string = `${this.iamHost}/v3/auth/tokens`;
    const request: http.HttpRequest = http.createHttp();

    try {
      const resp: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json;charset=utf8' },
        extraData: JSON.stringify(this.buildBody()),
        connectTimeout: 15000,
        readTimeout: 15000
      });

      if (resp.responseCode !== 201 && resp.responseCode !== 200) {
        const text: string = typeof resp.result === 'string'
          ? resp.result : JSON.stringify(resp.result);
        Logger.error(IotDaAuth.MODULE, `IAM 换 token 失败 HTTP ${resp.responseCode}: ${text}`);
        throw new Error(`IAM 鉴权失败 HTTP ${resp.responseCode}`);
      }

      // token 在响应头 X-Subject-Token，不在 body
      const token: string = this.readHeader(resp, 'X-Subject-Token');
      if (token.length === 0) {
        throw new Error('IAM 响应头里没有 X-Subject-Token');
      }

      const t: IamToken = new IamToken();
      t.token = token;
      t.expiresAt = Date.now() + 24 * 3600 * 1000;
      this.cached = t;

      Logger.info(IotDaAuth.MODULE, 'IAM token 获取成功（有效期约 24h）');
      return token;
    } catch (e) {
      if (e instanceof Error) {
        throw e;
      }
      const be: BusinessError = e as BusinessError;
      throw new Error(`IAM 网络异常: ${be.code} ${be.message}`);
    } finally {
      request.destroy();
    }
  }

  /**
   * 从响应头里取字段。
   * http.HttpResponse.header 是 Object，不同版本可能大小写不同，
   * 所以统一转成小写再比一次，避免踩坑。
   */
  private readHeader(resp: http.HttpResponse, name: string): string {
    const lower: string = name.toLowerCase();
    try {
      const map: Record<string, string> = resp.header as Record<string, string>;
      const keys: string[] = Object.keys(map);
      for (const k of keys) {
        if (k.toLowerCase() === lower) {
          return `${map[k]}`;
        }
      }
    } catch (e) {
      Logger.warn(IotDaAuth.MODULE, `读响应头失败: ${(e as Error).message}`);
    }
    return '';
  }
}
