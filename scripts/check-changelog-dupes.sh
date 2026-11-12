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
doc="${CHANGELOG_DOC:-}"
if [[ -z "$doc" ]]; then
  # 更新日志唯一事实源=versions.json（docs.html 前端渲染源）；门禁消费其合成 HTML。
  if [[ -f versions.json ]]; then
    doc="$(mktemp "${TMPDIR:-/tmp}/changelog-doc.XXXXXX")"
    python3 scripts/versions_to_doc.py versions.json > "$doc"
    trap 'rm -f "$doc"' EXIT
  else
    doc="docs.html"
  fi
fi
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

# —— 统一条目格式（用户裁定：更新日志必须有统一标准与格式，并写清在哪个页面）——
# 模板：<类型>：<页面>·<能力名>——<一句话行为描述>
#   类型 = 新增/优化/修复/加固/安全/其他；页面 = 面板真实导航名（下方白名单），
#   不得漏写、不得写「那个卡片」之类模糊位置；能力名 = 名词短语 ≤16 字（非整句）；
#   分隔符固定「·」与「——」；描述一句话，子能力用「；」并入，不另立条目。
# 判定字节安全：白名单 grep -Fx 全行匹配、分隔符 bash 模式匹配、字数 char_count。
# 白名单与 awk 的 full 字段同口径（已去空白），故一律不含空格。
# 只约束被测版本段：历史段按当时口径保留，不回改、不参与格式判定。
entry_pages() {
  cat <<'EOF'
仪表盘
负载均衡
安全总览
安全策略
拦截页面
规则集
事件日志
配置预览
系统设置
用户认证
API密钥
集群管理
免费证书
任务监控
操作日志
威胁大屏
全局
EOF
}

# 字符数（与 locale 无关）：去掉 UTF-8 续接字节后的字节数即字符数。
# 定义在自测入口之前——自测夹具按同一口径构造长度边界。
char_count() {
  printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | LC_ALL=C wc -c | tr -d ' '
}

max_subject_chars=16
# 违规原因（空串=合规）：逐条给因，便于按行修正；不做多字节相等判定。
entry_format_reason() {
  local body="$1" page subject desc
  case "${body}" in
    *"·"*"——"*) ;;
    *) printf '缺少统一分隔符（应为 <页面>·<能力名>——<描述>）\n'; return 0 ;;
  esac
  page="${body%%·*}"
  subject="${body#*·}"; subject="${subject%%——*}"
  desc="${body#*——}"
  if [[ -z "${page}" || -z "${subject}" ]]; then
    printf '页面或能力名为空\n'; return 0
  fi
  if [[ -z "${desc}" ]]; then
    printf '缺少行为描述（「——」后不能为空）\n'; return 0
  fi
  if ! entry_pages | LC_ALL=C grep -Fxq -- "${page}"; then
    printf '页面「%s」不在面板导航白名单内\n' "${page}"; return 0
  fi
  if [[ "$(char_count "${subject}")" -gt "${max_subject_chars}" ]]; then
    printf '能力名 %s 字超上限 %s（应为名词短语，非整句）\n' "$(char_count "${subject}")" "${max_subject_chars}"; return 0
  fi
  return 0
}

# —— 统一主题格式（2026-11-13 用户裁定：主题同样要有标准）——
# 模板：<能力名1>、<能力名2>、<能力名3>。
#   ≤45 字、≤4 项、分隔符统一「、」、句号结尾、不带类型前缀、禁括号解释；
#   每个能力名必须与该版本条目同源（双向子串命中），主题不得吹条目没有的能力；
#   首屏徽标摘要（若该版本有徽标行）必须等于主题去尾句号——消除两份手工文案。
max_theme_chars=45
max_theme_items=4

