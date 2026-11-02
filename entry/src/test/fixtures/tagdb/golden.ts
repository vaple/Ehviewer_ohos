/** 由 scripts/tagdb/gen_golden.py 从 convert_doc.json 生成，勿手改（--check 会拦住不一致）。 */

/** `#source` 的生成时间列（固定值，逐字比对的前提）。 */
export const GOLDEN_BUILT_AT: string = "2026-11-02T09:30:00Z";

/** 与 `convert_doc.json` 逐字相同的上游 JSON（ArkTS 单测进程读不到 fixture 文件，只能内联）。 */
export const CONVERT_DOC_JSON: string = "{\n  \"repo\": \"EhTagTranslation/Database\",\n  \"head\": { \"sha\": \"abcdef0123456789abcdef0123456789abcdef01\" },\n  \"version\": 7,\n  \"data\": [\n    {\n      \"namespace\": \"artist\",\n      \"frontMatters\": { \"name\": \"艺术家\", \"abbr\": \"a\", \"description\": \"画师\" },\n      \"data\": {\n        \"some artist\": { \"name\": \"某画师\", \"intro\": \"第一行\\n第二行\", \"links\": \"\" },\n        \"aaa artist\": { \"name\": \"甲画师\" },\n        \"back\\\\slash tag\": { \"name\": \"反\\\\斜杠\" }\n      }\n    },\n    {\n      \"namespace\": \"female\",\n      \"frontMatters\": { \"name\": \"女性\" },\n      \"data\": {\n        \"sample tags\": { \"name\": \"示\\t例\", \"intro\": \"\" },\n        \"empty name\": { \"name\": \"   \", \"intro\": \"没有译名\" },\n        \"no name\": { \"intro\": \"也没有译名\" }\n      }\n    }\n  ]\n}\n";

/** Python 生成器的产物；ArkTS `dbJsonToTsv` 必须给出同一个串。 */
export const GOLDEN_TSV: string = "#tagdb\t1\n#source\tabcdef0123456789abcdef0123456789abcdef01\t2026-11-02T09:30:00Z\n#rows\nartist\t艺术家\nfemale\t女性\n#tags\nartist\taaa artist\t甲画师\nartist\tback\\\\slash tag\t反\\\\斜杠\nartist\tsome artist\t某画师\nfemale\tsample tags\t示\\t例\n#intro\nartist\tsome artist\t第一行\\n第二行\n";
