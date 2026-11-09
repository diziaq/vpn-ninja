#!/usr/bin/env python3
"""Generate docs/guide.html: the whole path as navigable cards, each opening a detail panel.

Single sources: the STEPS list below (the path) and docs/LESSONS.md (problems and fixes, parsed
by their L-numbers, never retyped here). After editing either, run:

    python3 docs/src/gen_guide.py
    python3 ~/.claude/skills/html-report/scripts/embed-fonts.py docs/guide.html   # optional: house fonts

The page works offline, without JavaScript (all panels stacked) and in print.
"""
import html
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "docs", "guide.html")
LESSONS = os.path.join(ROOT, "docs", "LESSONS.md")

# status: done | now | next | planned | later
STEPS = [
    dict(id="plan", n=1, title="Plan the gates", date="5 Nov", status="done", stage="Prepare",
         result="Gated plan: the cheapest question that can kill the plan goes first.",
         goal="Decide what to test, in what order, and what each test must show before money or time goes into the next step.",
         did=["Wrote the gated rollout plan (gates 0.1, G0-G5) and researched the censorship facts.",
              "Chose VLESS + Reality as the main protocol, AmneziaWG 3.1 for phones, a commercial service as backup (D-02).",
              "Chose GL-MT3000 routers, two identical units (D-06)."],
         evidence=["docs/plan-v1-gated-rollout.html", "docs/FACTS.md", "docs/DECISIONS.md"],
         lessons=[], better=["Write the privacy rules (what may be published) on day one, next to the plan."]),
    dict(id="p0", n=2, title="Phase 0: Russian PC", date="5 Nov", status="done", stage="Probe Russia",
         result="PASS: tools run without admin, regular ISP, filtering visible.",
         goal="Is the remote Russian PC usable as a probe and representative of Russian internet?",
         did=["Quick check package over Remote Desktop: PowerShell, curl, no proxy, no HTTPS inspection.",
              "Blocked sites time out, LinkedIn fails TLS: the filter is visible from this line."],
         evidence=["evidence/EVIDENCE-phase0-quick-20261105-210922.txt", "windows/phase0-EXECUTED/"],
         lessons=["L13"], better=["Plan every package around the short Remote Desktop window (one package, several phases)."]),
    dict(id="p1", n=3, title="Phase 1: hosters", date="5 Nov", status="done", stage="Probe Russia",
         result="PASS: Time4VPS and BuyVM reachable; Hetzner, OVH, Linode blocked.",
         goal="Which hosting providers can be reached from Russia at all (whole subnets get blocked)?",
         did=["Downloaded test files from provider looking-glass sites through the Russian line.",
              "Vultr Frankfurt froze at 15,957 bytes: the ~16 KB stall seen live."],
         evidence=["evidence/EVIDENCE-phase1-hosting-20261105-214320.txt", "windows/phase1-EXECUTED/"],
         lessons=[], better=["Fix broken test URLs before the session (two providers were inconclusive)."]),
    dict(id="buyA", n=4, title="Buy server A", date="5 Nov", status="done", stage="Server A",
         result="Time4VPS, Lithuania, monthly with a 30-day refund window.",
         goal="One cheap server at a provider that passed phase 1, refundable if its address is blocked.",
         did=["Registered with real data from normal (non-VPN) internet (D-14); paid monthly first (D-13).",
              "Set up an SSH key with a passphrase on the Mac."],
         evidence=["docs/DECISIONS.md (D-03, D-13, D-14)"], lessons=["L14"],
         better=["Manage servers from a personal device from the start, not the employer-managed laptop (L15)."]),
    dict(id="p2a", n=5, title="Phase 2a: server address", date="5 Nov", status="done", stage="Server A",
         result="PASS: ports open 3/3; 8 MB downloads complete with and without SNI.",
         goal="Is this specific server address reachable from Russia before we build anything on it?",
         did=["Temporary test web server on the VPS; the Russian PC downloaded 8 MB over HTTP and HTTPS, 3 times each."],
         evidence=["evidence/EVIDENCE-phase2a-ipcheck-20261105-232638.txt", "windows/phase2a-EXECUTED/", "server/test-web-start.sh"],
         lessons=[], better=[]),
    dict(id="ssh", n=6, title="Key-only SSH", date="6 Nov", status="done", stage="Server A",
         result="Password login off, verified from outside.",
         goal="No password login on the server, proven, not assumed.",
         did=["The hoster's image kept password login on despite our setting; fixed and verified with sshd -T and a clean outside test."],
         evidence=["server/ssh-hardening-fix.sh", "server/EXECUTION-RECORD.md"], lessons=["L1", "L2"], better=[]),
    dict(id="setupA", n=7, title="Server A setup", date="8 Nov", status="done", stage="Server A",
         result="Xray running: Vision on 443, XHTTP on 8443; firewall, fail2ban, auto-updates.",
         goal="Hardened server with the VPN entry points, configured by one repeatable script.",
         did=["setup-server.sh v1.1 failed on the real server (Xray could not read its config); v1.2 fixed it the same day.",
              "Camouflage site auto-picked from the server's own network; links saved to the password manager."],
         evidence=["evidence/EVIDENCE-phase2b-server-20261107-215823.txt", "server/setup-server.sh"],
         lessons=["L3", "L4", "L14", "L15", "L17", "L18"],
         better=["Test setup-server.sh end to end in a container with the real Xray installer before the first real run."]),
    dict(id="p2b", n=8, title="Phase 2b: tunnel test", date="8 Nov", status="done", stage="Prove from Russia",
         result="PASS: 4 of 5 variants; all three Vision fingerprints; ~20 Mbit/s.",
         goal="Does the VPN itself get through the filter: exit address, repeated requests, big download, blocked sites?",
         did=["Five variants (Vision x3 fingerprints, XHTTP x2) through a local proxy on the Russian PC; Xray bundled in the zip.",
              "Blocked sites reached; sites refusing Russian users opened; two HTTP 400 answers were script artefacts."],
         evidence=["evidence/EVIDENCE-phase2b-tunnel-20261108-195210.txt", "windows/phase2b2c-EXECUTED/"],
         lessons=["L9", "L10", "L16"], better=["Count any HTTP answer as 'reached' from the start (L9)."]),
    dict(id="p2c", n=9, title="Phase 2c: 12 h monitor", date="8-9 Nov", status="done", stage="Prove from Russia",
         result="PASS: 289/289 cycles on both links, evening covered, no gaps.",
         goal="Does it keep working over hours, including the evening peak, not just for 15 minutes?",
         did=["Restartable monitor: one line every 2.5 min, evidence rewritten every cycle, single instance via a lock.",
              "Two bugs found in Docker before first use; the Windows-only parts (keep-awake, stop, restart) proven on the real PC."],
         evidence=["evidence/EVIDENCE-phase2c-monitor-20261108-200950.txt", "windows/phase2b2c-EXECUTED/phase2c-monitor.ps1"],
         lessons=["L8", "L11", "L12", "L19", "L20", "L21", "L22"],
         better=["Add a periodic large download and fingerprint rotation to the monitor (step 13)."]),
    dict(id="rotate", n=10, title="Key rotation", date="9 Nov", status="done", stage="Operate",
         result="All secrets replaced; old links refused; camouflage kept.",
         goal="Links had been on a machine we do not control: make them worthless.",
         did=["rotate-keys.sh: new client ID, Reality keys, short ID, XHTTP path; validated before switching; tested in Docker first."],
         evidence=["evidence/EVIDENCE-rotate-keys-20261109-055215.txt", "server/rotate-keys.sh"],
         lessons=["L5", "L6", "L7"], better=["Give every tester their own client ID so nothing needs rotating (step 14)."]),
    dict(id="repo", n=11, title="Repository", date="9 Nov", status="done", stage="Operate",
         result="Publish-safe git history; private values only in .private/.",
         goal="One place for everything, safe to publish, that a new session can start from.",
         did=["Imported every phase as its own commit, redacted; pre-commit guard blocks addresses, names, keys.",
              "Packages are built with a pinned, verified Xray instead of committing binaries."],
         evidence=["CLAUDE.md", "tools/privacy.py", "tools/build-ru-probe.sh"], lessons=[], better=[]),
    dict(id="serverB", n=12, title="Server B", date="next", status="next", stage="Second server",
         result="Second provider for failover; G2 completes when B passes 2b + monitor.",
         goal="A second server at a different provider, so one blocked address does not cut us off.",
         did=["Buy BuyVM Luxembourg (or Vultr Stockholm); phase 2a for its address; setup-server.sh v1.3; phase 2b + monitor."],
         evidence=["docs/NEXT-STEPS.md item 1"], lessons=["L13"], better=[]),
    dict(id="monv12", n=13, title="Monitor v1.2", date="next", status="next", stage="Second server",
         result="Large downloads every ~15 min; optional fingerprint rotation.",
         goal="Measure real capacity and catch stalls that only hit big transfers.",
         did=["Add a 20 MB download per link every 6th cycle, reported separately; test in Docker like v1.1."],
         evidence=["docs/NEXT-STEPS.md item 2"], lessons=["L11"], better=[]),
    dict(id="clients", n=14, title="Per-client IDs", date="planned", status="planned", stage="Others",
         result="Each tester or friend gets a revocable ID.",
         goal="Share access without sharing one key.",
         did=["manage-clients.sh: add/list/remove a named client, validated and verified; expiry list on the server."],
         evidence=["docs/NEXT-STEPS.md item 3"], lessons=["L7"], better=[]),
    dict(id="g3", n=15, title="Friends (G3)", date="planned", status="planned", stage="Others",
         result="Works on 2+ home ISPs and mobile.",
         goal="The office line may be filtered more lightly than home lines; prove it where we will live.",
         did=["Friends import their own link into Hiddify/Happ/v2RayTun; Wi-Fi, mobile, evening; report ISP and whitelist mode."],
         evidence=["docs/NEXT-STEPS.md item 4"], lessons=[], better=[]),
    dict(id="g4", n=16, title="AmneziaWG + OpenVPN probe (G4)", date="planned", status="planned", stage="Others",
         result="Decides whether the work laptop needs the router.",
         goal="AWS Client VPN is OpenVPN-based (blocked directly); measure it, and give phones a second protocol.",
         did=["AmneziaWG 3.1 only (never the Xray container: port conflict); temporary OpenVPN server on B, 10 min from a friend's phone."],
         evidence=["docs/NEXT-STEPS.md item 5"], lessons=[], better=[]),
    dict(id="router", n=17, title="Router kit + twin test", date="planned", status="planned", stage="Router",
         result="Ready-to-flash kit; sing-box twin passes from Russia.",
         goal="Have the router configuration proven before the router exists in Russia.",
         did=["OpenWrt images and packages downloaded in advance; setup-router.sh; the router's engine (sing-box) run on the Russian PC."],
         evidence=["docs/NEXT-STEPS.md item 6"], lessons=[], better=[]),
    dict(id="buyRouter", n=18, title="Order and check routers", date="13-15 Nov", status="planned", stage="Router",
         result="2 units kept (main + spare) after the arrival check.",
         goal="Genuine GL-MT3000 units waiting at a pickup point on arrival.",
         did=["Order from 2-3 sellers ~16 days before arrival; check at the counter and at home before keeping."],
         evidence=["docs/router-arrival-check.html"], lessons=["L23"], better=[]),
    dict(id="domain", n=19, title="Own domain (self-steal)", date="later", status="later", stage="Later",
         result="Camouflage under our control; name and address agree.",
         goal="Stop depending on a stranger's site for the disguise.",
         did=["Cheap non-.ru domain, DNS-only record to the server; setup-selfsteal.sh; re-run 2b."],
         evidence=["docs/vpn-explained.html#domain"], lessons=["L24", "L25"], better=[]),
    dict(id="day1", n=20, title="Departure and Day 1", date="~29 Nov", status="planned", stage="Arrive",
         result="Apps work on day 1; router the first evening.",
         goal="Arrive with working fallbacks; set the router up without pressure.",
         did=["Final Russian-PC test; secrets backed up; phone and laptop apps; router setup the first evening."],
         evidence=["docs/NEXT-STEPS.md item 8"], lessons=[], better=[]),
]

