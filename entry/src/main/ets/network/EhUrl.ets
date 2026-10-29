import { SearchFilters, filtersActive } from '../search/SearchQuery';

/** 排行榜时间档（源 `EhTopListAdapter.urlFollow`：昨日 15/月 13/年 12/总 11）。 */
export type TopListRange = 'yesterday' | 'month' | 'year' | 'all';

/** 站点。 */
export enum EhSite {
  E,
  EX
}

/** E-Hentai / ExHentai 的域名与主链路端点构造（纯函数，可 Local Test）。 */
export class EhUrl {
  static readonly DOMAIN_E: string = 'e-hentai.org';
  static readonly DOMAIN_EX: string = 'exhentai.org';
  static readonly THUMB_PREFIX: string = 'https://ehgt.org/';

  static referer(site: EhSite): string {
    return site === EhSite.EX ? `https://${EhUrl.DOMAIN_EX}` : `https://${EhUrl.DOMAIN_E}`;
  }

  static host(site: EhSite): string {
    return `${EhUrl.referer(site)}/`;
  }

  static home(site: EhSite): string {
    return `${EhUrl.host(site)}home.php`;
  }

  /** 前台画廊列表页（游客可见）：`https://<host>/`。 */
  static frontPage(site: EhSite): string {
    return EhUrl.host(site);
  }

  /**
   * 订阅列表（源 `ListUrlBuilder` MODE_SUBSCRIPTION，与首页同形）：
   * `https://<host>/watched[?f_search=<enc>][&page=<n>]`（`page` 0 起，`0` 不带参；需登录）。
   * `/watched` 支持完整搜索参数（f_search/f_cats/advsearch），这里用于拼「搜索排除」条件。
   */
  static watched(site: EhSite, page: number, search: string = ''): string {
    const params: string[] = [];
    const word: string = search.trim();
    if (word.length > 0) {
      params.push(`f_search=${EhUrl.encodeQuery(word)}`);
    }
    if (page > 0) {
      params.push(`page=${page}`);
    }
    const base: string = `${EhUrl.host(site)}watched`;
    return params.length === 0 ? base : `${base}?${params.join('&')}`;
  }

  /** 热门（源 MODE_WHATS_HOT）：`https://<host>/popular`（单页）。 */
  static popular(site: EhSite): string {
    return `${EhUrl.host(site)}popular`;
  }

  /**
   * 云收藏列表（源 `FavListUrlBuilder.build`）：
   * `https://<host>/favorites.php[?favcat=<n>][?f_search=<enc>&sn=on&st=on&sf=on][&page=<n>]`。
   * `favCat` `-1` = 全部（不带参）；`keyword` 为空不带搜索三件套；`page` 0 起，`0` 不带参。
   */
  static favorites(site: EhSite, favCat: number, keyword: string, page: number): string {
    const params: string[] = [];
    if (favCat >= 0 && favCat <= 9) {
      params.push(`favcat=${favCat}`);
    }
    const word: string = keyword.trim();
    if (word.length > 0) {
      params.push(`f_search=${EhUrl.encodeQuery(word)}`);
      params.push('sn=on');
      params.push('st=on');
      params.push('sf=on');
    }
    if (page > 0) {
      params.push(`page=${page}`);
    }
    const base: string = `${EhUrl.host(site)}favorites.php`;
    return params.length === 0 ? base : `${base}?${params.join('&')}`;
  }

  /**
   * 收藏增/改/删提交地址（源 `EhUrl.getAddFavorites`）：
   * `https://<host>/gallerypopups.php?gid=<gid>&t=<token>&act=addfav`。
   */
  static addFav(site: EhSite, gid: number, token: string): string {
    return `${EhUrl.host(site)}gallerypopups.php?gid=${gid}&t=${token}&act=addfav`;
  }

  /**
   * 收藏排序切换地址（源 `FavoritesScene.getPageData(append)`：往收藏页 URL 后缀
   * `inline_set=fs_f|fs_p` 再 GET；GET 本身即设置服务端排序偏好）。
   */
  static favOrderUrl(site: EhSite, order: string, favCat: number, keyword: string, page: number): string {
    const url: string = EhUrl.favorites(site, favCat, keyword, page);
    const sep: string = url.includes('?') ? '&' : '?';
    return `${url}${sep}inline_set=fs_${order}`;
  }

