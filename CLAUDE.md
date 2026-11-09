# CLAUDE.md: vpn-ninja (cold start for any new session)

Reliable internet from Russia for one person, built and proven in gated steps: two VPN servers (Xray VLESS +
Reality), travel routers (GL-MT3000, OpenWrt, Podkop), client apps, and a remote Russian PC used as a probe.
This repository is the whole project: plan, decisions, tested scripts, evidence, lessons. **Build on it; do not
redo finished work or rewrite tested scripts** without a reason, a version bump and a test.

## Start here (in this order)

1. This file.
2. `docs/STATUS.md`: gates and server state. `docs/NEXT-STEPS.md`: the ordered queue (item 1 is next).
3. `docs/DECISIONS.md` (D-01..D-19; do not reopen without new evidence), `docs/LESSONS.md` (every problem met,
   its fix, the rule it left; read before building anything), `docs/FACTS.md` (dated facts; re-check what matters).
4. `git log --oneline`: one commit per finished phase, newest last.
5. Optional for the human view: `docs/index.html`, the handbook: every HTML document as a tab (Plan, VPN explained,
   Router arrival check, Router setup, Plan v1 history).

Then reply with a 5-line summary of where things stand and the next step with exact commands.

## The user

- Communicates in **English only** (D-15). Confident computer user, not a network specialist: make the technical
  decision yourself, explain briefly why, give exact commands. One question per reply at most.
- Prefers **one step at a time**: give only the commands to run now, say where each runs (Mac `~]`, server
  `root@srvA`, Russian PC), never include trailing stop commands, avoid bare domains inside commands (L18).
- Priority: maximum reliability at balanced cost; robust over quick.
- Currently in Georgia; arrives in Russia around **2026-11-29**. Works remotely for an employer and needs the
  employer's GlobalProtect and AWS Client VPN on a work laptop. Employer approval (gate 0.1) is the user's to obtain;
  never design anything to hide the work location from the employer.

## Privacy (the repository may be published)

- **Never commit** real addresses, hostnames, the camouflage site, employer hosts, names, the probe PC's location,
  client IDs, keys or links. Committed files use placeholders: `<SERVER_A_IP>`, `<SERVER_A_HOST>`, `srvA`,
  `<CAMOUFLAGE_A>`, `<EMPLOYER_GP_PORTAL>`, `<RU-PC town>`, `the employer`, `the user`, ...
- Real values live in **`.private/`** (git-ignored): `servers.md` (what each placeholder means), `redact-map.tsv`
  (rules), `archive/` (the original folder with exact packages and zips), `evidence-raw/`. Read them when you need
  a real value for a command you give the user; never copy them into a tracked file or a commit message.
- The **pre-commit hook** (`git config core.hooksPath tools/git-hooks`; check it is set) runs
  `tools/privacy.py scan --staged` and blocks private values, unknown IPv4s, UUIDs, vless links, private keys and
  binaries. Never bypass it (`--no-verify` is denied in `.claude/settings.json`). If it blocks, redact.
- New evidence: save the raw file to `.private/evidence-raw/`, then
  `python3 tools/privacy.py redact .private/evidence-raw/<f> evidence/<f>`.
- A new server, domain or person: add a map line to `.private/redact-map.tsv` **before** committing anything that
  mentions it. New machine setup: `tools/templates/README.md`.
- Secrets (vless links, passwords, private keys) never go into chat, evidence or files: password manager only.
  The `secrets/` subfolder of the old working folder is off-limits to the agent.

## Environment and access

- The agent runs on the user's **work Mac, which is employer-managed (MDM)** with GlobalProtect. For server work
  the user disconnects GP from its menu; never disable GP's extension or enforcement (D-16, L15). Check
  `route -n get <ip>` before server steps (L14). GitHub downloads may fail while GP is on (L16).
- The agent's guard **forbids remote shells**: the user runs every server command; you give them one at a time.
  The SSH key is `~/.ssh/vpn_servers` (passphrase; `ssh-add --apple-use-keychain ~/.ssh/vpn_servers`).