# 主题违规原因（空串=合规）。subjects_file=该版本条目主语清单（每行一个）。
theme_reason() {
  local theme="$1" subjects_file="$2" item found
  local -a items
  if [[ -z "${theme}" ]]; then
    printf '主题为空\n'; return 0
  fi
  if [[ "$(char_count "${theme}")" -gt "${max_theme_chars}" ]]; then
    printf '主题 %s 字超上限 %s\n' "$(char_count "${theme}")" "${max_theme_chars}"; return 0
  fi
  case "${theme}" in
    *。) ;;
    *) printf '主题须以句号结尾\n'; return 0 ;;
  esac
  # 只拦「新增/优化/修复/加固」开头：安全/其他 也可能是能力名首词（安全总览…）。
  case "${theme}" in
    新增*|优化*|修复*|加固*) printf '主题不得带类型前缀（类型属条目层）\n'; return 0 ;;
  esac
  case "${theme}" in
    *"（"*|*"）"*|*"("*|*")"*) printf '主题不得含括号解释（细节留给条目与文档站）\n'; return 0 ;;
  esac
  case "${theme}" in
    *"·"*|*"，"*|*"——"*|*"："*|*":"*) printf '主题分隔符须统一为「、」\n'; return 0 ;;
  esac
  IFS='、' read -r -a items <<<"${theme%。}"
  if [[ "${#items[@]}" -gt "${max_theme_items}" ]]; then
    printf '主题 %s 项超上限 %s（合并同类）\n' "${#items[@]}" "${max_theme_items}"; return 0
  fi
  for item in "${items[@]}"; do
    if [[ -z "${item}" ]]; then
      printf '主题存在空项（检查「、」）\n'; return 0
    fi
    found=0
    while IFS= read -r subject; do
      [[ -n "${subject}" ]] || continue
      if [[ "${subject}" == *"${item}"* || "${item}" == *"${subject}"* ]]; then
        found=1; break
      fi
    done <"${subjects_file}"
    if [[ "${found}" -eq 0 ]]; then
      printf '主题能力名「%s」在本版本条目中无对应（主题不得超出条目）\n' "${item}"; return 0
    fi
  done
  return 0
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
    local name="$1" want_rc="$2" needle="$3" file="$4" ver="${5:-}" badge="${6:-}" got_rc
    set +e
    if [[ -n "${ver}" ]]; then
      out="$(CHANGELOG_DOC="${file}" BADGE_DOC="${badge:-/dev/null}" bash "${self_path}" "${ver}" 2>&1)"
    else
      out="$(CHANGELOG_DOC="${file}" BADGE_DOC="${badge:-/dev/null}" bash "${self_path}" 2>&1)"
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
<li>新增：威胁大屏·三栏版式——左中右三栏布局。</li>
<li>新增：威胁大屏·安全态势面板——态势汇总一览。</li>
<li>新增：威胁大屏·2D/3D 双视图——两种风格切换。</li>
<li>新增：威胁大屏·攻击光流——攻击来源连线。</li>
<li>新增：威胁大屏·流量采样频率——采样间隔可调。</li>
</ul>
<p>主题：三栏版式、攻击光流。</p>
EOF
  run_case "split sub-views are rejected" 1 '能力「威胁大屏」被' "${work}/split-subviews.html"

  # B) 合并形态：子能力用分号并入父条目 → 必须绿（避免误伤正确文案）。
  cat >"${work}/merged-parent.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：威胁大屏·实时态势——三栏版式与 2D/3D 双视图；攻击光流；流量采样。</li>
</ul>
<p>主题：实时态势。</p>
EOF
  run_case "merged parent entry passes" 0 'OK: v9.9.9' "${work}/merged-parent.html"

  # C) 近义主语：尾部通用后缀不是新能力。
  cat >"${work}/synonym.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：仪表盘·缓存预热——提前加载热点数据。</li>
<li>优化：仪表盘·缓存预热能力——提前加载热点数据。</li>
</ul>
<p>主题：缓存预热。</p>
EOF
  run_case "near-synonym subject is rejected" 1 '近义主语' "${work}/synonym.html"

  # D) 字节完全相同的重复主语（既有契约，防回归）。
  cat >"${work}/exact-dupe.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>优化：集群管理·集群同步——主从配置同步。</li>
<li>修复：集群管理·集群同步——主从配置同步。</li>
</ul>
<p>主题：集群同步。</p>
EOF
  run_case "exact duplicate subject is rejected" 1 '重复主语' "${work}/exact-dupe.html"

  # E) 跨版本：「新增」不得是上一版已存在的能力。
  cat >"${work}/cross-version.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：规则集·规则导入——批量导入规则。</li>
</ul>
<p>主题：规则导入。</p>
<h3>v9.9.8</h3>
<ul>
<li>优化：规则集·规则导入——批量导入规则。</li>
</ul>
EOF
  run_case "cross-version add conflicts" 1 '已出现在 v9.9.8' "${work}/cross-version.html"

  # F) 单条长度上限（≥70 字必须拒绝）。
  cat >"${work}/too-long.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>优化：仪表盘·长条目——这一条日志写得太长了已经超过七十个字符的上限需要拆开说明具体细节才符合写作规范要求并且还要继续拉长以确保触发长度门禁同时保留足够多的解释性从句来测试边界行为。</li>
