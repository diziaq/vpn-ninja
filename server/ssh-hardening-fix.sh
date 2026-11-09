#!/usr/bin/env bash
# Manual SSH hardening fix (already applied on server A on 2026-11-06, verified).
# Hoster images may set PermitRootLogin/PasswordAuthentication in the main sshd_config;
# sshd uses the FIRST value it reads, so a drop-in alone is not enough.
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak-$(date +%s)
grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config || sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
for f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do [ -f "$f" ] && [ "$f" != /etc/ssh/sshd_config.d/00-hardening.conf ] && sed -i -E 's/^[[:space:]]*(PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication)[[:space:]]/# hardening-disabled: &/I' "$f"; done
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\n' > /etc/ssh/sshd_config.d/00-hardening.conf
sshd -t && (systemctl reload ssh || systemctl restart ssh)
sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin) '
# Expected: passwordauthentication no / kbdinteractiveauthentication no / permitrootlogin without-password
