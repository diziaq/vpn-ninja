RU-PROBE: PHASE 2a, CHECK THE NEW SERVER'S IP
=============================================

Goal: before any VPN setup, check from the Russian PC that the rented
server's IP is not blocked and not throttled ("freeze after ~16 KB").
Do it in the first days, while the 30-day money-back guarantee applies.

PART 1. ON THE TIME4VPS PANEL (Mac browser)
  1. Client area > My Services > VPS > Manage > Install OS.
  2. Choose plain Ubuntu 24.04 64-bit (no control panel) > Continue.
  3. Wait 5-10 minutes, refresh. Press Install OS again >
     Last Installation Results: copy the root password into your
     password manager. Note the server's IPv4 address.

PART 2. ON THE MAC (Terminal)
  1. Put your SSH key on the server (asks for the root password once):
       ssh-copy-id -i ~/.ssh/vpn_servers.pub root@SERVER-IP
     Answer "yes" to the fingerprint question.
  2. Log in with the key:
       ssh -i ~/.ssh/vpn_servers root@SERVER-IP
  3. Paste the block from server-test-command.txt (first part) and press
     Enter. It should end with: TEST SERVER RUNNING
     Leave it running; you can close the Terminal window.

PART 3. ON THE RUSSIAN PC
  1. Copy ru-probe-phase2a.zip, Unblock, Extract (as before).
  2. servers.txt is already filled in (<SERVER_A_IP>). Nothing to edit.
  3. Double-click 3-RUN-SERVER-CHECK.cmd
  4. Send back the newest evidence\EVIDENCE-phase2a-ipcheck-....txt

PART 4. AFTER I CONFIRM THE RESULT
  On the server, run the stop command from server-test-command.txt.
  (Port 443 must be free before the VPN setup.)

VERDICTS
  PASS       IP usable; we continue with the VPN setup
  FROZEN     IP throttled: ask Time4VPS for another IP or get a refund
  BLOCKED    IP unreachable from this line
  UNSTABLE   mixed results; re-run later
  NO TEST SERVER  the test command is not running on the server

Data used: about 75 MB per server. Server IPs appear in the evidence file.
Never send passwords or keys.
