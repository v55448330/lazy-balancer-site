import re

p = 'docs.html'
s = open(p).read()
start = s.index('<h3>v2.4.0-beta（测试版）</h3>')
end = s.index('</section>', start)

JS_BLOCK = (
    '<div id="changelog-list"><p class="sec-sub">加载中…</p></div>\n'
    '  <noscript><p class="sec-sub">需启用 JavaScript 查看更新日志；也可直接查看 <a href="versions.json">versions.json</a>。</p></noscript>\n'
    '  <script>\n'
    '  (function(){\n'
    "    fetch('versions.json').then(function(r){return r.json()}).then(function(data){\n"
    "      var host=document.getElementById('changelog-list'); host.innerHTML='';\n"
    "      data.versions.forEach(function(v){\n"
    "        var h3=document.createElement('h3'); h3.textContent=v.version+'（'+v.channel_label+'）'; host.appendChild(h3);\n"
    "        if(v.theme){var p=document.createElement('p'); p.textContent='主题：'+v.theme; host.appendChild(p);}\n"
    "        var ul=document.createElement('ul');\n"
    "        (v.notes||[]).forEach(function(n){var li=document.createElement('li'); li.textContent=n; ul.appendChild(li);});\n"
    "        host.appendChild(ul);\n"
    "        (v.hints||[]).forEach(function(h){var p=document.createElement('p'); p.className='callout info'; p.textContent=h; host.appendChild(p);});\n"
    "      });\n"
    "    }).catch(function(){document.getElementById('changelog-list').innerHTML='<p class=\"sec-sub\">更新日志加载失败，请刷新重试。</p>';});\n"
    '  })();\n'
    '  </script>\n'
    '  '
)

s = s[:start] + JS_BLOCK + s[end:]
open(p, 'w').write(s)
print('ok, changelog-list refs:', s.count('changelog-list'))
