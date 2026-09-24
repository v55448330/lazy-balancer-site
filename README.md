# Lazy Balancer V2 — 产品介绍静态站

Lazy Balancer V2 的产品介绍落地页(纯静态,零依赖)。

**仓库**:https://git.xiaobao.cool/zhang/lazy-balancer-site(官网唯一仓库,更新都提交到这里)

## 使用

直接打开 `index.html` 即可,无需构建、无外部依赖(字体/脚本/样式全部内联):

```bash
open index.html            # macOS
python3 -m http.server     # 或任意静态服务器
```

## 内容结构

- Hero + 终端 mockup(host 网络一行启动)
- 关键指标(128 MCP 工具 / WAF 四态 / Coraza v3 / 双架构)
- 六大特性(流量分发 / WAF / ACME / 集群 / 可观测 / API+MCP)
- WAF 四态(关闭/仅自定义/检测/拦截)+ 防护手段条(黑白名单/信任名单/限流/GeoIP/自定义规则)
- 企业级能力 ×6(WAF 防火墙/多用户/MFA/审计/多节点集群/自定义品牌)
- 架构三图(管理通道↔数据通道分层 / 集群主从同步 / 请求之旅)
- 快速开始(host 网络 + restart 策略)
- 产品实拍轮播(12 张,点击放大灯箱)
- 用户手册 `docs.html`(九章节:快速上手/负载均衡/安全防护/规则库/免费证书/集群管理/系统设置/API 与自动化/运维手册)
- 技术栈 + CTA

## 截图规范(敏感信息)

实拍截图来自真实部署,截取前必须 DOM 级脱敏:

- 域名 → `app.example.com` / `api.example.com`
- 内网 IP → `10.0.0.x` / `172.16.0.x`
- 私有品牌名 → `Lazy Balancer`
- 邮箱 → `admin@example.com`
- 节点名 → `lb-node-01/02`

侧边栏「安全防护」「系统设置」二级菜单需展开后截取(展示完整功能树)。

## 素材

`assets/` 下 16 张 webp 截图:仪表盘/负载均衡/安全总览/安全策略/规则集/事件日志/集群管理/免费证书/操作日志/登录页/规则库卡片/处理流程(12 张落地页)+ 规则库卡片(健康标签)/威胁库更新弹框/IP 列表编辑/受信代理(4 张手册页 `shot-doc-*`)。

## 发布

**GitHub Pages** 唯一通道:`github` 远端(`v55448330/lazy-balancer-site`)master 分支根目录托管,推送即自动发布——无需 Docker 镜像/容器(已于 2026-09-17 裁撤)。线上:**www.lazybalancer.org**(CNAME 在仓库根)。

每次修改:`git push origin master && git push github master`(双远端)。
