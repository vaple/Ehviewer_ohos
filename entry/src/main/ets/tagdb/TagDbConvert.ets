import { escapeField, TAGDB_FORMAT } from './TagDbFormat';

/**
 * 上游 `db.text.json` → 我们的 `tagdb.v1.tsv`（**纯函数**：不碰文件、不碰网络、不碰 UI）。
 *
 * 为什么设备端还要一份转换器：更新链路吃的是上游原始 JSON，不在任何地方托管预转换产物。
 * 它必须与 `tools/tagdb/build_tagdb.py` 的 `build()` **逐字一致**（转义顺序、UTF-16 码元序、
 * 丢弃规则、段顺序），否则「内置快照没事、更新后写坏」会变成只在更新过的用户身上出现的延迟 bug。
 * 因此这里不发明任何规则：上游没给的东西（links / description / abbr 等）一律不写，译名为空的条目整条丢弃。
 *
 * 产物的最终形状由 `parseTagDb` 校验（更新流程里紧跟一步），任何格式问题都表现为抛错而不是写盘。
 */

/** 上游结构只声明用得到的字段；`JSON.parse` 的结果按此断言，不逐个字段做类型体操。 */
interface TagEntryWire {
  /** 上游用 `null` 表示「没有」：Python 生成器的 `entry.get("name") or ""` 会当空串，这里必须一致。 */
  name?: string | null;
  intro?: string | null;
}

interface FrontMattersWire {
  name?: string | null;
}

interface TagBlockWire {
  namespace?: string;
  frontMatters?: FrontMattersWire | null;
  data?: Record<string, TagEntryWire> | null;
}

interface HeadWire {
  sha?: string | null;
}

interface TagDbWire {
  head?: HeadWire | null;
  data?: TagBlockWire[];
}

/** 与 python 的 `FORMAT_VERSION` 同一个来源：运行时格式版本常量。 */
const FORMAT_LINE: string = `#tagdb\t${TAGDB_FORMAT}`;

/** git sha（40 位小写十六进制）。上游只会给这个形状；不像就说明结构/接口变了，必须人工确认。 */
const GIT_SHA: RegExp = /^[0-9a-f]{40}$/;

/**
 * `#source` 的生成时间必须是**定长** ISO8601 UTC：加载器用字典序比较沙箱快照与内置快照的新鲜度，
 * 带毫秒或时区偏移都会让比较结果随书写形式漂移。Python 生成端用同一形状。
 */
const ISO_UTC_SECONDS: RegExp = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;

/** 排序中间态：`key` 即 `ns + ':' + tag`（未转义），与解析端的二分键同一个串。 */
interface TagRow {
  ns: string;
  tag: string;
  name: string;
  intro: string;
  key: string;
}

/** `#rows` 的中间态：命名空间 + 中文名。 */
interface NsRow {
  ns: string;
  name: string;
}

function nowIsoUtc(): string {
  // `toISOString()` 带 3 位毫秒；截到秒再加 `Z`，与 python 的 strftime('%Y-%m-%dT%H:%M:%SZ') 同形。
  return new Date().toISOString().substring(0, 19) + 'Z';
}

/** 上游用 `null` 表示「没有」，Python 生成器统一 `or ""`；折叠成空串才是同一个口径。 */
function textOf(value: string | null | undefined): string {
  return value === undefined || value === null ? '' : value;
}

/**
 * `ns + ':' + tag` 的排序比较。直接 `<` / `>`：JS 字符串比较就是 UTF-16 码元序，
 * 与 python 端 `encode('utf-16-be')` 逐字节比较等价（用 `localeCompare` 会按语言规则排，破坏二分的假设）。
 */
function compareKey(a: TagRow, b: TagRow): number {
  if (a.key === b.key) {
    return 0;
  }
  return a.key < b.key ? -1 : 1;
}

