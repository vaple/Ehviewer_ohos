/**
 * 两个源的 latest release 真实响应（2026-10-30 抓取，未脱敏）。
 *
 * GitHub 那份是在 API 限流（403）后用同一次发布响应重建的：字段逐字一致，
 * assets 只保留两个 hap 相关项；GitCode 那份是完整原样响应（按 UTF-8 字节解码，
 * 不要用 `(Invoke-WebRequest).Content` —— 响应头没带 charset 时 PowerShell 会按 Latin-1 解成乱码）。
 *
 * 重新抓取：把响应压成一行后按 120 字符切块，逐块转义 `\` 与 `'` 再拼成单引号字符串
 * （切块必须在转义之前，否则会切开 `\\` / `\'` 造成未闭合字符串）。
 */
export const GITHUB_LATEST_JSON: string =
  '{"url": "https://api.github.com/repos/vaple/Ehviewer_ohos/releases/427594988","assets_url": "https://api.github.com/repo' +
  's/vaple/Ehviewer_ohos/releases/427594988/assets","html_url": "https://github.com/vaple/Ehviewer_ohos/releases/tag/v1.0.0' +
  '","id": 427594988,"node_id": "RE_kwDOVGHLfs4ZfJTs","tag_name": "v1.0.0","target_commitish": "main","name": "v1.0.0","dra' +
  'ft": false,"prerelease": false,"created_at": "2026-10-29T11:29:08Z","published_at": "2026-10-29T08:04:38Z","assets": [{"' +
  'url": "https://api.github.com/repos/vaple/Ehviewer_ohos/releases/assets/687818950","id": 687818950,"name": "ehviewer-1.0' +
  '.0.hap","content_type": "application/octet-stream","state": "uploaded","size": 843238,"download_count": 13,"created_at":' +
  ' "2026-10-29T08:04:36Z","browser_download_url": "https://github.com/vaple/Ehviewer_ohos/releases/download/v1.0.0/ehviewe' +
  'r-1.0.0.hap"},{"url": "https://api.github.com/repos/vaple/Ehviewer_ohos/releases/assets/687818947","id": 687818947,"name' +
  '": "ehviewer-1.0.0.hap.sha256","content_type": "application/octet-stream","state": "uploaded","size": 85,"download_count' +
  '": 3,"created_at": "2026-10-29T08:04:36Z","browser_download_url": "https://github.com/vaple/Ehviewer_ohos/releases/downl' +
  'oad/v1.0.0/ehviewer-1.0.0.hap.sha256"}],"body": "## 安装\\\\n\\\\n本页提供**未签名**的 hap，需要自带调试证书签名后安装（HapKit、小白调试助手等自签工具均可）。\\\\n\\\\n1. 下载' +
  ' `ehviewer-1.0.0.hap` 与同名 `.sha256`，先校验文件完整性\\\\n2. 用你自己的调试证书为它签名\\\\n3. 安装到已开启开发者模式、**HarmonyOS 7.0（API 26）及以上**的设备\\\\n\\\\n未签名包直接' +
  '安装会报 `9568320 no signature file`，属预期行为。签名证书与设备绑定，别人签好的包在你机器上装不上，所以这里只分发未签名包。\\\\n\\\\n```\\\\nsha256  426078fa66b3ac1db8d27a206e3' +
  '148bf8d8769b718405f35d69306df2fa6686a\\\\n```\\\\n\\\\n## 功能\\\\n\\\\n- E-Hentai / ExHentai 双站点，Cookie 登录\\\\n- 热门 / 订阅 / 排行 / 搜索（含站点语法与「搜' +
  '索排除」规则）\\\\n- 详情：标签、评分、评论、云端收藏分类、预览图\\\\n- 阅读器：横向 / 纵向、双击与双指缩放、进度记忆、离线打开已下载画廊\\\\n- 逐页下载、断点续传、暂停 / 继续 / 删除、后台长时任务 + 进度通知\\\\n- 浏览历史、' +
  '云端收藏\\\\n- 诊断日志脱敏落盘、崩溃收集、一键导出\\\\n\\\\n## 说明\\\\n\\\\n- 只提供客户端功能，不托管、不存储、不分发任何站点内容。\\\\n- 首次使用：在「我的 → 设置」里选择站点并导入 Cookie；已登录账号请选 ExHentai。' +
  '\\\\n- 暂不接受 Pull Request；问题请开 issue。\\\\n"}';
