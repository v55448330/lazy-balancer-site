# Lazy Balancer V2 官网 · 维护与发布流程(固化)

官网唯一仓库:**https://git.xiaobao.cool/zhang/lazy-balancer-site**
官网镜像:**registry.xiaobao.cool:443/zhang/lazy-balancer-site:<tag>**(仅 linux/amd64)

---

## 一、维护范围(Scope)

本仓库只负责 **Lazy Balancer V2 产品介绍官网(纯静态站)**:

- `index.html` — 单文件整站(样式/脚本全内联,**零外部依赖**——禁止引入 CDN 字体/库/分析脚本)
- `assets/` — 产品截图(webp)
- `Dockerfile` + `nginx.conf` + `.dockerignore` — Alpine Nginx 部署
- `README.md` / `DEPLOY.md` — 文档

**不范围**:产品代码(bug 修主仓库)、产品文档 `docs/`(主仓库)、多语言版本(暂无)。

---

## 二、修改流程(每次改动必须走完)

```
编辑 → 浏览器逐屏实证(桌面 1568px + 移动 390px) → 脱敏检查 → 提交推送 → (需要时)发版镜像
```

1. **浏览器实证是硬性门禁**——任何视觉/布局改动必须打开页面逐屏截图核对:
   - 改动涉及的每个区块都要看;SVG 图逐条连线/逐个文字检查
   - 移动端至少抽验一次(响应式断点 960/620)
2. **提交**:master 直推,commit 写清改了什么/为什么。
3. **发版镜像**(内容定稿后):
   ```bash
   docker build --platform linux/amd64 \
     -t registry.xiaobao.cool:443/zhang/lazy-balancer-site:<tag> \
     -t registry.xiaobao.cool:443/zhang/lazy-balancer-site:latest .
   docker push registry.xiaobao.cool:443/zhang/lazy-balancer-site:<tag>
   docker push registry.xiaobao.cool:443/zhang/lazy-balancer-site:latest
   ```
   - **仅 amd64**(用户裁定);arm64 宿主机跨平台构建即可
   - **tag 必须询问用户**,不得自行递增(与主产品同一底线)
   - 推送前 `docker login registry.xiaobao.cool:443`

---

## 三、截图规范(硬性)

截图来自真实本地部署(:8000),**截取前必须 DOM 级脱敏**:

| 类型 | 替换为 |
|---|---|
| 真实域名 | `app.example.com` / `api.example.com` |
| 内网 IP | `10.0.0.x` / `172.16.0.x` |
| 私有品牌名 | `Lazy Balancer` |
| 邮箱 | `admin@example.com` |
| 节点名 | `lb-node-01` / `lb-node-02` |

操作要点:
- 侧边栏「安全防护」「系统设置」二级菜单**必须展开**后截取(展示完整功能树)
- 脱敏用 TreeWalker 遍历文本节点替换(输入框 value 同步)
- 分辨率:**3200×2000**(Puppeteer `clip.scale: 2`;`deviceScaleFactor` 直接设置对本环境无效)
- 格式:webp quality 88

## 四、已踩过的坑(注意事项,勿再犯)

1. **SVG 渐变描边零高陷阱**:`stroke="url(#渐变)"` 用在零高度水平路径上,渐变按包围盒塌缩 → **整条线不可见**。连接线与箭头一律用实色/半透明实色。
2. **连线透明度错配**:同一逻辑通道的线条必须同档透明度(全不透明主线+50% 分支 = 主线刺眼像叠加)。
3. **箭头标记**:用**实心三角**(`fill`,M0 0 L8 4.5 L0 9 Z);空心折线标记(fill=none+描边)视觉上像双线叠加。
4. **CSS 特异性**:`.wrap` 类选择器会覆盖裸 `section` 元素选择器的 padding——区块间距必须写 `section.wrap`。改样式后必须实测间距,不能只看代码。
5. **正则会坑人**:跨块搬移 HTML 结构别用正则拼接,整段重写更安全(曾在 steps 块造成嵌套重复卡)。
6. **零外部依赖底线**:字体用系统栈;禁止外链 anything(隐私+离线可用+加载速度)。

## 五、版本记录

- **v1.0.0**(2026-09-17):首个正式镜像。整站含 Hero/特性/负载均衡/WAF 四态/企业六卡/架构三图/部署后三步/产品预览轮播(9 图 2x)/技术栈/CTA;Alpine Nginx 部署。
