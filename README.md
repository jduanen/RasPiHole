# RasPiHole: RaspberryPi-based Pi-hole DNS Server with Unbound

A Raspberry Pi 3B running Pi-hole (DNS sinkhole + ad blocker) and Unbound (recursive
resolver), serving DNS and DHCP to the home LAN/WLAN.

## Quick Start

```bash
# From this machine — copies config files and runs the installer on the Pi
./deploy.sh [jdn@rpihole.local]
```

After the script finishes, follow the **DHCP Cutover** steps it prints, then verify
with the commands in [Verification](#verification) below.

---

# Hardware

- Raspberry Pi 3B (1 GB DRAM)
- uSD card
  - Critical: reliable and fast
  - Aim for 32–128 GB, Class 10/UHS-I minimum
    - Avoid A2-rated cards on Pi 3B — underperform due to limited controller support
  - SanDisk Extreme Pro (A1-rated, U3/V30) is a good choice
    - ~20 MB/s practical speeds; best IOzone scores for Pi 3B+
    - SanDisk excels for OS logging/boot without corruption risks
  - Pi 3B's SD interface caps at ~20–25 MB/s; endurance (TBW) and random I/O matter more than peak speed
  - Official recommendations: SanDisk Ultra, Samsung EVO Select
- PSU: official Raspberry Pi supply (critical — use a robust one)

---

# Software

## Manual Installation and Configuration

Steps below document what `install.sh` automates. Follow them if you prefer a manual setup.

1. **Install OS on uSD card**
   - Use the latest `raspi-imager`
   - Choose Raspberry Pi OS Lite (64-bit) — Trixie
   - Set hostname, enable SSH, disable Wi-Fi

2. **Set a DHCP reservation in your router** for the Pi's MAC → `192.168.166.2`

3. **Log in and update the system**
   ```bash
   ssh jdn@rpihole.local
   sudo apt update && sudo apt upgrade -y
   ```

4. **Configure a static IP** (Pi OS Bookworm/Trixie uses NetworkManager, not dhcpcd)
   ```bash
   # Find the ethernet device and its connection profile
   nmcli dev          # note the DEVICE name for type 'ethernet' (e.g. eth0)
   nmcli con show     # find the NAME whose DEVICE column matches

   # Replace <conn> with that name (e.g. "Wired connection 1")
   sudo nmcli con mod "<conn>" \
       ipv4.method manual \
       ipv4.addresses "192.168.166.2/24" \
       ipv4.gateway "192.168.166.1" \
       ipv4.dns "127.0.0.1"
   sudo nmcli con up "<conn>"
   ```

5. **Install and configure Unbound**
   ```bash
   sudo apt install unbound dnsutils -y
   sudo cp etc/unbound/unbound.conf.d/pi-hole.conf /etc/unbound/unbound.conf.d/
   sudo systemctl enable unbound
   sudo systemctl restart unbound
   ```
   Verify:
   ```bash
   dig pi-hole.net @127.0.0.1 -p 5335
   ```
   Should return a valid answer.

6. **Install Pi-hole**
   ```bash
   curl -sSL https://install.pi-hole.net | bash
   ```
   In the interactive installer:
   - Upstream DNS → Custom → `127.0.0.1#5335`
   - Enable DHCP: yes — range `192.168.166.100` to `192.168.166.250`

7. **Verify the stack** — see [Verification](#verification) below.

8. **DHCP cutover** — see [DHCP Cutover](#dhcp-cutover) below.

9. **Access the web UI**
   - `http://192.168.166.2/admin` (or `http://rpihole.local/admin`)
   - Reset password: `pihole -a -p`

10. **Add recommended blocklists** — in Admin → Adlists:
    - `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` (default)
    - `https://oisd.nl/` — comprehensive, well-maintained

---

## DHCP Cutover

Pi-hole's built-in DHCP (powered by FTL/dnsmasq) serves all LAN/WLAN leases.
**Two DHCP servers on the same subnet will conflict** — cut over carefully:

1. Log into your router and **disable its DHCP server**.
2. Pi-hole DHCP is already active after install (range: `192.168.166.100–250`).
3. Reconnect each client (or wait for lease expiry) so it picks up a Pi-hole lease.
4. Verify active leases in Admin → DHCP.

Static IP addresses below `.100` (e.g., `.2` for the Pi, `.7` for DGX Spark) are
outside the dynamic range and safe from conflicts.

---

## Verification

```bash
# Full DNS stack (Pi-hole → Unbound → root servers)
dig pi-hole.net @192.168.166.2

# Ad blocking — should return 0.0.0.0
dig doubleclick.net @192.168.166.2

# Unbound direct (run on the Pi)
dig pi-hole.net @127.0.0.1 -p 5335
```

---

## Configuration Files

| Repo path | Deployed to |
|---|---|
| `etc/unbound/unbound.conf.d/pi-hole.conf` | `/etc/unbound/unbound.conf.d/pi-hole.conf` |
| `etc/pihole/setupVars.conf` | `/etc/pihole/setupVars.conf` |

### Unbound config (`etc/unbound/unbound.conf.d/pi-hole.conf`)

```yaml
server:
    verbosity: 0
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes
    do-ip6: no

    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: no
    edns-buffer-size: 1472
    prefetch: yes
    num-threads: 1
    so-rcvbuf: 1m

    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10
```

---

## Architecture Notes

### DNS flow

```
LAN client → Pi-hole (port 53) → Unbound (port 5335) → DNS root servers
                ↓
         ad/tracker blocked → 0.0.0.0
```

### Why Unbound instead of a forwarding resolver?

- **Recursive**: walks the DNS tree itself — no Google/Cloudflare required
- **Private**: queries go directly to authoritative root servers
- **Cached**: results are cached locally for speed
- dnsmasq is simpler (forwarding only + DHCP), but Unbound gives full DNSSEC and recursion

### Why Pi-hole for DHCP?

Pi-hole's integrated DHCP (via FTL/dnsmasq) resolves client hostnames automatically,
so every device on the LAN appears by name in Pi-hole's query log. Running a separate
dnsmasq instance alongside Pi-hole will conflict — don't do it.
