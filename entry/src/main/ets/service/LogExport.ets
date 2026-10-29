import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { zlib } from '@kit.BasicServicesKit';
import { redact } from '../common/Redact';
import { DiagLog } from './DiagLog';
import { Logger } from '../common/Logger';

/**
 * 诊断日志导出：把沙盒日志脱敏复制到 `cache/logs-export/`，打 zip，交给系统分享。
 *
 * 为什么复制而不是直接压缩原目录：导出前要再过一遍 `redact()`（双保险），
 * 且不能把 `fault/` 之外的运行文件（比如 `meta.json` 之外的中间文件）带出去。
 */
export interface ExportMeta {
  version: string;
  apiVersion: number;
  model: string;
  site: string;
  lang: string;
  loggedIn: boolean;
  exportedAtMs: number;
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** `ehviewer-logs-20261027-220405.zip`（秒级时间戳，方便区分多次导出）。 */
export function exportName(tsMs: number): string {
  const d: Date = new Date(tsMs);
  const date: string = `${d.getFullYear()}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}`;
  const time: string = `${pad2(d.getHours())}${pad2(d.getMinutes())}${pad2(d.getSeconds())}`;
  return `ehviewer-logs-${date}-${time}.zip`;
}

/** 导出包的元信息（不含任何凭据）。 */
export function metaJson(m: ExportMeta): string {
  return JSON.stringify(m);
}

function ensureDir(path: string): void {
  if (!fs.accessSync(path)) {
    fs.mkdirSync(path, true);
  }
}

/** 把一个目录下的文件复制到目标目录：文本按 `redact()` 脱敏，二进制（`.dmp`）原样拷。 */
function copyRedacted(srcDir: string, destDir: string, suffix: string): number {
  if (srcDir.length === 0 || !fs.accessSync(srcDir)) {
    return 0;
  }
  ensureDir(destDir);
  const names: string[] = fs.listFileSync(srcDir);
  let copied: number = 0;
  for (let i = 0; i < names.length; i++) {
    const name: string = names[i];
    if (suffix.length > 0 && !name.endsWith(suffix)) {
      continue;
    }
    if (name.endsWith('.dmp')) {
      // Native Crash 的 minidump：二进制，不能当文本读。
      fs.copyFileSync(`${srcDir}/${name}`, `${destDir}/${name}`);
      copied += 1;
      continue;
    }
    const text: string = fs.readTextSync(`${srcDir}/${name}`);
    const file = fs.openSync(`${destDir}/${name}`,
      fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    try {
      fs.writeSync(file.fd, redact(text));
    } finally {
      fs.closeSync(file);
    }
    copied += 1;
  }
  return copied;
}

export class LogExport {
  /**
   * 打包日志：`cache/logs-export/<时间>/` → `cache/logs/<exportName>`。
   * 返回 zip 的沙箱绝对路径。
   */
  static async pack(ctx: common.Context, meta: ExportMeta): Promise<string> {
    const src: string = `${ctx.cacheDir}/logs-export/${exportName(meta.exportedAtMs).replace('.zip', '')}`;
    if (fs.accessSync(src)) {
      fs.rmdirSync(src);
    }
    ensureDir(src);

    const copied: number = copyRedacted(DiagLog.dir(), src, '.log');
    copyRedacted(DiagLog.faultDir(), `${src}/fault`, '');

    const metaFile = fs.openSync(`${src}/meta.json`,
      fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    try {
      fs.writeSync(metaFile.fd, metaJson(meta));
    } finally {
      fs.closeSync(metaFile);
    }

    ensureDir(`${ctx.cacheDir}/logs`);
    const zipPath: string = `${ctx.cacheDir}/logs/${exportName(meta.exportedAtMs)}`;
    await zlib.compressFile(src, zipPath, {});
    Logger.info('Diag', `exported ${copied} log files -> ${zipPath}`);
    return zipPath;
  }

  /** 拉起系统分享面板（微信 / 邮件 / 文件管理都从这里走）。 */
  static async share(ctx: common.Context, zipPath: string): Promise<void> {
    const data: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.ZIP_ARCHIVE,
      uri: fileUri.getUriFromPath(zipPath),
      title: 'EhViewer 诊断日志'
    });
    const controller: systemShare.ShareController = new systemShare.ShareController(data);
    await controller.show(ctx as common.UIAbilityContext, {});
  }
}
