#!/usr/bin/env python3
"""把 Claude Code 的项目规则同步给 Codex：
  CLAUDE.md             → AGENTS.md
  .claude/agents/*.md   → .codex/agents/*.toml

Claude 那一侧是唯一来源，Codex 这一侧的文件不要直接改。生成时只做两处替换：标题行，以及正文里的 CLAUDE.md → AGENTS.md。

用法：
  python3 tools/sync_codex.py           重新生成
  python3 tools/sync_codex.py --check   只检查是否一致（不一致时返回 1，clean.sh 会调用）
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GENERATED_NOTE = "由 tools/sync_codex.py 从 {src} 生成，不要直接修改；改 {src} 后重新运行脚本。"


def read_text(path):
    return path.read_text(encoding="utf-8").replace("\r\n", "\n")


def agents_md(claude_md):
    """CLAUDE.md 正文 → AGENTS.md 正文。"""
    lines = claude_md.split("\n")
    if not lines[0].startswith("# CLAUDE.md"):
        raise ValueError("CLAUDE.md 第一行应以 '# CLAUDE.md' 开头")
    title = lines[0].replace("# CLAUDE.md", "# AGENTS.md", 1)
    note = "> " + GENERATED_NOTE.format(src="CLAUDE.md")
    body = "\n".join(lines[1:]).replace("CLAUDE.md", "AGENTS.md")
    return title + "\n\n" + note + "\n" + body


def parse_agent(md):
    """拆出 .claude/agents/*.md 的 frontmatter（简单的 key: value）和正文。"""
    if not md.startswith("---\n"):
        raise ValueError("缺少 frontmatter")
    front, body = md[4:].split("\n---\n", 1)
    meta = {}
    for line in front.splitlines():
        key, _, value = line.partition(":")
        meta[key.strip()] = value.strip()
    return meta, body.strip("\n")


def toml_basic(s):
    """TOML 单行基本字符串。"""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def toml_multiline(s):
    """TOML 多行基本字符串；反斜杠和引号都转义，保证内容原样往返。"""
    return '"""\n' + s.replace("\\", "\\\\").replace('"', '\\"') + '"""'


def codex_agent(md, src):
    meta, body = parse_agent(md)
    return (
        "# " + GENERATED_NOTE.format(src=src) + "\n"
        + "name = " + toml_basic(meta["name"]) + "\n"
        + "description = " + toml_basic(meta["description"]) + "\n"
        + "developer_instructions = " + toml_multiline(body.replace("CLAUDE.md", "AGENTS.md")) + "\n"
    )


def targets():
    """返回 [(目标路径, 期望内容)]。"""
    out = [(ROOT / "AGENTS.md", agents_md(read_text(ROOT / "CLAUDE.md")))]
    for src in sorted((ROOT / ".claude" / "agents").glob("*.md")):
        rel = src.relative_to(ROOT).as_posix()
        out.append((ROOT / ".codex" / "agents" / (src.stem + ".toml"), codex_agent(read_text(src), rel)))
    return out


def main(argv):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")  # Windows 控制台默认不是 UTF-8
    check = "--check" in argv
    expected = targets()
    expected_paths = {p for p, _ in expected}
    stale = [p for p in (ROOT / ".codex" / "agents").glob("*.toml") if p not in expected_paths]
    diff = [p for p, text in expected if not p.exists() or read_text(p) != text]

    if check:
        for p in diff:
            print("  不一致：" + p.relative_to(ROOT).as_posix())
        for p in stale:
            print("  多余（.claude/agents 里没有对应文件）：" + p.relative_to(ROOT).as_posix())
        return 1 if diff or stale else 0

    for p, text in expected:
        p.parent.mkdir(parents=True, exist_ok=True)
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    for p in stale:
        p.unlink()
        print("  删除 " + p.relative_to(ROOT).as_posix())
    print("已同步 %d 个文件" % len(expected))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
