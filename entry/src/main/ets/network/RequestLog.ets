import { redact } from '../common/Redact';

/**
 * 一行 HTTP 日志：`GET <url> → 200 33154B 87ms text/html`。
 *
 * 只在纯 ArkTS 这一层记，不用 RCP 自己的日志（它在系统侧，用户导不出来）。
 * URL 先过 `redact()`，避免 cookie/token 类参数进日志。
 */
export function requestLine(method: string, url: string, status: number, bytes: number, ms: number,
  contentType: string): string {
  const safeUrl: string = redact(url);
  const type: string = contentType.length > 0 ? ` ${contentType}` : '';
  return `${method} ${safeUrl} → ${status} ${bytes}B ${ms}ms${type}`;
}
