#!/usr/bin/env bash
# Installs Pi-hole + Unbound on a fresh Raspberry Pi OS Lite (64-bit) image.
# Must be run as root on the Pi itself; copy this repo's files there first via deploy.sh.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "Run as root: sudo bash install.sh"

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 1. Update system ───────────────────────────────────────────────────────
info "Updating system packages..."
apt update && apt upgrade -y

# ── 2. Static IP ──────────────────────────────────────────────────────────
DHCPCD_CONF="/etc/dhcpcd.conf"
if grep -q "^interface eth0" "$DHCPCD_CONF"; then
    info "Static IP already present in dhcpcd.conf — skipping."
else
    info "Configuring static IP in dhcpcd.conf..."
    cat >> "$DHCPCD_CONF" << 'EOF'

# RasPiHole: static IP
interface eth0
static ip_address=192.168.166.2/24
static routers=192.168.166.1
static domain_name_servers=127.0.0.1
EOF
    info "Restarting dhcpcd to apply static IP..."
    systemctl restart dhcpcd
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
echo -e "${YELLOW}  DHCP CUTOVER — do this once, in order:${NC}"
echo "  1. Log into your router and DISABLE its DHCP server."
echo "  2. Pi-hole DHCP is already active (range: 192.168.166.100–250)."
echo "  3. Reconnect/renew clients so they pick up Pi-hole leases."
echo "  4. Verify: check Pi-hole admin → DHCP for active leases."
echo
echo "  Recommended blocklists (add via Admin → Adlists):"
echo "    https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
echo "    https://oisd.nl/"
echo "════════════════════════════════════════════════════════════════"
