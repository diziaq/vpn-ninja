RU-PROBE: PHASE 0 QUICK CHECK
=============================

WHAT THIS IS
Read-only network checks for the Windows PC in Russia. The scripts install
nothing and change no settings. Each run writes ONE evidence file that you
send back.

STEP 1. COPY THE ZIP TO THE WINDOWS PC
  Option A: copy ru-probe-phase0.zip on the Mac, then paste it onto the
            Windows desktop inside the Remote Desktop window.
  Option B: if pasting files does not work, in the Windows App (Remote
            Desktop) on the Mac edit this PC's connection, open "Folders",
            add a Mac folder that contains the zip and reconnect. In Windows
            open File Explorer > This PC > the redirected folder, and copy
            the zip to the desktop.
  Option C: email it to yourself or use cloud storage, then download it on
            the Windows PC.

STEP 2. UNBLOCK AND EXTRACT
  1. Right-click the zip > Properties. If there is an "Unblock" checkbox at
     the bottom, tick it and click OK. This avoids security prompts.
  2. Right-click the zip > Extract All... > Extract.
  3. You now have a folder named ru-probe. Any location works.

STEP 3. services.txt (nothing to do)
  The GlobalProtect portal is already filled in. Change it only if asked.

STEP 4. RUN THE QUICK CHECK (2-4 minutes)
  Open the ru-probe folder and double-click:  1-RUN-QUICK-CHECK.cmd
  - "Do you want to run this file?"        -> click Run.
  - "Windows protected your PC" (blue box) -> More info -> Run anyway.
  A black window shows progress. When it finishes, the evidence folder opens.

  If double-clicking is blocked or the window closes at once:
  1. Open the ru-probe folder in File Explorer.
  2. Click the address bar at the top, type  powershell  and press Enter.
     A PowerShell window opens in that folder.
  3. Paste this line and press Enter:
       powershell -NoProfile -ExecutionPolicy Bypass -File .\phase0-quick.ps1

STEP 5. SEND THE EVIDENCE BACK
  In ru-probe\evidence take the newest file:
      EVIDENCE-phase0-quick-<date>-<time>.txt
  Copy it back to the Mac the same way as in step 1, or open it in Notepad,
  press Ctrl+A, Ctrl+C and paste the text into the chat.

IF SOMETHING GOES WRONG
  - Red text such as "running scripts is disabled on this system" before any
    checks start: copy the window text or take a screenshot and send that.
    It is the evidence for this step.
  - Antivirus warns about the script: do not force it; send the warning text.
  - Looks stuck: single tests can wait up to 30 seconds and the whole run is
    under 5 minutes. After 10 minutes press Ctrl+C; the evidence file is still
    written.

EVIDENCE RULE (all scripts in this folder)
  - Each run writes one file: evidence\EVIDENCE-<phase>-<script>-<time>.txt
  - It is written at the end of every run, also on failure or Ctrl+C.
  - Safe to share: public IP masked, computer name replaced by a short code,
    no passwords. The work endpoint from services.txt
    (<EMPLOYER_GP_PORTAL>) does appear in it.
  - Raw data stays in the runs folder. Send it only if asked.

LATER, ONLY WHEN ASKED
  Full audit (5-10 min):
    powershell -NoProfile -ExecutionPolicy Bypass -File .\phase0-audit.ps1
  Heartbeat (12 h, own window; close Remote Desktop with X, do not sign out):
    powershell -NoProfile -ExecutionPolicy Bypass -File .\heartbeat.ps1 -Hours 12
