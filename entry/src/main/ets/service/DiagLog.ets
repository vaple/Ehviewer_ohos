import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { formatBytes } from '../common/Bytes';
import { redact } from '../common/Redact';
import { logLine } from './LogFormat';
import {
  APP_LOG_DEPTH,
  APP_LOG_LIMIT_BYTES,
  CRASH_LOG_DEPTH,
  CRASH_LOG_LIMIT_BYTES,
  FAULT_KEEP_COUNT,
  FaultFile,
  faultsToDelete,
  shouldRotate,
  shouldSweep
} from './LogRetention';

/**
 * 应用内诊断日志：把 `Logger` 的内容双写进沙盒文件，供设置页导出。
 *
 * 结构：`<baseDir>/app.log`（滚动 3 份 / 1MB）、`crash.log`（滚动 2 份 / 512KB）、
 * `fault/`（`hiAppEvent` 给的系统故障日志拷贝）、`meta.json`（清扫时间 / 起始时间 / 最近崩溃）。
 *
 * **唯一的兜底边界**：写文件失败 → hilog 记一次 → 停写 5 分钟再试；
 * 日志系统不能把 App 拖崩，也不能在 UI 线程上反复抛错。
 */
const DOMAIN: number = 0x0000;
const TAG: string = 'DiagLog';
/** 攒够多少行立刻落盘（其余靠 1s 定时器）。 */
const FLUSH_LINES: number = 32;
const FLUSH_INTERVAL_MS: number = 1000;
/** 写失败后停写时长。 */
const RETRY_AFTER_MS: number = 5 * 60 * 1000;
const META_FILE: string = 'meta.json';
const MINUTE_MS: number = 60 * 1000;

interface Meta {
  lastSweepMs: number;
  sinceMs: number;
  lastCrashMs: number;
}

export interface DiagStats {
  totalBytes: number;
  appFiles: number;
  crashFiles: number;
  faultCount: number;
  lastCrashMs: number;
  sinceMs: number;
}

let logsDir: string = '';
let faultsDir: string = '';
let pendingApp: string[] = [];
let pendingCrash: string[] = [];
let timerId: number = -1;
let retryAtMs: number = 0;
let meta: Meta = { lastSweepMs: 0, sinceMs: 0, lastCrashMs: 0 };

function relativeTime(tsMs: number, nowMs: number): string {
  const diff: number = Math.max(0, nowMs - tsMs);
  if (diff < MINUTE_MS) {
    return '刚刚';
  }
  if (diff < 60 * MINUTE_MS) {
    return `${Math.floor(diff / MINUTE_MS)} 分钟前`;
  }
  if (diff < 24 * 60 * MINUTE_MS) {
    return `${Math.floor(diff / (60 * MINUTE_MS))} 小时前`;
  }
  return `${Math.floor(diff / (24 * 60 * MINUTE_MS))} 天前`;
}

/** 设置页副标题：`812 KB · 最近崩溃：3 天前` / `还没有日志`。 */
export function statsSummary(s: DiagStats, nowMs: number): string {
  if (s.totalBytes <= 0 && s.appFiles === 0 && s.crashFiles === 0 && s.faultCount === 0) {
    return '还没有日志';
  }
  const crash: string = s.lastCrashMs > 0 ? `最近崩溃：${relativeTime(s.lastCrashMs, nowMs)}` : '无崩溃记录';
  return `${formatBytes(s.totalBytes)} · ${crash}`;
}

export class DiagLog {
  /** 设置日志根目录（如 `context.filesDir + '/logs'`）并做一次清理。幂等。 */
  static init(baseDir: string): void {
    logsDir = baseDir;
    faultsDir = `${baseDir}/fault`;
    if (!DiagLog.ensureDir(logsDir) || !DiagLog.ensureDir(faultsDir)) {
      return;
    }
    meta = DiagLog.loadMeta();
    if (meta.sinceMs <= 0) {
      meta.sinceMs = Date.now();
      DiagLog.saveMeta();
    }
    if (shouldSweep(meta.lastSweepMs, Date.now())) {
      DiagLog.sweep();
    }
  }

