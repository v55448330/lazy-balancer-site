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
#   4) 长度：条目可见正文（类型前缀＋描述，去 HTML 标签、去空白）<70 字符——
#      写作规范要求「一句话一个事实、无解释性从句」，细节留给文档站。超限条目
#      逐行打印行号与字数，任一超限退出码 1。长度门只约束被测版本段（即发布前
#      正在写的这一段）；历史段落按当时口径保留，不回改、不参与判定。
#   5) 近义主语与能力词表：主语去尾部通用后缀（能力/功能/面板/…）后同名即失败
#      ——「缓存预热」与「缓存预热能力」是一条能力；并按 capability_groups 词表
#      把同一能力的别名（如 威胁大屏 / 安全态势 / 光流 / 流量采样 / 2D / 3D）
#      归成一个 canonical 名，同一版本段里 ≥2 条独立条目命中同一 canonical 即失败。
#      词表存在的原因是主语字节相等太粗：v2.3.8 曾把「威胁大屏」拆成五条独立
#      日志，主语字节全不同，纯字节去重为绿。另对「一条主语是另一条前缀」打印
#      提示（不失败）——同版本内的不同能力也可能共享前缀，最终仍需人审。
#
# 实现注记：主语是中文，**比较一律走 cut/sort/uniq/grep -F 的字节比较**——
# BSD awk 的 `$3==s` 对多字节字符串在本机环境会误判相等（实测不同中文主语
# 比较为真），故 awk 只做段/条目切分，不做相等判定。能力词表内的子串判定用
# bash 模式匹配（`== *alias*`），不做跨语言字符串比较。
#
# 用法：bash scripts/check-changelog-dupes.sh [vX.Y.Z]
#   省略版本号时取更新日志段最前面的版本。通过时打印条目清单（类型 | 主语 |
#   字数），便于直接贴进交付报告；任一违规（重复主语 / 近义主语 / 能力拆分 /
#   跨版本冲突 / 单条超长）退出码 1。
#   CHANGELOG_DOC=<file> 可改读取的文档（自测用例用）。
#   bash scripts/check-changelog-dupes.sh --self-test 跑门禁自身的鉴别力用例：
#   事故形态必须红、通过形态必须绿（含威胁大屏五条拆分与近义主语两种盲区）。
set -euo pipefail

self_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.."
doc="${CHANGELOG_DOC:-docs.html}"
[[ -f "${doc}" ]] || { echo "ERROR: 缺少 ${doc}" >&2; exit 1; }

# —— 能力词表：同一能力的别名/子视图 ——
# 只放「面向用户的同一能力」的别名；通用词（集群、证书、规则）刻意不入表，
# 否则同版本里两个相邻但不同的能力会被误判成拆分。canonical<TAB>别名1|别名2…
capability_groups() {
  cat <<'EOF'
威胁大屏	威胁大屏|安全态势|光流|流量采样|2D|3D
后台任务	后台任务|任务引擎|任务监控|任务日志
证书续签	证书续签|证书自动续期|续签重试
自动封禁	自动封禁|自动拉黑|封禁名单
备份导入	备份导入|导入备份|备份还原
EOF
}

# 主语归一：剥掉尾部一个通用名词。「缓存预热」与「缓存预热能力」是同一能力，
# 字节比较却判成两条。中文无词干可提取，只做这一层，避免过度归一。
normalize_subject() {
  printf '%s' "$1" | sed -E 's/(能力|功能|面板|页面|大屏|视图|支持|机制|流程|特性|设置|配置|名单|列表)$//'
}

# 主语 → canonical 能力名：命中词表别名用 canonical，否则用归一主语。
canonicalize_subject() {
  local canonical aliases alias
  local -a alias_arr
  while IFS=$'\t' read -r canonical aliases; do
    [[ -n "${canonical}" ]] || continue
    IFS='|' read -r -a alias_arr <<<"${aliases}"
    for alias in "${alias_arr[@]}"; do
      [[ -n "${alias}" ]] || continue
      if [[ "$1" == *"${alias}"* ]]; then
        printf '%s\n' "${canonical}"
        return 0
      fi
    done
  done < <(capability_groups)
  normalize_subject "$1"
}

