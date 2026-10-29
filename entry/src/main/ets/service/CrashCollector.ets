import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { Logger } from '../common/Logger';
import { redact } from '../common/Redact';
import { CrashFields, crashReport, faultFileName, isProbablyText, parseCrashParams, pathsOf } from './CrashSummary';
import { DiagLog } from './DiagLog';

/**
 * 崩溃订阅：`hiAppEvent` 的 `APP_CRASH` / `APP_FREEZE`。
 *
 * 时序要点：崩溃时进程已死，`onReceive` 发生在**下次启动**。收到后
 * 1) 把摘要 + ≤500 行 hilog 写进 `crash.log`；2) 把 `external_log` 指向的系统故障日志
 * **拷进 `fault/` 再删原件**（官方要求：不删会撞 5MB 上限，新日志写不进去）。
 *
 * 不用 `errorManager.on('error')`：API 26 起它与 HiAppEvent 的 JsCrash 订阅互斥。
 *
 * 两处要注意的地方：
 * - 系统故障日志**可能是二进制 dump、也可能没有扩展名** → 按内容（NUL 字节）判断，不靠后缀；
 * - 同一次崩溃的多份日志用序号区分文件名，否则后一份会把前一份覆盖又被删掉。
 */
const FAULT_TEXT_MAX_CHARS: number = 2 * 1024 * 1024;
const FAULT_READ_MAX_BYTES: number = 2 * 1024 * 1024;

function writeText(path: string, text: string): void {
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
  try {
    fs.writeSync(file.fd, text);
  } finally {
    fs.closeSync(file);
  }
}

function writeBytes(path: string, bytes: ArrayBuffer): void {
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
  try {
    fs.writeSync(file.fd, bytes);
  } finally {
    fs.closeSync(file);
  }
}

/** 读文件前 `maxBytes` 字节（避免一次把 15MB 的 dump 读进内存）。 */
function readHeadBytes(path: string, maxBytes: number): ArrayBuffer {
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const size: number = fs.statSync(path).size;
    const want: number = Math.min(size, maxBytes);
    const buffer: ArrayBuffer = new ArrayBuffer(want);
    fs.readSync(file.fd, buffer);
    return buffer;
  } finally {
    fs.closeSync(file);
  }
}

export class CrashCollector {
  /** 在 `EntryAbility.onCreate` 里尽早调用（官方要求：业务之前注册，否则漏订阅）。 */
  static install(): void {
    const watcher: hiAppEvent.Watcher = {
      name: 'crashWatcher',
      appEventFilters: [
        {
          domain: hiAppEvent.domain.OS,
          names: [hiAppEvent.event.APP_CRASH, hiAppEvent.event.APP_FREEZE]
        }
      ],
      onReceive: (domain: string, appEventGroups: Array<hiAppEvent.AppEventGroup>) => {
        for (let i = 0; i < appEventGroups.length; i++) {
          const infos: Array<hiAppEvent.AppEventInfo> = appEventGroups[i].appEventInfos;
          for (let j = 0; j < infos.length; j++) {
            const fields: CrashFields = parseCrashParams(infos[j].params as Record<string, Object>);
            // 不在启动路径上做几十 MB 的同步 IO：推迟到首帧之后再落盘。
            setTimeout(() => {
              CrashCollector.recordCrash(fields);
            }, 0);
          }
        }
      }
    };
    hiAppEvent.addWatcher(watcher);

    // 页面切换日志（API 24+）：崩溃时能看出用户在哪几个页面之间操作。
    const policy: hiAppEvent.EventPolicy = {
      appCrashPolicy: { pageSwitchLogEnable: true }
    };
    hiAppEvent.configEventPolicy(policy).catch((e: BusinessError) => {
      Logger.error('Crash', `configEventPolicy failed code=${e.code}`);
    });
  }

  /** 落盘一次崩溃：摘要进 `crash.log`，系统故障日志拷进 `fault/` 后删原件。 */
  static recordCrash(f: CrashFields): void {
    DiagLog.appendCrash(crashReport(f));
    let index: number = 0;
    for (let i = 0; i < f.externalLogs.length; i++) {
      CrashCollector.captureFault(f.externalLogs[i], f, index);
      index += 1;
    }
    const pages: string[] = pathsOf(f.pageSwitchLog);
    if (pages.length === 0 && f.pageSwitchLog.length > 0) {
      Logger.error('Crash', `page_switch_log unreadable: ${f.pageSwitchLog}`);
    }
    for (let i = 0; i < pages.length; i++) {
      CrashCollector.captureFault(pages[i], f, index);
      index += 1;
    }
  }

  private static captureFault(src: string, f: CrashFields, index: number): void {
    try {
      if (!fs.accessSync(src)) {
        return;
      }
      if (fs.statSync(src).isDirectory()) {
        // 目录形态的故障日志不在这里处理（拷一个目录要遍历，收益低）：留下日志说明。
        Logger.error('Crash', `fault is a directory, skipped: ${src}`);
        return;
      }
      const bytes: ArrayBuffer = readHeadBytes(src, FAULT_READ_MAX_BYTES);
      const binary: boolean = !isProbablyText(new Uint8Array(bytes));
      const dest: string = `${DiagLog.faultDir()}/${faultFileName(f.timeMs, f.crashType, index, binary ? '.dmp' : '.txt')}`;
      if (binary) {
        writeBytes(dest, bytes);
      } else {
        const decoder = util.TextDecoder.create('utf-8');
        let text: string = decoder.decodeToString(new Uint8Array(bytes));
        if (text.length > FAULT_TEXT_MAX_CHARS) {
          text = `${text.substring(0, FAULT_TEXT_MAX_CHARS)}\n… truncated`;
        }
        // 写盘前就脱敏（导出时还会再脱一次）：沙盒里的副本也不该带凭据。
        writeText(dest, redact(text));
      }
      // 只有成功落盘才删原件：官方要求处理完及时删，否则超 5MB 后新日志写不进来。
      fs.unlinkSync(src);
    } catch (e) {
      Logger.error('Crash', `capture fault failed ${src}: ${e}`);
    }
  }
}

/** 把「当前在干什么」挂到崩溃事件上（进详情 / 进阅读 / 开始下载时调用）。 */
export function setDiagContext(text: string): void {
  const params: Record<string, hiAppEvent.ParamType> = { 'ctx': text };
  hiAppEvent.setEventParam(params, hiAppEvent.domain.OS, hiAppEvent.event.APP_CRASH)
    .catch((e: BusinessError) => {
      Logger.error('Crash', `setEventParam failed code=${e.code}`);
    });
}
