# Lazy Balancer V2 — 产品介绍静态站

Lazy Balancer V2 的产品介绍落地页(纯静态,零依赖,单文件)。

## 使用

直接打开 `index.html` 即可,无需构建、无外部依赖(字体/脚本/样式全部内联):

```bash
open index.html            # macOS
python3 -m http.server     # 或任意静态服务器
```

## 内容结构

- Hero + 终端 mockup(一行 docker run 启动)
- 关键指标(127 MCP 工具 / WAF 四态 / Coraza v3 / 双架构)
- 六大特性(流量分发 / WAF / ACME / 集群 / 可观测 / API+MCP)
- WAF 四态防护(off / custom_only / detection / blocking)
- 架构 SVG(管理面 Go + 数据面 Caddy + 持久层 SQLite + 校验链)
- 三分钟快速开始 + 技术栈 + CTA
- 页脚(QQ 群 303410331 / GitHub / Docker Hub)

## 部署

任意静态托管均可(GitHub Pages / Nginx / OSS):整个站点仅 `index.html` 一个文件。