GATES = [("0.1", "Employer approval", "now", "open (user's action)"),
         ("G0", "Russian PC usable", "done", "pass"),
         ("G1", "Hosters reachable", "done", "pass"),
         ("2a", "Server A address", "done", "pass"),
         ("G2", "Tunnel survives", "now", "A pass; B open"),
         ("G3", "Home ISPs", "planned", "not started"),
         ("G4", "Laptop needs router?", "planned", "not decided"),
         ("G5", "Router in Russia", "planned", "not started")]

STATUS_WORD = {"done": "done", "now": "now", "next": "next", "planned": "planned", "later": "later"}
ICON = {
    "done": '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="7.5" fill="currentColor"/><path d="M4.5 8.2 7 10.6 11.6 5.4" stroke="#fff" stroke-width="2" fill="none"/></svg>',
    "now": '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.2" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M8 1.8a6.2 6.2 0 0 1 0 12.4z" fill="currentColor"/></svg>',
    "next": '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 2l10 6-10 6z" fill="currentColor"/></svg>',
    "planned": '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.2" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>',
    "later": '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.2" fill="none" stroke="currentColor" stroke-width="1.6" stroke-dasharray="2.5 2"/></svg>',
}


def e(s):
    return html.escape(s, quote=True)


def md_inline(s):
    s = e(s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", s)


def load_lessons():
    """Parse '| L<n> | problem | fix | [rule] |' rows from LESSONS.md, plus the fresh-start list."""
    lessons, fresh, section = {}, [], ""
    with open(LESSONS, encoding="utf-8") as f:
        lines = f.read().splitlines()
    for line in lines:
        if line.startswith("## "):
            section = line[3:].strip()
        m = re.match(r"^\|\s*(L\d+)\s*\|(.*)\|\s*$", line)
        if m:
            cells = [c.strip() for c in m.group(2).split("|")]
            lessons[m.group(1)] = dict(section=section, problem=cells[0], fix=cells[1],
                                       rule=cells[2] if len(cells) > 2 else "")
        m2 = re.match(r"^\d+\.\s+(.*)$", line)
        if m2 and section.startswith("If we started fresh"):
            fresh.append(m2.group(1))
    return lessons, fresh


def card(s):
    nl = len(s["lessons"])
    badge = f'<span class="badge" title="{nl} problem(s) met and solved here">{nl} lesson{"s" if nl != 1 else ""}</span>' if nl else ""
    return (f'<li class="step {s["status"]}"><a class="card" href="#step-{s["id"]}" data-step="{s["id"]}">'
            f'<span class="num">{s["n"]:02d}</span><span class="when">{e(s["date"])}</span>'
            f'<span class="ttl">{e(s["title"])}</span>'
            f'<span class="st {s["status"]}">{ICON[s["status"]]}{STATUS_WORD[s["status"]]}</span>'
            f'<span class="res">{e(s["result"])}</span>{badge}</a></li>')


def detail(s, lessons):
    parts = [f'<section class="detail" id="step-{s["id"]}" aria-labelledby="h-{s["id"]}">',
             f'<p class="eyebrow">Step {s["n"]:02d} &middot; {e(s["stage"])} &middot; {e(s["date"])}</p>',
             f'<h3 id="h-{s["id"]}">{e(s["title"])} <span class="st {s["status"]}">{ICON[s["status"]]}{STATUS_WORD[s["status"]]}</span></h3>',
             f'<p class="goal"><b>Question.</b> {e(s["goal"])}</p>',
             f'<p><b>Result.</b> {e(s["result"])}</p>',
             '<h4>What we did' + (' / will do' if s["status"] != "done" else '') + '</h4><ul>' +
             "".join(f"<li>{e(x)}</li>" for x in s["did"]) + "</ul>"]
    if s["lessons"]:
        parts.append('<h4>Problems met and how we got past them</h4><div class="lessons">')
        for lid in s["lessons"]:
            L = lessons[lid]
            rule = f'<p class="rule"><b>Rule:</b> {md_inline(L["rule"])}</p>' if L["rule"] else ""
            parts.append(f'<details class="lesson"><summary><span class="lid">{lid}</span> {md_inline(L["problem"])}</summary>'
                         f'<p><b>Fix:</b> {md_inline(L["fix"])}</p>{rule}</details>')
        parts.append("</div>")
    if s["better"]:
        parts.append('<h4>Next time</h4><ul class="better">' + "".join(f"<li>{e(x)}</li>" for x in s["better"]) + "</ul>")
    parts.append('<p class="files"><b>Files:</b> ' + ", ".join(f"<code>{e(x)}</code>" for x in s["evidence"]) + "</p>")
    parts.append('<p class="back"><a href="#path">Back to the path</a></p></section>')
    return "".join(parts)


def build():
    lessons, fresh = load_lessons()
    for s in STEPS:
        for lid in s["lessons"]:
            assert lid in lessons, f"step {s['id']} cites unknown lesson {lid}"
    used = {lid for s in STEPS for lid in s["lessons"]}
    stages = []
    for s in STEPS:
        if not stages or stages[-1][0] != s["stage"]:
            stages.append((s["stage"], []))
        stages[-1][1].append(s)
    rail = "".join(f'<li class="stage"><p class="stage-name">{e(name)}</p><ol class="steps">' +
                   "".join(card(s) for s in items) + "</ol></li>" for name, items in stages)
    gates = "".join(f'<li class="gate {st}"><span class="gid">{e(g)}</span> {e(t)} '
                    f'<span class="st {st}">{ICON[st]}{e(w)}</span></li>' for g, t, st, w in GATES)
    details = "".join(detail(s, lessons) for s in STEPS)
    by_section = {}
    for lid, L in lessons.items():
        by_section.setdefault(L["section"], []).append((lid, L))
    steps_for = {}
    for s in STEPS:
        for lid in s["lessons"]:
            steps_for.setdefault(lid, []).append(s)
    lesson_index = "".join(
        f'<h3>{e(sec)}</h3><ul class="lindex">' + "".join(
            f'<li><span class="lid">{lid}</span> {md_inline(L["problem"])} '
            + " ".join(f'<a href="#step-{s["id"]}" data-step="{s["id"]}">step {s["n"]:02d}</a>' for s in steps_for.get(lid, []))
            + "</li>" for lid, L in items) + "</ul>"
        for sec, items in by_section.items())
    fresh_html = "".join(f"<li>{md_inline(x)}</li>" for x in fresh)
    done = sum(1 for s in STEPS if s["status"] == "done")
    page = TEMPLATE.format(rail=rail, gates=gates, details=details, lesson_index=lesson_index,
                           fresh=fresh_html, done=done, total=len(STEPS), nlessons=len(lessons),
                           unused=len(set(lessons) - used))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(page)
    print(f"wrote {OUT}: {len(STEPS)} steps, {len(lessons)} lessons ({len(set(lessons) - used)} not tied to a step)")


TEMPLATE = """<!doctype html>
<html lang="en" data-doc="vpn-ninja-guide">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>VPN path guide</title>
<script>document.documentElement.classList.add('js');</script>
<style>
/* fonts:begin */
/* fonts:end */
:root{{color-scheme:light;
  --surface:#fcfcfb;--surface-2:#f2f1ee;--rule:#d9d7d2;--ink:#1b1b1a;--ink-2:#52514e;--line:#6b6a66;
  --accent:#0072B2;--focus:#0072B2;--good:#00754f;--warning:#8a5a00;--next:#0072B2;--muted:#6b6a66;
  --font:"IBM Plex Sans",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
  --font-c:"IBM Plex Sans Condensed","IBM Plex Sans","Arial Narrow",system-ui,sans-serif;
  --mono:"IBM Plex Mono",ui-monospace,Menlo,Consolas,monospace;
  --s1:.25rem;--s2:.5rem;--s3:.75rem;--s4:1rem;--s5:1.5rem;--s6:2rem;--s7:3rem;--radius:4px;--measure:75ch}}
*,*::before,*::after{{box-sizing:border-box}}
html{{background:var(--surface);color:var(--ink);font:16px/1.55 var(--font)}}
body{{margin:0;background:var(--surface)}}
h1,h2,h3,h4{{font-family:var(--font-c);font-weight:600;line-height:1.2;margin:0}}
h1{{font-size:2rem}} h2{{font-size:1.4rem;margin:var(--s7) 0 var(--s3);padding-top:var(--s3);border-top:1px solid var(--rule)}}
h3{{font-size:1.2rem;margin:0 0 var(--s2)}} h4{{font-size:1rem;margin:var(--s4) 0 var(--s1)}}
p,li{{max-width:var(--measure)}} p{{margin:0 0 var(--s3)}} b{{font-weight:600}} a{{color:var(--accent)}}
code{{font-family:var(--mono);font-size:.85em;background:var(--surface-2);padding:.05em .3em;border-radius:3px}}
:focus-visible{{outline:2px solid var(--focus);outline-offset:2px}}
.wrap{{max-width:80rem;margin:0 auto;padding:var(--s6) var(--s5) var(--s7)}}
@media (max-width:40rem){{.wrap{{padding:var(--s5) 16px var(--s7)}}}}
.eyebrow{{font:600 .75rem var(--font-c);letter-spacing:.08em;text-transform:uppercase;color:var(--ink-2);margin:0 0 var(--s1)}}
.lede{{font-size:1.1rem}}
.st{{display:inline-flex;align-items:center;gap:.25rem;font:600 .8rem var(--font);white-space:nowrap;vertical-align:middle}}
.st svg{{width:.9rem;height:.9rem}}
.st.done{{color:var(--good)}} .st.now{{color:var(--warning)}} .st.next{{color:var(--next)}} .st.planned,.st.later{{color:var(--muted)}}
.gates{{display:flex;flex-wrap:wrap;gap:var(--s2);list-style:none;padding:0;margin:var(--s4) 0}}
.gate{{border:1px solid var(--rule);border-radius:999px;padding:.15rem .7rem;font-size:.85rem;background:var(--surface-2)}}
.gid{{font:600 .85rem var(--font-c)}}
.howto{{font-size:.9rem;color:var(--ink-2)}}
/* the path */
.path{{list-style:none;padding:0;margin:var(--s4) 0;display:grid;grid-template-columns:repeat(auto-fit,minmax(15rem,1fr));gap:var(--s4)}}
.stage-name{{font:600 .8rem var(--font-c);letter-spacing:.06em;text-transform:uppercase;color:var(--ink-2);margin:0 0 var(--s2);
  border-bottom:2px solid var(--rule);padding-bottom:var(--s1)}}
.steps{{list-style:none;padding:0;margin:0;display:flex;flex-direction:column;gap:var(--s2)}}
.card{{display:grid;grid-template-columns:auto 1fr auto;gap:0 var(--s2);text-decoration:none;color:var(--ink);
  background:var(--surface-2);border:1px solid var(--rule);border-left:5px solid var(--line);border-radius:var(--radius);padding:var(--s2) var(--s3)}}
.card:hover{{border-color:var(--line)}}
.step.done .card{{border-left-color:var(--good)}} .step.now .card{{border-left-color:var(--warning)}}
.step.next .card{{border-left-color:var(--next);background:#e8f2f9}}
.step.planned .card,.step.later .card{{background:transparent;border-style:dashed;border-left-style:solid}}
.card[aria-current="true"]{{outline:2px solid var(--accent);outline-offset:1px}}
.num{{font:600 .8rem var(--font-c);color:var(--ink-2);grid-row:1}} .when{{font-size:.75rem;color:var(--ink-2);grid-column:3;grid-row:1;text-align:right}}
.ttl{{font:600 1rem var(--font-c);grid-column:1/4}} .card .st{{grid-column:1/4}}
.res{{font-size:.85rem;color:var(--ink-2);grid-column:1/4}}
.badge{{grid-column:1/4;justify-self:start;font-size:.72rem;border:1px solid var(--line);border-radius:999px;padding:0 .45rem;margin-top:var(--s1);color:var(--ink-2)}}
/* details */
.detail{{border:1px solid var(--rule);border-radius:var(--radius);padding:var(--s4) var(--s5);margin:var(--s4) 0;background:#fff}}
.js .detail{{display:none}} .js .detail.open{{display:block}}
.goal{{font-size:1.02rem}}
.lessons{{display:flex;flex-direction:column;gap:var(--s1)}}
details.lesson{{border-left:4px solid #b84a00;background:var(--surface-2);padding:var(--s1) var(--s3);border-radius:3px}}
details.lesson summary{{cursor:pointer}} details.lesson p{{margin:var(--s1) 0}}
.lid{{font:600 .78rem var(--font-c);border:1px solid currentColor;border-radius:3px;padding:0 .3rem;color:#b84a00;margin-right:.3rem}}
.rule{{color:var(--ink-2)}} .better li{{color:var(--ink)}} .files{{font-size:.85rem;color:var(--ink-2)}}
.back{{font-size:.85rem}} .js .back{{display:none}}
.lindex{{padding-left:1rem}} .lindex li{{margin-bottom:var(--s1);font-size:.92rem}}
.fresh li{{margin-bottom:var(--s1)}}
.map{{display:grid;grid-template-columns:max-content minmax(0,1fr);gap:.2rem var(--s4);font-size:.92rem}}
.map dt{{font-family:var(--mono);font-size:.85rem}} .map dd{{margin:0}}
@media (max-width:40rem){{.map{{grid-template-columns:minmax(0,1fr)}} .map dd{{margin-bottom:var(--s2)}}}}
footer{{margin-top:var(--s7);border-top:1px solid var(--rule);padding-top:var(--s3);font-size:.85rem;color:var(--ink-2)}}
@media (prefers-reduced-motion:reduce){{*{{transition:none!important;animation:none!important}}}}
@page{{margin:14mm 12mm}}
@media print{{html{{font-size:10pt}} .js .detail{{display:block}} .wrap{{padding:0}} .detail,.card{{break-inside:avoid}} details.lesson{{display:block}}
  details.lesson>*{{display:block}}}}
</style>
</head>
<body>
<div class="wrap">
<header>
  <p class="eyebrow">vpn-ninja &middot; journey guide &middot; generated from docs/src/gen_guide.py and docs/LESSONS.md</p>
  <h1>The whole path, step by step</h1>
  <p class="lede">Reliable internet from Russia, built and proven in gated steps. {done} of {total} steps are done; server A works from Russia. Click a card to open its detail: the question it answered, what we did, the problems we hit and how we got past them, and what we would do differently.</p>
  <ul class="gates" aria-label="Gates">{gates}</ul>
  <p class="howto">Status is shown by icon and word: done, now, next, planned, later. Keyboard: Tab to a card, Enter to open. Concepts (Reality, camouflage, the filter) are explained in <a href="vpn-explained.html">vpn-explained.html</a>.</p>
</header>

<h2 id="path">The path</h2>
<ol class="path">{rail}</ol>

<div id="details" aria-live="polite">{details}</div>

<h2 id="lessons">All {nlessons} problems and fixes</h2>
<p>Each links to the step where it happened. Full table with the rule each one left: <code>docs/LESSONS.md</code>.</p>
{lesson_index}

<h2 id="fresh">If we started fresh: do these from day one</h2>
<ol class="fresh">{fresh}</ol>

<h2 id="map">Where things live</h2>
<dl class="map">
  <dt>CLAUDE.md</dt><dd>Cold start for an agent: rules, conventions, privacy, how to continue.</dd>
  <dt>docs/STATUS.md</dt><dd>Gates and current server state.</dd>
  <dt>docs/NEXT-STEPS.md</dt><dd>The ordered work queue.</dd>
  <dt>docs/DECISIONS.md</dt><dd>Decisions D-01 onwards and why.</dd>
  <dt>docs/LESSONS.md</dt><dd>Problems, fixes, rules; source of the lessons on this page.</dd>
  <dt>server/</dt><dd>Server scripts and what ran on server A.</dd>
  <dt>windows/</dt><dd>Russian-PC packages (redacted copies); build a zip with <code>tools/build-ru-probe.sh</code>.</dd>
  <dt>evidence/</dt><dd>Returned evidence files (redacted).</dd>
  <dt>tools/</dt><dd>Privacy guard (pre-commit), package builder, tests.</dd>
  <dt>.private/</dt><dd>Not in git: real addresses and hosts, the original archive, raw logs.</dd>
</dl>

<footer>
  <p>Generated page; edit <code>docs/src/gen_guide.py</code> or <code>docs/LESSONS.md</code> and regenerate. Real addresses, hosts and keys are deliberately absent. Render check (2026-11-09): offline-check.sh passed (no external loads, headless render and PDF with the network blocked); screenshot and PDF pages looked at. Not checked: phone width, dark mode.</p>
</footer>
</div>
<script>
(function () {{
  var cards = Array.prototype.slice.call(document.querySelectorAll('.card'));
  var panels = Array.prototype.slice.call(document.querySelectorAll('.detail'));
  function open(id, scroll) {{
    var p = document.getElementById('step-' + id);
    if (!p) return;
    panels.forEach(function (x) {{ x.classList.toggle('open', x === p); }});
    cards.forEach(function (c) {{ c.setAttribute('aria-current', String(c.dataset.step === id)); }});
    if (scroll) p.scrollIntoView({{ block: 'start', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' }});
  }}
  document.addEventListener('click', function (ev) {{
    var a = ev.target.closest && ev.target.closest('a[data-step]');
    if (!a) return;
    ev.preventDefault();
    open(a.dataset.step, true);
    try {{ history.replaceState(null, '', '#step-' + a.dataset.step); }} catch (e) {{}}
  }});
  var m = /^#step-(.+)$/.exec(location.hash);
  var first = document.querySelector('.step.next .card') || cards[0];
  open(m ? m[1] : (first && first.dataset.step), !!m);
  window.addEventListener('beforeprint', function () {{ panels.forEach(function (x) {{ x.classList.add('open'); }}); document.querySelectorAll('details').forEach(function (d) {{ d.open = true; }}); }});
}})();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    build()
