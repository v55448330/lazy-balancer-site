#!/bin/sh
# IndexNow 提交（Bing/360/搜狗/Yandex 共享协议）——官网发布后执行一次
KEY=$(cat "$(ls *.txt | grep -E '^[0-9a-f]{32}\.txt$' | head -1)")
URLS="https://www.lazybalancer.org/
https://www.lazybalancer.org/docs.html"
curl -sm 15 "https://api.indexnow.org/indexnow?url=https://www.lazybalancer.org/&key=${KEY}" >/dev/null 2>&1 && echo "ping ok" || echo "ping fail"
curl -sm 15 -X POST "https://api.indexnow.org/indexnow" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d "{\"host\":\"www.lazybalancer.org\",\"key\":\"${KEY}\",\"keyLocation\":\"https://www.lazybalancer.org/${KEY}.txt\",\"urlList\":[\"https://www.lazybalancer.org/\",\"https://www.lazybalancer.org/docs.html\"]}"
echo