export const GITCODE_LATEST_JSON: string =
  '{"tag_name":"v1.0.0","target_commitish":"677e535624e3f3ed8140749d77c82f1b71e51e1a","prerelease":false,"name":"v1.0.0","b' +
  'ody":"## 安装\\\\n\\\\n本页提供**未签名**的 hap，需要自带调试证书签名后安装（HapKit、小白调试助手等自签工具均可）。\\\\n\\\\n1. 下载 `ehviewer-1.0.0.hap` 与同名 `.sha256`，先校验文件完整' +
  '性\\\\n2. 用你自己的调试证书为它签名\\\\n3. 安装到已开启开发者模式、**HarmonyOS 7.0（API 26）及以上**的设备\\\\n\\\\n未签名包直接安装会报 `9568320 no signature file`，属预期行为。签名证书' +
  '与设备绑定，别人签好的包在你机器上装不上，所以这里只分发未签名包。\\\\n\\\\n```\\\\nsha256  426078fa66b3ac1db8d27a206e3148bf8d8769b718405f35d69306df2fa6686a\\\\n```\\\\' +
  'n\\\\n## 功能\\\\n\\\\n- E-Hentai / ExHentai 双站点，Cookie 登录\\\\n- 热门 / 订阅 / 排行 / 搜索（含站点语法与「搜索排除」规则）\\\\n- 详情：标签、评分、评论、云端收藏分类、预览图\\\\n- 阅读器：横向' +
  ' / 纵向、双击与双指缩放、进度记忆、离线打开已下载画廊\\\\n- 逐页下载、断点续传、暂停 / 继续 / 删除、后台长时任务 + 进度通知\\\\n- 浏览历史、云端收藏\\\\n- 诊断日志脱敏落盘、崩溃收集、一键导出\\\\n\\\\n## 说明\\\\n\\\\n- 只提' +
  '供客户端功能，不托管、不存储、不分发任何站点内容。\\\\n- 首次使用：在「我的 → 设置」里选择站点并导入 Cookie；已登录账号请选 ExHentai。\\\\n- 暂不接受 Pull Request；问题请开 issue。\\\\n","autho' +
  'r":{"id":"1116514","login":"u012939801","name":"obserword","avatar_url":"https://cdn-img.gitcode.com/fe/fe/3f498e60fec8f' +
  'f5d36ad5b8aa83897373a8daa3638b0f6647074a9c26cb19d5e.png","html_url":"https://gitcode.com/u012939801","type":"User","url"' +
  ':"https://api.gitcode.com/api/v5/users/u012939801"},"created_at":"2026-10-30T10:49:13+08:00","assets":[{"browser_downloa' +
  'd_url":"https://raw.gitcode.com/u012939801/Ehviewer_ohos/archive/refs/heads/v1.0.0.zip","name":"v1.0.0.zip","type":"sour' +
  'ce"},{"browser_download_url":"https://raw.gitcode.com/u012939801/Ehviewer_ohos/archive/refs/heads/v1.0.0.tar.gz","name":' +
  '"v1.0.0.tar.gz","type":"source"},{"browser_download_url":"https://raw.gitcode.com/u012939801/Ehviewer_ohos/archive/refs/' +
  'heads/v1.0.0.tar.bz2","name":"v1.0.0.tar.bz2","type":"source"},{"browser_download_url":"https://raw.gitcode.com/u0129398' +
  '01/Ehviewer_ohos/archive/refs/heads/v1.0.0.tar","name":"v1.0.0.tar","type":"source"},{"browser_download_url":"https://gi' +
  'tcode.com/u012939801/Ehviewer_ohos/releases/download/v1.0.0/ehv-1.0.0.hap","name":"ehv-1.0.0.hap","type":"attach","id":2' +
  '80476,"size":843238,"digest":"sha256:426078fa66b3ac1db8d27a206e3148bf8d8769b718405f35d69306df2fa6686a"},{"browser_downlo' +
  'ad_url":"https://gitcode.com/u012939801/Ehviewer_ohos/releases/download/v1.0.0/ehv-1.0.0.hap.sha256","name":"ehv-1.0.0.h' +
  'ap.sha256","type":"attach","id":280475,"size":85,"digest":"sha256:aee0ecb202473a27d84fa97042393af45037b8eda44f5472d4c5bb' +
  '75bd7257e1"}],"release_status":"latest"}';
