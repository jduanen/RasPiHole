#!/usr/bin/env bash
# Installs Pi-hole + Unbound on a fresh Raspberry Pi OS Lite (64-bit) image.
# Must be run as root on the Pi itself; copy this repo's files there first via deploy.sh.
set -euo pipefail
trap '' HUP  # survive SSH disconnect when the network interface bounces

LOG=/var/log/raspihole-install.log
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "Run as root: sudo bash install.sh"

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 1. Update system ───────────────────────────────────────────────────────
info "Updating system packages..."
apt update && apt upgrade -y

# ── 2. Static IP (NetworkManager — Pi OS Bookworm/Trixie) ────────────────
info "Configuring static IP via NetworkManager..."

# nmcli dev uses type 'ethernet'; nmcli con show uses '802-3-ethernet' — use dev to find the interface first
ETH_DEV=$(nmcli -t -f DEVICE,TYPE dev 2>/dev/null \
          | grep ':ethernet' | cut -d: -f1 | head -1)
[ -z "$ETH_DEV" ] && error "No ethernet device found. Check: nmcli dev"

CONN=$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null \
       | grep ":${ETH_DEV}$" | cut -d: -f1 | head -1)
[ -z "$CONN" ] && CONN=$(nmcli -t -f NAME,DEVICE con show 2>/dev/null \
       | grep ":${ETH_DEV}$" | cut -d: -f1 | head -1)
[ -z "$CONN" ] && error "No connection profile found for ${ETH_DEV}. Check: nmcli con show"

CURRENT=$(nmcli -g ipv4.addresses con show "$CONN" 2>/dev/null || true)
if [ "$CURRENT" = "192.168.166.2/24" ]; then
    info "Static IP already configured on '${CONN}' — skipping."
else
    info "Setting static IP on connection '${CONN}'..."
    nmcli con mod "$CONN" \
        ipv4.method   manual \
        ipv4.addresses "192.168.166.2/24" \
        ipv4.gateway  "192.168.166.1" \
        ipv4.dns      "127.0.0.1"

    info "Network will bounce — SSH may disconnect. Install continues in background."
    info "Follow progress: tail -f ${LOG}"
    # Detach I/O from the PTY before the bounce so the script survives losing the terminal.
    exec < /dev/null >> "$LOG" 2>&1

    nmcli con up "$CONN" || true
    sleep 3
fi

# ── 3. Install Unbound ────────────────────────────────────────────────────
info "Installing Unbound and dnsutils..."
apt install -y unbound dnsutils

# ── 4. Configure Unbound ──────────────────────────────────────────────────
info "Installing Unbound config..."
mkdir -p /etc/unbound/unbound.conf.d
cp "${SETUP_DIR}/etc/unbound/unbound.conf.d/pi-hole.conf" \
   /etc/unbound/unbound.conf.d/pi-hole.conf

# ── 5. Start Unbound ──────────────────────────────────────────────────────
info "Enabling and starting Unbound..."
systemctl enable unbound
systemctl restart unbound
sleep 3

info "Verifying Unbound (port 5335)..."
if dig pi-hole.net @127.0.0.1 -p 5335 +short +time=5 | grep -qE '[0-9]+\.[0-9]+'; then
    info "Unbound is working."
else
    error "Unbound failed to resolve. Check: journalctl -u unbound -n 30"
fi

# ── 6. Pre-configure Pi-hole ──────────────────────────────────────────────
info "Writing Pi-hole setupVars.conf..."
mkdir -p /etc/pihole
cp "${SETUP_DIR}/etc/pihole/setupVars.conf" /etc/pihole/setupVars.conf

# ── 7. Install Pi-hole ────────────────────────────────────────────────────
info "Installing Pi-hole (unattended)..."
curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended

# ── 8. Verify stack ───────────────────────────────────────────────────────
info "Verifying DNS stack..."
sleep 5  # let FTL start up

if dig pi-hole.net @127.0.0.1 +short +time=5 | grep -qE '[0-9]+\.[0-9]+'; then
    info "Pi-hole DNS resolution: OK"
else
    warn "Pi-hole DNS resolution check failed — verify manually after it fully starts."
fi

BLOCKED=$(dig doubleclick.net @127.0.0.1 +short +time=5 || true)
if echo "$BLOCKED" | grep -qE '^(0\.0\.0\.0|::)$'; then
    info "Ad blocking: OK (doubleclick.net → blocked)"
else
    warn "Ad blocking: doubleclick.net returned '${BLOCKED:-empty}' — blocklists may still be loading."
fi

# ── Done ──────────────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════════════════════"
echo "  Pi-hole + Unbound installation complete"
echo "════════════════════════════════════════════════════════════════"
echo
echo "  Web UI :  http://192.168.166.2/admin"
echo "  Reset password :  pihole -a -p"
echo
echo -e "${YELLOW}  DNS SETUP — point your router at Pi-hole:${NC}"
echo "  In the AmpliFi app: Router → Internet → DNS Server"
echo "  Set primary DNS to 192.168.166.2"
echo "  Your router keeps serving DHCP; Pi-hole handles DNS."
echo
echo "  Recommended blocklists (add via Admin → Adlists):"
echo "    https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
echo "    https://oisd.nl/"
echo "════════════════════════════════════════════════════════════════"
