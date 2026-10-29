/** HTTP 抽象的输入选项。 */
export interface HttpRequestOptions {
  headers?: Record<string, string>;
  cookies?: Record<string, string>;
  timeoutMs?: number;
}

/** 归一化后的 HTTP 响应。 */
export interface HttpResponse {
  status: number;
  contentType: string;
  body: string;
  /** 响应 Cookie（name → value）。 */
  cookies?: Record<string, string>;
}

/** 统一的 HTTP 客户端抽象，便于以接口注入、解耦设备依赖。 */
export interface HttpClient {
  get(url: string, opt?: HttpRequestOptions): Promise<HttpResponse>;
  postForm(url: string, form: Record<string, string>, opt?: HttpRequestOptions): Promise<HttpResponse>;
  /** JSON POST（`api.php` 用）；非 2xx 抛 `AppError`（走 `send` 的统一错误映射）。 */
  postJson(url: string, body: object, opt?: HttpRequestOptions): Promise<HttpResponse>;
  /** 拉取二进制响应体（图片等）；非 2xx 抛 `AppError`。 */
  getBytes(url: string, opt?: HttpRequestOptions): Promise<ArrayBuffer>;
}
