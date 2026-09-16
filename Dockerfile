# Lazy Balancer V2 官网静态站——Alpine Nginx 极简部署
# 整站为纯静态(index.html + assets/),无构建步骤,直接 COPY 进镜像
FROM nginx:alpine

# 静态资源:官网单页 + 截图素材
COPY index.html /usr/share/nginx/html/
COPY assets/ /usr/share/nginx/html/assets/

# 站点配置:webp 长缓存 + 安全头 + gzip
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1/ >/dev/null 2>&1 || exit 1