# —— 自测：门禁自身的鉴别力（--self-test） ——
# 每个夹具生成一份精简文档，用 CHANGELOG_DOC 指向它并以子进程跑同一份脚本
# （隔离全局状态）。事故形态必须红、通过形态必须绿——只验「绿」的门禁无法
# 证明它仍能拦住回归。
self_test() {
  local work out rc=0 boundary_69 boundary_70
  work="$(mktemp -d "${TMPDIR:-/tmp}/changelog-dupes-selftest.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '${work}'" EXIT

  run_case() {  # name expect_rc expect_text docfile [version]
    local name="$1" want_rc="$2" needle="$3" file="$4" ver="${5:-}" got_rc
    set +e
    if [[ -n "${ver}" ]]; then
      out="$(CHANGELOG_DOC="${file}" bash "${self_path}" "${ver}" 2>&1)"
    else
      out="$(CHANGELOG_DOC="${file}" bash "${self_path}" 2>&1)"
    fi
    got_rc=$?
    set -e
    if [[ "${got_rc}" -ne "${want_rc}" ]]; then
      echo "FAIL [${name}] 退出码 ${got_rc}，期望 ${want_rc}" >&2
      printf '%s\n' "${out}" | sed 's/^/    /' >&2
      rc=1
      return
    fi
    if [[ -n "${needle}" && "${out}" != *"${needle}"* ]]; then
      echo "FAIL [${name}] 输出未包含「${needle}」" >&2
      printf '%s\n' "${out}" | sed 's/^/    /' >&2
      rc=1
      return
    fi
    echo "ok   [${name}]"
  }

  # A) 事故原形态：同一能力的子视图拆成五条独立条目（主语字节全不同）。
  cat >"${work}/split-subviews.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：威胁大屏——三栏版式。</li>
<li>新增：安全态势面板。</li>
<li>新增：2D/3D 双视图。</li>
<li>新增：攻击光流。</li>
<li>新增：流量采样频率可调。</li>
</ul>
EOF
  run_case "split sub-views are rejected" 1 '能力「威胁大屏」被' "${work}/split-subviews.html"

  # B) 合并形态：子能力用分号并入父条目 → 必须绿（避免误伤正确文案）。
  cat >"${work}/merged-parent.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：威胁大屏——三栏版式与 2D/3D 双视图；攻击光流；流量采样。</li>
</ul>
EOF
  run_case "merged parent entry passes" 0 'OK: v9.9.9' "${work}/merged-parent.html"

  # C) 近义主语：尾部通用后缀不是新能力。
  cat >"${work}/synonym.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：缓存预热。</li>
<li>优化：缓存预热能力。</li>
</ul>
EOF
  run_case "near-synonym subject is rejected" 1 '近义主语' "${work}/synonym.html"

  # D) 字节完全相同的重复主语（既有契约，防回归）。
  cat >"${work}/exact-dupe.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>优化：集群同步。</li>
<li>修复：集群同步。</li>
</ul>
EOF
  run_case "exact duplicate subject is rejected" 1 '重复主语' "${work}/exact-dupe.html"

  # E) 跨版本：「新增」不得是上一版已存在的能力。
  cat >"${work}/cross-version.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：规则导入。</li>
</ul>
<h3>v9.9.8</h3>
<ul>
<li>优化：规则导入。</li>
</ul>
EOF
  run_case "cross-version add conflicts" 1 '已出现在 v9.9.8' "${work}/cross-version.html"

  # F) 单条长度上限（≥70 字必须拒绝）。
  cat >"${work}/too-long.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>优化：这一条日志写得太长了已经超过七十个字符的上限需要拆开说明具体细节才符合写作规范要求并且还要继续拉长以确保触发长度门禁同时保留足够多的解释性从句来测试边界行为。</li>
</ul>
EOF
  run_case "over-length entry is rejected" 1 '<70 字' "${work}/too-long.html"

  # G) 精确长度边界：类型前缀计入正文，69 字必须绿，70 字必须红。
  # run_case 同时断言退出码与门禁输出的实际字数，防止夹具长度或判定口径漂移。
  boundary_69="优化：$(printf '界%.0s' {1..66})"
  boundary_70="${boundary_69}界"
  printf '<h3>v9.9.9</h3>\n<ul>\n<li>%s</li>\n</ul>\n' "${boundary_69}" >"${work}/exactly-69.html"
  printf '<h3>v9.9.9</h3>\n<ul>\n<li>%s</li>\n</ul>\n' "${boundary_70}" >"${work}/exactly-70.html"
  run_case "69-character entry passes" 0 '第 3 行，69 字' "${work}/exactly-69.html"
  run_case "70-character entry is rejected" 1 '第 3 行，70 字' "${work}/exactly-70.html"

  # H) 前缀相同但不失败：提示必须出现，退出码仍为 0（人审定位，不误伤）。
  cat >"${work}/prefix-hint.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：证书上传。</li>
<li>新增：证书上传失败回滚。</li>
</ul>
EOF
  run_case "shared prefix only hints" 0 '前缀' "${work}/prefix-hint.html"

  # I) 干净段：条目清单必须打印（交付报告依赖该输出）。
  cat >"${work}/clean.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：缓存预热。</li>
</ul>
EOF
  run_case "clean section prints item list" 0 '条目清单' "${work}/clean.html"

  if [[ "${rc}" -eq 0 ]]; then
    echo "selftest: all cases passed"
  else
    echo "selftest: FAILED" >&2
  fi
  return "${rc}"
}

