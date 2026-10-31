#!/usr/bin/env python3
"""Publish a Markdown file to WordPress through the REST API.

Credentials come from the environment (never from argv, so they do not end up
in shell history):

    WP_URL=https://blog.example.com \
    WP_USER=admin \
    WP_APP_PASSWORD='xxxx xxxx xxxx xxxx' \
    python scripts/wp_publish.py docs/blog-post.md --status publish

Use --dry-run to write the generated HTML next to the source file without
touching the site.  Requires only the standard library.
"""

from __future__ import annotations

import argparse
import base64
import html
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


def inline(text: str) -> str:
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", text)
    text = re.sub(r"!\[([^\]]*)\]\(([^)]+)\)", r'<img src="\2" alt="\1" />', text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text


def markdown_to_html(source: str) -> str:
    lines = source.splitlines()
    out: list[str] = []
    i = 0
    in_code = False
    code_buffer: list[str] = []
    list_kind: str | None = None
    table_buffer: list[str] = []

    def close_list() -> None:
        nonlocal list_kind
        if list_kind:
            out.append(f"</{list_kind}>")
            list_kind = None

    def flush_table() -> None:
        if not table_buffer:
            return
        rows = [r.strip().strip("|") for r in table_buffer if r.strip()]
        table_buffer.clear()
        if len(rows) < 2:
            return
        header = [c.strip() for c in rows[0].split("|")]
        body = [[c.strip() for c in r.split("|")] for r in rows[2:]]
        out.append("<table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in header) + "</tr></thead><tbody>")
        for row in body:
            out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>")
        out.append("</tbody></table>")

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if stripped.startswith("```"):
            close_list()
            flush_table()
            if in_code:
                out.append("<pre><code>" + html.escape("\n".join(code_buffer)) + "</code></pre>")
                code_buffer.clear()
                in_code = False
            else:
                in_code = True
            i += 1
            continue

        if in_code:
            code_buffer.append(line)
            i += 1
            continue

        if not stripped:
            close_list()
            flush_table()
            i += 1
            continue

        if stripped.startswith("|") and stripped.endswith("|"):
            close_list()
            table_buffer.append(stripped)
            i += 1
            continue

        flush_table()

        heading = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if heading:
            close_list()
            level = len(heading.group(1))
            out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
            i += 1
            continue

        if re.match(r"^---+$", stripped):
            close_list()
            out.append("<hr />")
            i += 1
            continue

        if stripped.startswith(">"):
            close_list()
            out.append(f"<blockquote><p>{inline(stripped.lstrip('> ').strip())}</p></blockquote>")
            i += 1
            continue

        ordered = re.match(r"^\d+\.\s+(.*)$", stripped)
        unordered = re.match(r"^[-*]\s+(.*)$", stripped)
        if ordered or unordered:
            kind = "ol" if ordered else "ul"
            if list_kind != kind:
                close_list()
                out.append(f"<{kind}>")
                list_kind = kind
            out.append(f"<li>{inline((ordered or unordered).group(1))}</li>")
            i += 1
            continue

        close_list()
        out.append(f"<p>{inline(stripped)}</p>")
        i += 1

    close_list()
    flush_table()
    if in_code:
        out.append("<pre><code>" + html.escape("\n".join(code_buffer)) + "</code></pre>")
    return "\n".join(out)


def post_to_wordpress(base: str, user: str, app_password: str, payload: dict) -> dict:
    url = base.rstrip("/") + "/wp-json/wp/v2/posts"
    token = base64.b64encode(f"{user}:{app_password}".encode("utf-8")).decode("ascii")
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Basic {token}",
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json",
            "User-Agent": "tile-remnant-publisher/1.0",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")[:800]
        raise SystemExit(f"BLOCKED: WordPress 返回 {exc.code}: {body}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"BLOCKED: 无法连接 {base}: {exc.reason}") from exc


def main() -> int:
    parser = argparse.ArgumentParser(description="Publish Markdown to WordPress")
    parser.add_argument("file", type=Path)
    parser.add_argument("--status", default="draft", choices=("draft", "publish", "private"))
    parser.add_argument("--title", default=None)
    parser.add_argument("--slug", default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--url", default=os.getenv("WP_URL", ""))
    parser.add_argument("--user", default=os.getenv("WP_USER", ""))
    parser.add_argument("--app-password", default=os.getenv("WP_APP_PASSWORD", ""))
    args = parser.parse_args()

    if not args.file.exists():
        raise SystemExit(f"找不到文件: {args.file}")

    source = args.file.read_text(encoding="utf-8")
    title = args.title
    if title is None:
        for line in source.splitlines():
            if line.startswith("# "):
                title = line[2:].strip()
                break
    title = title or args.file.stem
    content = markdown_to_html(source)

    if args.dry_run:
        target = args.file.with_suffix(".html")
        target.write_text(content, encoding="utf-8")
        print(f"dry-run: HTML 已写入 {target} ({len(content)} 字节)")
        return 0

    missing = [name for name, value in (("WP_URL", args.url), ("WP_USER", args.user), ("WP_APP_PASSWORD", args.app_password)) if not value]
    if missing:
        print("BLOCKED: 缺少环境变量 " + ", ".join(missing), file=sys.stderr)
        print("文章本体已就绪，可直接复制粘贴到 WordPress 编辑器：", file=sys.stderr)
        print(f"  {args.file}", file=sys.stderr)
        return 2

    result = post_to_wordpress(
        args.url,
        args.user,
        args.app_password,
        {"title": title, "content": content, "status": args.status, "slug": args.slug},
    )
    print(f"published: id={result.get('id')} status={result.get('status')} link={result.get('link')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
