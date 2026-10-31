import { describe, it, expect } from '@ohos/hypium';
import { EhClient } from '../../main/ets/network/EhClient';
import { DetailCache, sharedDetailCache } from '../../main/ets/network/DetailCache';
import { CookieJar } from '../../main/ets/network/CookieJar';
import { HttpClient, HttpRequestOptions, HttpResponse } from '../../main/ets/network/HttpClient';
import { EhSite } from '../../main/ets/network/EhUrl';
import { GalleryDetail } from '../../main/ets/model/GalleryDetail';
import { GALLERY_DETAIL_HTML } from '../fixtures/galleryDetailPage';

const GID: number = 4253086;
const TOKEN: string = 'tok';
const RATE_BODY: string = '{"rating_avg":4.5,"rating_cnt":100}';

/** 内存 Cookie 仓库（对应 `CookieStore` 的接口面）。 */
class FakeJar implements CookieJar {
  private jar: Map<string, string> = new Map<string, string>();

  all(): Record<string, string> {
    const out: Record<string, string> = {};
    this.jar.forEach((value: string, key: string) => {
      out[key] = value;
    });
    return out;
  }

  set(name: string, value: string): void {
    this.jar.set(name, value);
  }

  flush(): Promise<void> {
    return Promise.resolve();
  }
}

/** 计数用 HTTP 假件：详情 GET 一律回真实 fixture，写操作回最小合法包。 */
class FakeHttp implements HttpClient {
  detailGets: number = 0;

  get(url: string, opt?: HttpRequestOptions): Promise<HttpResponse> {
    this.detailGets += 1;
    const resp: HttpResponse = { status: 200, contentType: 'text/html', body: GALLERY_DETAIL_HTML };
    return Promise.resolve(resp);
  }

  postForm(url: string, form: Record<string, string>, opt?: HttpRequestOptions): Promise<HttpResponse> {
    const resp: HttpResponse = { status: 200, contentType: 'text/html', body: '<html></html>' };
    return Promise.resolve(resp);
  }

  postJson(url: string, body: object, opt?: HttpRequestOptions): Promise<HttpResponse> {
    const resp: HttpResponse = { status: 200, contentType: 'application/json', body: RATE_BODY };
    return Promise.resolve(resp);
  }

  getBytes(url: string, opt?: HttpRequestOptions): Promise<ArrayBuffer> {
    return Promise.resolve(new ArrayBuffer(0));
  }
}

function newClient(http: FakeHttp): EhClient {
  return new EhClient(http, new FakeJar(), { cache: new DetailCache(25, 180000, () => 0) });
}

export default function ehClientCacheTest() {
  describe('EhClientCache', () => {
    it('second_call_serves_from_cache', 0, async () => {
      const http: FakeHttp = new FakeHttp();
      const client: EhClient = newClient(http);
      const a: GalleryDetail | null = await client.getGalleryDetail(EhSite.E, GID, TOKEN, 0);
      const b: GalleryDetail | null = await client.getGalleryDetail(EhSite.E, GID, TOKEN, 0);
      expect(a !== null).assertTrue();
      expect(b !== null).assertTrue();
      expect(http.detailGets).assertEqual(1);
    });

    it('different_thumb_size_is_a_separate_entry', 0, async () => {
      const http: FakeHttp = new FakeHttp();
      const client: EhClient = newClient(http);
      await client.getGalleryDetail(EhSite.E, GID, TOKEN, 0);
      await client.getGalleryDetail(EhSite.E, GID, TOKEN, 2);
      expect(http.detailGets).assertEqual(2);
    });

    it('favorite_invalidates_cache', 0, async () => {
      const http: FakeHttp = new FakeHttp();
      const client: EhClient = newClient(http);
      await client.getGalleryDetail(EhSite.E, GID, TOKEN, 0);
      await client.addFavorite(EhSite.E, GID, TOKEN, 0);
      await client.getGalleryDetail(EhSite.E, GID, TOKEN, 0);
      expect(http.detailGets).assertEqual(2);
    });

    it('rate_invalidates_cache', 0, async () => {
      const http: FakeHttp = new FakeHttp();
      const client: EhClient = newClient(http);
      await client.getGalleryDetail(EhSite.E, GID, TOKEN, 0);
      await client.rateGallery(EhSite.E, GID, TOKEN, 4.5, 12345, 'key');
      await client.getGalleryDetail(EhSite.E, GID, TOKEN, 0);
      expect(http.detailGets).assertEqual(2);
    });

    it('options_omitted_uses_shared_cache', 0, async () => {
      const http: FakeHttp = new FakeHttp();
      const client: EhClient = new EhClient(http, new FakeJar());
      const gid: number = 999000001;
      await client.getGalleryDetail(EhSite.E, gid, TOKEN, 0);
      await client.getGalleryDetail(EhSite.E, gid, TOKEN, 0);
      expect(http.detailGets).assertEqual(1);
      // 收尾：共享单例是全 App 用的，别把这条用例的数据留给别的用例。
      sharedDetailCache.clear();
    });

    it('explicit_disabled_cache_hits_network_every_time', 0, async () => {
      const http: FakeHttp = new FakeHttp();
      const client: EhClient =
        new EhClient(http, new FakeJar(), { cache: new DetailCache(25, 0) });
      await client.getGalleryDetail(EhSite.E, GID, TOKEN, 0);
      await client.getGalleryDetail(EhSite.E, GID, TOKEN, 0);
      expect(http.detailGets).assertEqual(2);
    });
  });
}
