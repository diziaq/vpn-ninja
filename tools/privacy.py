#!/usr/bin/env python3
"""Privacy tooling for this repository: redact text for git, and scan what is about to be committed.

  privacy.py redact SRC DST      copy SRC to DST with private values replaced (map + generic IPv4)
  privacy.py redact - -          stdin to stdout
  privacy.py scan FILE...        report private values in files; exit 1 if any
  privacy.py scan --staged       same, for the files staged in git (used by the pre-commit hook)

Private values come from .private/redact-map.tsv (never committed; regex TAB replacement per line).
Independently of the map, the scanner always flags: any IPv4 address not in tools/allowed-ips.txt,
a full UUID, a vless:// link, a Reality private key line, and a PEM private key.
Bytes are preserved apart from replacements (CRLF files stay CRLF). Binary files are skipped.
Override the private folder with VPN_NINJA_PRIVATE (used by the tests).
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRIVATE = os.environ.get("VPN_NINJA_PRIVATE", os.path.join(ROOT, ".private"))
MAP_FILE = os.path.join(PRIVATE, "redact-map.tsv")
ALLOWED_IPS_FILE = os.path.join(ROOT, "tools", "allowed-ips.txt")

IPV4 = re.compile(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")
GENERIC = [
    ("full UUID (client ID?)", re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")),
    ("vless:// link", re.compile(r"vless://[0-9a-fA-F]")),
    ("Reality private key", re.compile(r"(?i)private\s*key\s*[:=]\s*[A-Za-z0-9_\-]{40,}")),
    ("PEM private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
]


def load_map():
    if not os.path.isfile(MAP_FILE):
        return None
    rules = []
    with open(MAP_FILE, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\r\n")
            if not line or line.startswith("#"):
                continue
            if "\t" not in line:
                sys.exit(f"{MAP_FILE}:{n}: expected 'regex<TAB>replacement'")
            pat, rep = line.split("\t", 1)
            rules.append((re.compile(pat), rep))
    return rules


def load_allowed_ips():
    allowed = set()
    if os.path.isfile(ALLOWED_IPS_FILE):
        with open(ALLOWED_IPS_FILE, encoding="utf-8") as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if line:
                    allowed.add(line)
    return allowed


def is_binary(data):
    return b"\0" in data[:8192]


def redact_text(text, rules, allowed):
    for pat, rep in rules:
        text = pat.sub(rep, text)
    return IPV4.sub(lambda m: m.group(0) if ip_allowed(m.group(0), allowed) else "<ip>", text)


def ip_allowed(ip, allowed):
    """Exact entries, or prefixes ending in '.' (used for the RFC 5737 documentation ranges)."""
    return ip in allowed or any(a.endswith(".") and ip.startswith(a) for a in allowed)


def cmd_redact(src, dst):
    rules = load_map()
    if rules is None:
        sys.exit(f"Private map not found: {MAP_FILE}. Refusing to redact without it.")
    allowed = load_allowed_ips()
    data = sys.stdin.buffer.read() if src == "-" else open(src, "rb").read()
    if is_binary(data):
        sys.exit(f"{src}: binary file, not redacted")
    text = data.decode("utf-8")  # strict: fail loudly on non-UTF-8 rather than corrupting
    out = redact_text(text, rules, allowed).encode("utf-8")
    if dst == "-":
        sys.stdout.buffer.write(out)
    else:
        os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(out)


def staged_files():
    out = subprocess.run(["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"],
                         cwd=ROOT, check=True, capture_output=True).stdout
    return [os.path.join(ROOT, p) for p in out.decode().split("\0") if p]


def staged_blob(path):
    rel = os.path.relpath(path, ROOT)
    return subprocess.run(["git", "show", f":{rel}"], cwd=ROOT, check=True, capture_output=True).stdout


def scan(paths, staged):
    rules = load_map()
    if rules is None:
        print(f"WARNING: {MAP_FILE} missing: only generic checks (IPs, UUIDs, links, keys) run.", file=sys.stderr)
        rules = []
    allowed = load_allowed_ips()
    hits = 0
    for p in paths:
        try:
            data = staged_blob(p) if staged else open(p, "rb").read()
        except (OSError, subprocess.CalledProcessError):
            continue
        if is_binary(data):
            if staged:
                print(f"BLOCK {os.path.relpath(p, ROOT)}: binary file staged (binaries are built, not committed)")
                hits += 1
            continue
        text = data.decode("utf-8", errors="replace")
        for ln, line in enumerate(text.splitlines(), 1):
            found = []
            for pat, _ in rules:
                if pat.search(line):
                    found.append(f"private value /{pat.pattern}/")
            for ip in IPV4.findall(line):
                if not ip_allowed(ip, allowed):
                    found.append("IPv4 not in tools/allowed-ips.txt")
            for name, pat in GENERIC:
                if pat.search(line):
                    found.append(name)
            for what in found:
                hits += 1
                print(f"BLOCK {os.path.relpath(p, ROOT)}:{ln}: {what}")
    if hits:
        print(f"\n{hits} finding(s). Redact with: python3 tools/privacy.py redact SRC DST "
              f"(real values belong in .private/).", file=sys.stderr)
        return 1
    return 0


def main(argv):
    if len(argv) >= 2 and argv[0] == "redact" and len(argv) == 3:
        cmd_redact(argv[1], argv[2])
        return 0
    if argv and argv[0] == "scan":
        if argv[1:] == ["--staged"]:
            return scan(staged_files(), staged=True)
        if len(argv) > 1:
            return scan(argv[1:], staged=False)
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
