include config.mk

GENERATED = build/99-tanmatsu.rules \
            build/rfc2217proxy-p4.service \
            build/rfc2217proxy-p6.service \
            build/badgelinkproxy.service \
            build/tanmatsu-tunnel.service

.PHONY: all install uninstall clean check

all: $(GENERATED)

build:
	mkdir -p build

# Generate udev rules
#
# For ESP32 JTAG/serial: match any 303a:1001 device by kernel name.
# Each ttyACM device gets its own rfc2217proxy@ instance with a
# unique port. The first device gets P4_PORT, the second P6_PORT.
#
# The SSH tunnel is triggered by any ESP32 JTAG/serial device.
build/99-tanmatsu.rules: config.mk | build
	@echo "Generating udev rules..."
	@echo '# Tanmatsu ESP32 JTAG/serial debug units' > $@
	@echo '# P4 ($(P4_DEV)) -> port $(P4_PORT), P6 ($(P6_DEV)) -> port $(P6_PORT)' >> $@
	@echo 'ACTION=="add", KERNEL=="$(P4_DEV)", SUBSYSTEM=="tty", ATTRS{idVendor}=="$(ESP_VID)", ATTRS{idProduct}=="$(ESP_PID)", TAG+="systemd", ENV{SYSTEMD_WANTS}="rfc2217proxy-p4.service"' >> $@
	@echo 'ACTION=="add", KERNEL=="$(P6_DEV)", SUBSYSTEM=="tty", ATTRS{idVendor}=="$(ESP_VID)", ATTRS{idProduct}=="$(ESP_PID)", TAG+="systemd", ENV{SYSTEMD_WANTS}="rfc2217proxy-p6.service tanmatsu-tunnel.service"' >> $@
	@echo '' >> $@
	@echo '# Tanmatsu BadgeLink (P4 in badgelink mode)' >> $@
	@echo 'ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="$(BADGELINK_VID)", ATTR{idProduct}=="$(BADGELINK_PID)", TAG+="systemd", ENV{SYSTEMD_WANTS}="badgelinkproxy.service"' >> $@

# P4 service
build/rfc2217proxy-p4.service: config.mk | build
	@echo "Generating P4 service..."
	@printf '[Unit]\n' > $@
	@printf 'Description=RFC2217 proxy for Tanmatsu P4\n' >> $@
	@printf 'BindsTo=dev-$(P4_DEV).device\n' >> $@
	@printf 'After=dev-$(P4_DEV).device\n' >> $@
	@printf 'Conflicts=badgelinkproxy.service\n' >> $@
	@printf '\n[Service]\nType=simple\n' >> $@
	@printf 'ExecStart=/usr/local/bin/rfc2217proxy -d /dev/$(P4_DEV) -p $(P4_PORT) -b $(P4_BAUD)\n' >> $@

# P6 service
build/rfc2217proxy-p6.service: config.mk | build
	@echo "Generating P6 service..."
	@printf '[Unit]\n' > $@
	@printf 'Description=RFC2217 proxy for Tanmatsu P6\n' >> $@
	@printf 'BindsTo=dev-$(P6_DEV).device\n' >> $@
	@printf 'After=dev-$(P6_DEV).device\n' >> $@
	@printf '\n[Service]\nType=simple\n' >> $@
	@printf 'ExecStart=/usr/local/bin/rfc2217proxy -d /dev/$(P6_DEV) -p $(P6_PORT) -b $(P6_BAUD)\n' >> $@

# Generate BadgeLink service
# BadgeLink is a raw USB device (no /dev node), so we can't use BindsTo.
# The service is started by udev and stopped when manually stopped or
# when badgelinkproxy exits (the device disconnects → libusb fails → exit).
build/badgelinkproxy.service: config.mk | build
	@echo "Generating BadgeLink service..."
	@printf '[Unit]\n' > $@
	@printf 'Description=BadgeLink USB-to-TCP proxy for Tanmatsu\n' >> $@
	@printf 'Conflicts=rfc2217proxy-p4.service\n' >> $@
	@printf '\n[Service]\nType=simple\n' >> $@
	@printf 'ExecStart=/usr/local/bin/badgelinkproxy -p $(BADGELINK_PORT)\n' >> $@

