# Mac commands (run in Terminal; prompt looks like `~]`)

Server A: `<SERVER_A_IP>` (Time4VPS, Lithuania). SSH key: `~/.ssh/vpn_servers` (ed25519, has a passphrase).
Tip: disconnect GlobalProtect before managing personal servers (otherwise the server sees the corporate IP <EMPLOYER_NET> and the employer sees the connection).

## SSH key (already created on 2026-11-05)
    ssh-keygen -t ed25519 -f ~/.ssh/vpn_servers -C vpn-servers
    cat ~/.ssh/vpn_servers.pub

## New server: put key, log in
    ssh-copy-id -i ~/.ssh/vpn_servers.pub root@SERVER-IP
    ssh -i ~/.ssh/vpn_servers root@SERVER-IP
    # If "REMOTE HOST IDENTIFICATION HAS CHANGED" after a reinstall:
    ssh-keygen -R SERVER-IP

## Copy a script to the server and run it
    scp -i ~/.ssh/vpn_servers server/setup-server.sh root@SERVER-IP:/root/
    ssh -i ~/.ssh/vpn_servers root@SERVER-IP 'bash /root/setup-server.sh'

## Verify password login is really disabled (clean test, ignores local ssh config/agent)
    ssh -F /dev/null -o IdentityAgent=none -o PubkeyAuthentication=no -o PreferredAuthentications=password root@SERVER-IP
    # Expected: "Permission denied (publickey)."

## Check public DNS of a host (bypasses the corporate VPN resolver)
    dig +short HOSTNAME @1.1.1.1
