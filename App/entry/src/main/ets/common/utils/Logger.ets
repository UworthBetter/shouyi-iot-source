import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 统一日志封装。分层架构下所有模块共用同一 domain，便于按模块过滤。
 */
export class Logger {
  private static readonly DOMAIN: number = 0x9901;
  private static readonly TAG: string = 'ShouYi';

  static debug(module: string, message: string): void {
    hilog.debug(Logger.DOMAIN, Logger.TAG, '[%{public}s] %{public}s', module, message);
  }

  static info(module: string, message: string): void {
    hilog.info(Logger.DOMAIN, Logger.TAG, '[%{public}s] %{public}s', module, message);
  }

  static warn(module: string, message: string): void {
    hilog.warn(Logger.DOMAIN, Logger.TAG, '[%{public}s] %{public}s', module, message);
  }

  static error(module: string, message: string): void {
    hilog.error(Logger.DOMAIN, Logger.TAG, '[%{public}s] %{public}s', module, message);
  }
}
