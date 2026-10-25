#!/usr/bin/env python3
"""Render the repository landing page: fills {{RELEASES}} in index.tmpl.html from public GitHub releases."""
import html, json, subprocess, sys
out = subprocess.run(["gh","release","list","--repo","Valeneo/releases","--limit","100","--json","tagName,isPrerelease,publishedAt,name"],
                     capture_output=True,text=True,check=True).stdout
rows=[]
for r in json.loads(out):
    d = json.loads(subprocess.run(["gh","release","view",r["tagName"],"--repo","Valeneo/releases","--json","assets"],
                                  capture_output=True,text=True,check=True).stdout)
    links = "".join(f'<a href="{html.escape(a["url"])}">{html.escape(a["name"])}</a>' for a in d["assets"])
    tag = ' <span class="tag">beta</span>' if r["isPrerelease"] else ""
    rows.append(f'<tr><td>{html.escape(r["name"] or r["tagName"])}{tag}</td><td>{r["publishedAt"][:10]}</td><td>{links}</td></tr>')
body = ('<table><tr><th>Release</th><th>Date</th><th>Files</th></tr>'+"".join(rows)+'</table>') if rows else \
       '<p>Nothing published yet. Packages will appear here as they ship.</p>'
tmpl = open(sys.argv[1]).read()
open(sys.argv[2],"w").write(tmpl.replace("{{RELEASES}}", body))
