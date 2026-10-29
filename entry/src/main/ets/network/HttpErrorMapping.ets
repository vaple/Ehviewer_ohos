import { AppError } from '../common/AppError';
import { detectSadPanda, detectHtmlError, pageText } from '../parser/EhErrorDetector';

/** Sad Panda（站点错误页）对应的自定义 code。 */
export const SAD_PANDA_CODE: number = -2;

/**
 * 将 HTTP 响应映射为应用异常。纯函数，无设备依赖。
 * 返回 `null` 表示响应正常、无需报错。
 * `bodyLen` 预留给按错误图体积（如 509 的 9615 字节 gif）细分错误的场景。
 */
export function mapHttpError(status: number, contentType: string | undefined, bodyLen: number): AppError | null {
  const ct: string = contentType === undefined ? '' : contentType.toLowerCase();
  if (ct.includes('sadpanda')) {
    return new AppError(SAD_PANDA_CODE, 'Sad Panda');
  }
  if (status >= 400) {
    return AppError.fromHttpStatus(status);
  }
  return null;
}

/**
 * 综合响应（状态码 / 响应头 / 响应体）→ `AppError`；正常响应返回 `null`。
 * Sad Panda 由**响应头**判定，错误页由**响应体**判定（源 `EhEngine.doThrowException`）。
 */
export function mapResponseError(status: number, contentType: string, contentDisposition: string,
  contentLength: string, body: string): AppError | null {
  if (detectSadPanda(contentDisposition, contentType, contentLength)) {
    return new AppError(SAD_PANDA_CODE, 'Sad Panda');
  }
  const bodyError: AppError | null = detectHtmlError(body);
  if (bodyError !== null) {
    return bodyError;
  }
  const err: AppError | null = mapHttpError(status, contentType, body.length);
  if (err === null) {
    return null;
  }
  // 把站点回的可见文字原样当消息（用户看得懂 `You are currently at … limit of …`）。
  const siteText: string = pageText(body);
  return siteText.length > 0 ? new AppError(err.code, siteText) : err;
}
