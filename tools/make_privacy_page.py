"""Bee Bee — the privacy policy as a page of the site.

  python tools/make_privacy_page.py [output.html]

Turns store/privacy_policy.md (Portuguese first, English after) into
site/privacidade.html, in the site's own look, so the policy has the public
address Google Play asks for: https://beebee.cyberhat.com.br/privacidade.html

The note to the developer at the top of the .md (the block that starts with
">") is left out. The two fields in square brackets have to be filled in
before the page goes online; the script says so if they are still there.
"""
import html
import re
import sys

SRC = "store/privacy_policy.md"
OUT = sys.argv[1] if len(sys.argv) > 1 else "site/privacidade.html"

text = open(SRC, encoding="utf-8").read().replace("\r\n", "\n")


def inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"\*(.+?)\*", r"<em>\1</em>", s)
    s = re.sub(r"(https?://[^\s<)]+[^\s<).,;])", r'<a href="\1">\1</a>', s)
    return s


def render(md):
    out = []
    for block in re.split(r"\n\s*\n", md.strip()):
        lines = block.split("\n")
        if lines[0].startswith(">"):
            continue                                   # the note to the developer
        if lines[0].startswith("# "):
            out.append("<h1>%s</h1>" % inline(lines[0][2:]))
        elif lines[0].startswith("## "):
            out.append("<h2>%s</h2>" % inline(lines[0][3:]))
        elif lines[0].startswith("- "):
            items, cur = [], ""
            for ln in lines:
                if ln.startswith("- "):
                    if cur:
                        items.append(cur)
                    cur = ln[2:]
                else:
                    cur += " " + ln.strip()
            items.append(cur)
            out.append("<ul>%s</ul>" % "".join("<li>%s</li>" % inline(i) for i in items))
        else:
            out.append("<p>%s</p>" % inline(" ".join(ln.strip() for ln in lines)))
    return "\n".join(out)


pt, en = text.split("\n---\n", 1)
page = """<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Bee Bee — Política de Privacidade / Privacy Policy</title>
<meta name="robots" content="index, follow">
<link rel="icon" href="assets/favicon.png">
<style>
@font-face { font-family: "Jersey 10"; src: url("assets/Jersey10-Regular.ttf") format("truetype"); font-display: swap; }
* { box-sizing: border-box; }
body { margin: 0; font-family: system-ui, -apple-system, "Segoe UI", Roboto, Arial, sans-serif; font-size: 17px; line-height: 1.6; color: #2b1840; background: #fff8e6; }
header { background: linear-gradient(180deg, #1f6fd0, #54b3ed); padding: 26px 20px 30px; text-align: center; }
header img { width: min(300px, 70%%); height: auto; }
header p { margin: 14px 0 0; }
header a { color: #fff; font-weight: 700; }
main { width: min(760px, 100%% - 40px); margin: 0 auto; padding: 24px 0 60px; }
h1 { font-family: "Jersey 10", system-ui, sans-serif; font-weight: 400; font-size: 44px; line-height: 1; margin: 34px 0 6px; color: #3d2152; }
h2 { font-size: 20px; margin: 30px 0 6px; color: #3d2152; }
a { color: #1f5fc0; }
hr { border: 0; border-top: 4px solid #3d2152; margin: 56px 0 10px; }
ul { padding-left: 22px; }
li { margin: 6px 0; }
</style>
</head>
<body>
<header>
  <a href="./"><img src="assets/logo.png" alt="Bee Bee"></a>
  <p><a href="./">&larr; Voltar ao jogo</a> &nbsp;·&nbsp; <a href="#english">English</a></p>
</header>
<main>
%s
<hr id="english">
%s
</main>
</body>
</html>
""" % (render(pt), render(en))

open(OUT, "w", encoding="utf-8", newline="\n").write(page)
left = sorted(set(re.findall(r"\[[A-ZÀ-Ú\- ]{6,}\]", text)))
print("wrote", OUT)
if left:
    print("NOT READY TO PUBLISH: fill in", ", ".join(left), "in", SRC)
