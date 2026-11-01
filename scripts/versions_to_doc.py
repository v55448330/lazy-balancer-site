#!/usr/bin/env python3
"""versions.json → 合成更新日志 HTML（去重门禁的解析源）。
docs.html 更新日志已改为前端从 versions.json 渲染；门禁保持既有 HTML 解析逻辑，
运行前用本脚本把 JSON 转成同构 HTML。usage: versions_to_doc.py <versions.json>"""
import json, sys

data = json.load(open(sys.argv[1]))
out = []
for v in data["versions"]:
    out.append(f"<h3>{v['version']}（{v['channel_label']}）</h3>")
    if v.get("theme"):
        out.append(f"<p>主题：{v['theme']}</p>")
    out.append("<ul>")
    for n in v.get("notes", []):
        out.append(f"<li>{n}</li>")
    out.append("</ul>")
    for h in v.get("hints", []):
        out.append(f'<p class="callout info">{h}</p>')
print("\n".join(out))
