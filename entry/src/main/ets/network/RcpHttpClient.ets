import { rcp } from '@kit.RemoteCommunicationKit';
import { util } from '@kit.ArkTS';
import { AppError } from '../common/AppError';
import { mapResponseError } from './HttpErrorMapping';
import { RequestBuilder } from './RequestBuilder';
import { Logger } from '../common/Logger';
import { requestLine } from './RequestLog';
import { HttpClient, HttpRequestOptions, HttpResponse } from './HttpClient';

/**
 * 基于 RCP（`@kit.RemoteCommunicationKit`）的 `HttpClient` 实现。
 *
 * 全 App 共用一个 session：RCP 的连接池按 session 隔离，每个页面各建一个 = 每次请求都重新 TCP+TLS。
 * 真机实测（nova 14 Pro，出境 RTT ≈350 ms）：新 session 的页面请求 1.4–2.1 s，
 * 同一 session 内并发请求 0.5–0.8 s —— 差值就是握手成本。
 */
let sharedSession: rcp.Session | undefined = undefined;

function sharedRcpSession(): rcp.Session {
  if (sharedSession === undefined) {
    sharedSession = rcp.createSession();
  }
  return sharedSession;
}

export class RcpHttpClient implements HttpClient {
  async get(url: string, opt?: HttpRequestOptions): Promise<HttpResponse> {
    const headers: Record<string, string> = RcpHttpClient.mergeHeaders(opt);
    const cookies: Record<string, string> = RcpHttpClient.cookiesOf(opt);
    const req = new rcp.Request(url, 'GET', headers, undefined, cookies, undefined, RcpHttpClient.configOf(opt));
    return this.send(req);
  }

  async postForm(url: string, form: Record<string, string>, opt?: HttpRequestOptions): Promise<HttpResponse> {
    const headers: Record<string, string> = RcpHttpClient.mergeHeaders(opt);
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    const cookies: Record<string, string> = RcpHttpClient.cookiesOf(opt);
    const body: string = RcpHttpClient.encodeForm(form);
    const req = new rcp.Request(url, 'POST', headers, body, cookies, undefined, RcpHttpClient.configOf(opt));
    return this.send(req);
  }

  async postJson(url: string, body: object, opt?: HttpRequestOptions): Promise<HttpResponse> {
    const headers: Record<string, string> = RcpHttpClient.mergeHeaders(opt);
    headers['Content-Type'] = 'application/json';
    const cookies: Record<string, string> = RcpHttpClient.cookiesOf(opt);
    const payload: string = JSON.stringify(body);
    const req = new rcp.Request(url, 'POST', headers, payload, cookies, undefined, RcpHttpClient.configOf(opt));
    return this.send(req);
  }

  async getBytes(url: string, opt?: HttpRequestOptions): Promise<ArrayBuffer> {
    const headers: Record<string, string> = RcpHttpClient.mergeHeaders(opt);
    const cookies: Record<string, string> = RcpHttpClient.cookiesOf(opt);
    const req = new rcp.Request(url, 'GET', headers, undefined, cookies, undefined, RcpHttpClient.configOf(opt));
    const startedAt: number = Date.now();
    const resp: rcp.Response = await sharedRcpSession().fetch(req);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // 图片字节**只记失败**：成功行会把 1MB 窗口刷满，把真正的失败挤出去。
      Logger.error('Http', requestLine('GET', url, resp.statusCode, resp.body?.byteLength ?? 0,
        Date.now() - startedAt, 'image'));
      throw new AppError(resp.statusCode, `HTTP ${resp.statusCode}`);
    }
    const buffer: ArrayBuffer | undefined = resp.body;
    return buffer === undefined ? new ArrayBuffer(0) : buffer;
  }

  private async send(req: rcp.Request): Promise<HttpResponse> {
    const startedAt: number = Date.now();
    const resp: rcp.Response = await sharedRcpSession().fetch(req);

    const ctRaw: string | string[] | undefined = resp.headers['content-type'];
    const contentType: string = typeof ctRaw === 'string' ? ctRaw : '';
    const cdRaw: string | string[] | undefined = resp.headers['content-disposition'];
    const contentDisposition: string = typeof cdRaw === 'string' ? cdRaw : '';
    const clRaw: string | string[] | undefined = resp.headers['content-length'];
    const contentLength: string = typeof clRaw === 'string' ? clRaw : '';

    const buffer: ArrayBuffer | undefined = resp.body;
    let body: string = '';
    if (buffer !== undefined) {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      body = decoder.decodeToString(new Uint8Array(buffer));
    }

    Logger.info('Http', requestLine(req.method, req.url.toString(), resp.statusCode, body.length,
      Date.now() - startedAt, contentType));

    const err: AppError | null =
      mapResponseError(resp.statusCode, contentType, contentDisposition, contentLength, body);
    if (err !== null) {
      throw err;
    }

    const jar: Record<string, string> = {};
    const respCookies: rcp.ResponseCookie[] | undefined = resp.cookies;
    if (respCookies !== undefined) {
      for (let i = 0; i < respCookies.length; i++) {
        const c: rcp.ResponseCookie = respCookies[i];
        if (c.name !== undefined && c.value !== undefined) {
          jar[c.name] = c.value;
        }
      }
    }

    const result: HttpResponse = { status: resp.statusCode, contentType: contentType, body: body, cookies: jar };
    return result;
  }

  private static mergeHeaders(opt?: HttpRequestOptions): Record<string, string> {
    const merged: Record<string, string> = RequestBuilder.defaultHeaders();
    if (opt === undefined || opt.headers === undefined) {
      return merged;
    }
    const extra: Record<string, string> = opt.headers;
    const keys: string[] = Object.keys(extra);
    for (let i = 0; i < keys.length; i++) {
      merged[keys[i]] = extra[keys[i]];
    }
    return merged;
  }

  private static cookiesOf(opt?: HttpRequestOptions): Record<string, string> {
    if (opt !== undefined && opt.cookies !== undefined) {
      return opt.cookies;
    }
    return {};
  }

  /** 依据选项构造请求级 RCP 配置：始终带超时（防连接挂死），有 `timeoutMs` 时覆盖。 */
  private static configOf(opt?: HttpRequestOptions): rcp.Configuration {
    // `inactivityMs` 是防「连上了但服务端不再发数据」的关键（默认无限等）；连接/传输默认 60s。
    const cfg: rcp.Configuration = {
      transfer: {
        timeout: { connectMs: 20000, transferMs: 60000, inactivityMs: 20000 }
      }
    };
    if (opt === undefined) {
      return cfg;
    }
    if (opt.timeoutMs !== undefined) {
      cfg.transfer = {
        timeout: {
          connectMs: opt.timeoutMs,
          transferMs: opt.timeoutMs,
          inactivityMs: 30000
        }
      };
    }
    return cfg;
  }

  /** x-www-form-urlencoded 编码（纯函数）。 */
  static encodeForm(form: Record<string, string>): string {
    const parts: string[] = [];
    const keys: string[] = Object.keys(form);
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(form[key])}`);
    }
    return parts.join('&');
  }
}
