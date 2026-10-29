import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const PREF_NAME: string = 'eh_cookies';
const KEY: string = 'cookies';

/** Cookie 存储：内存缓存 + `@ohos.data.preferences` 持久化。 */
export class CookieStore {
  private cookies: Map<string, string> = new Map<string, string>();
  private store: preferences.Preferences | undefined = undefined;

  /** 读取已持久化的 Cookie；需在 Ability 创建后调用。 */
  async init(context: common.Context): Promise<void> {
    this.store = await preferences.getPreferences(context, { name: PREF_NAME });
    const raw: string = this.store.getSync(KEY, '{}') as string;
    const parsed: Record<string, string> = JSON.parse(raw) as Record<string, string>;
    const keys: string[] = Object.keys(parsed);
    for (let i = 0; i < keys.length; i++) {
      this.cookies.set(keys[i], parsed[keys[i]]);
    }
  }

  get(name: string): string | undefined {
    return this.cookies.get(name);
  }

  set(name: string, value: string): void {
    this.cookies.set(name, value);
  }

  remove(name: string): void {
    this.cookies.delete(name);
  }

  has(name: string): boolean {
    return this.cookies.has(name);
  }

  /** 以普通对象形式返回当前全部 Cookie（用于拼装请求头）。 */
  all(): Record<string, string> {
    const out: Record<string, string> = {};
    this.cookies.forEach((value: string, key: string) => {
      out[key] = value;
    });
    return out;
  }

  /** 写回并落盘。 */
  async flush(): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    this.store.putSync(KEY, JSON.stringify(this.all()));
    await this.store.flush();
  }
}
