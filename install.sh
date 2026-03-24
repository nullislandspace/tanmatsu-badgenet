#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Tanmatsu rfc2217proxy + badgelinkproxy + SSH tunnel installer ==="
echo ""

# Check for root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)."
    exit 1
fi

# Check rfc2217proxy is installed (built and installed from badgefs)
if ! command -v rfc2217proxy >/dev/null 2>&1; then
    echo "Error: rfc2217proxy is not installed."
    echo "Build and install it from the badgefs project:"
    echo "  cd ~/src/badgefs && make && sudo make install"
    exit 1
fi

# Check badgelinkproxy is installed (built and installed from badgefs)
if ! command -v badgelinkproxy >/dev/null 2>&1; then
    echo "Error: badgelinkproxy is not installed."
    echo "Build and install it from the badgefs project:"
    echo "  cd ~/src/badgefs && make && sudo make install"
    exit 1
fi

# Disable the default ser2net service (in case it was previously used)
echo "--- Disabling default ser2net service..."
systemctl disable --now ser2net.service 2>/dev/null || true

# Stop old ser2net-based services if running
systemctl stop ser2net-tanmatsu-p4.service 2>/dev/null || true
systemctl stop ser2net-tanmatsu-p6.service 2>/dev/null || true

# Clean up old ser2net config files
rm -f /etc/ser2net-tanmatsu-p4.yaml
rm -f /etc/ser2net-tanmatsu-p6.yaml

# Install udev rules
echo "--- Installing udev rules..."
cp "$SCRIPT_DIR/99-tanmatsu.rules" /etc/udev/rules.d/99-tanmatsu.rules

# Install systemd service files
echo "--- Installing systemd service files..."
cp "$SCRIPT_DIR/ser2net-tanmatsu-p4.service" /etc/systemd/system/ser2net-tanmatsu-p4.service
cp "$SCRIPT_DIR/ser2net-tanmatsu-p6.service" /etc/systemd/system/ser2net-tanmatsu-p6.service
cp "$SCRIPT_DIR/badgelinkproxy.service" /etc/systemd/system/badgelinkproxy.service
cp "$SCRIPT_DIR/tanmatsu-tunnel.service" /etc/systemd/system/tanmatsu-tunnel.service

# Reload systemd and udev
echo "--- Reloading systemd and udev..."
systemctl daemon-reload
udevadm control --reload-rules
udevadm trigger --subsystem-match=tty
udevadm trigger --subsystem-match=usb

echo ""
echo "=== Installation complete ==="
echo ""
echo "All services start/stop automatically when the Tanmatsu is"
echo "connected/disconnected. No manual action needed."
echo ""
echo "On the server (cavac@cavac.at), use:"
echo "  P4 serial:  rfc2217://localhost:4000?ign_set_control"
echo "  P6 serial:  rfc2217://localhost:4001?ign_set_control"
echo "  BadgeLink:  localhost:4002"
echo ""
echo "Example:"
echo "  idf.py -p rfc2217://localhost:4000?ign_set_control flash monitor"
