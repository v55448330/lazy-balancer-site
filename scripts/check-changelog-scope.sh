#!/usr/bin/env bash
# 更新日志版本范围/必需能力门禁（release-notes/<tag>.json 为版本级事实源）。
#
# 解决的根因（用户多轮纠正）：
#   - 把 beta 开发期间的“修复”写进版本日志（不是 v2.4.4 用户可感知的发布变化）；
#   - 漏写本版本已经交付的能力（默认策略/API 接入/MCP 总开关/CC 默认值等）；
#   - 把首次交付的新能力写成“重构”（上一版并不存在）。
#
# 门禁口径：
#   1) manifest 的 tag/base_tag/theme/notes 与 versions.json 顶部版本逐字一致；
#   2) beta 版本禁止“修复：”条目（修复并入兜底条或留在版本内，不面向上一版用户）；
#   3) manifest.features 每个必需能力必须在 notes 文本中出现；
#   4) “重构：”条目的能力必须在 base_tag 版本的 notes/theme 中存在，否则必须写“新增”；
#   5) 条目类型只允许：新增/优化/加固/安全/其他（allow_fixes=true 时允许修复）。
#
# 用法：bash scripts/check-changelog-scope.sh [tag]
#   RELEASE_ROOT=<dir> 可指定仓库根（自测用）。
#   --self-test 跑鉴别力用例：缺能力/版本内修复/把新能力写重构/主题漂移必须红。
set -euo pipefail

root="${RELEASE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
script="$root/scripts/check-changelog-scope.sh"

if [[ "${1:-}" == "--self-test" ]]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/changelog-scope.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/scripts" "$tmp/release-notes"
  cp "$script" "$tmp/scripts/check-changelog-scope.sh"

  write_fixture() { # $1=case, $2=manifest json, $3=versions json
    rm -rf "$tmp/case"; mkdir -p "$tmp/case/scripts" "$tmp/case/release-notes"
    cp "$tmp/scripts/check-changelog-scope.sh" "$tmp/case/scripts/"
    printf '%s' "$2" > "$tmp/case/release-notes/v9.9.9-beta.json"
    printf '%s' "$3" > "$tmp/case/versions.json"
  }
  run_case() { # $1=name, $2=expect(pass|fail), $3=manifest, $4=versions
    write_fixture "$1" "$3" "$4"
    set +e
    RELEASE_ROOT="$tmp/case" bash "$tmp/case/scripts/check-changelog-scope.sh" >"$tmp/out" 2>&1
    rc=$?
    set -e
    if [[ "$2" == pass && $rc -ne 0 ]]; then echo "SELFTEST FAIL: $1 expected pass: $(cat "$tmp/out")" >&2; exit 1; fi
    if [[ "$2" == fail && $rc -eq 0 ]]; then echo "SELFTEST FAIL: $1 expected fail" >&2; exit 1; fi
  }
  base='{"versions":[{"version":"v9.9.9-beta","theme":"功能甲、功能乙。","notes":["新增：页面·功能甲——描述甲","优化：页面·功能乙——描述乙"]},{"version":"v9.9.8","theme":"旧功能。","notes":["新增：页面·旧功能——旧描述"]}]}'
  okm='{"tag":"v9.9.9-beta","base_tag":"v9.9.8","theme":"功能甲、功能乙。","features":["功能甲","功能乙"],"allow_fixes":false,"notes":["新增：页面·功能甲——描述甲","优化：页面·功能乙——描述乙"]}'
  miss='{"tag":"v9.9.9-beta","base_tag":"v9.9.8","theme":"功能甲、功能乙。","features":["功能甲","功能乙","功能丙"],"allow_fixes":false,"notes":["新增：页面·功能甲——描述甲","优化：页面·功能乙——描述乙"]}'
  fixm='{"tag":"v9.9.9-beta","base_tag":"v9.9.8","theme":"功能甲、功能乙。","features":["功能甲","功能乙"],"allow_fixes":false,"notes":["新增：页面·功能甲——描述甲","修复：页面·功能乙——错误修复"]}'
  refm='{"tag":"v9.9.9-beta","base_tag":"v9.9.8","theme":"功能甲、新功能。","features":["功能甲","新功能"],"allow_fixes":false,"notes":["新增：页面·功能甲——描述甲","重构：页面·新功能——描述"]}'
  drift='{"tag":"v9.9.9-beta","base_tag":"v9.9.8","theme":"功能甲、功能丙。","features":["功能甲","功能乙"],"allow_fixes":false,"notes":["新增：页面·功能甲——描述甲","优化：页面·功能乙——描述乙"]}'
  run_case clean pass "$okm" "$base"
  run_case missing-feature fail "$miss" "$base"
  run_case beta-fix fail "$fixm" "$base"
  run_case refactor-new fail "$refm" "$base"
  run_case theme-drift fail "$drift" "$base"
  echo "selftest: all cases passed"
  exit 0
