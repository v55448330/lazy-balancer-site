#!/usr/bin/env bash
# 更新日志去重门禁（docs.html）：一个面向用户的能力 = 一条日志。
#
# 判定口径（与人工门禁同源，机器化）：
#   1) 条目解析：段内每个 <li> 取「类型（新增/优化/修复/其他）+ 主语」，主语 =
#      类型后的第一个短句，截止于 —— / — / ， / ； / 。 /（；
#   2) 段内重复：同一主语在本版本段出现两次即失败（不论类型）——子视图/子能力
#      必须用分号并入父条目，同一能力不得跨「新增/优化/修复」分摊；
#   3) 跨版本归类：本版本「新增」的主语不得在上一个已发布版本的条目里出现过
#      ——上一版已存在的能力只能写优化/修复。反方向（优化/修复 主语必须在上一版
#      出现过）不可机器判定：修复/优化常针对上一版日志未提及的细节，强行要求会
#      产生假失败，故不检查。
#
# 实现注记：主语是中文，**比较一律走 cut/sort/uniq/grep -F 的字节比较**——
# BSD awk 的 `$3==s` 对多字节字符串在本机环境会误判相等（实测不同中文主语
# 比较为真），故 awk 只做段/条目切分，不做相等判定。
#
# 用法：bash scripts/check-changelog-dupes.sh [vX.Y.Z]
#   省略版本号时取更新日志段最前面的版本。通过时打印条目清单（类型 | 主语），
#   便于直接贴进交付报告；任一违规退出码 1。
set -euo pipefail

cd "$(dirname "$0")/.."
doc="docs.html"
[[ -f "${doc}" ]] || { echo "ERROR: 缺少 ${doc}" >&2; exit 1; }

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/changelog-dupes.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT
records_file="${tmp_dir}/records.tsv"

# —— 抽取全文档的更新日志条目：version<TAB>type<TAB>subject<TAB>line ——
# 只认 <h3>vX.Y.Z…</h3> 开头的版本段；段内 <li> 逐条解析。
awk '
  {
    line = $0
  }
  line ~ /^[ \t]*<h3>v[0-9]+\.[0-9]+\.[0-9]+/ {
    ver = line
    sub(/^[ \t]*<h3>/, "", ver)
    sub(/[（(].*$/, "", ver)
    sub(/<.*$/, "", ver)
    gsub(/[ \t]/, "", ver)
    cur = ver
    next
  }
  cur != "" && line ~ /<li>/ {
    s = line
    sub(/^.*<li>/, "", s)
    gsub(/<[^>]*>/, "", s)
    if (s !~ /^(新增|优化|修复|其他)[：:]/) next
    typ = s
    sub(/[：:].*$/, "", typ)
    sub(/^(新增|优化|修复|其他)[：:]/, "", s)
    gsub(/——.*$/, "", s)
    gsub(/—.*$/, "", s)
    gsub(/，.*$/, "", s)
    gsub(/；.*$/, "", s)
    gsub(/。.*$/, "", s)
    gsub(/（.*$/, "", s)
    gsub(/^[ \t]+|[ \t]+$/, "", s)
    if (s == "") next
    printf "%s\t%s\t%s\t%d\n", cur, typ, s, NR
  }
' "${doc}" >"${records_file}" || { echo "ERROR: 解析 ${doc} 失败" >&2; exit 1; }

version="${1:-}"
if [[ -z "${version}" ]]; then
  version="$(awk -F'\t' 'NR == 1 { print $1 }' "${records_file}")"
fi
[[ -n "${version}" ]] || { echo "ERROR: 无法定位任何版本段（${doc} 结构已变？）" >&2; exit 1; }

section_file="${tmp_dir}/section.tsv"
awk -F'\t' -v v="${version}" '$1 == v' "${records_file}" >"${section_file}"
if [[ ! -s "${section_file}" ]]; then
  echo "ERROR: 未找到版本段 ${version} 的条目（版本号写错或该段无「类型：描述」条目）" >&2
  exit 1
fi

# 上一版段 = 记录流中本版本之后出现的第一个版本号。
prev_version="$(awk -F'\t' -v v="${version}" 'seen && $1 != v { print $1; exit } $1 == v { seen = 1 }' "${records_file}")"

fail=0

# —— 段内重复主语 ——
dupe_subjects="$(cut -f3 "${section_file}" | LC_ALL=C sort | LC_ALL=C uniq -d)"
if [[ -n "${dupe_subjects}" ]]; then
  echo "ERROR: ${version} 段存在重复主语——一个能力只写一条（子能力用「；」并入父条目，同一能力不得跨类型分摊）：" >&2
  while IFS= read -r subject; do
    [[ -n "${subject}" ]] || continue
    echo "  重复主语「${subject}」：" >&2
    grep -F -- $'\t'"${subject}"$'\t' "${section_file}" \
      | awk -F'\t' '{ printf "    第 %s 行（%s）\n", $4, $2 }' >&2
  done <<<"${dupe_subjects}"
  fail=1
fi

# —— 「新增」主语不得在上一版出现过 ——
if [[ -n "${prev_version}" ]]; then
  prev_subjects_file="${tmp_dir}/prev-subjects.txt"
  awk -F'\t' -v v="${prev_version}" '$1 == v { print $3 }' "${records_file}" >"${prev_subjects_file}"
  cross_report=""
  while IFS= read -r record; do
    [[ -n "${record}" ]] || continue
    subject="$(cut -f3 <<<"${record}")"
    lineno="$(cut -f4 <<<"${record}")"
    if grep -Fxq -f <(printf '%s\n' "${subject}") "${prev_subjects_file}"; then
      prev_line="$(grep -F -- $'\t'"${subject}"$'\t' "${records_file}" | awk -F'\t' -v v="${prev_version}" '$1 == v { print $4; exit }')"
      cross_report+="  「新增：${subject}」（第 ${lineno} 行）已出现在 ${prev_version}（第 ${prev_line} 行）——上一版已有的能力只能写优化/修复"$'\n'
    fi
  done < <(awk -F'\t' '$2 == "新增"' "${section_file}")
  if [[ -n "${cross_report}" ]]; then
    echo "ERROR: ${version} 的「新增」条目与 ${prev_version} 段冲突：" >&2
    printf '%s' "${cross_report}" >&2
    fail=1
  fi
fi

# —— 条目清单（交付报告直接贴这一段）——
echo "版本段：${version}（上一版：${prev_version:-无}）"
echo "条目清单（类型 | 主语）："
awk -F'\t' '{ printf "  %s | %s（第 %s 行）\n", $2, $3, $4 }' "${section_file}"
echo "分类计数：$(awk -F'\t' '{ c[$2]++ } END { for (t in c) printf " %s=%d", t, c[t]; printf " 合计=%d", NR }' "${section_file}")"

if [[ "${fail}" -ne 0 ]]; then
  exit 1
fi
echo "OK: ${version} 段无重复主语、无跨版本归类冲突。"
