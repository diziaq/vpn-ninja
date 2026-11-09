# vpn-ninja

Reliable internet from Russia for one person, built and proven step by step: two self-hosted VPN servers
(Xray VLESS + Reality), travel routers, client apps, and a remote Russian PC used as a test probe.
Every step is gated: the cheapest question that can kill the plan goes first, and each test leaves an
evidence file.

- **Where it stands:** `docs/STATUS.md`; what comes next: `docs/NEXT-STEPS.md`.
- **The handbook:** open `docs/index.html` in a browser (works offline): the Plan tab shows every step as a card,
  with the problems met and how they were solved; other tabs explain the concepts and the router check and setup.
- **Lessons:** `docs/LESSONS.md`. **Decisions:** `docs/DECISIONS.md`.
- **Working with an agent:** start Claude Code in this folder; `CLAUDE.md` is the cold-start file.

## Privacy

Real server addresses, hostnames, names and keys are not in this repository. Files use placeholders such as
`<SERVER_A_IP>`; the real values stay in the git-ignored `.private/` folder. A pre-commit hook blocks private
values. Setting up on a new machine: `tools/templates/README.md`.

## Building a Russian-PC package

    tools/build-ru-probe.sh phase2b2c-EXECUTED     # -> dist/ru-probe-phase2b2c.zip

It bundles the official Xray release (pinned version, SHA-256 verified). Zips and binaries are never committed.
