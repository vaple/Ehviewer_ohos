"""一键打包：release 构建 -> 校验未签名产物 -> dist/ehviewer-<versionName>.hap

只产出**未签名**包（GitHub Release 分发用，用户侧自签工具装）。

用法：
    python scripts/package.py                  # 用当前 versionName 打包
    python scripts/package.py --bump patch     # 先把 versionName 升一个 patch（minor/major 同理），再打包
    python scripts/package.py --no-build       # 只搬运/校验已有产物（在 IDE 里「编译 Hap(s)」之后用这个）
    python scripts/package.py --out D:\\share   # 换输出目录（默认 <repo>/dist）

版本号规则（单一真源 = AppScope/app.json5 的 versionName）：
    versionCode = major * 1_000_000 + minor * 10_000 + patch * 100
    1.0.0 -> 1000000 / 1.0.1 -> 1000100 / 1.2.3 -> 1020300

    versionCode 由工程级 hvigorfile.ts 在**构建期**注入产物（IDE 点「编译 Hap(s)」和本脚本
    走的是同一个钩子），不写源文件。因此校验产物时用**公式值**比对，不读 app.json5 里的
    versionCode（那里可能是旧值，构建期会被覆盖）。--bump 会顺手把公式值写进 app.json5，
    纯粹为了让文件不至于长期显示旧数字。

约束：
    - 只读 build-profile.json5，绝不写它（本机签名配置常驻工作区，由 pre-commit 守卫兜底）。
    - 只取 entry-default-unsigned.hap：即使工作区配了签名，分发出去的也永远是未签名包。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_JSON = ROOT / "AppScope" / "app.json5"
OUTPUT_DIR = ROOT / "entry" / "build" / "default" / "outputs" / "default"
UNSIGNED_HAP = OUTPUT_DIR / "entry-default-unsigned.hap"
SIGNED_HAP = OUTPUT_DIR / "entry-default-signed.hap"
HAP_NAME_PREFIX = "ehviewer"

SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
BUNDLE_RE = re.compile(r'("bundleName"\s*:\s*")([^"]*)(")')
VERSION_CODE_RE = re.compile(r'("versionCode"\s*:\s*)(\d+)')
VERSION_NAME_RE = re.compile(r'("versionName"\s*:\s*")([^"]*)(")')

# hvigor 输出里值得打到屏幕上的行（其余 WARN 噪音丢掉，失败时再整体回显尾部）
KEEP_LINE_HINTS = (
    "BUILD SUCCESSFUL",
    "BUILD FAILED",
    "ERROR",
    "Will skip sign",
    "[version]",
    "Finished :entry:default@CompileArkTS",
    "Finished :entry:default@PackageHap",
    "Finished :entry:default@SignHap",
)
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


class PackageError(RuntimeError):
    pass


def version_code_of(version_name: str) -> int:
    m = SEMVER_RE.match(version_name)
    if not m:
        raise PackageError(
            f"versionName 不是 x.y.z 形式：{version_name!r}（脚本不猜版本，请先改成 1.0.0 这种）"
        )
    major, minor, patch = (int(v) for v in m.groups())
    if minor > 99 or patch > 99:
        raise PackageError(f"minor/patch 不能超过 99（现在 {major}.{minor}.{patch}），否则公式会串位")
    return major * 1_000_000 + minor * 10_000 + patch * 100


def bump_version(version_name: str, part: str) -> str:
    m = SEMVER_RE.match(version_name)
    if not m:
        raise PackageError(f"versionName 不是 x.y.z 形式，无法 --bump：{version_name!r}")
    major, minor, patch = (int(v) for v in m.groups())
    if part == "major":
        major, minor, patch = major + 1, 0, 0
    elif part == "minor":
        minor, patch = minor + 1, 0
    else:
        patch += 1
    return f"{major}.{minor}.{patch}"


def read_app_json() -> tuple[str, str, str]:
    """返回 (原文, bundleName, versionName)。原文按字节读出，保留原有换行。"""
    raw = APP_JSON.read_bytes().decode("utf-8")
    bundle = BUNDLE_RE.search(raw)
    name = VERSION_NAME_RE.search(raw)
    if not (bundle and name):
        raise PackageError(f"{APP_JSON} 里找不到 bundleName / versionName")
    return raw, bundle.group(2), name.group(2)


def rewrite_version(raw: str, version_name: str, version_code: int) -> str:
    """把 versionName 与公式值的 versionCode 一起写回（只为让 app.json5 可读，构建期以 hvigor 为准）。"""
    new = VERSION_NAME_RE.sub(lambda m: f"{m.group(1)}{version_name}{m.group(3)}", raw, count=1)
    new = VERSION_CODE_RE.sub(lambda m: f"{m.group(1)}{version_code}", new, count=1)
    if new == raw:
        raise PackageError("versionName/versionCode 回写失败（原文未变化）")
    return new


TAGDB_SCRIPT = ROOT / "scripts" / "tagdb" / "build_tagdb.py"


def ensure_tagdb() -> None:
    """打包前补齐内置标签翻译快照。

    与工程级 `hvigorfile.ts` 的 preBuild 钩子走**同一个入口**（`build_tagdb.py --ensure`）：
    "文件在不在 / 新不新"的判断只活在脚本里，这里和钩子都不自己实现一遍。
    钩子随后还会跑一次，那时是 304 命中、几乎零成本。
    """
    print("[tagdb] 检查内置翻译快照…", flush=True)
    proc = subprocess.run(
        [sys.executable, str(TAGDB_SCRIPT), "--ensure"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    for line in (proc.stdout or "").splitlines():
        if line.startswith(("ensure=", "wrote ")):
            print(f"[tagdb] {line}", flush=True)
    if proc.returncode != 0:
        print(proc.stdout or "", file=sys.stderr)
        print(proc.stderr or "", file=sys.stderr)
        raise PackageError("内置标签翻译快照生成失败（构建需要联网，见 AGENTS.md §5）")


def devecocli_command() -> list[str]:
    exe = shutil.which("devecocli")
    if not exe:
        raise PackageError("找不到 devecocli（确认 DevEco/命令行工具在 PATH 里）")
    if exe.lower().endswith((".cmd", ".bat")):
        return ["cmd", "/c", exe]
    return [exe]


def run_build() -> None:
    cmd = [*devecocli_command(), "build", "--product", "default", "--build-mode", "release"]
    print(f"[build] {' '.join(cmd)}", flush=True)
    tail: list[str] = []
    proc = subprocess.Popen(
        cmd,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    assert proc.stdout is not None
    for line in proc.stdout:
        clean = ANSI_RE.sub("", line).rstrip()
        if not clean:
            continue
        tail.append(clean)
        if len(tail) > 200:
            del tail[0]
        if any(hint in clean for hint in KEEP_LINE_HINTS):
            print(f"[build] {clean.strip()}", flush=True)
    code = proc.wait()
    if code != 0 or not any("BUILD SUCCESSFUL" in line for line in tail[-20:]):
        print("---- hvigor 输出尾部 ----", file=sys.stderr)
        print("\n".join(tail[-40:]), file=sys.stderr)
        raise PackageError(f"构建失败（devecocli 退出码 {code}）")


def signature_block_size(hap: Path) -> int | None:
    """未签名 hap 的中央目录紧跟最后一个本地文件；签名块插在两者之间 -> 返回间隙字节数。

    返回 None 表示结构不规整（本地头带 data descriptor，无法按 csize 跳），调用方只报警不判定。
    """
    raw = hap.read_bytes()
    pos = 0
    while raw[pos:pos + 4] == b"PK\x03\x04":
        flag, = struct.unpack("<H", raw[pos + 6:pos + 8])
        csize, = struct.unpack("<I", raw[pos + 18:pos + 22])
        nlen, elen = struct.unpack("<HH", raw[pos + 26:pos + 30])
        if flag & 0x08 or csize == 0:
            return None
        pos += 30 + nlen + elen + csize
    eocd = raw.rfind(b"PK\x05\x06")
    if eocd < 0:
        return None
    cd_offset, = struct.unpack("<I", raw[eocd + 16:eocd + 20])
    return cd_offset - pos


def inspect_hap(hap: Path, bundle: str, version_name: str, version_code: int) -> str:
    """校验产物是未签名的 release 包且版本对得上，返回包的 compatible API。"""
    if not hap.is_file():
        raise PackageError(f"找不到未签名产物：{hap.relative_to(ROOT)}（先构建一次，或用 IDE 的「编译 Hap(s)」）")

    block = signature_block_size(hap)
    if block is None:
        print("[warn] 无法按 zip 结构判定签名块（本地头带 data descriptor），跳过该项检查")
    elif block > 0:
        raise PackageError(f"产物里带了签名块（{block} 字节），不是未签名包")

    with zipfile.ZipFile(hap) as zf:
        names = zf.namelist()
        signed_entries = [n for n in names if n.startswith("META-INF/") or n.lower().endswith((".p7b", ".rsa", ".sf"))]
        if signed_entries:
            raise PackageError(f"产物里有签名相关文件：{', '.join(signed_entries[:5])}")
        try:
            module = json.loads(zf.read("module.json"))
        except KeyError as exc:
            raise PackageError("产物里没有 module.json，包结构不对") from exc
        pack_info = json.loads(zf.read("pack.info")) if "pack.info" in names else {}

    app = module.get("app", {})
    if app.get("bundleName") != bundle:
        raise PackageError(f"包内 bundleName 不一致：{app.get('bundleName')} != {bundle}")
    if app.get("debug") is not False:
        raise PackageError(
            f"包是 debug 构建（debug={app.get('debug')}），不是 release 产物"
            "（IDE 里把 Build Mode 切到 release 再编译）"
        )
    build_mode = app.get("buildMode")
    if build_mode is not None and build_mode != "release":
        raise PackageError(f"包内 buildMode={build_mode}，不是 release")
    if app.get("versionName") != version_name:
        raise PackageError(f"包内 versionName={app.get('versionName')} != 预期 {version_name}")
    if app.get("versionCode") != version_code:
        raise PackageError(
            f"包内 versionCode={app.get('versionCode')} != 预期 {version_code}"
            "（预期值按 versionName 公式算，由 hvigorfile.ts 构建期注入；对不上说明构建没走钩子）"
        )

    modules = pack_info.get("summary", {}).get("modules") or []
    return str(modules[0].get("apiVersion", {}).get("compatible", "")) if modules else ""


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="打包未签名 HAP 到 dist/（EhViewer 侧载分发用）")
    parser.add_argument("--bump", choices=("major", "minor", "patch"), help="先升 versionName，再打包")
    parser.add_argument("--no-build", action="store_true", help="跳过构建，只搬运/校验现有产物")
    parser.add_argument("--out", default="dist", help="输出目录（默认 dist/，相对路径以仓库根为基准）")
    args = parser.parse_args(argv)

    bumped_to: str | None = None
    try:
        raw, bundle, version_name = read_app_json()
        if args.bump:
            version_name = bump_version(version_name, args.bump)
            version_code = version_code_of(version_name)
            APP_JSON.write_bytes(rewrite_version(raw, version_name, version_code).encode("utf-8"))
            bumped_to = version_name
            print(f"[version] {args.bump} bump -> {version_name} ({version_code})，已写入 AppScope/app.json5")
        else:
            version_code = version_code_of(version_name)
            print(f"[version] {version_name} ({version_code})")

        if args.no_build:
            print("[build] 跳过（--no-build）")
        else:
            ensure_tagdb()
            run_build()

        api = inspect_hap(UNSIGNED_HAP, bundle, version_name, version_code)

        out_dir = Path(args.out)
        if not out_dir.is_absolute():
            out_dir = ROOT / out_dir
        out_dir.mkdir(parents=True, exist_ok=True)
        dest = out_dir / f"{HAP_NAME_PREFIX}-{version_name}.hap"
        if dest.exists():
            print(f"[out] 覆盖同名旧包：{dest.name}（同版本重打）")
        shutil.copyfile(UNSIGNED_HAP, dest)
        digest = sha256_of(dest)
        (dest.parent / f"{dest.name}.sha256").write_text(f"{digest}  {dest.name}\n", encoding="utf-8", newline="\n")

        size_kb = dest.stat().st_size / 1024
        api_text = f"API{api}" if api else "API?"
        print()
        print(f"[OK] {dest.relative_to(ROOT) if dest.is_relative_to(ROOT) else dest}")
        print(f"     {size_kb:.0f} KB   {bundle} {version_name} ({version_code})   {api_text}   unsigned")
        print(f"     sha256 {digest}")
        if SIGNED_HAP.is_file():
            print(f"     注意：本次也生成了签名包 {SIGNED_HAP.relative_to(ROOT)}（绑本机设备白名单，只能自己装，别分发）")
        return 0
    except PackageError as exc:
        sys.stdout.flush()  # 让上面的进度行先出来，失败原因不至于跑到前面
        print(f"[FAIL] {exc}", file=sys.stderr)
        if bumped_to is not None:
            print(
                f"[FAIL] AppScope/app.json5 的 versionName 已是 {bumped_to}（未回滚，重跑不要再加 --bump）",
                file=sys.stderr,
            )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
