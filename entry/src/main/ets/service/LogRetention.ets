/**
 * 日志保留策略（纯函数）：什么时候清扫、哪些故障日志该删、当前日志是否该轮转。
 *
 * 策略：业务日志 `1MB × 3`、崩溃日志 `512KB × 2`、
 * 故障日志最多 5 个且不超过 7 天、清扫间隔 3 天（避免每次冷启动都扫目录）。
 */

const DAY_MS: number = 24 * 3600 * 1000;

/** 业务日志单文件上限（1MB）。 */
export const APP_LOG_LIMIT_BYTES: number = 1024 * 1024;
/** 崩溃日志单文件上限（512KB）。 */
export const CRASH_LOG_LIMIT_BYTES: number = 512 * 1024;
/** 业务日志保留份数（`app.log` + `app.1.log` + `app.2.log`）。 */
export const APP_LOG_DEPTH: number = 3;
/** 崩溃日志保留份数（`crash.log` + `crash.1.log`）。 */
export const CRASH_LOG_DEPTH: number = 2;
/** `fault/` 目录最多保留的故障文件数。 */
export const FAULT_KEEP_COUNT: number = 5;
/** 保留天数（超过就删）。 */
export const KEEP_DAYS: number = 7;
/** 两次清扫的最小间隔（3 天）。 */
export const SWEEP_INTERVAL_MS: number = 3 * DAY_MS;

/** 一个故障日志文件（`fault/` 下）。 */
export interface FaultFile {
  name: string;
  bytes: number;
  mtimeMs: number;
}

/** 距上次清扫是否已经超过间隔（`lastSweepMs = 0` 表示从没扫过）。 */
export function shouldSweep(lastSweepMs: number, nowMs: number): boolean {
  if (lastSweepMs <= 0) {
    return true;
  }
  return nowMs - lastSweepMs >= SWEEP_INTERVAL_MS || nowMs < lastSweepMs;
}

/**
 * 该删除的故障日志名：**超龄**（> 7 天）与**超额**（保留最新 5 个）取并集。
 * 先按修改时间升序，最旧的排前面。
 */
export function faultsToDelete(files: FaultFile[], nowMs: number): string[] {
  const sorted: FaultFile[] = files.slice();
  sorted.sort((a: FaultFile, b: FaultFile) => a.mtimeMs - b.mtimeMs);

  const maxAgeMs: number = KEEP_DAYS * DAY_MS;
  const out: string[] = [];
  const survivors: number = Math.min(sorted.length, FAULT_KEEP_COUNT);
  const overCountStart: number = sorted.length - survivors;
  for (let i = 0; i < sorted.length; i++) {
    const expired: boolean = nowMs - sorted[i].mtimeMs > maxAgeMs;
    if (expired || i < overCountStart) {
      out.push(sorted[i].name);
    }
  }
  return out;
}

/** 当前日志是否已经达到上限（达到就轮转一次）。 */
export function shouldRotate(activeBytes: number, limitBytes: number): boolean {
  return activeBytes >= limitBytes;
}