fi

tag="${1:-}"
python3 - "$root" "$tag" <<'PY'
import json, os, sys
root, tag = sys.argv[1], sys.argv[2]
versions = json.load(open(os.path.join(root, 'versions.json'), encoding='utf-8'))
items = versions.get('versions') or []
if not items:
    print('ERROR: versions.json 无版本条目'); sys.exit(1)
item = items[0]
if tag:
    found = [v for v in items if v.get('version') == tag]
    if not found:
        print(f'ERROR: versions.json 缺少版本 {tag}'); sys.exit(1)
    item = found[0]
tag = item['version']
mpath = os.path.join(root, 'release-notes', f'{tag}.json')
if not os.path.isfile(mpath):
    print(f'ERROR: 缺少版本日志 manifest release-notes/{tag}.json'); sys.exit(1)
m = json.load(open(mpath, encoding='utf-8'))
errs = []
if m.get('tag') != tag: errs.append(f'manifest.tag={m.get("tag")} != {tag}')
if m.get('theme') != item.get('theme'): errs.append('manifest.theme 与 versions.json 主题不一致')
if m.get('notes') != item.get('notes'): errs.append('manifest.notes 与 versions.json 条目不一致')
base_tag = m.get('base_tag') or ''
base = next((v for v in items if v.get('version') == base_tag), None)
if base is None: errs.append(f'base_tag {base_tag!r} 不在 versions.json')
notes = m.get('notes') or []
text = '\n'.join(notes)
allowed = {'新增', '优化', '加固', '安全', '其他'}
if m.get('allow_fixes'): allowed.add('修复')
for i, n in enumerate(notes, 1):
    kind = n.split('：', 1)[0]
    if kind not in allowed:
        errs.append(f'第 {i} 条类型「{kind}」不允许（beta 版本内修复不得入日志）')
    if tag.endswith('-beta') and kind == '修复' and not m.get('allow_fixes'):
        errs.append(f'第 {i} 条是版本内修复，不应进入 {tag} 更新日志')
for feat in m.get('features') or []:
    feat = str(feat).strip()
    if feat and feat not in text:
        errs.append(f'缺少必需能力：{feat}')
if base is not None:
    base_text = '\n'.join((base.get('notes') or [])) + '\n' + (base.get('theme') or '')
    for i, n in enumerate(notes, 1):
        if not n.startswith('重构：'):
            continue
        cap = n.split('：', 1)[1].split('——', 1)[0]
        if '·' in cap: cap = cap.split('·', 1)[1]
        if cap and cap not in base_text:
            errs.append(f'第 {i} 条把首次交付能力写成「重构」：{cap}（上一版不存在，应写新增）')
if errs:
    print(f'ERROR: {tag} 更新日志版本范围/能力清单不符：')
    for e in errs: print('  -', e)
    sys.exit(1)
print(f'OK: {tag} 版本范围/必需能力校验通过（features={len(m.get("features") or [])}, notes={len(notes)}）')
PY
