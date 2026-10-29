import { AppError } from './AppError';
import { KOKOMADE_CODE, NO_HATH_CLIENT_CODE, PINING_CODE } from '../parser/EhErrorDetector';

/**
 * 异常 → 用户看到的文字。
 *
 * **规则只有一条：原文透传**。站点返回什么（`mapResponseError` 会把响应体的可见文字塞进
 * `AppError.message`）就显示什么，平台的网络错误也原样显示 —— 用这个应用的人看得懂
 * `You are currently at 4321 towards your account limit of 5000` / `Couldn't resolve host name`，
 * 改写反而丢信息。技术细节（状态码、堆栈）另有 `Logger` 记录。
 *
 * 唯一例外是 3 个**站点玩笑码**（`kokomade` / `pining for the fjords` / `No H@H client`），
 * 原文对用户没有信息量，换一句中文。将来做国际化时，只需要把这三行换成 `$r('app.string.*')`。
 */
export function errorText(e: Object | null, parseReason: string = ''): string {
  if (e instanceof AppError) {
    switch (e.code) {
      case KOKOMADE_CODE:
        return '画廊已被删除';
      case PINING_CODE:
        return '画廊正在归档，稍后再试';
      case NO_HATH_CLIENT_CODE:
        return '需要站点分配 H@H 客户端';
      default:
        break;
    }
  }
  if (e instanceof Error && e.message.length > 0) {
    return e.message;
  }
  if (e !== null) {
    return `${e}`;
  }
  // 解析返回 null（不是异常）：把原因带上，用户能直接转述（如 `no #gn` = 站点版式变了）。
  return parseReason.length > 0 ? `解析失败 (${parseReason})` : '出错了，请重试';
}