  /**
   * 排行榜分档画廊榜（源 MODE_TOP_LIST + `EhTopListAdapter.urlFollow`）：
   * `https://e-hentai.org/toplist.php?tl=<档>[&p=<n>]`（`page` 0 起，`0` 不带参）。
   * 排行榜只有 E 站提供（EX 同地址返回 404）。
   * `?tl=` 页是画廊列表形（`table.itg/gltc`），复用 `GalleryListParser`。
   */
  static toplist(range: TopListRange, page: number): string {
    let tl: number = 15;
    if (range === 'month') {
      tl = 13;
    } else if (range === 'year') {
      tl = 12;
    } else if (range === 'all') {
      tl = 11;
    }
    const base: string = `https://${EhUrl.DOMAIN_E}/toplist.php?tl=${tl}`;
    return page > 0 ? `${base}&p=${page}` : base;
  }

  /**
   * Java `URLEncoder.encode(s, "UTF-8")` 的最小等价：空格 → `+`。
   * 与上游 Android 版 EhViewer `ListUrlBuilder` 一致（仅 `!'()*-._~` 等少数符号编码不同）。
   */
  static encodeQuery(raw: string): string {
    return encodeURIComponent(raw).replace(/%20/g, '+');
  }

  /**
   * 关键词搜索 URL（源 `ListUrlBuilder.build` MODE_NORMAL）：
   * `https://<host>/?f_search=<enc>[&f_cats=<mask>][&advsearch=1&…][&page=<n>]`。
   * `page` 0 起，`0` 不带参；`query` 为空不带 `f_search`；`fCats` 为 0/缺省不带 `f_cats`；
   * `filters` 任一激活才带 `advsearch=1` 及其参数（无它服务端忽略过滤参数）。
   */
  static search(site: EhSite, query: string, page: number, fCats?: number, filters?: SearchFilters): string {
    const params: string[] = [];
    const keyword: string = query.trim();
    if (keyword.length > 0) {
      params.push(`f_search=${EhUrl.encodeQuery(keyword)}`);
    }
    if (fCats !== undefined && fCats !== 0) {
      params.push(`f_cats=${fCats}`);
    }
    if (filters !== undefined && filtersActive(filters)) {
      params.push('advsearch=1');
      if (filters.inTitle) {
        params.push('f_sname=on');
      }
      if (filters.inTags) {
        params.push('f_stags=on');
      }
      if (filters.inDesc) {
        params.push('f_sdesc=on');
      }
      if (filters.inTorrents) {
        params.push('f_storr=on');
      }
      if (filters.language) {
        params.push('f_sfl=on');
      }
      if (filters.minRating === 2 || filters.minRating === 3 ||
        filters.minRating === 4 || filters.minRating === 5) {
        params.push('f_sr=on');
        params.push(`f_srdd=${filters.minRating}`);
      }
      if (filters.onlyTorrents) {
        params.push('f_sto=on');
      }
      if (filters.pageFrom > 0 || filters.pageTo > 0) {
        params.push('f_sp=on');
        if (filters.pageFrom > 0) {
          params.push(`f_spf=${filters.pageFrom}`);
        }
        if (filters.pageTo > 0) {
          params.push(`f_spt=${filters.pageTo}`);
        }
      }
      // 忽略站点默认过滤（My Settings 的语言/上传者 + My Tags 的标签屏蔽）。
      if (filters.ignoreFilters) {
        params.push('f_sfl=on');
        params.push('f_sfu=on');
        params.push('f_sft=on');
      }
    }
    if (page > 0) {
      params.push(`page=${page}`);
    }
    const base: string = EhUrl.host(site);
    return params.length === 0 ? base : `${base}?${params.join('&')}`;
  }

  /**
   * 上传者列表 URL（源 `ListUrlBuilder.build` MODE_UPLOADER）：
   * `https://<host>/uploader/<enc>/[page]`（`page` 0 起，`0` 不带段）。
   */
  static uploader(site: EhSite, name: string, page: number): string {
    const base: string = `${EhUrl.host(site)}uploader/${EhUrl.encodeQuery(name.trim())}/`;
    return page > 0 ? `${base}${page}` : base;
  }

  /**
   * 标签列表 URL（源 `ListUrlBuilder.build` MODE_TAG）：
   * `https://<host>/tag/<enc>/[page]`（`page` 0 起，`0` 不带段）。
   */
  static tag(site: EhSite, name: string, page: number): string {
    const base: string = `${EhUrl.host(site)}tag/${EhUrl.encodeQuery(name.trim())}/`;
    return page > 0 ? `${base}${page}` : base;
  }

  static api(site: EhSite): string {
    return `${EhUrl.host(site)}api.php`;
  }

