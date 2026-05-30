#!/usr/bin/env python3
"""Convert 10-killer-questions.md to self-contained HTML5."""

import re
import html as html_module
from pathlib import Path

MD_PATH = Path(__file__).resolve().parent.parent / "answers" / "10-killer-questions.md"
OUT_PATH = Path(__file__).resolve().parent.parent / "answers-html" / "10-killer-questions.html"


def slugify(text: str) -> str:
    text = text.lower().strip()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    return text.strip("-")


def parse_table(lines: list[str], start: int) -> tuple[str, int]:
    rows = []
    i = start
    while i < len(lines) and lines[i].strip().startswith("|"):
        row = [c.strip() for c in lines[i].strip().strip("|").split("|")]
        rows.append(row)
        i += 1
    if len(rows) < 2:
        return "", start
    header = rows[0]
    body_rows = rows[2:] if len(rows) > 1 and re.match(r"^[\s|:-]+$", "|".join(rows[1])) else rows[1:]
    if len(rows) > 1 and re.match(r"^[\s|:-]+$", "|".join(rows[1])):
        pass
    else:
        body_rows = rows[1:]

    out = ["<table>", "<thead><tr>"]
    for h in header:
        out.append(f"<th>{html_module.escape(h)}</th>")
    out.append("</tr></thead><tbody>")
    for row in body_rows:
        out.append("<tr>")
        for cell in row:
            cell_html = inline_format(html_module.escape(cell))
            out.append(f"<td>{cell_html}</td>")
        out.append("</tr>")
    out.append("</tbody></table>")
    return "\n".join(out), i


def inline_format(text: str) -> str:
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return text


def convert_md_to_body(md: str) -> tuple[str, list[dict]]:
    lines = md.split("\n")
    toc: list[dict] = []
    parts: list[str] = []
    i = 0
    in_code = False
    code_lang = ""
    code_buf: list[str] = []

    def flush_code():
        nonlocal code_buf, code_lang, in_code
        if not in_code:
            return
        content = "\n".join(code_buf)
        if code_lang == "mermaid":
            parts.append(f'<div class="mermaid">\n{content}\n</div>')
        else:
            esc = html_module.escape(content)
            parts.append(f"<pre><code>{esc}</code></pre>")
        code_buf = []
        code_lang = ""
        in_code = False

    while i < len(lines):
        line = lines[i]

        if line.strip().startswith("```"):
            if in_code:
                flush_code()
            else:
                in_code = True
                code_lang = line.strip()[3:].strip() or ""
            i += 1
            continue

        if in_code:
            code_buf.append(line)
            i += 1
            continue

        if line.strip() == "---":
            parts.append("<hr>")
            i += 1
            continue

        if line.startswith("|"):
            tbl, i = parse_table(lines, i)
            parts.append(tbl)
            continue

        m = re.match(r"^(#{1,6})\s+(.+)$", line)
        if m:
            level = len(m.group(1))
            title = m.group(2).strip()
            sid = slugify(title)
            # disambiguate duplicate slugs
            base = sid
            n = 1
            existing = {e["id"] for e in toc}
            while sid in existing:
                n += 1
                sid = f"{base}-{n}"
            tag = f"h{min(level, 6)}"
            parts.append(f'<{tag} id="{sid}">{inline_format(html_module.escape(title))}</{tag}>')
            if level <= 3:
                toc.append({"level": level, "id": sid, "title": title})
            i += 1
            continue

        if line.strip().startswith("- ") or line.strip().startswith("* "):
            items = []
            while i < len(lines) and (
                lines[i].strip().startswith("- ") or lines[i].strip().startswith("* ")
            ):
                item = lines[i].strip()[2:]
                items.append(f"<li>{inline_format(html_module.escape(item))}</li>")
                i += 1
            parts.append("<ul>" + "".join(items) + "</ul>")
            continue

        m = re.match(r"^(\d+)\.\s+(.+)$", line.strip())
        if m:
            items = []
            while i < len(lines):
                m2 = re.match(r"^(\d+)\.\s+(.+)$", lines[i].strip())
                if not m2:
                    break
                items.append(f"<li>{inline_format(html_module.escape(m2.group(2)))}</li>")
                i += 1
            parts.append("<ol>" + "".join(items) + "</ol>")
            continue

        if line.strip().startswith("**Interview sound bite:**"):
            rest = line.strip().replace("**Interview sound bite:**", "").strip()
            parts.append(
                f'<blockquote class="sound-bite"><p><strong>Interview sound bite:</strong> '
                f"{inline_format(html_module.escape(rest))}</p></blockquote>"
            )
            i += 1
            continue

        if line.strip().startswith("*") and line.strip().endswith("*") and not line.strip().startswith("**"):
            italic = line.strip().strip("*")
            parts.append(f'<p class="meta"><em>{html_module.escape(italic)}</em></p>')
            i += 1
            continue

        if line.strip():
            parts.append(f"<p>{inline_format(html_module.escape(line.strip()))}</p>")
        i += 1

    flush_code()
    return "\n".join(parts), toc


