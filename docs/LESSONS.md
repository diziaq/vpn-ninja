# LESSONS: problems we hit, how we got past them, and what to do differently next time

Read before building or running anything. Each entry: what happened, the fix, the rule it left behind.
The Plan tab of `docs/index.html` shows the same items on the journey map.

## Server

| # | Problem | Fix | Rule |
|---|---|---|---|
| L1 | Time4VPS Ubuntu image: the main `sshd_config` says `PasswordAuthentication yes` before our drop-in; sshd takes the first value, so password login stayed on. | `setup-server.sh` neutralises conflicting lines in the main file and checks `sshd -T`. | Verify the **effective** state, never only the written config (D-09). |
| L2 | A "password disabled" test from the Mac still logged in with the key (agent/config). | `ssh -F /dev/null -o IdentityAgent=none -o PubkeyAuthentication=no -o PreferredAuthentications=password` | Negative tests must remove every other path to success. |
| L3 | Xray's official installer now runs the service as user `xray`; v1.1 gave the config to `nogroup` -> "permission denied", Xray down. | v1.2 reads the service user from systemd, sets `root:<group> 640`, then checks the user can read it. | Do not assume a third-party installer's defaults; check them at run time. |
| L4 | Sourcing `/etc/os-release` overwrote the script's `VERSION`; evidence said "v24.04.5". | Renamed to `SCRIPT_VERSION` (v1.3). | Never name script variables after common environment/OS variables. |
| L5 | Xray refused a temp config named `config.json.new-...`: it picks the format from the extension. | Temp file `config.new-<stamp>.json`. | Keep the real extension on temp files. |
| L6 | The camouflage auto-pick chose a different neighbour on the second setup run. | Key rotation (`rotate-keys.sh`) keeps the camouflage; never `FORCE=1` setup just to change keys. | Change one variable at a time once something passed. |
| L7 | Links were placed on a machine we do not control -> treated as leaked. | `rotate-keys.sh` replaced UUID, Reality keys, short ID, XHTTP path; old links refused. | Testers get their own client ID (`manage-clients.sh`, D-19). |

## Russian PC and test scripts

| # | Problem | Fix | Rule |
|---|---|---|---|
| L8 | PowerShell variable names ignore case: loop variable `$e` overwrote the evidence list `$E`; a silent `catch {}` hid it, so no evidence file was written (monitor v1.0). | Renamed; save errors are shown on screen (v1.1). A scan for case-colliding variable names is part of the test. | Never swallow errors in the path that writes evidence. |
| L9 | facebook.com and web.whatsapp.com answer HTTP 400 to scripts through a working tunnel; counted as "blocked". | Any HTTP answer = reached; censorship shows as timeout/reset (monitor v1.1). | Classify by transport outcome, not by HTTP status. |
| L10 | sberbank.ru failed on every variant (curl exit 60). | Not a tunnel issue: Russian national CA not trusted by default. | Know your control sites; exclude ones with their own failure modes. |
| L11 | 1 MB per-cycle checks read 7-11 Mbit/s while the 20 MB test showed ~20 Mbit/s. | Use the 20 MB figure for capacity. | Monitor v1.2: add a periodic large download (NEXT-STEPS 2). |
| L12 | The first monitor start was closed after one cycle. | Restart-by-design worked: new file, stale lock taken over, leftover xray cleaned. | Long runs must be restartable by a non-expert without thinking. |
| L13 | Remote-desktop sessions to the Russian PC are short. | One package for several phases; links re-read every cycle; evidence rewritten every cycle. | Design packages around the session window, not around the phase list. |

## Work Mac and the agent's environment

| # | Problem | Fix | Rule |
|---|---|---|---|
| L14 | Traffic to the VPS went through the corporate GlobalProtect tunnel; the server saw the employer's address. | Disconnect GP from its menu before server work. | Check the route (`route -n get <ip>`) before any server step. |
| L15 | The work Mac is employer-managed (MDM); stopping the GP agent cut all network access (enforcement). | Never disable the extension or enforcement (D-16). Longer term: manage servers from an own device. | Do not defeat an employer control. |
| L16 | GitHub downloads failed (HTTP 503/504) while GP was connected. | Disconnect GP, or download elsewhere and pass `XRAY_ZIP=`; the checksum is verified either way. | Bundle binaries in packages; pin version and SHA-256. |
| L17 | The agent's guard forbids remote shells and (in the old workspace) writes outside it. | The user runs server commands; files are staged and copied with one `rsync`. This repo is inside the agent's workspace, so writes work here. | Plan for the user executing; give one command per step and say where it runs. |
| L18 | A pasted command block once included its trailing stop command; a domain inside a command became a link. | Minimal blocks; no bare domains in commands. | Give only what runs now. |

## Testing Windows scripts on a Mac (Docker)

| # | Problem | Fix |
|---|---|---|
| L19 | Docker Desktop could not see the agent's `/private/tmp` scratch folder (empty mounts). | `docker create` + `docker cp` instead of `-v`. |
| L20 | `mcr.microsoft.com/powershell:latest` pulled a non-arm64 image on Apple silicon (exec format error). | `ubuntu:22.04` + the official PowerShell `linux-arm64` tarball + `libicu70`. |
| L21 | A killed process stayed a zombie and looked "alive" to the lock check. | Run test containers with `--init` (Windows has no zombies; test artefact). |
| L22 | `pkill -f "client-1.json"` killed the test's own shell (its command line contained the pattern). | Read the PID from the lock file and `kill` it; never `pkill -f` with a pattern the caller's command line contains. |

## Purchases and services

| # | Problem | Fix |
|---|---|---|
| L23 | Router prices on Russian marketplaces ranged 6,400-23,000 RUB for the same card with ~14-day delivery. | Spread = seller margin, card-only prices, bundled variants, bait listings. Buy ~7,500-11,000 RUB from established sellers, 2-3 sellers, order ~16 days before arrival. |
| L24 | Namecheap blocks automated reading; it also stopped serving Russia-based users in 2022 (not re-checked). | Prefer Cloudflare Registrar for the own domain; check registrar terms for users in Russia. |
| L25 | Idea: camouflage site on an own EC2 instance. | Does not fix the name/address mismatch (the site must run on the VPN server itself); adds a machine to maintain. |

## If we started fresh: do these from day one

1. Bundle `xray.exe` (pinned, checksum-verified) in every Russian-PC package; never download on that PC.
2. One restartable package per session window: tunnel test + monitor + host check, links re-read live.
3. Monitor with a periodic large download and fingerprint rotation (NEXT-STEPS 2).
4. Per-client IDs from the first link that leaves our devices; no shared links, no rotation for everyone.
5. Test every script in Docker against a real Xray server before shipping, including crash/restart, a second
   start, a stop request and a server outage.
6. Keep the repo publish-safe from the first commit: private values in `.private/`, the pre-commit guard on.
7. Manage servers from a personal device, not the employer-managed laptop.
8. Order hardware ~16 days before arrival from 2-3 sellers, with the arrival check printed.
