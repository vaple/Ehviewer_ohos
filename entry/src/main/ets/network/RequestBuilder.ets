import { Constants } from '../common/Constants';

/** 请求头 / Cookie 组装。纯函数，无设备依赖，便于 Local Test。 */
export class RequestBuilder {
  static defaultHeaders(): Record<string, string> {
    return {
      'User-Agent': Constants.USER_AGENT,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9'
    };
  }

  /** 将 Cookie 映射拼成 `k=v; k2=v2`。 */
  static cookieHeader(cookies: Record<string, string>): string {
    const parts: string[] = [];
    const keys: string[] = Object.keys(cookies);
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      parts.push(`${key}=${cookies[key]}`);
    }
    return parts.join('; ');
  }
}