  /** 日志系统是否可用（未初始化 / 写失败冷却中都为 false）。 */
  static enabled(): boolean {
    return logsDir.length > 0 && (retryAtMs === 0 || Date.now() >= retryAtMs);
  }

  /** 业务日志：入队，攒够 32 行或 1 秒落盘。 */
  static append(level: string, tag: string, msg: string): void {
    if (!DiagLog.enabled()) {
      return;
    }
    pendingApp.push(logLine(Date.now(), level, tag, redact(msg)));
    if (pendingApp.length >= FLUSH_LINES) {
      DiagLog.flush();
      return;
    }
    DiagLog.scheduleFlush();
  }

  /** 崩溃摘要：立刻落盘（进程随时可能再死一次）。 */
  static appendCrash(text: string): void {
    if (!DiagLog.enabled()) {
      return;
    }
    pendingCrash.push(redact(text));
    meta.lastCrashMs = Date.now();
    DiagLog.saveMeta();
    DiagLog.flush();
  }

  static flush(): void {
    if (timerId >= 0) {
      clearTimeout(timerId);
      timerId = -1;
    }
    if (!DiagLog.enabled()) {
      pendingApp = [];
      pendingCrash = [];
      return;
    }
    if (pendingApp.length === 0 && pendingCrash.length === 0) {
      return;
    }
    const appLines: string[] = pendingApp;
    const crashLines: string[] = pendingCrash;
    pendingApp = [];
    pendingCrash = [];
    try {
      if (appLines.length > 0) {
        DiagLog.appendText(`${logsDir}/app.log`, appLines.join('\n') + '\n');
        DiagLog.rotateIfNeeded('app', APP_LOG_LIMIT_BYTES, APP_LOG_DEPTH);
      }
      if (crashLines.length > 0) {
        DiagLog.appendText(`${logsDir}/crash.log`, crashLines.join('\n') + '\n');
        DiagLog.rotateIfNeeded('crash', CRASH_LOG_LIMIT_BYTES, CRASH_LOG_DEPTH);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, '%{public}s', `write failed, pause 5min: ${e}`);
      retryAtMs = Date.now() + RETRY_AFTER_MS;
      // 写失败别把内容丢光：放回队列（封顶防无限增长），冷却结束后重试。
      pendingApp = appLines.concat(pendingApp).slice(0, FLUSH_LINES * 4);
      pendingCrash = crashLines.concat(pendingCrash);
    }
  }

  /** 统计（同步；目录内文件数很少，可接受）。 */
  static stats(): DiagStats {
    let totalBytes: number = 0;
    let appFiles: number = 0;
    let crashFiles: number = 0;
    let faultCount: number = 0;
    try {
      if (logsDir.length > 0 && fs.accessSync(logsDir)) {
        const names: string[] = fs.listFileSync(logsDir);
        for (let i = 0; i < names.length; i++) {
          const name: string = names[i];
          if (name.startsWith('app') && name.endsWith('.log')) {
            appFiles += 1;
            totalBytes += fs.statSync(`${logsDir}/${name}`).size;
          } else if (name.startsWith('crash') && name.endsWith('.log')) {
            crashFiles += 1;
            totalBytes += fs.statSync(`${logsDir}/${name}`).size;
          }
        }
      }
      const faults: FaultFile[] = DiagLog.listFaults();
      faultCount = faults.length;
      for (let i = 0; i < faults.length; i++) {
        totalBytes += faults[i].bytes;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, '%{public}s', `stats failed: ${e}`);
    }
    return {
      totalBytes: totalBytes,
      appFiles: appFiles,
      crashFiles: crashFiles,
      faultCount: faultCount,
      lastCrashMs: meta.lastCrashMs,
      sinceMs: meta.sinceMs
    };
  }

  /** 清空全部日志（保留目录与 `sinceMs` 重置）。 */
  static clear(): void {
    pendingApp = [];
    pendingCrash = [];
    if (logsDir.length === 0 || !fs.accessSync(logsDir)) {
      return;
    }
    const names: string[] = fs.listFileSync(logsDir);
    for (let i = 0; i < names.length; i++) {
      const name: string = names[i];
      if (name.endsWith('.log')) {
        fs.unlinkSync(`${logsDir}/${name}`);
      }
    }
    const faults: FaultFile[] = DiagLog.listFaults();
    for (let i = 0; i < faults.length; i++) {
      fs.unlinkSync(`${faultsDir}/${faults[i].name}`);
    }
    meta.lastCrashMs = 0;
    meta.sinceMs = Date.now();
    DiagLog.saveMeta();
  }