  /**
   * 高级设置页（源 `EhUrl.getUConfigUrl` + `UConfigActivity`）：
   * `https://<host>/uconfig.php`。站内 WebView 编辑服务端展示偏好（`uconfig` cookie 形态）；
   * App 只负责带 Cookie 打开 + 关时写回 Cookie，无本地键解析。
   */
  static uconfig(site: EhSite): string {
    return `${EhUrl.host(site)}uconfig.php`;
  }

  /**
   * 我的标签页（源 `EhUrl.getMyTagsUrl` + `MyTagsActivity` 薄包）：
   * `https://<host>/mytags`。站内管理关注标签；App 只负责带 Cookie 打开 + 关时写回。
   */
  static myTags(site: EhSite): string {
    return `${EhUrl.host(site)}mytags`;
  }

  /** 详情页：`https://<host>/g/<gid>/<token>/` */
  static galleryDetail(site: EhSite, gid: number, token: string): string {
    return `${EhUrl.host(site)}g/${gid}/${token}/`;
  }

  /**
   * 详情页的**预览分块**：`https://<host>/g/<gid>/<token>/?p=<chunk>`（`chunk === 0` 时不带 `p`）。
   * 每个分块返回该段页码的 `/s/<pToken>/<gid>-<page>` 链接（每块 20 页），
   * 用于**任意跳页**取 pToken（源 `EhUrl.getGalleryDetailUrl(gid, token, index, false)`）。
   */
  static galleryDetailChunk(site: EhSite, gid: number, token: string, chunk: number): string {
    const base: string = EhUrl.galleryDetail(site, gid, token);
    return chunk > 0 ? `${base}?p=${chunk}` : base;
  }

  /** 图片页：`https://<host>/s/<pToken>/<gid>-<page>`（可选 H@H `?nl=`）。 */  static galleryPage(site: EhSite, gid: number, page: number, pToken: string, skipHathKey?: string): string {
    let url: string = `${EhUrl.host(site)}s/${pToken}/${gid}-${page}`;
    if (skipHathKey !== undefined && skipHathKey.length > 0) {
      url += `?nl=${skipHathKey}`;
    }
    return url;
  }

  /**
   * 缩略图分辨率重写（源 `EhUtils.handleThumbUrlResolution`）：
   * `size` 1 → `_250`，2 → `_300`（替换末段 `_xxx` 后缀）；0/非法值原样返回。
   * 与 `fixedPreviewThumb` 串联：先定域、再定尺寸。
   */
  static thumbResolution(originUrl: string, size: number): string {
    let resolution: string = '';
    if (size === 1) {
      resolution = '250';
    } else if (size === 2) {
      resolution = '300';
    } else {
      return originUrl;
    }
    const index1: number = originUrl.lastIndexOf('_');
    const index2: number = originUrl.lastIndexOf('.');
    if (index1 >= 0 && index2 >= 0 && index1 < index2) {
      return originUrl.substring(0, index1 + 1) + resolution + originUrl.substring(index2);
    }
    return originUrl;
  }

  /**
   * 修正预览缩略图 URL 到 `ehgt.org`。
   * 末三段为 `third/second/last` 且 `last` 自 `third.length` 起以 `second` 开头时，
   * 返回 `https://ehgt.org/<third>/<second>/<last>`；否则原样返回。
   */
  static fixedPreviewThumb(originUrl: string): string {
    let clean: string = originUrl;
    const hashIndex: number = clean.indexOf('#');
    if (hashIndex >= 0) {
      clean = clean.substring(0, hashIndex);
    }
    const queryIndex: number = clean.indexOf('?');
    if (queryIndex >= 0) {
      clean = clean.substring(0, queryIndex);
    }
    const schemeIndex: number = clean.indexOf('://');
    if (schemeIndex < 0) {
      return originUrl;
    }
    const afterScheme: string = clean.substring(schemeIndex + 3);
    const slashIndex: number = afterScheme.indexOf('/');
    if (slashIndex < 0) {
      return originUrl;
    }
    const rawParts: string[] = afterScheme.substring(slashIndex + 1).split('/');
    const segments: string[] = [];
    for (let i = 0; i < rawParts.length; i++) {
      if (rawParts[i].length > 0) {
        segments.push(rawParts[i]);
      }
    }
    if (segments.length < 3) {
      return originUrl;
    }
    const last: string = segments[segments.length - 1];
    const second: string = segments[segments.length - 2];
    const third: string = segments[segments.length - 3];
    if (last.startsWith(second, third.length)) {
      return `${EhUrl.THUMB_PREFIX}${third}/${second}/${last}`;
    }
    return originUrl;
  }
}
