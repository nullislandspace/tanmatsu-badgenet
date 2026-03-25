include config.mk

GENERATED = build/99-tanmatsu.rules \
            build/rfc2217proxy@.service \
            build/rfc2217proxy-start \
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
	@echo '# Tanmatsu ESP32 JTAG/serial debug units (P4 and P6)' > $@
	@echo '# Each ttyACM device gets an rfc2217proxy instance.' >> $@
	@echo '# Port assignment: first device=$(P4_PORT), second=$(P6_PORT)' >> $@
	@echo 'ACTION=="add", SUBSYSTEM=="tty", ATTRS{idVendor}=="$(ESP_VID)", ATTRS{idProduct}=="$(ESP_PID)", TAG+="systemd", ENV{SYSTEMD_WANTS}="rfc2217proxy@%k.service tanmatsu-tunnel.service"' >> $@
	@echo '' >> $@
	@echo '# Tanmatsu BadgeLink (P4 in badgelink mode)' >> $@
	@echo 'ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="$(BADGELINK_VID)", ATTR{idProduct}=="$(BADGELINK_PID)", TAG+="systemd", ENV{SYSTEMD_WANTS}="badgelinkproxy.service"' >> $@

# Template service for rfc2217proxy
# %i is the kernel device name (e.g. ttyACM0)
# Port is assigned by a helper: first device gets P4_PORT, second gets P6_PORT
build/rfc2217proxy@.service: config.mk | build
	@echo "Generating rfc2217proxy@ template service..."
	@printf '[Unit]\n' > $@
	@printf 'Description=RFC2217 proxy for %%i\n' >> $@
	@printf 'BindsTo=dev-%%i.device\n' >> $@
	@printf 'After=dev-%%i.device\n' >> $@
	@printf '\n[Service]\nType=simple\n' >> $@
	@printf 'ExecStart=/usr/local/bin/rfc2217proxy-start %%i $(P4_PORT) $(P6_PORT) $(P4_BAUD)\n' >> $@

# Helper script that assigns ports to devices
build/rfc2217proxy-start: config.mk | build
	@echo "Generating rfc2217proxy-start helper..."
	@echo '#!/bin/bash' > $@
	@echo '# Assign a unique port to each ESP32 JTAG/serial device.' >> $@
	@echo '# First device (lowest ttyACM number) gets port $$2, second gets $$3.' >> $@
	@echo 'DEV="$$1"' >> $@
	@echo 'PORT_A="$$2"' >> $@
	@echo 'PORT_B="$$3"' >> $@
	@echo 'BAUD="$$4"' >> $@
	@echo '' >> $@
	@echo '# Find all ESP32 JTAG/serial ttyACM devices, sorted' >> $@
	@echo 'DEVS=$$(for d in /sys/class/tty/ttyACM*; do' >> $@
	@echo '    name=$$(basename "$$d")' >> $@
	@echo '    vid=$$(cat "$$d/device/../idVendor" 2>/dev/null)' >> $@
	@echo '    pid=$$(cat "$$d/device/../idProduct" 2>/dev/null)' >> $@
	@echo '    [ "$$vid" = "$(ESP_VID)" ] && [ "$$pid" = "$(ESP_PID)" ] && echo "$$name"' >> $@
	@echo 'done | sort)' >> $@
	@echo '' >> $@
	@echo '# Assign port based on position' >> $@
	@echo 'PORT=$$PORT_A' >> $@
	@echo 'IDX=0' >> $@
	@echo 'for d in $$DEVS; do' >> $@
	@echo '    if [ "$$d" = "$$DEV" ]; then' >> $@
	@echo '        [ $$IDX -eq 0 ] && PORT=$$PORT_A || PORT=$$PORT_B' >> $@
	@echo '        break' >> $@
	@echo '    fi' >> $@
	@echo '    IDX=$$((IDX + 1))' >> $@
	@echo 'done' >> $@
	@echo '' >> $@
	@echo 'exec /usr/local/bin/rfc2217proxy -d "/dev/$$DEV" -p "$$PORT" -b "$$BAUD"' >> $@
	@chmod +x $@

# Generate BadgeLink service
build/badgelinkproxy.service: config.mk | build
	@echo "Generating BadgeLink service..."
	@printf '[Unit]\n' > $@
	@printf 'Description=BadgeLink USB-to-TCP proxy for Tanmatsu\n' >> $@
	@printf 'BindsTo=dev-tanmatsu_badgelink.device\n' >> $@
	@printf 'After=dev-tanmatsu_badgelink.device\n' >> $@
	@printf '\n[Service]\nType=simple\n' >> $@
	@printf 'ExecStart=/usr/local/bin/badgelinkproxy -p $(BADGELINK_PORT)\n' >> $@

# Generate SSH tunnel service
build/tanmatsu-tunnel.service: config.mk | build
	@echo "Generating SSH tunnel service..."
	@printf '[Unit]\n' > $@
	@printf 'Description=SSH reverse tunnel for Tanmatsu serial ports\n' >> $@
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
	systemctl stop 'rfc2217proxy@*.service' 2>/dev/null || true
	systemctl stop badgelinkproxy.service 2>/dev/null || true
	systemctl stop tanmatsu-tunnel.service 2>/dev/null || true
	# Install
	install -m 644 build/99-tanmatsu.rules /etc/udev/rules.d/99-tanmatsu.rules
	install -m 644 build/rfc2217proxy@.service /etc/systemd/system/
	install -m 644 build/badgelinkproxy.service /etc/systemd/system/
	install -m 644 build/tanmatsu-tunnel.service /etc/systemd/system/
	install -m 755 build/rfc2217proxy-start /usr/local/bin/
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
	systemctl stop 'rfc2217proxy@*.service' 2>/dev/null || true
	systemctl stop badgelinkproxy.service 2>/dev/null || true
	systemctl stop tanmatsu-tunnel.service 2>/dev/null || true
	# Remove badgenet files
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
