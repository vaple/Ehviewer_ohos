import { describe, it, expect } from '@ohos/hypium';
import {
  ReleaseClient,
  ReleaseInfo,
  ReleasePick,
  ReleaseSource,
  compareVersion,
  isNewer,
  parseRelease,
  parseTagName,
  pickBetter
} from '../../main/ets/network/ReleaseClient';
import { HttpClient, HttpResponse } from '../../main/ets/network/HttpClient';
import {
  UpdateState,
  downloadUrlOf,
  updateState,
  updateSummary
} from '../../main/ets/state/UpdateState';
import { UpdateManager, buildDownloadConfig } from '../../main/ets/service/UpdateManager';
import { request } from '@kit.BasicServicesKit';
import { GITHUB_LATEST_JSON, GITCODE_LATEST_JSON } from '../fixtures/updateRelease';

/** 桩 HTTP：按 url 域名决定返回注入的响应体还是失败（单测不碰网络）。 */
class StubHttp implements HttpClient {
  private ghBody: string = '';
  private gcBody: string = '';
  private failGh: boolean = false;
  private failGc: boolean = false;

  static ok(ghBody: string, gcBody: string): StubHttp {
    const stub: StubHttp = new StubHttp();
    stub.ghBody = ghBody;
    stub.gcBody = gcBody;
    return stub;
  }

  static allFail(): StubHttp {
    const stub: StubHttp = new StubHttp();
    stub.failGh = true;
    stub.failGc = true;
    return stub;
  }

  get(url: string): Promise<HttpResponse> {
    if (url.indexOf('api.github.com') >= 0) {
      if (this.failGh) {
        return Promise.reject(new Error('github down'));
      }
      const okBody: HttpResponse = { status: 200, contentType: 'application/json', body: this.ghBody };
      return Promise.resolve(okBody);
    }
    if (this.failGc) {
      return Promise.reject(new Error('gitcode down'));
    }
    const gcResp: HttpResponse = { status: 200, contentType: 'application/json', body: this.gcBody };
    return Promise.resolve(gcResp);
  }

  postForm(_url: string, _form: Record<string, string>): Promise<HttpResponse> {
    return Promise.reject(new Error('unused'));
  }

  postJson(_url: string, _body: object): Promise<HttpResponse> {
    return Promise.reject(new Error('unused'));
  }

  getBytes(_url: string): Promise<ArrayBuffer> {
    return Promise.reject(new Error('unused'));
  }
}