def build_toc_html(toc: list[dict]) -> str:
    chunks = ['<nav class="toc" aria-label="Table of contents">', "<h2>Contents</h2>", "<ol>"]
    current_section = None
    subsection_open = False
    for entry in toc:
        level = entry["level"]
        title = html_module.escape(entry["title"])
        eid = entry["id"]
        if level == 2:
            if subsection_open:
                chunks.append("</ol>")
                subsection_open = False
            if current_section is not None:
                chunks.append("</li>")
            chunks.append(f'<li><a href="#{eid}">{title}</a>')
            current_section = eid
        elif level == 3:
            if not subsection_open:
                chunks.append("<ol>")
                subsection_open = True
            chunks.append(f'<li class="toc-sub"><a href="#{eid}">{title}</a></li>')
    if subsection_open:
        chunks.append("</ol>")
    if current_section is not None:
        chunks.append("</li>")
    chunks.append("</ol></nav>")
    return "\n".join(chunks)


def main():
    md = MD_PATH.read_text(encoding="utf-8")
    body, toc = convert_md_to_body(md)
    toc_html = build_toc_html(toc)

    doc = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Killer Questions — Full System Design Answers</title>
  <style>
    :root {{
      --bg: #fafbfc;
      --surface: #ffffff;
      --text: #1a1f36;
      --muted: #5e6c84;
      --accent: #0052cc;
      --accent-soft: #deebff;
      --border: #dfe1e6;
      --code-bg: #f4f5f7;
      --blockquote: #6554c0;
      --shadow: 0 1px 3px rgba(9, 30, 66, 0.08);
    }}
    * {{ box-sizing: border-box; }}
    html {{ scroll-behavior: smooth; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, sans-serif;
      font-size: 16px;
      line-height: 1.65;
      color: var(--text);
      background: var(--bg);
      margin: 0;
      padding: 0;
    }}
    .page-header {{
      background: linear-gradient(135deg, #0747a6 0%, #0052cc 50%, #2684ff 100%);
      color: #fff;
      padding: 2.5rem 1.5rem 2rem;
      text-align: center;
    }}
    .page-header h1 {{
      margin: 0 0 0.5rem;
      font-size: clamp(1.5rem, 4vw, 2rem);
      font-weight: 700;
      letter-spacing: -0.02em;
    }}
    .page-header p {{
      margin: 0;
      opacity: 0.92;
      font-size: 1.05rem;
      max-width: 42rem;
      margin-inline: auto;
    }}
    .layout {{
      max-width: 52rem;
      margin: 0 auto;
      padding: 2rem 1.25rem 4rem;
    }}
    .toc {{
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 1.25rem 1.5rem;
      margin-bottom: 2.5rem;
      box-shadow: var(--shadow);
    }}
    .toc h2 {{
      margin: 0 0 0.75rem;
      font-size: 1.1rem;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }}
    .toc > ol {{
      margin: 0;
      padding-left: 1.25rem;
    }}
    .toc > ol > li {{
      margin: 0.35rem 0;
    }}
    .toc > ol > li > ol {{
      margin: 0.25rem 0 0.5rem;
      padding-left: 1.25rem;
      list-style: lower-alpha;
    }}
    .toc a {{
      color: var(--accent);
      text-decoration: none;
    }}
    .toc a:hover {{ text-decoration: underline; }}
    .toc-sub {{ font-size: 0.92rem; }}
    article {{
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 2rem 1.75rem;
      box-shadow: var(--shadow);
    }}
    article h1 {{ font-size: 1.75rem; margin-top: 0; }}
    article h2 {{
      font-size: 1.45rem;
      margin-top: 2.5rem;
      padding-top: 1.5rem;
      border-top: 1px solid var(--border);
      color: #172b4d;
    }}
    article h2:first-of-type {{ border-top: none; padding-top: 0; margin-top: 0; }}
    article h3 {{
      font-size: 1.15rem;
      margin-top: 1.75rem;
      color: #253858;
    }}
    article p {{ margin: 0.85rem 0; }}
    article ul, article ol {{
      margin: 0.75rem 0;
      padding-left: 1.5rem;
    }}
    article li {{ margin: 0.35rem 0; }}
    article hr {{
      border: none;
      border-top: 1px solid var(--border);
      margin: 2rem 0;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      margin: 1.25rem 0;
      font-size: 0.92rem;
    }}
    th, td {{
      border: 1px solid var(--border);
      padding: 0.6rem 0.75rem;
      text-align: left;
      vertical-align: top;
    }}
    th {{
      background: var(--accent-soft);
      font-weight: 600;
      color: #172b4d;
    }}
    tr:nth-child(even) td {{ background: #fafbfc; }}
    code {{
      font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
      font-size: 0.88em;
      background: var(--code-bg);
      padding: 0.15em 0.35em;
      border-radius: 3px;
    }}
    pre {{
      background: var(--code-bg);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 1rem;
      overflow-x: auto;
      font-size: 0.85rem;
    }}
    pre code {{ background: none; padding: 0; }}
    .mermaid {{
      margin: 1.5rem 0;
      padding: 1rem;
      background: #fafbfc;
      border: 1px solid var(--border);
      border-radius: 8px;
      overflow-x: auto;
    }}
    blockquote.sound-bite {{
      margin: 1.25rem 0;
      padding: 1rem 1.25rem;
      border-left: 4px solid var(--blockquote);
      background: #f3f0ff;
      border-radius: 0 6px 6px 0;
    }}
    blockquote.sound-bite p {{ margin: 0; }}
    p.meta {{
      margin-top: 2rem;
      font-size: 0.9rem;
      color: var(--muted);
      text-align: center;
    }}
    .page-footer {{
      max-width: 52rem;
      margin: 0 auto;
      padding: 1.5rem 1.25rem 3rem;
      text-align: center;
      font-size: 0.9rem;
      color: var(--muted);
    }}
    .page-footer a {{
      color: var(--accent);
      text-decoration: none;
    }}
    .page-footer a:hover {{ text-decoration: underline; }}
    @media (max-width: 640px) {{
      article {{ padding: 1.25rem 1rem; }}
      table {{ font-size: 0.82rem; }}
      th, td {{ padding: 0.45rem 0.5rem; }}
    }}
  </style>
</head>
<body>
  <header class="page-header">
    <h1>Killer Questions — Full System Design Answers</h1>
    <p>Deep mini design docs for the six hardest Claude-style AI chat frontend questions.</p>
  </header>
  <div class="layout">
    {toc_html}
    <article>
{body}
    </article>
  </div>
  <footer class="page-footer">
    <a href="index.html">← System Design Answers Index</a>
  </footer>
  <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
  <script>
    mermaid.initialize({{
      startOnLoad: true,
      theme: "neutral",
      securityLevel: "loose",
      flowchart: {{ useMaxWidth: true, htmlLabels: true }},
      sequence: {{ useMaxWidth: true }}
    }});
  </script>
</body>
</html>
"""
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(doc, encoding="utf-8")
    print(f"Wrote {OUT_PATH} ({len(doc)} bytes)")


if __name__ == "__main__":
    main()