if [[ "${1:-}" == "--self-test" ]]; then
  if self_test; then
    exit 0
  fi
  exit 1
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/changelog-dupes.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT
records_file="${tmp_dir}/records.tsv"

# —— 抽取全文档的更新日志条目：version<TAB>type<TAB>subject<TAB>line<TAB>text ——
# 只认 <h3>vX.Y.Z…</h3> 开头的版本段；段内 <li> 逐条解析。text 是该条目的可见
# 正文（类型前缀＋描述，去标签、去空白），供长度门逐条计字符数。
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
    full = s
    gsub(/[ \t]+/, "", full)
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
    printf "%s\t%s\t%s\t%d\t%s\n", cur, typ, s, NR, full
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

# —— 近义主语：归一（尾部通用后缀 + 能力别名）后同名 ——
# 「新增：缓存预热」＋「优化：缓存预热能力」在字节层是两个主语，语义上是一条
# 能力被跨类型分摊。已按字节判过重复的主语不再重复报告（同一个问题只说一次）。
norm_file="${tmp_dir}/section-norm.tsv"
: >"${norm_file}"
while IFS=$'\t' read -r _ver typ subject lineno _text; do
  [[ -n "${subject}" ]] || continue
  if [[ -n "${dupe_subjects}" ]] && grep -Fxq -- "${subject}" <<<"${dupe_subjects}"; then
    continue
  fi
  printf '%s\t%s\t%s\t%s\n' "$(canonicalize_subject "${subject}")" "${lineno}" "${typ}" "${subject}" >>"${norm_file}"
done <"${section_file}"
dupe_canon="$(cut -f1 "${norm_file}" | LC_ALL=C sort | LC_ALL=C uniq -d)"
if [[ -n "${dupe_canon}" ]]; then
  echo "ERROR: ${version} 段存在近义主语——同一能力不得拆成多条（主语归一后同名，含尾部通用后缀与能力别名）：" >&2
  while IFS= read -r canon; do
    [[ -n "${canon}" ]] || continue
    echo "  归一能力「${canon}」：" >&2
    grep -F -- "${canon}"$'\t' "${norm_file}" \
      | awk -F'\t' '{ printf "    第 %s 行（%s：%s）\n", $2, $3, $4 }' >&2
  done <<<"${dupe_canon}"
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