export default function updateTest() {
  describe('Update', () => {
    it('parseTagName_strips_v_prefix', 0, () => {
      expect(parseTagName('v1.0.0')).assertEqual('1.0.0');
      expect(parseTagName('1.2.3')).assertEqual('1.2.3');
      expect(parseTagName('v10.2.3')).assertEqual('10.2.3');
      expect(parseTagName('release-1.0') === undefined).assertTrue();
      expect(parseTagName('1.0.0-beta') === undefined).assertTrue();
      expect(parseTagName('') === undefined).assertTrue();
    });

    it('compareVersion_orders_numerically', 0, () => {
      expect(compareVersion('1.0.0', '1.0.1')).assertEqual(-1);
      expect(compareVersion('1.2', '1.2.0')).assertEqual(0);
      expect(compareVersion('2.0.0', '10.0.0')).assertEqual(-1);
      expect(compareVersion('1.0.0', '1.0.0')).assertEqual(0);
      expect(compareVersion('1.1.0', '1.0.9')).assertEqual(1);
    });

    it('isNewer_only_when_remote_higher', 0, () => {
      expect(isNewer('1.0.1', '1.0.0')).assertTrue();
      expect(isNewer('1.0.0', '1.0.0')).assertFalse();
      expect(isNewer('0.9.0', '1.0.0')).assertFalse();
    });

    it('parseRelease_github_fixture', 0, () => {
      const gh: ReleaseInfo | undefined = parseRelease(GITHUB_LATEST_JSON, ReleaseSource.GITHUB);
      expect(gh === undefined).assertFalse();
      if (gh !== undefined) {
        expect(gh.tag).assertEqual('v1.0.0');
        expect(gh.version).assertEqual('1.0.0');
        expect(gh.hapName).assertEqual('ehviewer-1.0.0.hap');
        expect(gh.hapUrl.endsWith('/ehviewer-1.0.0.hap')).assertTrue();
        expect(gh.notes.indexOf('## 安装') >= 0).assertTrue();
        expect(gh.source).assertEqual(ReleaseSource.GITHUB);
      }
    });

    it('parseRelease_gitcode_fixture', 0, () => {
      const gc: ReleaseInfo | undefined = parseRelease(GITCODE_LATEST_JSON, ReleaseSource.GITCODE);
      expect(gc === undefined).assertFalse();
      if (gc !== undefined) {
        expect(gc.tag).assertEqual('v1.0.0');
        expect(gc.version).assertEqual('1.0.0');
        expect(gc.hapName).assertEqual('ehv-1.0.0.hap');
        expect(gc.hapUrl.endsWith('/ehv-1.0.0.hap')).assertTrue();
        expect(gc.notes.indexOf('## 安装') >= 0).assertTrue();
        expect(gc.source).assertEqual(ReleaseSource.GITCODE);
      }
    });

    it('parseRelease_ignores_sha256_asset_and_archives', 0, () => {
      const body: string = '{"tag_name":"v1.2.0","body":"x","assets":[' +
        '{"name":"a.zip","browser_download_url":"https://example.com/a.zip"},' +
        '{"name":"ehv-1.2.0.hap.sha256","browser_download_url":"https://example.com/ehv-1.2.0.hap.sha256"},' +
        '{"name":"y.hap","browser_download_url":"https://example.com/y.hap"}]}';
      const rel: ReleaseInfo | undefined = parseRelease(body, ReleaseSource.GITCODE);
      expect(rel?.hapName).assertEqual('y.hap');
      expect(rel?.hapUrl).assertEqual('https://example.com/y.hap');
    });

    it('parseRelease_rejects_prerelease_and_garbage', 0, () => {
      expect(parseRelease('{"tag_name":"v1.2.0","prerelease":true,"assets":[]}', ReleaseSource.GITCODE) === undefined)
        .assertTrue();
      expect(parseRelease('not json', ReleaseSource.GITHUB) === undefined).assertTrue();
      expect(parseRelease('{"tag_name":"v1.2.0","assets":[{"name":"a.zip","browser_download_url":"u"}]}',
        ReleaseSource.GITHUB) === undefined).assertTrue();
      expect(parseRelease('{"tag_name":"release-1.0","assets":[]}', ReleaseSource.GITHUB) === undefined).assertTrue();
    });

    it('pickBetter_prefers_gitcode_when_versions_equal', 0, () => {
      const gh: ReleaseInfo = {
        source: ReleaseSource.GITHUB, tag: 'v1.0.0', version: '1.0.0',
        notes: 'g', hapName: 'ehviewer-1.0.0.hap', hapUrl: 'https://gh/x.hap'
      };
      const gc: ReleaseInfo = {
        source: ReleaseSource.GITCODE, tag: 'v1.0.0', version: '1.0.0',
        notes: 'c', hapName: 'ehv-1.0.0.hap', hapUrl: 'https://gc/x.hap'
      };
      const pick: ReleasePick | undefined = pickBetter(gh, gc);
      expect(pick === undefined).assertFalse();
      if (pick !== undefined) {
        expect(pick.mirrors.length).assertEqual(2);
        expect(pick.mirrors[0].source).assertEqual(ReleaseSource.GITCODE);
        expect(pick.chosen.hapUrl).assertEqual('https://gc/x.hap');
      }
    });

    it('pickBetter_keeps_single_mirror_when_versions_differ', 0, () => {
      const gh: ReleaseInfo = {
        source: ReleaseSource.GITHUB, tag: 'v1.2.0', version: '1.2.0',
        notes: 'g', hapName: 'ehviewer-1.2.0.hap', hapUrl: 'https://gh/y.hap'
      };
      const gc: ReleaseInfo = {
        source: ReleaseSource.GITCODE, tag: 'v1.1.0', version: '1.1.0',
        notes: 'c', hapName: 'ehv-1.1.0.hap', hapUrl: 'https://gc/y.hap'
      };
      const pick: ReleasePick | undefined = pickBetter(gh, gc);
      expect(pick === undefined).assertFalse();
      if (pick !== undefined) {
        expect(pick.chosen.version).assertEqual('1.2.0');
        expect(pick.chosen.source).assertEqual(ReleaseSource.GITHUB);
        expect(pick.mirrors.length).assertEqual(1);
      }
    });

    it('pickBetter_handles_single_source', 0, () => {
      const gc: ReleaseInfo = {
        source: ReleaseSource.GITCODE, tag: 'v1.0.0', version: '1.0.0',
        notes: 'c', hapName: 'ehv-1.0.0.hap', hapUrl: 'https://gc/x.hap'
      };
      const pick: ReleasePick | undefined = pickBetter(undefined, gc);
      expect(pick === undefined).assertFalse();
      if (pick !== undefined) {
        expect(pick.mirrors.length).assertEqual(1);
        expect(pick.chosen.source).assertEqual(ReleaseSource.GITCODE);
      }
      expect(pickBetter(undefined, undefined) === undefined).assertTrue();
    });

    it('releaseClient_survives_one_source_down', 0, async () => {
      // GitHub 回了乱码（等价于不可用），GitCode 正常 → 用 GitCode
      const client: ReleaseClient = new ReleaseClient(StubHttp.ok('not json', GITCODE_LATEST_JSON));
      const pick: ReleasePick | undefined = await client.latest();
      expect(pick === undefined).assertFalse();
      if (pick !== undefined) {
        expect(pick.chosen.source).assertEqual(ReleaseSource.GITCODE);
        expect(pick.mirrors.length).assertEqual(1);
      }
    });

    it('releaseClient_returns_undefined_when_both_fail', 0, async () => {
      const pick: ReleasePick | undefined = await new ReleaseClient(StubHttp.allFail()).latest();
      expect(pick === undefined).assertTrue();
    });

    it('updateManager_check_writes_state_on_success', 0, async () => {
      const ok: boolean = await UpdateManager.check(StubHttp.ok(GITHUB_LATEST_JSON, GITCODE_LATEST_JSON));
      const state: UpdateState = updateState();
      expect(ok).assertTrue();
      expect(state.lastCheckOk).assertTrue();
      expect(state.lastCheckAtMs > 0).assertTrue();
      expect(state.latestVersion).assertEqual('1.0.0');
      expect(state.latestTag).assertEqual('v1.0.0');
      expect(state.hapName).assertEqual('ehv-1.0.0.hap');
      expect(state.gitcodeUrl.endsWith('/ehv-1.0.0.hap')).assertTrue();
      expect(state.githubUrl.endsWith('/ehviewer-1.0.0.hap')).assertTrue();
    });

    it('updateManager_check_keeps_versions_when_both_fail', 0, async () => {
      const state: UpdateState = updateState();
      state.latestVersion = '9.9.9';
      expect(await UpdateManager.check(StubHttp.allFail())).assertFalse();
      expect(state.lastCheckOk).assertFalse();
      // 一次失败不能把已知的最新版本抹掉（否则红点会意外消失）
      expect(updateState().latestVersion).assertEqual('9.9.9');
    });

    it('updateSummary_never_claims_latest_before_first_check', 0, () => {
      expect(updateSummary(new UpdateState(), '1.0.0')).assertEqual('尚未检查');
    });

    it('updateSummary_reports_last_failure', 0, () => {
      const state: UpdateState = new UpdateState();
      state.lastCheckAtMs = 1;
      state.lastCheckOk = false;
      expect(updateSummary(state, '1.0.0')).assertEqual('上次检查失败');
    });

    it('updateSummary_reports_latest_and_update', 0, () => {
      const state: UpdateState = new UpdateState();
      state.lastCheckAtMs = 1;
      state.lastCheckOk = true;
      state.latestVersion = '1.0.0';
      expect(updateSummary(state, '1.0.0')).assertEqual('当前已是最新');
      expect(updateSummary(state, '0.9.0')).assertEqual('有新版本 1.0.0');
    });

    it('downloadUrlOf_prefers_gitcode', 0, () => {
      const state: UpdateState = new UpdateState();
      expect(downloadUrlOf(state)).assertEqual('');
      state.githubUrl = 'https://gh/x.hap';
      expect(downloadUrlOf(state)).assertEqual('https://gh/x.hap');
      state.gitcodeUrl = 'https://gc/x.hap';
      expect(downloadUrlOf(state)).assertEqual('https://gc/x.hap');
    });

    it('download_config_carries_picker_uri_and_overwrite', 0, () => {
      // 注意：`request.agent.Mode` / `Action` 在本地单测运行时是 undefined（kit 桩），
      // 断言它们相等会假绿 → 这里只钉我们自己填的值；`mode === FOREGROUND` 由代码审阅 + 真机验证兜。
      const uri: string = 'file://docs/storage/Users/currentUser/Download/ehv-1.0.0.hap';
      const config: request.agent.Config = buildDownloadConfig('https://gc/x.hap', uri);
      expect(config.saveas).assertEqual(uri);
      expect(config.url).assertEqual('https://gc/x.hap');
      expect(config.overwrite).assertTrue();
      expect(config.gauge).assertTrue();
    });

    it('check_keeps_only_winner_url_when_versions_differ', 0, async () => {
      // GitHub 1.2.0 / GitCode 1.1.0 → 只留 GitHub 的地址（另一版本不能当备选下载）
      const gh: string = '{"tag_name":"v1.2.0","body":"g","assets":[' +
        '{"name":"ehviewer-1.2.0.hap","browser_download_url":"https://gh/1.2.0.hap"}]}';
      const gc: string = '{"tag_name":"v1.1.0","body":"c","assets":[' +
        '{"name":"ehv-1.1.0.hap","browser_download_url":"https://gc/1.1.0.hap"}]}';
      expect(await UpdateManager.check(StubHttp.ok(gh, gc))).assertTrue();
      const state: UpdateState = updateState();
      expect(state.latestVersion).assertEqual('1.2.0');
      expect(state.githubUrl).assertEqual('https://gh/1.2.0.hap');
      expect(state.gitcodeUrl).assertEqual('');
      expect(downloadUrlOf(state)).assertEqual('https://gh/1.2.0.hap');
    });
  });
}