</ul>
<p>主题：长条目。</p>
EOF
  run_case "over-length entry is rejected" 1 '<70 字' "${work}/too-long.html"

  # G) 精确长度边界：类型前缀计入正文，69 字必须绿，70 字必须红。
  # run_case 同时断言退出码与门禁输出的实际字数，防止夹具长度或判定口径漂移。
  # 统一格式前缀（优化：+仪表盘+·+界+——）共 10 字，描述 59 字 → 合计 69 字。
  boundary_69="优化：仪表盘·界——$(printf '界%.0s' {1..59})"
  boundary_70="${boundary_69}界"
  printf '<h3>v9.9.9</h3>\n<ul>\n<li>%s</li>\n</ul>\n<p>主题：界。</p>\n' "${boundary_69}" >"${work}/exactly-69.html"
  printf '<h3>v9.9.9</h3>\n<ul>\n<li>%s</li>\n</ul>\n<p>主题：界。</p>\n' "${boundary_70}" >"${work}/exactly-70.html"
  run_case "69-character entry passes" 0 '第 3 行，69 字' "${work}/exactly-69.html"
  run_case "70-character entry is rejected" 1 '第 3 行，70 字' "${work}/exactly-70.html"

  # H) 前缀相同但不失败：提示必须出现，退出码仍为 0（人审定位，不误伤）。
  cat >"${work}/prefix-hint.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：免费证书·证书上传——手动上传证书文件。</li>
<li>新增：免费证书·证书上传失败回滚——失败回滚到上一份。</li>
</ul>
<p>主题：证书上传、证书上传失败回滚。</p>
EOF
  run_case "shared prefix only hints" 0 '前缀' "${work}/prefix-hint.html"

  # I) 干净段：条目清单必须打印（交付报告依赖该输出）。
  cat >"${work}/clean.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：仪表盘·连接监控面板——弹框查看连接。</li>
</ul>
<p>主题：连接监控面板。</p>
EOF
  run_case "clean section prints item list" 0 '条目清单' "${work}/clean.html"

  # J) 格式门：缺统一分隔符（旧写法「能力——描述」漏页面）必须红。
  cat >"${work}/fmt-no-sep.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：连接监控面板——弹框查看连接。</li>
</ul>
<p>主题：连接监控面板。</p>
EOF
  run_case "missing page separator is rejected" 1 '缺少统一分隔符' "${work}/fmt-no-sep.html"

  # K) 格式门：页面不在面板导航白名单（模糊位置/自造页面名）必须红。
  cat >"${work}/fmt-bad-page.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：那个卡片·连接监控面板——弹框查看连接。</li>
</ul>
<p>主题：连接监控面板。</p>
EOF
  run_case "unknown page is rejected" 1 '不在面板导航白名单内' "${work}/fmt-bad-page.html"

  # L) 格式门：能力名写成整句（>16 字）必须红——能力名是名词短语。
  cat >"${work}/fmt-sentence-subject.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：安全总览·自动封禁计数可选四类口径并且支持自定义组合——可选四类计数。</li>
</ul>
<p>主题：自动封禁计数。</p>
EOF
  run_case "sentence-as-capability is rejected" 1 '字超上限' "${work}/fmt-sentence-subject.html"

  # M) 格式门：「——」后无描述必须红（只有位置没有行为=无效条目）。
  cat >"${work}/fmt-no-desc.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：仪表盘·连接监控面板——</li>
</ul>
<p>主题：连接监控面板。</p>
EOF
  run_case "empty description is rejected" 1 '缺少行为描述' "${work}/fmt-no-desc.html"

  # N) 主题门：缺主题必须红（主题是版本段必备件）。
  cat >"${work}/theme-missing.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：仪表盘·连接监控面板——弹框查看连接。</li>
</ul>
EOF
  run_case "missing theme is rejected" 1 '缺少主题' "${work}/theme-missing.html"

  # O) 主题门：超 45 字必须红。
  cat >"${work}/theme-too-long.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：仪表盘·连接监控面板——弹框查看连接。</li>
</ul>
<p>主题：连接监控面板、实时挑战监控、自动封禁口径、触发筛选、人机验证方式、验证组件插入、CC 防护卡片。</p>
EOF
  run_case "over-length theme is rejected" 1 '段主题不符统一格式' "${work}/theme-too-long.html"

  # P) 主题门：带类型前缀必须红（类型属条目层）。
  cat >"${work}/theme-typed.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：仪表盘·连接监控面板——弹框查看连接。</li>
