/**
 * 解析 Cookie 串为映射。
 * 支持两种常见格式（也可混用）：
 * - `Cookie` 头 / `WebCookieManager` 返回：`k=v; k2=v2`
 * - 用户从别处抄的逐行格式：`k=v\nk2=v2`（设置页「导入 Cookie」用）
 */
export function parseCookieString(raw: string): Record<string, string> {
  const out: Record<string, string> = {};
  const parts: string[] = raw.split(new RegExp('[;\\n\\r]+'));
  for (let i = 0; i < parts.length; i++) {
    let pair: string = parts[i].trim();
    // 容忍整段是 `Cookie: k=v; ...` 的复制形式。
    if (i === 0 && pair.toLowerCase().startsWith('cookie:')) {
      pair = pair.substring('cookie:'.length).trim();
    }
    const eq: number = pair.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const name: string = pair.substring(0, eq).trim();
    const value: string = pair.substring(eq + 1).trim();
    if (name.length > 0) {
      out[name] = value;
    }
  }
  return out;
}