/** 上游 JSON 文本 → 整份 TSV 文本（含末尾换行）。`builtAt` 可注入，测试用它固定时间。 */
export function dbJsonToTsv(jsonText: string, builtAt: string = nowIsoUtc()): string {
  if (!ISO_UTC_SECONDS.test(builtAt)) {
    throw new Error(`tagdb convert: 生成时间不是 ISO8601 UTC（形如 2026-11-02T09:30:00Z）：${builtAt}`);
  }

  let doc: TagDbWire;
  try {
    doc = JSON.parse(jsonText) as TagDbWire;
  } catch (e) {
    // 原始异常拼进 message（调用方只把它写进日志）：要能区分「上游返回了 HTML 错误页」与「JSON 结构变了」。
    throw new Error(`tagdb convert: 上游响应不是合法 JSON：${e}`);
  }

  const head: HeadWire | null | undefined = doc.head;
  const sha: string | null | undefined = head === undefined || head === null ? undefined : head.sha;
  if (sha === undefined || sha === null || sha.length === 0) {
    // 不能编一个假的 sha：它同时是「是否已是最新」的判断依据。
    throw new Error('tagdb convert: 上游 JSON 缺 head.sha');
  }
  if (!GIT_SHA.test(sha)) {
    throw new Error(`tagdb convert: head.sha 不像 40 位 git sha：${sha}`);
  }

  const blocks: TagBlockWire[] | undefined = doc.data;
  if (blocks === undefined || !Array.isArray(blocks)) {
    throw new Error('tagdb convert: 上游 JSON 缺 data 数组');
  }

  const nsRows: NsRow[] = [];
  const rows: TagRow[] = [];
  for (let i = 0; i < blocks.length; i++) {
    const block: TagBlockWire = blocks[i];
    const ns: string | undefined = block.namespace;
    if (ns === undefined || ns.length === 0) {
      throw new Error(`tagdb convert: 第 ${i + 1} 个命名空间块缺 namespace`);
    }
    const front: FrontMattersWire | null | undefined = block.frontMatters;
    const nsName: string = front === undefined || front === null ? '' : textOf(front.name);
    // `rows` 是上游的命名空间索引（伪命名空间），只进 `#rows`，不重复进 `#tags`。
    nsRows.push({ ns: ns, name: nsName });
    if (ns === 'rows') {
      continue;
    }
    const entries: Record<string, TagEntryWire> | null | undefined = block.data;
    if (entries === undefined || entries === null) {
      continue;
    }
    const tags: string[] = Object.keys(entries);
    for (let j = 0; j < tags.length; j++) {
      const tag: string = tags[j];
      const entry: TagEntryWire = entries[tag];
      const name: string = textOf(entry.name);
      // 译名为空就不进表：解析端命中后直接返回译名，空串会把界面上的标签抹成空白；不入表则自然回退原文。
      // 释义跟着一起丢——没有译名的释义用不上，留着只会让 `#intro` 出现 `#tags` 里不存在的 key。
      if (name.trim().length === 0) {
        continue;
      }
      const intro: string = textOf(entry.intro);
      rows.push({ ns: ns, tag: tag, name: name, intro: intro, key: `${ns}:${tag}` });
    }
  }

  if (rows.length === 0) {
    throw new Error('tagdb convert: 上游 JSON 里没有可用标签条目（结构可能变了）');
  }

  // 解析端要求 `#tags` 按 key 严格递增（二分查找的前提），排序必须在**未转义**的 key 上做。
  rows.sort(compareKey);

  const lines: string[] = [];
  lines.push(FORMAT_LINE);
  lines.push(`#source\t${sha}\t${builtAt}`);
  lines.push('#rows');
  for (let i = 0; i < nsRows.length; i++) {
    lines.push(`${escapeField(nsRows[i].ns)}\t${escapeField(nsRows[i].name)}`);
  }
  lines.push('#tags');
  for (let i = 0; i < rows.length; i++) {
    const row: TagRow = rows[i];
    lines.push(`${escapeField(row.ns)}\t${escapeField(row.tag)}\t${escapeField(row.name)}`);
  }
  // `#intro` 只放非空释义，顺序沿用 `#tags`（解析端不校验顺序，但保持有序便于人肉对照）。
  lines.push('#intro');
  for (let i = 0; i < rows.length; i++) {
    const row: TagRow = rows[i];
    if (row.intro.length > 0) {
      lines.push(`${escapeField(row.ns)}\t${escapeField(row.tag)}\t${escapeField(row.intro)}`);
    }
  }
  // 只用 LF（不写 CRLF、不写 BOM）：`parseTagDb` 见到裸 CR 会整份拒绝。
  return lines.join('\n') + '\n';
}
