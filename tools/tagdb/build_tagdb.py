#!/usr/bin/env python3
"""生成 / 校验内置标签翻译快照 `tagdb.v1.tsv`。

用法（在仓库根目录跑，`--out` 默认仓库内的 rawfile 路径，与当前工作目录无关）：

    # 下载上游最新快照并写入内置产物（发版前跑一次，产物要一起提交）
    python tools/tagdb/build_tagdb.py

    # 用本地已下载的上游快照（例如 %TEMP%\\ehtag_db.text.json），省掉重复下载
    python tools/tagdb/build_tagdb.py --src "$env:TEMP\\ehtag_db.text.json"

    # 只构建 + 校验，不写文件；顺带确认已入库的产物与源数据同步
    python tools/tagdb/build_tagdb.py --src ... --check

    # 写到别处（调试 / 对比新旧格式）
    python tools/tagdb/build_tagdb.py --src ... --out build/tagdb.debug.tsv

产物为什么入库：标签翻译是浏览与搜索时随时要用、且首次启动（含离线）就得有的东西，
不能等一次网络往返；快照只有约 3 MB，压进 hap 后约 1.9 MB。运行期另有"设备端转更新文件"
的路径，靠文件头 `#tagdb` 的格式版本判断能否覆盖内置这份——所以版本号是硬契约，不能随手改。

格式权威：docs/superpowers/specs/2026-11-02-tag-translation-design.md §2.2。
解析端 entry/src/main/ets/tagdb/TagDbFormat.ets 的 escapeField / parseTagDb 与本文件
**必须逐字一致**：转义顺序、列数、按 UTF-16 码元排序。两边不一致的后果是"内置的没事、
更新后写坏"，属于只在部分用户身上延迟出现的 bug，所以这里对格式一律硬断言，不兜底。

数据来源：https://github.com/EhTagTranslation/Database（GFDL / CC BY-NC-SA 3.0）。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SOURCE_URL = "https://raw.githubusercontent.com/EhTagTranslation/Database/release/db.text.json"

# 脚本在 tools/tagdb/ 下，往上两级是仓库根；默认输出跟着仓库走，不依赖 cwd。
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "entry/src/main/resources/rawfile/tagdb.v1.tsv"

FORMAT_VERSION = 1
# `rows` 是上游的命名空间索引（伪命名空间），只进 `#rows` 的中文名表，不重复进 `#tags`。
ROWS_NS = "rows"
# 上游稳定在此量级；超出说明结构或统计口径变了，先人工确认再改这两条，别让脚本静默放过。
EXPECTED_NS = 13
TAG_MIN = 44_000
TAG_MAX = 45_500


def escape_field(raw: str) -> str:
    """字段 → 单行安全文本。

    顺序必须是先 `\\` 再 TAB/LF，否则替换出的反斜杠会被二次转义（与 ArkTS `escapeField` 同序）。
    CR 直接丢弃：行分隔只用 LF，CR 只可能来自上游的 CRLF，留着会让字段末尾多一个隐形字符。
    """
    return (
        raw.replace("\\", "\\\\")
        .replace("\t", "\\t")
        .replace("\n", "\\n")
        .replace("\r", "")
    )


def sort_key(row: tuple[str, str, str, str]) -> bytes:
    """`ns + ':' + tag` 的 UTF-16 大端字节串，即 UTF-16 码元序。

    为什么不用 Python 默认的字符串序：默认序比较**码点**，而 ArkTS 的 `<` 比较 **UTF-16 码元**；
    一个字面量 U+1F600 超出 BMP 时，两者在"它 vs U+FFFD"上的先后相反——生成端放行、解析端
    就会因"未严格递增"整份拒绝。编码成 utf-16-be 后逐字节比较与码元序完全一致。
    surrogatepass：万一上游混进孤立代理项，按单个码元编码也比直接抛错更贴近解析端行为。
    """
    ns, tag, _name, _intro = row
    return f"{ns}:{tag}".encode("utf-16-be", "surrogatepass")


def load_source(src: str | None) -> dict:
    if src is None:
        print(f"下载 {SOURCE_URL}", file=sys.stderr)
        try:
            with urllib.request.urlopen(SOURCE_URL, timeout=120) as resp:
                raw = resp.read()
        except OSError as exc:
            raise SystemExit(
                f"下载失败：{exc}\n"
                "可先手动下载再用 --src 指向本地文件，例如：\n"
                f'  python tools/tagdb/build_tagdb.py --src "$env:TEMP\\ehtag_db.text.json"'
            )
        try:
            return json.loads(raw.decode("utf-8"))
        except ValueError as exc:
            raise SystemExit(f"上游响应不是合法 JSON：{exc}")

    path = Path(src)
    if not path.is_file():
        raise SystemExit(f"--src 指向的文件不存在：{path}")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def build(doc: dict, built_at: str) -> str:
    """上游 JSON → 整份快照文本（未落盘）。纯函数，方便 --check 复用同一份逻辑。"""
    head = doc.get("head") or {}
    sha = head.get("sha")
    if not isinstance(sha, str) or not sha:
        raise SystemExit("上游 JSON 缺 head.sha，无法写 #source（不能编一个假的）")

    ns_rows: list[tuple[str, str]] = []
    tag_rows: list[tuple[str, str, str, str]] = []
    dropped_empty_name = 0

    for block in doc.get("data") or []:
        ns = block["namespace"]
        # 只取 frontMatters.name：description / rules / copyright / abbr 是上游编辑器元数据，界面上不出现。
        ns_name = (block.get("frontMatters") or {}).get("name") or ""
        ns_rows.append((ns, ns_name))
        if ns == ROWS_NS:
            continue
        for tag, entry in (block.get("data") or {}).items():
            name = entry.get("name") or ""
            # 译名为空就别进表：解析端命中后直接返回译名，空串会把界面上的标签抹成空白；
            # 不入表则自然回退原文，与"没装翻译"表现一致。释义跟着一起丢，没有译名的释义用不上。
            if not name.strip():
                dropped_empty_name += 1
                continue
            tag_rows.append((ns, tag, name, entry.get("intro") or ""))

    if dropped_empty_name:
        print(f"跳过译名为空的条目 {dropped_empty_name} 条", file=sys.stderr)

    tag_rows.sort(key=sort_key)

    lines: list[str] = [f"#tagdb\t{FORMAT_VERSION}", f"#source\t{sha}\t{built_at}"]
    lines.append("#rows")
    for ns, ns_name in ns_rows:
        lines.append(f"{escape_field(ns)}\t{escape_field(ns_name)}")
    lines.append("#tags")
    for ns, tag, name, _intro in tag_rows:
        lines.append(f"{escape_field(ns)}\t{escape_field(tag)}\t{escape_field(name)}")
    # `#intro` 只放非空释义，顺序沿用 `#tags`（解析端不校验，但保持有序便于人肉对照与将来做流式加载）。
    lines.append("#intro")
    for ns, tag, _name, intro in tag_rows:
        if intro:
            lines.append(f"{escape_field(ns)}\t{escape_field(tag)}\t{escape_field(intro)}")

    return "\n".join(lines) + "\n"


def fail(msg: str) -> None:
    """格式问题一律硬失败：产物是要随包分发的，静默放过等于把坏文件推给所有用户。"""
    raise SystemExit(f"校验失败：{msg}")


def validate(text: str) -> dict:
    """对**生成物本身**做与解析端同口径的校验，并加几条构建期的数据量断言。"""
    if text.startswith("\ufeff"):
        fail("文件以 BOM 开头（UTF-8 不允许带 BOM）")
    if "\ufeff" in text:
        fail("文件里出现 U+FEFF（BOM 只可能是编码器误加）")
    if "\r" in text:
        fail("文件含裸 CR（换行只能 LF，CRLF 会让每行末尾多一个隐形字符）")

    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()  # 允许且默认带一个末尾换行；其余空行视为异常
    if not lines:
        fail("空文件")
    if lines[0] != f"#tagdb\t{FORMAT_VERSION}":
        fail(f"首行应为 #tagdb<TAB>{FORMAT_VERSION}，实际 {lines[0]!r}")

    sha = built_at = None
    section: str | None = None
    section_order: list[str] = []
    ns_rows: list[tuple[str, str]] = []
    tag_rows: list[tuple[str, str, str]] = []
    intro_rows: list[tuple[str, str, str]] = []

    for lineno, line in enumerate(lines[1:], start=2):
        if line == "":
            fail(f"第 {lineno} 行是空行（只允许文件末尾一个换行）")
        if line.startswith("#"):
            cols = line.split("\t")
            head = cols[0]
            if head == "#source":
                if len(cols) != 3:
                    fail(f"第 {lineno} 行 #source 有 {len(cols)} 列（应 3 列）")
                sha, built_at = cols[1], cols[2]
                section = None
                continue
            if head in ("#rows", "#tags", "#intro"):
                if len(cols) != 1:
                    fail(f"第 {lineno} 行段头 {head} 后面不应再有列")
                # 段头重复不报错的话，同名段会被悄悄合并，计数断言反而看不出问题。
                if head in section_order:
                    fail(f"第 {lineno} 行段头 {head} 重复出现")
                section = head
                section_order.append(head)
                continue
            fail(f"第 {lineno} 行未知段头 {head!r}")

        cols = line.split("\t")
        if section == "#rows":
            if len(cols) != 2:
                fail(f"第 {lineno} 行 #rows 有 {len(cols)} 列（应 2 列）")
            ns_rows.append((cols[0], cols[1]))
        elif section == "#tags":
            if len(cols) != 3:
                fail(f"第 {lineno} 行 #tags 有 {len(cols)} 列（应 3 列）")
            tag_rows.append((cols[0], cols[1], cols[2]))
        elif section == "#intro":
            if len(cols) != 3:
                fail(f"第 {lineno} 行 #intro 有 {len(cols)} 列（应 3 列）")
            intro_rows.append((cols[0], cols[1], cols[2]))
        else:
            fail(f"第 {lineno} 行不在任何段内：{line[:40]!r}")

    # 段的出现顺序是加载器的假设（顺序读一遍就建完表），虽然在解析端也能容忍乱序，但生成端只允许一种写法。
    if section_order != ["#rows", "#tags", "#intro"]:
        fail(f"段顺序应为 #rows → #tags → #intro，实际 {section_order}")

    if sha is None or built_at is None:
        fail("缺 #source 段")
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        fail(f"#source 的 sha 不像 git sha：{sha!r}")
    # 定长 + 大写 Z 才保证"字典序即时间序"（加载器靠字符串比较判新鲜度）。
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", built_at):
        fail(f"#source 的生成时间不是 ISO8601 UTC（形如 2026-11-02T09:30:00Z）：{built_at!r}")

    if len(ns_rows) != EXPECTED_NS:
        fail(f"#rows 有 {len(ns_rows)} 个命名空间（应 {EXPECTED_NS} 个；上游结构变了就人工确认后改 EXPECTED_NS）")
    ns_set = {row[0] for row in ns_rows}
    if len(ns_set) != len(ns_rows):
        fail("#rows 有重复命名空间")
    if ROWS_NS not in ns_set:
        fail(f"#rows 缺伪命名空间 {ROWS_NS!r}")

    if not (TAG_MIN <= len(tag_rows) <= TAG_MAX):
        fail(f"#tags 有 {len(tag_rows)} 条（应落在 {TAG_MIN}–{TAG_MAX}；上游增长后确认无误再调窗口）")
    if not (0 < len(intro_rows) < len(tag_rows)):
        fail(f"#intro 有 {len(intro_rows)} 条，需 > 0 且 < #tags 的 {len(tag_rows)} 条")

    prev: bytes | None = None
    tag_keys: set[str] = set()
    for index, (ns, tag, _name) in enumerate(tag_rows):
        key = f"{ns}:{tag}"
        if ns == ROWS_NS:
            fail(f"第 {index + 1} 条 tag 用了伪命名空间 {ROWS_NS!r}（它只该出现在 #rows）")
        if ns not in ns_set:
            fail(f"tag {key!r} 的命名空间不在 #rows 里")
        if key in tag_keys:
            fail(f"#tags 有重复 key：{key!r}")
        tag_keys.add(key)
        # 用与生成时同一个编码比较，确保"生成即合法"，不靠解析端碰运气。
        cur = key.encode("utf-16-be", "surrogatepass")
        if prev is not None and not cur > prev:
            fail(f"#tags 未按 UTF-16 码元序严格递增：{key!r} 不大于上一条")
        prev = cur

    prev = None
    for index, (ns, tag, _intro) in enumerate(intro_rows):
        key = f"{ns}:{tag}"
        if key not in tag_keys:
            fail(f"第 {index + 1} 条 #intro 的 key 不在 #tags 里：{key!r}")
        cur = key.encode("utf-16-be", "surrogatepass")
        if prev is not None and not cur > prev:
            fail(f"#intro 未按 #tags 的顺序排列：{key!r}")
        prev = cur

    return {
        "rows": len(ns_rows),
        "tags": len(tag_rows),
        "intro": len(intro_rows),
        "sha": sha,
        "built_at": built_at,
    }


def without_built_at(text: str) -> str:
    """抹掉 `#source` 的时间列，用于和已入库文件比对：同一份源数据重跑时只有时间会变。"""
    out = []
    for line in text.split("\n"):
        if line.startswith("#source\t"):
            cols = line.split("\t")
            if len(cols) == 3:
                out.append(f"#source\t{cols[1]}")
                continue
        out.append(line)
    return "\n".join(out)


def check_committed(out: Path, text: str) -> None:
    if not out.is_file():
        print(f"file=absent（{out} 还没生成）")
        return
    with open(out, encoding="utf-8", newline="") as f:
        committed = f.read()
    # 先按同一套规则验一遍已入库的文件：不一致时才能区分"数据过期"与"文件被 CRLF/BOM 弄坏"。
    validate(committed)
    if without_built_at(committed) != without_built_at(text):
        fail(f"已入库的 {out} 与当前源数据不一致（源数据更新了？重跑不带 --check 生成后重新提交）")
    print("file=in-sync")


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="生成 / 校验内置标签翻译快照 tagdb.v1.tsv",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"上游缺省地址：{SOURCE_URL}\n缺省输出：{DEFAULT_OUT}",
    )
    parser.add_argument("--src", metavar="PATH", help="本地已下载的上游 db.text.json；省略则从上游下载")
    parser.add_argument("--out", metavar="PATH", default=str(DEFAULT_OUT), help="输出路径（默认 rawfile 里的内置产物）")
    parser.add_argument("--check", action="store_true", help="只构建并校验，不写文件；同时确认已入库产物与源数据同步")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    doc = load_source(args.src)
    text = build(doc, now_iso())
    summary = validate(text)

    # 第一行是给测试 / 脚本 grep 的稳定摘要，不要改格式。
    print(
        f"rows={summary['rows']} tags={summary['tags']} intro={summary['intro']} format={FORMAT_VERSION}"
    )
    print(
        f"source={summary['sha']} built={summary['built_at']} bytes={len(text.encode('utf-8'))}"
    )

    if args.check:
        check_committed(Path(args.out), text)
        return 0

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    # newline="" + 显式 utf-8：不让 Windows 把 LF 翻成 CRLF，也不让 Python 写 BOM。
    with open(out, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    print(f"wrote {out} bytes={out.stat().st_size}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
