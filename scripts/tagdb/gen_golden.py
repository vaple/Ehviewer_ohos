#!/usr/bin/env python3
"""从 `convert_doc.json` 生成 Python 侧的黄金样本，供 ArkTS 单测逐字比对。

用法（在仓库根目录跑）：

    # 重新生成 fixture（改了 convert_doc.json 或生成器规则之后）
    python scripts/tagdb/gen_golden.py

    # 只比对、不写文件；不一致直接非 0 退出（发版 / CI 用）
    python scripts/tagdb/gen_golden.py --check

为什么需要：Python 生成器（发版产物）与 ArkTS 转换器（设备端更新）是两套独立实现，规则必须逐字一致
（转义顺序、丢弃规则、按 UTF-16 码元排序、段顺序）。只靠人工对账时，任何一侧单独改了规则都不会被发现。
这里把**同一份** JSON 交给 Python 生成器跑出 TSV，落成 `golden.tsv`（人看的）+ `golden.ts`（测试 import 的形态，
单测进程读不到 fixture 文件），单测断言
`dbJsonToTsv(CONVERT_DOC_JSON, GOLDEN_BUILT_AT) === GOLDEN_TSV`。

`#source` 的时间列固定成 `BUILT_AT`：真实生成时它是"当前时间"，逐字比对必须固定。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

# 脚本与 build_tagdb.py 同目录：直接复用它的 build()，不复制规则（复制出来就又变成"两套实现"了）。
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_tagdb import build  # noqa: E402  (必须先插 sys.path)

# 脚本在 scripts/tagdb/ 下，往上两级是仓库根。
REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_DIR = REPO_ROOT / "entry/src/test/fixtures/tagdb"
DOC_PATH = FIXTURE_DIR / "convert_doc.json"
TSV_PATH = FIXTURE_DIR / "golden.tsv"
TS_PATH = FIXTURE_DIR / "golden.ts"

BUILT_AT = "2026-11-02T09:30:00Z"


def ts_literal(text: str) -> str:
    """Python/JSON 字符串 → TS 双引号字面量。

    `json.dumps` 的转义规则（\\\\ \\" \\n \\t \\r \\uXXXX）与 JS 字符串字面量兼容；`ensure_ascii=False`
    保留中文可读性。换成手写 replace 很容易漏掉反斜杠的二次转义。
    """
    return json.dumps(text, ensure_ascii=False)


def render_ts(doc_text: str, tsv: str) -> str:
    lines = [
        "/** 由 scripts/tagdb/gen_golden.py 从 convert_doc.json 生成，勿手改（--check 会拦住不一致）。 */",
        "",
        "/** `#source` 的生成时间列（固定值，逐字比对的前提）。 */",
        f"export const GOLDEN_BUILT_AT: string = {ts_literal(BUILT_AT)};",
        "",
        "/** 与 `convert_doc.json` 逐字相同的上游 JSON（ArkTS 单测进程读不到 fixture 文件，只能内联）。 */",
        f"export const CONVERT_DOC_JSON: string = {ts_literal(doc_text)};",
        "",
        "/** Python 生成器的产物；ArkTS `dbJsonToTsv` 必须给出同一个串。 */",
        f"export const GOLDEN_TSV: string = {ts_literal(tsv)};",
        "",
    ]
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    check = "--check" in argv
    doc_text = DOC_PATH.read_text(encoding="utf-8")
    doc = json.loads(doc_text)
    tsv = build(doc, BUILT_AT)
    ts = render_ts(doc_text, tsv)

    if check:
        drift = []
        for path, expected in ((TSV_PATH, tsv), (TS_PATH, ts)):
            if not path.is_file():
                drift.append(f"{path} 不存在")
                continue
            with open(path, encoding="utf-8", newline="") as f:
                if f.read() != expected:
                    drift.append(f"{path} 与生成器输出不一致")
        if drift:
            raise SystemExit("黄金样本过期（重跑 python scripts/tagdb/gen_golden.py）：\n  " + "\n  ".join(drift))
        print(f"golden=in-sync tags={len(tsv.splitlines())} lines")
        return 0

    # newline=""：不让 Windows 把 LF 翻成 CRLF（ArkTS 端的解析器见到裸 CR 会整份拒绝）。
    with open(TSV_PATH, "w", encoding="utf-8", newline="") as f:
        f.write(tsv)
    with open(TS_PATH, "w", encoding="utf-8", newline="") as f:
        f.write(ts)
    print(f"wrote {TSV_PATH} bytes={TSV_PATH.stat().st_size}")
    print(f"wrote {TS_PATH} bytes={TS_PATH.stat().st_size}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