# —— 能力词表交叉：同一 canonical 能力被 ≥2 条独立条目描述 ——
# 主语字节去重拦不住事故原形态：子视图被写成「威胁大屏」「安全态势面板」
# 「2D/3D 双视图」「光流」「流量采样」时主语全不同。词表把别名归成一个 canonical，
# 同段命中 ≥2 条即判拆分（子能力必须用「；」并入父条目）。
group_report=""
while IFS=$'\t' read -r canonical aliases; do
  [[ -n "${canonical}" ]] || continue
  local_alias_arr=()
  IFS='|' read -r -a local_alias_arr <<<"${aliases}"
  matched=""
  while IFS=$'\t' read -r _ver typ subject lineno text; do
    [[ -n "${text}" ]] || continue
    for alias in "${local_alias_arr[@]}"; do
      [[ -n "${alias}" ]] || continue
      if [[ "${text}" == *"${alias}"* ]]; then
        matched+="${lineno}"$'\t'"${typ}"$'\t'"${subject}"$'\n'
        break
      fi
    done
  done <"${section_file}"
  entry_count="$(printf '%s' "${matched}" | grep -c . || true)"
  if [[ "${entry_count}" -ge 2 ]]; then
    group_report+="  能力「${canonical}」被 ${entry_count} 条条目分别描述（子视图/子能力必须用「；」并入父条目）："$'\n'
    while IFS=$'\t' read -r gline gtyp gsubject; do
      [[ -n "${gline}" ]] || continue
      group_report+="    第 ${gline} 行（${gtyp}：${gsubject}）"$'\n'
    done <<<"${matched}"
    fail=1
  fi
done < <(capability_groups)
if [[ -n "${group_report}" ]]; then
  echo "ERROR: ${version} 段存在同一能力的拆分条目（能力别名按词表归一）：" >&2
  printf '%s' "${group_report}" >&2
fi

# —— 前缀互含：只提示不失败 ——
# 一条主语是另一条的前缀，可能是同一能力被拆开，也可能是同版本内两个确有区别
# 的能力（如「安全事件列表…」与「安全事件保留…」）；机器无法分辨，交人审。
hint_report=""
while IFS=$'\t' read -r canon_a line_a _typ_a _subject_a; do
  [[ -n "${canon_a}" ]] || continue
  while IFS=$'\t' read -r canon_b line_b _typ_b _subject_b; do
    [[ -n "${canon_b}" ]] || continue
    if [[ "${line_a}" == "${line_b}" || "${canon_a}" == "${canon_b}" ]]; then
      continue
    fi
    if [[ "${canon_b}" == "${canon_a}"* ]]; then
      hint_report+="    第 ${line_a} 行「${canon_a}」是第 ${line_b} 行「${canon_b}」的前缀"$'\n'
    fi
  done <"${norm_file}"
done <"${norm_file}"

# —— 单条长度：<70 字符（用户裁定）——
# 口径：条目可见正文（类型前缀＋描述，去 HTML 标签、去空白）的 UTF-8 字符数。
# 计数与 locale 无关（BSD awk 的 length() 数的是字节）：去掉全部续接字节
# （0x80-0xBF）后的字节数即字符数。
char_count() {
  printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | LC_ALL=C wc -c | tr -d ' '
}
max_chars=69
over_report=""
while IFS=$'\t' read -r _ver _typ _subject lineno text; do
  [[ -n "${text}" ]] || continue
  chars="$(char_count "${text}")"
  if [[ "${chars}" -gt "${max_chars}" ]]; then
    over_report+="    第 ${lineno} 行（${chars} 字）：${text}"$'\n'
  fi
done <"${section_file}"
if [[ -n "${over_report}" ]]; then
  echo "ERROR: ${version} 段有条目超过 <70 字（上限 69 字）——一句话一个事实，解释性从句移入文档站；能力子项用「；」并入父条目：" >&2
  printf '%s' "${over_report}" >&2
  fail=1
fi

# —— 条目清单（交付报告直接贴这一段）——
if [[ -n "${hint_report}" ]]; then
  echo "提示（不失败，需人工确认）：${version} 段有主语互含前缀，请确认不是同一能力被拆成两条："
  printf '%s' "${hint_report}"
fi
echo "版本段：${version}（上一版：${prev_version:-无}）"
echo "条目清单（类型 | 主语 | 字数）："
while IFS=$'\t' read -r _ver typ subject lineno text; do
  [[ -n "${text}" ]] || continue
  printf '  %s | %s（第 %s 行，%s 字）\n' "${typ}" "${subject}" "${lineno}" "$(char_count "${text}")"
done <"${section_file}"
echo "分类计数：$(awk -F'\t' '{ c[$2]++ } END { for (t in c) printf " %s=%d", t, c[t]; printf " 合计=%d", NR }' "${section_file}")"

if [[ "${fail}" -ne 0 ]]; then
  exit 1
fi
echo "OK: ${version} 段无重复/近义主语、无能力拆分、无跨版本归类冲突、单条均 ≤${max_chars} 字。"
