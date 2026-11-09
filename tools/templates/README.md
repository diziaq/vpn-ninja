# Templates for machine-local files

These templates are committed; the files made from them are not. Nothing here holds a real value.

| Template | Copy to | Holds | Committed? |
|---|---|---|---|
| `redact-map.tsv.example` | `.private/redact-map.tsv` | real value -> placeholder rules; the pre-commit guard blocks every one of them | no (`.private/` is ignored) |
| `servers.md.example` | `.private/servers.md` | the real values behind each placeholder, for the person running commands | no |
| `settings.local.json.example` | `.claude/settings.local.json` | this machine's Claude Code permissions (paths to local tools, Docker, extra folders) | no (ignored) |

The shared Claude Code settings are `.claude/settings.json` (committed): read-only git and lint commands are
allowed; push, `git add -A`/`.`, `commit -a` and `--no-verify` are denied. Put anything machine-specific in
`settings.local.json`, which overrides it locally.

## Setting up this repository on a new machine

1. Clone, then turn on the commit guard (repository-local setting):

       git config core.hooksPath tools/git-hooks

2. Restore `.private/` from your backup. It is not in git; it holds the real values, the original archive, raw
   logs and `downloads/` (verified Xray and PowerShell files; without them the first build downloads Xray from
   GitHub and caches it). Without a backup, create it from the templates:

       mkdir -p .private
       cp tools/templates/redact-map.tsv.example .private/redact-map.tsv
       cp tools/templates/servers.md.example .private/servers.md

   Then replace every example value with the real one (server addresses and hostnames from the hoster's panel,
   the rest from the password manager). Keep the placeholders on the right-hand side unchanged.

3. Claude Code, optional:

       cp tools/templates/settings.local.json.example .claude/settings.local.json

   Replace `/Users/YOU` with your home folder; delete entries you do not need. JSON allows no comments, so the
   explanation is here: the `allow` entries let the agent run Docker tests and the HTML checks without asking;
   `additionalDirectories` gives it read access outside the repository.

4. Check that everything works and that git holds nothing private under your map:

       bash tools/test/test-privacy.sh
       python3 tools/privacy.py scan $(git ls-files)

   Both must pass. If the scan reports a finding, a real value reached git: stop and fix it before pushing.

## Rules for the map

- Specific before broad: a full address before its network prefix, a full hostname before a short name.
- Escape dots (`\.`); use `(?i)` for names that appear in different cases.
- A new server, domain or person in the project means a new line here **before** the first file mentioning it
  is committed. The guard can only block what the map (or its generic IP/UUID/link/key checks) knows.
- Back up `.private/` together with the password manager export; git cannot restore it.
