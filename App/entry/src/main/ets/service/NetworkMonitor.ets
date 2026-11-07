import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/utils/Logger';

/** 网络状态变化回调 */
export type NetworkListener = (online: boolean) => void;

/**
 * 网络状态监听。
 *
 * 作用：网络恢复时触发一次全量数据刷新。
 * 与赛题一不同，本作品的核心安全能力在**设备端**（开发板本地判定 + 声光报警），
 * 所以 App 侧离线只影响"查看"，不影响"守护"——这是本作品的关键设计取舍。
 */
export class NetworkMonitor {
  private static readonly MODULE: string = 'NetworkMonitor';
  private static online: boolean = true;
  private static listeners: NetworkListener[] = [];
  private static registered: boolean = false;

  static isOnline(): boolean {
    return NetworkMonitor.online;
  }

  /** 注册网络状态监听（幂等） */
  static start(): void {
    if (NetworkMonitor.registered) {
      return;
    }
    try {
      const netHandle: connection.NetConnection = connection.createNetConnection();
      netHandle.on('netAvailable', () => {
        NetworkMonitor.update(true);
      });
      netHandle.on('netLost', () => {
        NetworkMonitor.update(false);
      });
      netHandle.on('netUnavailable', () => {
        NetworkMonitor.update(false);
      });
      netHandle.register((err: BusinessError) => {
        if (err) {
          Logger.error(NetworkMonitor.MODULE, `网络监听注册失败: ${err.code} ${err.message}`);
          return;
        }
        Logger.info(NetworkMonitor.MODULE, '网络监听已注册');
      });
      NetworkMonitor.registered = true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.error(NetworkMonitor.MODULE, `创建网络连接对象失败: ${e.message}`);
    }
  }

  /** 主动查询一次当前网络状态 */
  static async refresh(): Promise<boolean> {
    try {
      // 注意：hasDefaultNet 是 connection 模块的【模块级函数】，
      // 不是 NetConnection 的实例方法；旧写法 netHandle.getNetCapabilities() 编译不过。
      const online: boolean = await connection.hasDefaultNet();
      NetworkMonitor.update(online);
      return online;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.warn(NetworkMonitor.MODULE, `查询网络状态失败，按离线处理: ${e.message}`);
      NetworkMonitor.update(false);
      return false;
    }
  }

  static subscribe(listener: NetworkListener): void {
    if (NetworkMonitor.listeners.indexOf(listener) < 0) {
      NetworkMonitor.listeners.push(listener);
    }
  }

  static unsubscribe(listener: NetworkListener): void {
    const idx: number = NetworkMonitor.listeners.indexOf(listener);
    if (idx >= 0) {
      NetworkMonitor.listeners.splice(idx, 1);
    }
  }

  private static update(online: boolean): void {
    const changed: boolean = NetworkMonitor.online !== online;
    NetworkMonitor.online = online;
    if (changed) {
      Logger.info(NetworkMonitor.MODULE, online ? '网络已恢复' : '网络已断开');
    }
    for (const l of NetworkMonitor.listeners) {
      l(online);
    }
  }
}
