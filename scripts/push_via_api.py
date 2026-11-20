"""通过 GitHub Git Data API 推送本地仓库（绕过 github.com:443 被墙的问题）。

用法：
    python push_via_api.py <owner/repo> [branch]

依赖：gh CLI 已登录（用于取 token），Python 标准库。
"""

from __future__ import annotations

import base64
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

API = "https://api.github.com"


def token() -> str:
    out = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit("gh auth token 失败，请先 gh auth login")
    return out.stdout.strip()


def call(method: str, path: str, tok: str, payload: dict | None = None) -> dict:
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        API + path,
        data=data,
        method=method,
        headers={
            "Authorization": f"token {tok}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "User-Agent": "color-match-push",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        print(f"  ! HTTP {exc.code} {method} {path}: {body[:200]}")
        raise


def main() -> None:
    repo = sys.argv[1] if len(sys.argv) > 1 else "z7ui/color-match"
    branch = sys.argv[2] if len(sys.argv) > 2 else "main"
    tok = token()

    root = Path(__file__).resolve().parent.parent
    files = subprocess.run(
        ["git", "ls-files"], cwd=root, capture_output=True, text=True
    ).stdout.splitlines()
    if not files:
        raise SystemExit("没有可提交的文件")

    # 空仓库不允许创建 blob：先用 Contents API 放一个占位文件，建出 main 分支
    try:
        call("GET", f"/repos/{repo}/git/ref/heads/{branch}", tok)
        print("分支已存在，直接覆盖")
    except Exception:
        print("空仓库，先创建初始 commit")
        call(
            "PUT",
            f"/repos/{repo}/contents/.gitkeep",
            tok,
            {
                "message": "chore: init",
                "content": base64.b64encode(b"init\n").decode(),
                "branch": branch,
            },
        )

    tree_items = []
    for i, rel in enumerate(files, 1):
        path = root / rel
        content = path.read_bytes()
        blob = call(
            "POST",
            f"/repos/{repo}/git/blobs",
            tok,
            {"content": base64.b64encode(content).decode(), "encoding": "base64"},
        )
        tree_items.append(
            {"path": rel, "mode": "100644", "type": "blob", "sha": blob["sha"]}
        )
        print(f"[{i}/{len(files)}] {rel}")

    tree = call("POST", f"/repos/{repo}/git/trees", tok, {"tree": tree_items})

    # 取当前分支的 HEAD 作为 parent（仓库初始化时可能已经有 README）
    parent_sha: str | None = None
    try:
        ref = call("GET", f"/repos/{repo}/git/ref/heads/{branch}", tok)
        parent_sha = ref["object"]["sha"]
    except Exception:
        parent_sha = None

    commit_payload: dict = {
        "message": "feat: 选色助手 MVP —— 拍照/标定/两两与多对一对比/导出",
        "tree": tree["sha"],
    }
    if parent_sha:
        commit_payload["parents"] = [parent_sha]
    else:
        commit_payload["parents"] = []

    commit = call("POST", f"/repos/{repo}/git/commits", tok, commit_payload)

    info = call("GET", f"/repos/{repo}", tok)
    default_branch = info.get("default_branch", "main")

    if parent_sha:
        call(
            "PATCH",
            f"/repos/{repo}/git/refs/heads/{branch}",
            tok,
            {"sha": commit["sha"], "force": True},
        )
    else:
        call(
            "POST",
            f"/repos/{repo}/git/refs",
            tok,
            {"ref": f"refs/heads/{branch}", "sha": commit["sha"]},
        )

    if default_branch != branch:
        call("PATCH", f"/repos/{repo}", tok, {"default_branch": branch})

    print(f"完成：https://github.com/{repo}/commit/{commit['sha']}")


if __name__ == "__main__":
    main()
