/**
 * 平台错误的一行日志文本（`BusinessError` 的关键信息在 `code` 上，只看 `message` 会得到 "undefined"）。
 *
 * 为什么单独一层：`TagDb`（加载/开关）与 `TagDbUpdater`（更新）都要把原始异常写进日志，
 * 两处各抄一份迟早会因为一边改了格式而对不上日志。放在 `tagdb/` 且**不碰文件系统**——
 * `TagDb` 的本地单测会沿依赖链 import 到这里，拖进 fs 会让纯逻辑单测在无沙箱环境里挂掉。
 */

export interface CodedError {
  code?: number;
  message?: string;
}

export function describeError(e: Object): string {
  const coded: CodedError = e as CodedError;
  const message: string = coded.message !== undefined && coded.message.length > 0 ? coded.message : `${e}`;
  return coded.code === undefined ? message : `[${coded.code}] ${message}`;
}
