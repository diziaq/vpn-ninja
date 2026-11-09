# FACTS (researched 2026-11-05 to 2026-11-08; re-check anything that matters, things change weekly)

## Russian filtering

- Plain WireGuard and OpenVPN blocked since February 2026; 469 VPN services blocked (SecurityLab).
- TSPU lets a connection start, judges behaviour after ~16 KB, silently stalls or resets. Since
  August 2026 whole subnets of VPN-popular hosters are blocked. Uneven by ISP and region.
  (Teplitsa analysis: https://te-st.org/2026/09/30/vlessmore/)
- Data-center networks inside Russia are filtered less than home ISPs (why RU-PC on an office ISP is a
  better probe than a Russian VPS).
- Big clouds often throttled or blocked from Russia: on RU-PC, Hetzner/OVH/Linode fully blocked; AWS
  and Cloudflare were fine on this ISP.
- Mobile internet "whitelist mode" in many regions: only allowlisted IPs reachable; no tunnel helps.
- Many Russian apps detect an active VPN: split tunnelling for Russian services is required.
- A SIM arriving from abroad may get no mobile data/SMS for up to 24 h (captcha link can lift it).
- Legal (not legal advice): no fine for merely using a VPN; fines for advertising VPNs, for
  knowingly searching extremist materials (KoAP 13.53, 3-5k RUB); VPN use is an aggravating
  circumstance in crimes; VPN *service owners* must connect to RKN's system (fines up to 8 mln RUB),
  so keep friends' access small, temporary, free.
- Since 2026 Russian hosting providers may not host VPN infrastructure (anti-fraud package); a further
  ban from 2028-03-01 is proposed.

## Protocols and software

- Xray-core current release seen: 26.10.31. `xray x25519` prints `PrivateKey:` and
  `Password (PublicKey):`. Reality on non-443 ports triggers a warning.
- AmneziaWG 1.5 and 2.0 are vulnerable to blocking; Amnezia recommends 3.1 for self-hosted; 2.0 and 3.1
  share one container (app cannot run both). Routers (Keenetic, OpenWrt, GL.iNet) do not support AWG 3.x.
  (https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted/)
- Podkop: beta, needs OpenWrt 24.10+, URLTest auto-switch across VLESS links; URLTest does not accept
  XHTTP. (https://github.com/itdoginfo/podkop; subscription helper:
  https://github.com/Naz1anmak/podkop-urltest-subscription)
- RealiTLScanner authors advise not to scan from cloud servers (flag risk).

## Hardware

- GL-MT3000 Beryl AX: MediaTek MT7981B dual-core, 512 MB RAM, Wi-Fi 6, 2.5G WAN + 1G LAN, USB 3.0,
  USB-C 5 V / 3 A (no battery; works from a USB-C PD power bank of 15 W+), ~8 W typical. Official
  OpenWrt supported (25.12.5 current). Official store price $86.90; GL supports firmware 2 years after
  the last production batch. Stock firmware admin at http://192.168.8.1; SSID/key on the bottom label.
- GL-MT3000 regional versions (checked 2026-11-09): only two exist, **CN** (mainland China) and
  **Global**; "international" and "global" are names for the same Global version. GL.iNet staff: CN units lack the VPN
  and AdGuard Home features; Taobao/Tmall sell only CN; no official CN-to-Global conversion after
  2023-04 ("No, this isn't supported", 2025-06). How to tell: a CN unit comes with Chinese packaging and
  manual, and its stock admin UI has no VPN menu. CN units also turned up on Lazada Thailand.
  User reports only (UNVERIFIED): the region code sits in the Factory partition (offset 0x88), and
  vanilla OpenWrt flashes and works on CN units "the same as others". No source covers the Wi-Fi
  regulatory domain on CN units under vanilla OpenWrt.
  (https://forum.gl-inet.com/t/statement-on-the-purchase-of-products-in-mainland-china/29186,
  https://forum.openwrt.org/t/converting-gl-inet-mt3000-beryl-ax-from-cn-to-global/165159)
- GL-MT3600BE Beryl 7: official OpenWrt only since 25.12.5; MT7990 Wi-Fi driver still maturing
  (https://openwrt.org/toh/gl.inet/gl-mt3600be). Not used (D-06).
- GL.iNet official store does not ship to Russia. Georgian shop phone-ge.com looked like a scraped
  doorway shop (no legal details, identical prices across products): avoid prepayment there.

## Hosters

- Time4VPS: Lithuania; Linux VPS (KVM) plans; VPN explicitly an allowed use; 30-day money-back;
  payments card/PayPal/wire/Alipay/crypto; late payment: suspend +1 day, terminate +3, delete +7.
  Forbids VPN/proxy while ordering. Looking glass: https://lg.time4vps.com
- BuyVM: Luxembourg; Slice 1024 $3.50/mo, 2048 $7; refund only within 3 days and only card/PayPal;
  frequent out-of-stock with a Cloudzy banner; new-account verification can delay.
  Test file: https://speedtest.lu.buyvm.net/100MB.test
- Vultr: hourly; card link without deposit possible (some cards need $5); Destroy to stop billing.
  Test files: https://<code>-ping.vultr.com/vultr.com.100MB.bin (Frankfurt froze from RU-PC).
