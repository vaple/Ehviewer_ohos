/**
 * 日志脱敏：把凭据的值替换成 `***`，其余内容原样保留。
 *
 * 只处理**值**，键名与文本结构不动 —— 这样日志仍然可读（能看出"这里有一个 apikey"），
 * 但分享出去的 zip 里没有可用的凭据。画廊 `token` 是公开的（URL 里就有），不脱敏。
 *
 * 覆盖三种形态：`k=v`、`k: v`、JSON 的 `"k":"v"`，以及 `Cookie:` / `Authorization:` 头整行。
 * 多行文本逐行生效（正则 `m` 标志）。
 */

/** 敏感键名（大小写不敏感；`sk` 这类短键靠词边界避免误伤 `task=` 之类）。 */
const SENSITIVE_KEYS: string[] = [
  'ipb_member_id',
  'ipb_pass_hash',
  'ipb_session_id',
  'igneous',
  'sk',
  'apikey',
  'apiuid',
  'password',
  'passwd',
  'cookie',
  'set-cookie',
  'cf_clearance'
];

/**
 * 整行抹值的请求头（`Set-Cookie` 也抹，值里同样带会话）。
 * 前缀允许出现在**行中**（`headers: cookie: ...` 形态，RCP/ArkWeb 的日志就是这样），只要求词边界。
 */
const HEADER_LINE: RegExp =
  new RegExp('(^|[^A-Za-z0-9_-])((?:set-cookie|cookie|proxy-authorization|authorization)\\s*:\\s*).*$', 'gim');

/** 把一条 `k=v` / `k: v` / `"k":"v"` 的值换成 `***`（保留引号与分隔符）。 */
function redactKey(text: string, key: string): string {
  const pattern: string = '(^|[^A-Za-z0-9_])("?' + key + '"?)(\\s*[=:]\\s*)("?)([^"&;,\\s}]+)\\4';
  const re: RegExp = new RegExp(pattern, 'gi');
  return text.replace(re, (_all: string, prefix: string, name: string, sep: string, quote: string) =>
    `${prefix}${name}${sep}${quote}***${quote}`);
}

/** 脱敏一段日志文本。 */
export function redact(text: string): string {
  if (text.length === 0) {
    return text;
  }
  let out: string = text.replace(HEADER_LINE, (_all: string, prefix: string, head: string) =>
    `${prefix}${head}***`);
  for (let i = 0; i < SENSITIVE_KEYS.length; i++) {
    out = redactKey(out, SENSITIVE_KEYS[i]);
  }
  return out;
}