</ul>
<p>主题：新增连接监控面板。</p>
EOF
  run_case "typed theme is rejected" 1 '不得带类型前缀' "${work}/theme-typed.html"

  # Q) 主题门：括号解释必须红（细节留给条目与文档站）。
  cat >"${work}/theme-paren.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：仪表盘·连接监控面板——弹框查看连接。</li>
</ul>
<p>主题：连接监控面板（活跃/待关闭/已关闭）。</p>
EOF
  run_case "parenthesised theme is rejected" 1 '不得含括号解释' "${work}/theme-paren.html"

  # R) 主题门：分隔符混用（· 或 ，）必须红。
  cat >"${work}/theme-sep.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：仪表盘·连接监控面板——弹框查看连接。</li>
<li>新增：安全总览·实时挑战监控——查看进行中的会话。</li>
</ul>
<p>主题：连接监控面板 · 实时挑战监控。</p>
EOF
  run_case "mixed theme separator is rejected" 1 '分隔符须统一' "${work}/theme-sep.html"

  # S) 主题门：无句号结尾必须红。
  cat >"${work}/theme-no-dot.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：仪表盘·连接监控面板——弹框查看连接。</li>
</ul>
<p>主题：连接监控面板</p>
EOF
  run_case "theme without full stop is rejected" 1 '须以句号结尾' "${work}/theme-no-dot.html"

  # T) 主题门：主题能力名在条目中无对应必须红（主题不得超出条目）。
  cat >"${work}/theme-unmatched.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：仪表盘·连接监控面板——弹框查看连接。</li>
</ul>
<p>主题：连接监控面板、威胁大屏。</p>
EOF
  run_case "theme beyond entries is rejected" 1 '在本版本条目中无对应' "${work}/theme-unmatched.html"

  # U) 主题门：项数超 4 必须红（首屏可读，合并同类）。
  cat >"${work}/theme-too-many.html" <<'EOF'
<h3>v9.9.9</h3>
<ul>
<li>新增：仪表盘·甲能力——行为一。</li>
<li>新增：仪表盘·乙能力——行为二。</li>
<li>新增：仪表盘·丙能力——行为三。</li>
<li>新增：仪表盘·丁能力——行为四。</li>
<li>新增：仪表盘·戊能力——行为五。</li>
</ul>
<p>主题：甲能力、乙能力、丙能力、丁能力、戊能力。</p>
EOF
  run_case "too many theme items are rejected" 1 '项超上限' "${work}/theme-too-many.html"

  # V) 徽标同源：摘要与主题不一致必须红（两处不得各写一份文案）。
  cat >"${work}/badge-mismatch.html" <<'EOF'
<b>测试版 v9.9.9</b>（连接监控面板与别的能力）
EOF
  run_case "badge differing from theme is rejected" 1 '徽标摘要与主题不同源' "${work}/clean.html" "" "${work}/badge-mismatch.html"

  # W) 徽标同源：摘要=主题去尾句号必须绿。
  cat >"${work}/badge-match.html" <<'EOF'
<b>测试版 v9.9.9</b>（连接监控面板）
EOF
  run_case "badge matching theme passes" 0 'OK: v9.9.9' "${work}/clean.html" "" "${work}/badge-match.html"

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
    if (s !~ /^(新增|优化|修复|加固|安全|其他)[：:]/) next
    full = s
    gsub(/[ \t]+/, "", full)
    typ = s
    sub(/[：:].*$/, "", typ)
    sub(/^(新增|优化|修复|加固|安全|其他)[：:]/, "", s)
    # 统一格式的页面前缀（<页面>·）不参与主语去重/跨版本判定——页面由格式门
    # 单独校验；剥掉后主语=能力名，与历史段（无页面前缀）同口径可比。
    sub(/^[^·]*·/, "", s)
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

