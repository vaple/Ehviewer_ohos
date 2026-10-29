/**
 * 日志行格式化（纯函数，无平台依赖）：
 * 时间戳、UTF-8 字节计数、按字符边界截断、单行化。
 *
 * 单条上限 `LOG_LINE_MAX_BYTES = 2048`：hilog 自身单条上限是 4096 字节（官方 FAQ），
 * 我们留一半余量，保证写进文件时既不触发 hilog 截断、也不会把多字节字符切成半个。
 */

/** 单条业务日志的内容上限（字节）。后缀 `…(+N)` 另计。 */
export const LOG_LINE_MAX_BYTES: number = 2048;

function pad(value: number, width: number): string {
  let s: string = value.toString();
  while (s.length < width) {
    s = '0' + s;
  }
  return s;
}

/** 本地时间 `yyyy-MM-dd HH:mm:ss.SSS`（日志时间线要和用户描述对得上，不能用 UTC）。 */
export function stamp(tsMs: number): string {
  const d: Date = new Date(tsMs);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1, 2)}-${pad(d.getDate(), 2)} ` +
    `${pad(d.getHours(), 2)}:${pad(d.getMinutes(), 2)}:${pad(d.getSeconds(), 2)}.` +
    `${pad(d.getMilliseconds(), 3)}`;
}

/** 一个码点的 UTF-8 字节宽度。 */
function byteWidthOf(codePoint: number): number {
  if (codePoint < 0x80) {
    return 1;
  }
  if (codePoint < 0x800) {
    return 2;
  }
  if (codePoint < 0x10000) {
    return 3;
  }
  return 4;
}

/** UTF-8 字节长度（按码点算，代理对记 4 字节）。 */
export function utf8Length(s: string): number {
  let bytes: number = 0;
  let i: number = 0;
  while (i < s.length) {
    const codePoint: number = s.codePointAt(i) as number;
    bytes += byteWidthOf(codePoint);
    i += codePoint > 0xFFFF ? 2 : 1;
  }
  return bytes;
}

/**
 * 按**字符边界**截断到 `maxBytes`：内容部分不会超过 `maxBytes`，
 * 被丢弃的字符数写成后缀 `…(+N)`（后缀不计入 `maxBytes`）。
 */
export function truncateUtf8(s: string, maxBytes: number): string {
  if (utf8Length(s) <= maxBytes) {
    return s;
  }
  let bytes: number = 0;
  let i: number = 0;
  while (i < s.length) {
    const codePoint: number = s.codePointAt(i) as number;
    const width: number = byteWidthOf(codePoint);
    if (bytes + width > maxBytes) {
      break;
    }
    bytes += width;
    i += codePoint > 0xFFFF ? 2 : 1;
  }
  const dropped: number = s.length - i;
  return `${s.substring(0, i)}…(+${dropped})`;
}

/** `<stamp> <level> <tag>: <msg>`；换行替换成 `⏎`，整行按字节上限截断。 */
export function logLine(tsMs: number, level: string, tag: string, msg: string): string {
  const single: string = msg.replace(/\r\n|\r|\n/g, '⏎');
  return truncateUtf8(`${stamp(tsMs)} ${level} ${tag}: ${single}`, LOG_LINE_MAX_BYTES);
}