# Generate SSH tunnel service
build/tanmatsu-tunnel.service: config.mk | build
	@echo "Generating SSH tunnel service..."
	@printf '[Unit]\n' > $@
	@printf 'Description=SSH reverse tunnel for Tanmatsu serial ports\n' >> $@
	@printf 'BindsTo=dev-$(P6_DEV).device\n' >> $@
	@printf 'After=dev-$(P6_DEV).device\n' >> $@
	@printf 'After=network-online.target\n' >> $@
	@printf 'Wants=network-online.target\n' >> $@
	@printf '\n[Service]\n' >> $@
	@printf 'User=$(LOCAL_USER)\n' >> $@
	@printf 'Environment=HOME=$(LOCAL_HOME)\n' >> $@
	@printf 'ExecStart=/usr/bin/ssh -R $(P4_PORT):127.0.0.1:$(P4_PORT) -R $(P6_PORT):127.0.0.1:$(P6_PORT) -R $(BADGELINK_PORT):127.0.0.1:$(BADGELINK_PORT) -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o BatchMode=yes $(REMOTE_USER)@$(REMOTE_HOST)\n' >> $@
	@printf 'Restart=on-failure\nRestartSec=5\n' >> $@

# Check prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v rfc2217proxy >/dev/null 2>&1 || { echo "ERROR: rfc2217proxy not installed (cd ~/src/badgefs && make && sudo make install)"; exit 1; }
	@command -v badgelinkproxy >/dev/null 2>&1 || { echo "ERROR: badgelinkproxy not installed (cd ~/src/badgefs && make && sudo make install)"; exit 1; }
	@echo "OK"

# Install (requires root)
install: check $(GENERATED)
	@if [ "$$(id -u)" -ne 0 ]; then echo "Error: run with sudo"; exit 1; fi
	@echo "=== Installing badgenet services ==="
	systemctl stop rfc2217proxy-p4.service 2>/dev/null || true
	systemctl stop rfc2217proxy-p6.service 2>/dev/null || true
	systemctl stop 'rfc2217proxy@*.service' 2>/dev/null || true
	systemctl stop badgelinkproxy.service 2>/dev/null || true
	systemctl stop tanmatsu-tunnel.service 2>/dev/null || true
	# Clean up old template service and helper
	rm -f /etc/systemd/system/rfc2217proxy@.service
	rm -f /usr/local/bin/rfc2217proxy-start
	# Install
	install -m 644 build/99-tanmatsu.rules /etc/udev/rules.d/99-tanmatsu.rules
	install -m 644 build/rfc2217proxy-p4.service /etc/systemd/system/
	install -m 644 build/rfc2217proxy-p6.service /etc/systemd/system/
	install -m 644 build/badgelinkproxy.service /etc/systemd/system/
	install -m 644 build/tanmatsu-tunnel.service /etc/systemd/system/
	systemctl daemon-reload
	udevadm control --reload-rules
	udevadm trigger --subsystem-match=tty
	udevadm trigger --subsystem-match=usb
	@echo ""
	@echo "=== badgenet installation complete ==="
	@echo ""
	@echo "Services start/stop automatically when any Tanmatsu is"
	@echo "connected/disconnected. No serial number configuration needed."
	@echo ""
	@echo "On the remote server ($(REMOTE_USER)@$(REMOTE_HOST)), use:"
	@echo "  P4 serial:  rfc2217://localhost:$(P4_PORT)"
	@echo "  P6 serial:  rfc2217://localhost:$(P6_PORT)"
	@echo "  BadgeLink:  localhost:$(BADGELINK_PORT)"

# Uninstall (requires root)
uninstall:
	@if [ "$$(id -u)" -ne 0 ]; then echo "Error: run with sudo"; exit 1; fi
	@echo "=== Uninstalling badgenet services ==="
	systemctl stop rfc2217proxy-p4.service 2>/dev/null || true
	systemctl stop rfc2217proxy-p6.service 2>/dev/null || true
	systemctl stop 'rfc2217proxy@*.service' 2>/dev/null || true
	systemctl stop badgelinkproxy.service 2>/dev/null || true
	systemctl stop tanmatsu-tunnel.service 2>/dev/null || true
	rm -f /etc/systemd/system/rfc2217proxy-p4.service
	rm -f /etc/systemd/system/rfc2217proxy-p6.service
	rm -f /etc/systemd/system/rfc2217proxy@.service
	rm -f /etc/systemd/system/badgelinkproxy.service
	rm -f /etc/systemd/system/tanmatsu-tunnel.service
	rm -f /etc/udev/rules.d/99-tanmatsu.rules
	rm -f /usr/local/bin/rfc2217proxy-start
	systemctl daemon-reload
	udevadm control --reload-rules
	@echo "Done"

clean:
	rm -rf build
