/**
 * 统一的应用异常。
 * `code` 承载业务/HTTP 状态码，未知情形为 -1。
 */
export class AppError extends Error {
  code: number;
  detail?: string;

  constructor(code: number, message: string, detail?: string) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.detail = detail;
  }

  /** 由 HTTP 状态码映射为应用异常（纯函数，可单测）。 */
  static fromHttpStatus(status: number): AppError {
    switch (status) {
      case 509:
        return new AppError(509, 'Bandwidth limit exceeded');
      case 403:
        return new AppError(403, 'Forbidden');
      default:
        return new AppError(-1, `Unknown error: ${status}`);
    }
  }
}
