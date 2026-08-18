#!/usr/bin/env python3
"""Push local clone markdown into Docmost. Stdlib only. No secrets in this file.

Each repo is cloned twice: src/<repo>/main and src/<repo>/staging.
Wiki gets a Coverage page (staging-only / main-only / both) plus a copy of each file under those branch parents.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from http.cookiejar import CookieJar
from pathlib import Path, PurePosixPath

BANNER_PREFIX = "> Synced from"
BRANCHES = ("main", "staging")
COVERAGE_KEY = "coverage"
GLOBAL_SPACE = "esafx-coverage"


def glob_ok(rel: str) -> bool:
    posix = PurePosixPath(rel.replace("\\", "/"))
    parts = posix.parts
    if posix.name.upper() == "README.MD" and len(parts) == 1:
        return True
    if len(parts) >= 2 and parts[0] == "docs" and posix.suffix.lower() == ".md":
        return True
    return False


def load_docs(root: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not root.is_dir():
        return out
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if glob_ok(rel):
            out[rel] = path.read_text(encoding="utf-8")
    return out


def read_sha(root: Path) -> str:
    sha_file = root / "HEAD_SHA"
    if sha_file.exists():
        return sha_file.read_text(encoding="utf-8").strip() or "MISSING"
    return "MISSING"


def title_from_markdown(text: str, fallback: str) -> str:
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("# "):
            return stripped[2:].strip() or fallback
    return fallback


def with_banner(body: str, repo: str, rel: str, sha: str, branch: str) -> str:
    banner = (
        f"{BANNER_PREFIX} `Esa-FX/{repo}/{rel}` on **{branch}** "
        f"@ `{sha[:12]}`. Edit in git.\n\n"
    )
    rest = body.lstrip()
    if rest.startswith(BANNER_PREFIX):
        rest = rest.split("\n", 1)[-1].lstrip("\n")
    return banner + rest


def file_digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def classify(staging: dict[str, str], main: dict[str, str]) -> list[dict]:
    rows: list[dict] = []
    for path in sorted(set(staging) | set(main)):
        s, m = staging.get(path), main.get(path)
        if s is None:
            state = "main-only"
        elif m is None:
            state = "staging-only"
        elif file_digest(s) == file_digest(m):
            state = "both-same"
        else:
            state = "both-diff"
        rows.append({"path": path, "state": state})
    return rows


def coverage_markdown(repo: str, rows: list[dict], sha_main: str, sha_staging: str) -> str:
    counts = {"both-same": 0, "both-diff": 0, "staging-only": 0, "main-only": 0}
    for row in rows:
        counts[row["state"]] = counts.get(row["state"], 0) + 1
    both = counts["both-same"] + counts["both-diff"]
    where = {
        "both-same": "both (same)",
        "both-diff": "both (diff)",
        "staging-only": "staging only",
        "main-only": "main only",
    }
    lines = [
        f"# {repo} — staging vs main",
        "",
        f"- **main** `{sha_main[:12]}`",
        f"- **staging** `{sha_staging[:12]}`",
        f"- both: **{both}** ({counts['both-same']} same, {counts['both-diff']} differ)",
        f"- staging only: **{counts['staging-only']}**",
        f"- main only: **{counts['main-only']}**",
        "",
        "| Path | staging | main | Where |",
        "| --- | --- | --- | --- |",
    ]
    for row in rows:
        st = row["state"]
        in_st = "yes" if st != "main-only" else "—"
        in_mn = "yes" if st != "staging-only" else "—"
        lines.append(f"| `{row['path']}` | {in_st} | {in_mn} | {where[st]} |")
    if not rows:
        lines.append("| *(no docs/**/*.md or README.md)* | — | — | — |")
    lines.append("")
    if sha_main not in ("", "MISSING") and sha_staging not in ("", "MISSING"):
        lines.append(
            f"[GitHub compare staging...main](https://github.com/Esa-FX/{repo}/compare/{sha_main}...{sha_staging})"
        )
        lines.append("")
    return "\n".join(lines)


def global_coverage_markdown(summaries: list[dict]) -> str:
    lines = [
        "# Esa-FX — staging vs main",
        "",
        "Docs (`docs/**/*.md` + `README.md`) per repo. **both** = path exists on both branches.",
        "",
        "| Repo | both (same) | both (diff) | staging only | main only |",
        "| --- | --- | --- | --- | --- |",
    ]
    for s in summaries:
        lines.append(
            f"| `{s['repo']}` | {s['both-same']} | {s['both-diff']} | "
            f"{s['staging-only']} | {s['main-only']} |"
        )
    if not summaries:
        lines.append("| *(no repos)* | — | — | — | — |")
    lines.append("")
    return "\n".join(lines)


def _unwrap(payload: object) -> object:
    if isinstance(payload, dict) and "data" in payload:
        return payload["data"]
    return payload


class Docmost:
    def __init__(self, base_url: str, email: str, password: str) -> None:
        self.base = base_url.rstrip("/")
        self.jar = CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.jar)
        )
        self._login(email, password)

    def _login(self, email: str, password: str) -> None:
        self._json("POST", "/api/auth/login", {"email": email, "password": password})

    def _json(self, method: str, path: str, body: dict | None = None) -> object:
        data = None if body is None else json.dumps(body).encode("utf-8")
        req = urllib.request.Request(
            self.base + path,
            data=data,
            method=method,
            headers={"Content-Type": "application/json", "Accept": "application/json"},
        )
        try:
            with self.opener.open(req, timeout=60) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")
            raise RuntimeError(f"{method} {path} → {exc.code}: {detail[:500]}") from exc
        if not raw:
            return {}
        return json.loads(raw.decode("utf-8"))

    def list_spaces(self) -> list[dict]:
        # v0.95 SpaceController is POST /spaces/ not /spaces/list.
        payload = _unwrap(self._json("POST", "/api/spaces/", {"limit": 100}))
        if isinstance(payload, dict):
            items = payload.get("items") or payload.get("spaces") or []
            return list(items)
        if isinstance(payload, list):
            return payload
        return []

    def ensure_space(self, name: str, slug: str) -> str:
        for space in self.list_spaces():
            if space.get("slug") == slug or space.get("name") == name:
                return str(space["id"])
        created = _unwrap(
            self._json(
                "POST",
                "/api/spaces/create",
                {"name": name, "slug": slug, "description": f"Synced from Esa-FX/{name}"},
            )
        )
        if not isinstance(created, dict) or "id" not in created:
            raise RuntimeError(f"space create failed for {slug}: {created!r}")
        return str(created["id"])

    def create_page(
        self,
        space_id: str,
        title: str,
        parent_page_id: str | None = None,
        markdown: str | None = None,
    ) -> str:
        body: dict = {"title": title, "spaceId": space_id}
        if parent_page_id:
            body["parentPageId"] = parent_page_id
        if markdown:
            body["content"] = markdown
            body["format"] = "markdown"
        created = _unwrap(self._json("POST", "/api/pages/create", body))
        if not isinstance(created, dict) or "id" not in created:
            raise RuntimeError(f"create page {title!r} failed: {created!r}")
        return str(created["id"])

    def update_page(self, page_id: str, title: str, markdown: str) -> None:
        self._json(
            "POST",
            "/api/pages/update",
            {
                "pageId": page_id,
                "title": title,
                "content": markdown,
                "format": "markdown",
                "operation": "replace",
            },
        )


def load_repos_yml(path: Path) -> dict:
    data: dict = {"repos": [], "globs": [], "branches": []}
    current_list: str | None = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        if line.startswith("  - "):
            if current_list:
                data[current_list].append(line[4:].strip())
            continue
        if ":" in line and not line.startswith(" "):
            key, val = line.split(":", 1)
            key, val = key.strip(), val.strip()
            current_list = key if val == "" else None
            if current_list:
                data.setdefault(current_list, [])
            else:
                data[key] = val.strip("'\"")
    return data


def _page_meta(pages: dict, key: str) -> tuple[str | None, str | None]:
    raw = pages.get(key)
    if isinstance(raw, dict):
        return raw.get("id"), raw.get("digest")
    if isinstance(raw, str):
        return raw, None
    return None, None


def upsert_markdown(
    client: Docmost | None,
    dry_run: bool,
    space_id: str,
    pages: dict,
    key: str,
    title: str,
    markdown: str,
    filename: str,
    parent_id: str | None,
    log_label: str,
) -> None:
    digest = file_digest(markdown)
    page_id, prev = _page_meta(pages, key)
    if page_id and prev == digest:
        return
    print(f"{'dry-run' if dry_run else 'sync'} {log_label}")
    if dry_run or client is None:
        return
    if page_id:
        client.update_page(str(page_id), title, markdown)
    else:
        page_id = client.create_page(space_id, title, parent_id, markdown)
    pages[key] = {"id": page_id, "digest": digest}


def ensure_parent(
    client: Docmost | None,
    dry_run: bool,
    space_id: str,
    parents: dict,
    title: str,
) -> str | None:
    existing = parents.get(title)
    if existing:
        return str(existing)
    print(f"{'dry-run' if dry_run else 'sync'} parent {title}")
    if dry_run or client is None:
        return None
    page_id = client.create_page(space_id, title)
    parents[title] = page_id
    return page_id


def sync_repo(
    client: Docmost | None,
    repo: str,
    src_root: Path,
    state: dict,
    dry_run: bool,
) -> dict:
    repo_dir = src_root / repo
    docs = {b: load_docs(repo_dir / b) for b in BRANCHES}
    shas = {b: read_sha(repo_dir / b) for b in BRANCHES}
    repo_state = state.setdefault("repos", {}).setdefault(
        repo,
        {"sha_main": "", "sha_staging": "", "space_id": "", "pages": {}, "parents": {}},
    )
    rows = classify(docs["staging"], docs["main"])
    counts = {"both-same": 0, "both-diff": 0, "staging-only": 0, "main-only": 0}
    for row in rows:
        counts[row["state"]] += 1
    summary = {"repo": repo, **counts}

    unchanged = (
        repo_state.get("sha_main") == shas["main"]
        and repo_state.get("sha_staging") == shas["staging"]
        and shas["main"] != "unknown"
    )
    if unchanged and repo_state.get("pages"):
        print(f"skip {repo}: main={shas['main'][:12]} staging={shas['staging'][:12]} unchanged")
        return summary

    slug = repo.lower().replace("_", "-")[:50]
    space_id = repo_state.get("space_id") or ""
    if not dry_run:
        if client is None:
            raise RuntimeError("Docmost client required unless --dry-run")
        space_id = client.ensure_space(repo, slug)
        repo_state["space_id"] = space_id
    pages: dict = repo_state.setdefault("pages", {})
    parents: dict = repo_state.setdefault("parents", {})

    coverage = coverage_markdown(repo, rows, shas["main"], shas["staging"])
    upsert_markdown(
        client,
        dry_run,
        space_id,
        pages,
        COVERAGE_KEY,
        f"{repo} — staging vs main",
        coverage,
        "coverage.md",
        None,
        f"{repo}/coverage",
    )

    for branch in BRANCHES:
        parent_id = ensure_parent(client, dry_run, space_id, parents, branch)
        sha = shas[branch]
        for rel, body in docs[branch].items():
            title = title_from_markdown(body, Path(rel).stem)
            markdown = with_banner(body, repo, rel, sha, branch)
            fname = f"{branch}-{Path(rel).name}"
            upsert_markdown(
                client,
                dry_run,
                space_id,
                pages,
                f"{branch}:{rel}",
                f"[{branch}] {title}",
                markdown,
                fname,
                parent_id,
                f"{repo}/{branch}/{rel}",
            )

    repo_state["sha_main"] = shas["main"]
    repo_state["sha_staging"] = shas["staging"]
    return summary


def self_check() -> int:
    assert glob_ok("README.md")
    assert glob_ok("docs/lead-intake.md")
    assert not glob_ok("src/main.py")
    titled = title_from_markdown("# Hello\nbody", "x")
    assert titled == "Hello"
    banner = with_banner("# Hello\nbody", "crm-service", "docs/a.md", "abcdef1234567890", "staging")
    assert BANNER_PREFIX in banner and "staging" in banner
    twice = with_banner(banner, "crm-service", "docs/a.md", "ffffffffffffffff", "main")
    assert twice.count(BANNER_PREFIX) == 1
    rows = classify(
        {"docs/a.md": "x", "docs/b.md": "y"},
        {"docs/a.md": "x", "docs/c.md": "z"},
    )
    states = {r["path"]: r["state"] for r in rows}
    assert states["docs/a.md"] == "both-same"
    assert states["docs/b.md"] == "staging-only"
    assert states["docs/c.md"] == "main-only"
    assert classify({"a.md": "1"}, {"a.md": "2"})[0]["state"] == "both-diff"
    md = coverage_markdown("crm-service", rows, "aaa", "bbb")
    assert "staging only" in md and "main only" in md and "both (same)" in md
    gmd = global_coverage_markdown(
        [{"repo": "crm-service", "both-same": 1, "both-diff": 0, "staging-only": 1, "main-only": 1}]
    )
    assert "crm-service" in gmd
    cfg = load_repos_yml(Path(__file__).resolve().parents[1] / "repos.yml")
    assert "crm-service" in cfg.get("repos", [])
    assert "main" in cfg.get("branches", []) and "staging" in cfg.get("branches", [])
    print("self-check ok")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-check", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--config", default=str(Path(__file__).resolve().parents[1] / "repos.yml"))
    parser.add_argument("--src-root", default="/var/lib/docmost-src")
    parser.add_argument("--state", default="/var/lib/docmost-sync/state.json")
    args = parser.parse_args()
    if args.self_check:
        return self_check()

    cfg = load_repos_yml(Path(args.config))
    src_root = Path(args.src_root)
    state_path = Path(args.state)
    state: dict = {"repos": {}}
    if state_path.exists():
        state = json.loads(state_path.read_text(encoding="utf-8"))

    url = os.environ.get("DOCMOST_URL", "").rstrip("/")
    email = os.environ.get("DOCMOST_EMAIL", "")
    password = os.environ.get("DOCMOST_PASSWORD", "")
    if not args.dry_run and not (url and email and password):
        print("DOCMOST_URL / DOCMOST_EMAIL / DOCMOST_PASSWORD required", file=sys.stderr)
        return 2
    client = None if args.dry_run else Docmost(url, email, password)

    summaries: list[dict] = []
    for repo in cfg.get("repos", []):
        if not (src_root / repo).is_dir():
            print(f"skip {repo}: clone missing at {src_root / repo}")
            continue
        try:
            summaries.append(sync_repo(client, repo, src_root, state, args.dry_run))
        except Exception as exc:  # noqa: BLE001 — one repo must not abort the rest
            print(f"FAIL {repo}: {exc}", file=sys.stderr)

    global_md = global_coverage_markdown(summaries)
    gstate = state.setdefault("global", {"space_id": "", "pages": {}})
    if not args.dry_run and client is not None:
        gstate["space_id"] = client.ensure_space("Esa-FX coverage", GLOBAL_SPACE)
        upsert_markdown(
            client,
            False,
            gstate["space_id"],
            gstate.setdefault("pages", {}),
            COVERAGE_KEY,
            "Esa-FX — staging vs main",
            global_md,
            "coverage.md",
            None,
            "esafx-coverage/index",
        )
    elif args.dry_run:
        print("dry-run esafx-coverage/index")

    state_path.parent.mkdir(parents=True, exist_ok=True)
    if not args.dry_run:
        state_path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
