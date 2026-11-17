#!/usr/bin/env python3
"""Condense a Claude Code session transcript (.jsonl, plus its sidecar folder) into a small JSON digest
for the site's trajectory page.

    python3 -I tools/trajectory_digest.py SESSION.jsonl [SESSION_DIR] -o site/data/trajectory.json

Kept: every prompt the user typed (with timestamps), Claude's visible replies (thinking is dropped), and per turn
the tool calls (name + one-line summary: a Bash description, a file path, a search pattern). Dropped: tool
outputs, thinking, images, attachments, system reminders, hook chatter, compaction summaries.
Scrubbed: e-mail addresses, tokens/keys, signed URLs, the container's home path. Review the output before
publishing it; the scrub is a safety net, not a guarantee.
"""
import argparse
import collections
import json
import os
import re
import sys

EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
SECRETS = [
    re.compile(r"\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})"),
    re.compile(r"\bsk-[A-Za-z0-9_-]{16,}"),
    re.compile(r"(?i)\b(bearer|token|api[_-]?key|password|secret)(\s*[:=]\s*|\s+)['\"]?[A-Za-z0-9._~+/=-]{12,}"),
    re.compile(r"https?://[^\s\"')]*(X-Amz-[A-Za-z]+=|[?&](sig|signature|token|Expires|key)=)[^\s\"')]*"),
    re.compile(r"\b[A-Za-z0-9+/]{60,}={0,2}"),  # long opaque blobs (base64 signatures etc.)
]
NOISE = ("<system-reminder>", "<command-", "<local-command", "<task-notification", "[SYSTEM NOTIFICATION",
         "Stop hook feedback", "[Request interrupted", "<bash-", "Caveat:", "<user-prompt-submit-hook>")


def scrub(text: str, emails: set) -> str:
    text = EMAIL.sub(lambda m: (emails.add(m.group(0)), "[email]")[1], text)
    for rx in SECRETS:
        text = rx.sub("[redacted]", text)
    text = re.sub(r"<system-reminder>.*?</system-reminder>", "", text, flags=re.S)
    return text.strip()


def clip(text: str, n: int) -> str:
    return text if len(text) <= n else text[:n].rstrip() + " [...]"


def tool_line(block: dict) -> str:
    name = block.get("name", "?")
    inp = block.get("input") or {}
    for key in ("description", "file_path", "pattern", "query", "url", "subject", "prompt", "command"):
        v = inp.get(key)
        if isinstance(v, str) and v.strip():
            v = v.strip().splitlines()[0]
            if key == "file_path":
                v = re.sub(r"^/home/user/[^/]+/", "", v)
            return f"{name}: {clip(v, 140)}"
    return name


def user_text(msg: dict) -> tuple[str, int]:
    """The typed text of a user message and how many images came with it ('' for tool results)."""
    content = msg.get("content")
    if isinstance(content, str):
        return content, 0
    texts, images = [], 0
    for b in content or []:
        if b.get("type") == "text":
            texts.append(b.get("text", ""))
        elif b.get("type") == "image":
            images += 1
        elif b.get("type") == "tool_result":
            return "", 0
    return "\n".join(texts), images


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("jsonl")
    ap.add_argument("sidecar", nargs="?")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--reply-chars", type=int, default=8000)
    ap.add_argument("--note-chars", type=int, default=600)
    args = ap.parse_args()

    emails: set = set()
    turns: list = []
    cur = None
    tools_total = collections.Counter()
    first_ts = last_ts = None
    models = collections.Counter()
    branches = collections.Counter()

    with open(args.jsonl, encoding="utf-8") as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if d.get("isSidechain"):
                continue
            ts = d.get("timestamp")
            if ts:
                first_ts = first_ts or ts
                last_ts = ts
            t = d.get("type")
            att = d.get("attachment") or {}
            origin = att.get("origin")
            human = (origin.get("kind") == "human") if isinstance(origin, dict) else "'kind': 'human'" in str(origin)
            if t == "attachment" and att.get("type") == "queued_command" and att.get("commandMode") == "prompt" and human:
                # a message the user typed while Claude was working: a turn of its own
                raw = att.get("prompt", "")
                text, images = user_text({"content": raw}) if isinstance(raw, list) else (str(raw), 0)
                text = text.strip()
                if (text or images) and not text.startswith(NOISE):
                    cur = {"t": ts, "prompt": scrub(text, emails), "images": images, "midturn": True,
                           "notes": [], "reply": "", "tools": collections.Counter(), "calls": []}
                    turns.append(cur)
                continue
            if t == "user":
                if d.get("isMeta") or d.get("isCompactSummary") or d.get("isVisibleInTranscriptOnly"):
                    continue
                text, images = user_text(d.get("message") or {})
                text = text.strip()
                if not text and not images:
                    continue
                if text.startswith(NOISE):
                    continue
                cur = {"t": ts, "prompt": scrub(text, emails), "images": images,
                       "notes": [], "reply": "", "tools": collections.Counter(), "calls": []}
                turns.append(cur)
            elif t == "assistant" and cur is not None:
                msg = d.get("message") or {}
                if msg.get("model") and not msg["model"].startswith("<"):
                    models[msg["model"]] += 1
                if d.get("gitBranch"):
                    branches[d["gitBranch"]] += 1
                for b in msg.get("content") or []:
                    if b.get("type") == "text" and b.get("text", "").strip():
                        txt = scrub(b["text"], emails)
                        if cur["reply"]:
                            cur["notes"].append(clip(cur["reply"], args.note_chars))
                        cur["reply"] = txt
                    elif b.get("type") == "tool_use":
                        cur["tools"][b.get("name", "?")] += 1
                        tools_total[b.get("name", "?")] += 1
                        if len(cur["calls"]) < 60:
                            cur["calls"].append(scrub(tool_line(b), emails))
                cur["end"] = ts

    out_turns = []
    for i, tr in enumerate(turns):
        out_turns.append({
            "n": i + 1, "t": tr["t"], "end": tr.get("end", tr["t"]),
            "prompt": tr["prompt"], "images": tr["images"], "midturn": tr.get("midturn", False),
            "reply": clip(tr["reply"], args.reply_chars),
            "notes": tr["notes"][-12:],
            "tools": dict(tr["tools"].most_common()),
            "calls": tr["calls"],
        })

    sidecar = {}
    if args.sidecar and os.path.isdir(args.sidecar):
        for root, _, files in os.walk(args.sidecar):
            for f in files:
                kind = os.path.relpath(root, args.sidecar).split(os.sep)[0]
                sidecar[kind] = sidecar.get(kind, 0) + 1

    digest = {
        "start": first_ts, "end": last_ts,
        "turn_count": len(out_turns),
        "tool_calls": sum(tools_total.values()),
        "tools": dict(tools_total.most_common()),
        "models": list(models),
        "branches": list(branches),
        "sidecar_files": sidecar,
        "turns": out_turns,
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(digest, fh, ensure_ascii=False, indent=0)
    print(f"{len(out_turns)} turns, {digest['tool_calls']} tool calls, {os.path.getsize(args.out) / 1e6:.2f} MB -> {args.out}")
    if emails:
        print(f"scrubbed {len(emails)} distinct e-mail address(es)", file=sys.stderr)


if __name__ == "__main__":
    main()
