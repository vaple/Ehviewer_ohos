import { stamp } from './LogFormat';
import { redact } from '../common/Redact';

/**
 * 崩溃事件的解析与文本化（纯函数）。
 *
 * `hiAppEvent` 给的 `params` 是 `Record<string, Object>`，字段可能缺失、类型可能不同
 * （`hilog` 是字符串数组、`external_log` 是路径数组、`process_life_time` 是秒）——
 * 全部在这里归一成 `CrashFields`，再拼成可直接写进 `crash.log` 的文本。
 *
 * 字段含义见官方《崩溃事件介绍》：`hilog` 最多 500 行、`external_log` 是沙箱故障日志**路径**。
 */
export interface CrashFields {
  timeMs: number;
  crashType: string;
  bundleVersion: string;
  pid: number;
  processLifeMs: number;
  exception: string;
  hilogLines: string[];
  externalLogs: string[];
  pageSwitchLog: string;
}

function strOf(params: Record<string, Object>, key: string): string {
  const v: Object | undefined = params[key];
  return typeof v === 'string' ? v as string : '';
}

function numOf(params: Record<string, Object>, key: string): number {
  const v: Object | undefined = params[key];
  return typeof v === 'number' ? v as number : 0;
}

function strArrayOf(params: Record<string, Object>, key: string): string[] {
  const v: Object | undefined = params[key];
  const out: string[] = [];
  if (!Array.isArray(v)) {
    return out;
  }
  const raw: Object[] = v as Object[];
  for (let i = 0; i < raw.length; i++) {
    if (typeof raw[i] === 'string') {
      out.push(raw[i] as string);
    }
  }
  return out;
}

/** `params` → `CrashFields`（缺失字段给安全默认值，不抛）。 */
export function parseCrashParams(params: Record<string, Object>): CrashFields {
  const exception: Object | undefined = params['exception'];
  return {
    timeMs: numOf(params, 'time') > 0 ? numOf(params, 'time') : Date.now(),
    crashType: strOf(params, 'crash_type'),
    bundleVersion: strOf(params, 'bundle_version'),
    pid: numOf(params, 'pid'),
    processLifeMs: numOf(params, 'process_life_time') * 1000,
    exception: exception === undefined ? '' : JSON.stringify(exception),
    hilogLines: strArrayOf(params, 'hilog'),
    externalLogs: strArrayOf(params, 'external_log'),
    pageSwitchLog: strOf(params, 'page_switch_log')
  };
}

/** `page_switch_log` 可能是单个路径，也可能是 JSON 数组字符串（当前平台给的是后者）。 */
export function pathsOf(raw: string): string[] {
  const text: string = raw.trim();
  if (text.length === 0) {
    return [];
  }
  if (!text.startsWith('[')) {
    return [text];
  }
  try {
    const arr: Object[] = JSON.parse(text) as Object[];
    const out: string[] = [];
    for (let i = 0; i < arr.length; i++) {
      if (typeof arr[i] === 'string') {
        out.push(arr[i] as string);
      }
    }
    return out;
  } catch (e) {
    return [];
  }
}

/** `20261027-015512_NativeCrash_0.txt` —— 带序号，同一次崩溃的多份日志不会互相覆盖。 */
export function faultFileName(timeMs: number, crashType: string, index: number, ext: string): string {
  const d: Date = new Date(timeMs);
  const pad = (v: number): string => (v < 10 ? `0${v}` : `${v}`);
  const date: string = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;
  const time: string = `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
  return `${date}-${time}_${crashType.length > 0 ? crashType : 'crash'}_${index}${ext}`;
}

/**
 * 判断一段字节是不是文本（系统故障日志可能是 cppcrash 的二进制 dump、也可能没有扩展名）。
 * 只看前 4KB 有没有 NUL：文本日志不会出现，二进制 dump 一定有。
 */
export function isProbablyText(bytes: Uint8Array): boolean {
  const limit: number = Math.min(bytes.length, 4096);
  for (let i = 0; i < limit; i++) {
    if (bytes[i] === 0) {
      return false;
    }
  }
  return true;
}

/** 拼成 `crash.log` 里的一段（首行时间、次行元信息、然后异常/路径/hilog）。 */
export function crashReport(f: CrashFields): string {
  const lines: string[] = [];
  lines.push(`== crash ${stamp(f.timeMs)} ==`);
  lines.push(`crash_type=${f.crashType} bundle=${f.bundleVersion} pid=${f.pid} ` +
    `life=${Math.round(f.processLifeMs / 1000)}s`);
  if (f.exception.length > 0) {
    lines.push('exception:');
    lines.push(f.exception);
  }
  if (f.pageSwitchLog.length > 0) {
    lines.push(`page_switch_log: ${f.pageSwitchLog}`);
  }
  if (f.externalLogs.length > 0) {
    lines.push(`external_log: ${f.externalLogs.join(', ')}`);
  }
  if (f.hilogLines.length > 0) {
    lines.push(`-- hilog (${f.hilogLines.length}) --`);
    for (let i = 0; i < f.hilogLines.length; i++) {
      lines.push(redact(f.hilogLines[i]));
    }
  }
  return lines.join('\n');
}