# —— 抽取各版本主题：version<TAB>line<TAB>theme（每段取第一条「主题：」）——
themes_file="${tmp_dir}/themes.tsv"
awk '
  { line = $0 }
  line ~ /^[ \t]*<h3>v[0-9]+\.[0-9]+\.[0-9]+/ {
    ver = line
    sub(/^[ \t]*<h3>/, "", ver)
    sub(/[（(].*$/, "", ver)
    sub(/<.*$/, "", ver)
    gsub(/[ \t]/, "", ver)
    cur = ver
    next
  }
  cur != "" && line ~ /主题：/ {
    s = line
    sub(/^.*主题：/, "", s)
    gsub(/<[^>]*>/, "", s)
    gsub(/^[ \t]+|[ \t]+$/, "", s)
    if (s != "") printf "%s\t%d\t%s\n", cur, NR, s
    cur = ""
  }
' "${doc}" >"${themes_file}" || { echo "ERROR: 解析主题失败" >&2; exit 1; }

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

# —— 统一条目格式：<类型>：<页面>·<能力名>——<描述>（用户裁定）——
# 页面必须在面板导航白名单内（写清在哪个页面），分隔符固定，能力名为名词短语。
# 与长度门同口径：只约束被测版本段，历史段按当时口径保留。
format_report=""
while IFS=$'\t' read -r _ver _typ _subject lineno text; do
  [[ -n "${text}" ]] || continue
  body="${text#*[:：]}"
  reason="$(entry_format_reason "${body}")"
  if [[ -n "${reason}" ]]; then
    format_report+="    第 ${lineno} 行：${reason}｜${text}"$'\n'
  fi
done <"${section_file}"
if [[ -n "${format_report}" ]]; then
  echo "ERROR: ${version} 段有条目不符统一格式 <类型>：<页面>·<能力名>——<一句话行为描述>（页面须为面板导航名，能力名 ≤${max_subject_chars} 字）：" >&2
  printf '%s' "${format_report}" >&2
  fail=1
fi

# —— 统一主题格式：<能力名1>、<能力名2>…。（2026-11-13 用户裁定）——
# 主题与条目同源：每个能力名必须能在本版本条目主语中找到（双向子串），
# 且首屏徽标摘要必须等于主题去尾句号——两处不得各写一份文案。
theme_line="$(awk -F'\t' -v v="${version}" '$1 == v { print $3; exit }' "${themes_file}")"
subjects_file="${tmp_dir}/subjects.txt"
cut -f3 "${section_file}" >"${subjects_file}"
if [[ -z "${theme_line}" ]]; then
  echo "ERROR: ${version} 段缺少主题（theme）——须为 <能力名1>、<能力名2>…。" >&2
  fail=1
else
  reason="$(theme_reason "${theme_line}" "${subjects_file}")"
  if [[ -n "${reason}" ]]; then
    echo "ERROR: ${version} 段主题不符统一格式 <能力名1>、<能力名2>…。（≤${max_theme_chars} 字、≤${max_theme_items} 项、能力名与本版本条目同源）：${reason}" >&2
    echo "    ${theme_line}" >&2
    fail=1
  fi
  badge_doc="${BADGE_DOC:-index.html}"
  if [[ -f "${badge_doc}" ]]; then
    badge="$(grep -o '<b>[^<]*</b>（[^）]*）' "${badge_doc}" | grep -F -- "${version}" | head -1 | sed -E 's/^.*（//; s/）$//')"
    if [[ -n "${badge}" && "${badge}" != "${theme_line%。}" ]]; then
      echo "ERROR: ${version} 首屏徽标摘要与主题不同源（徽标=主题去尾句号，不得各写一份）：" >&2
      echo "    徽标：${badge}" >&2
      echo "    主题：${theme_line%。}" >&2
      fail=1
    fi
  fi
fi

# —— 条目清单（交付报告直接贴这一段）——
if [[ -n "${hint_report}" ]]; then
  echo "提示（不失败，需人工确认）：${version} 段有主语互含前缀，请确认不是同一能力被拆成两条："
  printf '%s' "${hint_report}"
fi
echo "版本段：${version}（上一版：${prev_version:-无}）"
if [[ -n "${theme_line}" ]]; then
  echo "主题（上限 ${max_theme_chars} 字，实际 $(char_count "${theme_line}") 字）：${theme_line}"
fi
echo "条目清单（类型 | 页面 | 能力名 | 字数）："
while IFS=$'\t' read -r _ver typ subject lineno text; do
  [[ -n "${text}" ]] || continue
  body="${text#*[:：]}"
  case "${body}" in
    *"·"*) page="${body%%·*}" ;;
    *) page="—" ;;
  esac
  printf '  %s | %s | %s（第 %s 行，%s 字）\n' "${typ}" "${page}" "${subject}" "${lineno}" "$(char_count "${text}")"
done <"${section_file}"
echo "分类计数：$(awk -F'\t' '{ c[$2]++ } END { for (t in c) printf " %s=%d", t, c[t]; printf " 合计=%d", NR }' "${section_file}")"

if [[ "${fail}" -ne 0 ]]; then
  exit 1
fi
echo "OK: ${version} 段主题与条目格式统一（主题=能力名并列；条目=页面·能力名——描述）、无重复/近义主语、无能力拆分、无跨版本归类冲突、单条均 ≤${max_chars} 字。"
