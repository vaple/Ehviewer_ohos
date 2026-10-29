import { hilog } from '@kit.PerformanceAnalysisKit';
import { DiagLog } from '../service/DiagLog';

const DOMAIN: number = 0x0000;

/**
 * 双写日志：hilog（开发态 `hdc shell hilog` 直接看）+ 沙盒文件（`DiagLog`，用户可导出）。
 *
 * 签名保持不变，95 处调用零改动。文件侧自带脱敏与截断（`Redact` / `LogFormat`），
 * 调用方不需要关心敏感信息。
 */
export class Logger {
  static info(tag: string, message: string): void {
    hilog.info(DOMAIN, tag, '%{public}s', message);
    DiagLog.append('I', tag, message);
  }

  static error(tag: string, message: string): void {
    hilog.error(DOMAIN, tag, '%{public}s', message);
    DiagLog.append('E', tag, message);
  }
}
