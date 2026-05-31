#!/usr/bin/env python3
"""Convert system-design topic answers/*.md to answers-html/*.html."""

from __future__ import annotations

import html as html_module
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PREP_ROOT = SCRIPT_DIR.parent.parent


def slugify(text: str) -> str:
    text = text.lower().strip()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    return text.strip("-")


def inline_format(text: str) -> str:
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return text


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
    out = ["<table>", "<thead><tr>"]
    for h in header:
        out.append(f"<th>{html_module.escape(h)}</th>")
    out.append("</tr></thead><tbody>")
    for row in body_rows:
        out.append("<tr>")
        for cell in row:
            out.append(f"<td>{inline_format(html_module.escape(cell))}</td>")
        out.append("</tr>")
    out.append("</tbody></table>")
    return "\n".join(out), i


def convert_md_to_html(md: str) -> tuple[str, list[dict]]:
    lines = md.split("\n")
    toc: list[dict] = []
    parts: list[str] = []
    i = 0
    in_code = False
    code_lang = ""
    code_buf: list[str] = []
    in_qa = False
    qa_id = ""

    def flush_code():
        nonlocal code_buf, code_lang, in_code
        if not in_code:
            return
        content = "\n".join(code_buf)
        if code_lang == "mermaid":
            parts.append(f'<div class="mermaid-wrap"><pre class="mermaid">{content}</pre></div>')
        else:
            esc = html_module.escape(content)
            parts.append(f"<pre><code>{esc}</code></pre>")
        code_buf = []
        code_lang = ""
        in_code = False

    def close_qa():
        nonlocal in_qa
        if in_qa:
            parts.append("</article>")
            in_qa = False

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
            base = sid
            n = 1
            existing = {e["id"] for e in toc}
            while sid in existing:
                n += 1
                sid = f"{base}-{n}"

            if level == 2:
                close_qa()
                tag = "h2"
                cls = ' class="section"'
                parts.append(f'<{tag}{cls} id="{sid}">{inline_format(html_module.escape(title))}</{tag}>')
                toc.append({"level": 2, "id": sid, "title": title, "short": title[:40]})
            elif level == 3:
                close_qa()
                in_qa = True
                qa_id = sid
                parts.append(f'<article class="qa" id="{sid}">')
                parts.append(
                    f'<h3 class="question">{inline_format(html_module.escape(title))}</h3>'
                )
                toc.append({"level": 3, "id": sid, "title": title, "short": title[:36]})
            else:
                tag = f"h{min(level, 6)}"
                parts.append(f'<{tag} id="{sid}">{inline_format(html_module.escape(title))}</{tag}>')
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

        if line.strip():
            parts.append(f"<p>{inline_format(html_module.escape(line.strip()))}</p>")
        i += 1

    flush_code()
    close_qa()
    return "\n".join(parts), toc


def build_nav_toc(toc: list[dict]) -> str:
    items = [e for e in toc if e["level"] == 3]
    if not items:
        return ""
    lis = "".join(
        f'<li><a href="#{html_module.escape(e["id"])}">{html_module.escape(e["short"])}</a></li>'
        for e in items
    )
    return f'<ol class="toc">{lis}</ol>'


PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{title} | System Design Answers</title>
  <meta name="description" content="{description}">
  <style>
    :root {{
      --bg: #f8f9fb; --surface: #ffffff; --text: #1a1d26; --text-muted: #5c6370;
      --border: #e2e6ed; --accent: #3d5a80; --accent-soft: #eef2f7;
      --code-bg: #f0f2f6; --pre-bg: #1e2433; --pre-text: #e8ecf4;
      --nav-bg: rgba(248, 249, 251, 0.92); --shadow: 0 1px 3px rgba(0, 0, 0, 0.06);
    }}
    @media (prefers-color-scheme: dark) {{
      :root {{
        --bg: #12151c; --surface: #1a1f2a; --text: #e8ecf4; --text-muted: #9aa3b2;
        --border: #2d3548; --accent: #8cb4d9; --accent-soft: #232a38;
        --code-bg: #252d3d; --pre-bg: #0d1017; --pre-text: #d4dae6;
        --nav-bg: rgba(18, 21, 28, 0.94); --shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
      }}
    }}
    *, *::before, *::after {{ box-sizing: border-box; }}
    html {{ scroll-behavior: smooth; scroll-padding-top: 5.5rem; }}
    body {{ margin: 0; font-family: "Segoe UI", system-ui, sans-serif; font-size: 1.0625rem;
      line-height: 1.65; color: var(--text); background: var(--bg); }}
    .site-nav {{ position: sticky; top: 0; z-index: 100; background: var(--nav-bg);
      backdrop-filter: blur(10px); border-bottom: 1px solid var(--border); box-shadow: var(--shadow); }}
    .site-nav-inner {{ max-width: 900px; margin: 0 auto; padding: 0.75rem 1.5rem; }}
    .site-nav-title {{ font-size: 0.8125rem; font-weight: 600; text-transform: uppercase;
      letter-spacing: 0.04em; color: var(--text-muted); margin: 0 0 0.5rem; }}
    .toc {{ display: flex; flex-wrap: wrap; gap: 0.35rem 0.75rem; margin: 0; padding: 0;
      list-style: none; font-size: 0.8125rem; }}
    .toc a {{ color: var(--accent); text-decoration: none; white-space: nowrap; }}
    .toc a:hover {{ text-decoration: underline; }}
    .page {{ max-width: 900px; margin: 0 auto; padding: 2rem 1.5rem 4rem; }}
    header.page-header {{ margin-bottom: 2.5rem; padding-bottom: 1.5rem; border-bottom: 1px solid var(--border); }}
    h1 {{ font-size: 1.75rem; font-weight: 700; margin: 0 0 0.75rem; }}
    .lead {{ margin: 0; color: var(--text-muted); font-size: 1.05rem; }}
    h2.section {{ font-size: 1.35rem; font-weight: 700; margin: 2.5rem 0 1.25rem;
      color: var(--accent); border-bottom: 2px solid var(--accent-soft); padding-bottom: 0.35rem; }}
    article.qa {{ margin-bottom: 2.75rem; background: var(--surface); border: 1px solid var(--border);
      border-radius: 10px; padding: 1.5rem 1.75rem; box-shadow: var(--shadow); }}
    h3.question {{ font-size: 1.2rem; font-weight: 600; margin: 0 0 1rem; }}
    article.qa p {{ margin: 0 0 1rem; }}
    ol, ul {{ margin: 0 0 1rem; padding-left: 1.35rem; }}
    table {{ width: 100%; border-collapse: collapse; margin: 0 0 1rem; font-size: 0.95rem; }}
    th, td {{ border: 1px solid var(--border); padding: 0.55rem 0.75rem; text-align: left; }}
    th {{ background: var(--accent-soft); font-weight: 600; }}
    code {{ font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 0.88em;
      background: var(--code-bg); padding: 0.15em 0.4em; border-radius: 4px; }}
    pre {{ margin: 0 0 1rem; padding: 1rem; background: var(--pre-bg); color: var(--pre-text);
      border-radius: 8px; overflow-x: auto; font-size: 0.875rem; }}
    pre code {{ background: none; padding: 0; color: inherit; }}
    .mermaid-wrap {{ margin: 0 0 1rem; padding: 1rem; background: var(--surface);
      border: 1px solid var(--border); border-radius: 8px; overflow-x: auto; }}
    footer.page-footer {{ max-width: 900px; margin: 0 auto; padding: 1.5rem;
      border-top: 1px solid var(--border); font-size: 0.9375rem; }}
    footer.page-footer a {{ color: var(--accent); text-decoration: none; font-weight: 500; }}
  </style>
  <link rel="stylesheet" href="assets/interactive.css">
</head>
<body>
  <nav class="site-nav" aria-label="Table of contents">
    <div class="site-nav-inner">
      <p class="site-nav-title">On this page</p>
      {nav_toc}
    </div>
  </nav>
  <main class="page">
    <header class="page-header">
      <h1>{page_title}</h1>
      <p class="lead">{lead}</p>
    </header>
    {body}
  </main>
  <footer class="page-footer">
    <a href="index.html">← All sections</a> ·
    <a href="../{topic}-frontend-architecture.html">Architecture map</a>
  </footer>
  <script src="assets/interactive.js" defer></script>
</body>
</html>
"""


def convert_file(md_path: Path, html_path: Path, topic: str) -> None:
    md = md_path.read_text(encoding="utf-8")
    body, toc = convert_md_to_html(md)
    nav_toc = build_nav_toc(toc)

    first_line = md.split("\n")[0].lstrip("# ").strip()
    page_title = first_line or md_path.stem
    lead = f"Interview-depth answers for {topic.title()} frontend system design."

    doc = PAGE_TEMPLATE.format(
        title=html_module.escape(page_title),
        description=html_module.escape(lead),
        nav_toc=nav_toc,
        page_title=html_module.escape(page_title),
        lead=html_module.escape(lead),
        body=body,
        topic=topic,
    )
    html_path.parent.mkdir(parents=True, exist_ok=True)
    html_path.write_text(doc, encoding="utf-8")
    print(f"Wrote {html_path} ({len(doc)} bytes)")


def main():
    topic = sys.argv[1] if len(sys.argv) > 1 else None
    if not topic:
        print("Usage: md_to_html.py <topic>", file=sys.stderr)
        sys.exit(1)

    topic_dir = PREP_ROOT / "system-design" / topic
    answers_dir = topic_dir / "answers"
    html_dir = topic_dir / "answers-html"

    if not answers_dir.is_dir():
        print(f"Missing {answers_dir}", file=sys.stderr)
        sys.exit(1)

    md_files = sorted(answers_dir.glob("[0-9]*.md"))
    if not md_files:
        print(f"No answer files in {answers_dir}", file=sys.stderr)
        sys.exit(1)

    for md_path in md_files:
        html_path = html_dir / (md_path.stem + ".html")
        convert_file(md_path, html_path, topic)

    print(f"Converted {len(md_files)} files for topic '{topic}'")


if __name__ == "__main__":
    main()
