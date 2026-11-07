import { http } from '@kit.NetworkKit';

interface ApiResponse {
  code: number;
}

export interface WatchCaptcha extends ApiResponse {
  captchaEnabled: boolean;
  uuid?: string;
  img?: string;
}

export interface WatchLogin {
  username: string;
  password: string;
  code: string;
  uuid: string;
}

interface LoginResponse extends ApiResponse {
  token?: string;
}

export interface WatchRecord {
  id: number;
  deviceId: number;
  value?: number;
  systolic?: number;
  diastolic?: number;
  createTime?: string;
  date?: string;
  dateTime?: string;
}

export interface WatchHistoryPage extends ApiResponse {
  total: number;
  rows: WatchRecord[];
}

export class WatchHistoryApi {
  private static readonly BASE_URL: string = 'https://api.cecm.site/prod-api';
  private static readonly DEVICE_ID: string = '9323';
  private static token: string = '';
  private static sessionVersion: number = 0;
  static readonly PAGE_SIZE: number = 25;

  static captcha(): Promise<WatchCaptcha> {
    return WatchHistoryApi.request<WatchCaptcha>('/captchaImage');
  }

  static isSignedIn(): boolean {
    return WatchHistoryApi.token.length > 0;
  }

  static signOut(): void {
    WatchHistoryApi.setToken('');
  }

  private static setToken(token: string): void {
    WatchHistoryApi.token = token;
    WatchHistoryApi.sessionVersion++;
    AppStorage.setOrCreate('watchSessionVersion', WatchHistoryApi.sessionVersion);
  }

  static async login(credentials: WatchLogin): Promise<void> {
    const response = await WatchHistoryApi.request<LoginResponse>('/login', '', credentials);
    if (!response.token) {
      throw new Error('登录未返回会话，请重试');
    }
    WatchHistoryApi.setToken(response.token);
  }

  static async history(metric: string, page: number, pageSize: number = WatchHistoryApi.PAGE_SIZE):
    Promise<WatchHistoryPage> {
    if (!WatchHistoryApi.isSignedIn()) {
      throw new Error('请先登录耆康云盾');
    }
    const deviceId = WatchHistoryApi.DEVICE_ID;
    const result = await WatchHistoryApi.request<WatchHistoryPage>(
      `/health/${metric}/list?deviceId=${deviceId}&pageNum=${page}&pageSize=${pageSize}`, WatchHistoryApi.token);
    if (!Array.isArray(result.rows) || result.rows.some((row: WatchRecord) => String(row.deviceId) !== deviceId)) {
      throw new Error('服务器返回的记录与所选设备不符');
    }
    return result;
  }

  private static async request<T extends ApiResponse>(path: string, token: string = '',
    body?: WatchLogin): Promise<T> {
    const request = http.createHttp();
    const headers: Record<string, string> = { 'Content-Type': 'application/json; charset=utf-8' };
    if (token.length > 0) {
      headers['Authorization'] = `Bearer ${token}`;
    }
    try {
      const response = await request.request(WatchHistoryApi.BASE_URL + path, {
        method: body === undefined ? http.RequestMethod.GET : http.RequestMethod.POST,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        extraData: body === undefined ? undefined : JSON.stringify(body),
        connectTimeout: 8000,
        readTimeout: 8000
      });
      if (response.responseCode === 401 || response.responseCode === 403) {
        throw new Error('请检查登录状态和历史记录查看权限');
      }
      if (response.responseCode !== 200 || typeof response.result !== 'string') {
        throw new Error('耆康云盾暂时无法响应，请稍后重试');
      }
      const result = JSON.parse(response.result) as T;
      if (result.code === 401 || result.code === 403) {
        throw new Error('请检查登录状态和历史记录查看权限');
      }
      if (result.code !== 200) {
        throw new Error(body === undefined ? '暂时无法获取记录，请稍后重试' : '登录失败，请检查账号、密码和验证码');
      }
      return result;
    } finally {
      request.destroy();
    }
  }
}