- The Russian PC is reached by the user over Remote Desktop only (short sessions; no admin; never a full-tunnel
  VPN there, it cuts Remote Desktop: local SOCKS proxy mode only).
- Writes inside this repository are allowed; old paths on `/Volumes/...` are archived in `.private/archive/`.

## Working conventions

1. **Evidence rule**: every script writes exactly one evidence file (Windows `evidence\EVIDENCE-<phase>-<script>-<time>.txt`,
   server `/root/EVIDENCE-<phase>-...txt`), also on failure or Ctrl+C; header with script+version, run ID, machine
   hash, times, status, parameters; secrets masked.
2. **Windows scripts**: PowerShell 5.1 compatible, ASCII, CRLF, no admin, `curl.exe`, a double-click `.cmd`, a README
   (Russian `README-RU.txt` for whoever sits at the PC). Packages live in `windows/phaseX-READY-NOT-RUN/`; rename to
   `-EXECUTED` once evidence is in; never edit an executed package (`windows/MANIFEST.md`). Build zips with
   `tools/build-ru-probe.sh <folder>` (bundles pinned, checksum-verified Xray; zips and binaries are never committed).
3. **Server scripts**: bash, idempotent, verify the effective state (not the written config), validate Xray configs
   with `xray run -test`, keep a rollback, write evidence. Never `FORCE=1` setup to change keys: use
   `server/rotate-keys.sh`. Testers get their own client IDs (D-19).
4. **Test before shipping**: `bash -n` + shellcheck; PowerShell parsed with pwsh; end to end in Docker against a real
   Xray server, including crash/restart, second start, stop and outage (recipe and pitfalls: LESSONS L19-L22). Say
   plainly what could not be tested.
5. **Record progress** after each result: `docs/STATUS.md`, `docs/DECISIONS.md` (new D-number), `docs/LESSONS.md`
   (new L-number for every problem met), then rebuild the handbook: `python3 docs/src/build_docs.py` (add or update
   the step in the `STEPS` list of `docs/src/gen_guide.py`; hand-written pages are `docs/src/pages/*.html`; never edit
   `docs/index.html`). Each topic lives in one page: link to it (`router-setup.html#flash` becomes a tab link) instead
   of repeating it. Bump script versions with a reason.
6. **Git**: commit finished, tested steps with explicit paths (never `add -A`/`.`), the repository's own identity,
   no attribution trailers, never amend, never push (report branch and sha; the user pushes). One phase or logical
   change per commit; the body says why.

## Hard don'ts

- Do not regenerate keys unless asked; do not change the SSH port or re-enable password login; no public admin panels.
- Do not recommend routers other than GL-MT3000 (D-06), Russian-owned hosters, big clouds (AWS, Hetzner,
  DigitalOcean, OVH, Linode/Akamai, Scaleway, Oracle) for VPN servers, or FirstVDS.
- No heavy scans from servers (abuse flags). No AmneziaWG 2.0 or older on anything new; routers use VLESS.

## Folder map

- `docs/`: STATUS, NEXT-STEPS, DECISIONS, LESSONS, FACTS; `index.html` (the handbook, built by `docs/src/build_docs.py`
  from `docs/src/gen_guide.py`, `docs/src/pages/*.html` and `docs/src/fonts.css`); `history/` (old snapshots).
- `server/`: `setup-server.sh` v1.3, `rotate-keys.sh` v1.0, test web server, SSH fix; `EXECUTION-RECORD.md`
  (what ran on server A).
- `windows/`: Russian-PC packages (redacted copies) and `MANIFEST.md`.
- `evidence/`: returned evidence (redacted). `mac/commands.md`: Mac-side commands.
- `tools/`: `privacy.py` (redact/scan), `git-hooks/pre-commit`, `build-ru-probe.sh`, `allowed-ips.txt`, `test/`,
  `templates/` (machine-local file templates with setup steps).
- `.claude/settings.json`: shared permissions (denies push, broad adds, unverified commits).
- `.private/` (not in git): real values, original archive, raw evidence, and `downloads/` (verified Xray releases
  for Windows and linux-arm64, the PowerShell linux-arm64 tarball for Docker tests; the package builder uses this cache
  first, so builds work while GitHub is unreachable).