  /** 系统故障日志落点（`CrashCollector` 往里拷全文）。 */
  static faultDir(): string {
    return faultsDir;
  }

  /** 日志根目录（导出时整体复制）。 */
  static dir(): string {
    return logsDir;
  }

  // --- 内部 ---

  private static scheduleFlush(): void {
    if (timerId >= 0) {
      return;
    }
    timerId = setTimeout(() => {
      timerId = -1;
      DiagLog.flush();
    }, FLUSH_INTERVAL_MS);
  }

  private static ensureDir(path: string): boolean {
    try {
      if (!fs.accessSync(path)) {
        fs.mkdirSync(path, true);
      }
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, '%{public}s', `mkdir failed: ${e}`);
      return false;
    }
  }

  private static appendText(path: string, text: string): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.APPEND | fs.OpenMode.WRITE_ONLY);
    try {
      fs.writeSync(file.fd, text);
    } finally {
      fs.closeSync(file);
    }
  }

  private static rotateIfNeeded(base: string, limitBytes: number, depth: number): void {
    const active: string = `${logsDir}/${base}.log`;
    if (!fs.accessSync(active) || !shouldRotate(fs.statSync(active).size, limitBytes)) {
      return;
    }
    const oldest: string = `${logsDir}/${base}.${depth - 1}.log`;
    if (fs.accessSync(oldest)) {
      fs.unlinkSync(oldest);
    }
    for (let i = depth - 2; i >= 1; i--) {
      const from: string = `${logsDir}/${base}.${i}.log`;
      if (fs.accessSync(from)) {
        fs.renameSync(from, `${logsDir}/${base}.${i + 1}.log`);
      }
    }
    fs.renameSync(active, `${logsDir}/${base}.1.log`);
  }

  private static listFaults(): FaultFile[] {
    const out: FaultFile[] = [];
    if (faultsDir.length === 0 || !fs.accessSync(faultsDir)) {
      return out;
    }
    const names: string[] = fs.listFileSync(faultsDir);
    for (let i = 0; i < names.length; i++) {
      const stat = fs.statSync(`${faultsDir}/${names[i]}`);
      out.push({ name: names[i], bytes: stat.size, mtimeMs: stat.mtime * 1000 });
    }
    return out;
  }

  private static sweep(): void {
    try {
      const faults: FaultFile[] = DiagLog.listFaults();
      const doomed: string[] = faultsToDelete(faults, Date.now());
      for (let i = 0; i < doomed.length; i++) {
        fs.unlinkSync(`${faultsDir}/${doomed[i]}`);
      }
      DiagLog.rotateIfNeeded('app', APP_LOG_LIMIT_BYTES, APP_LOG_DEPTH);
      DiagLog.rotateIfNeeded('crash', CRASH_LOG_LIMIT_BYTES, CRASH_LOG_DEPTH);
    } catch (e) {
      hilog.error(DOMAIN, TAG, '%{public}s', `sweep failed: ${e}`);
    }
    meta.lastSweepMs = Date.now();
    DiagLog.saveMeta();
  }

  private static loadMeta(): Meta {
    const path: string = `${logsDir}/${META_FILE}`;
    const fallback: Meta = { lastSweepMs: 0, sinceMs: 0, lastCrashMs: 0 };
    try {
      if (!fs.accessSync(path)) {
        return fallback;
      }
      const raw: string = fs.readTextSync(path);
      if (raw.length === 0) {
        return fallback;
      }
      return JSON.parse(raw) as Meta;
    } catch (e) {
      hilog.error(DOMAIN, TAG, '%{public}s', `read meta failed: ${e}`);
      return fallback;
    }
  }

  private static saveMeta(): void {
    try {
      const file = fs.openSync(`${logsDir}/${META_FILE}`,
        fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      try {
        fs.writeSync(file.fd, JSON.stringify(meta));
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, '%{public}s', `write meta failed: ${e}`);
    }
  }
}
