include config.mk

ifeq ($(strip $(DEVICES)),)
$(error DEVICES is empty in config.mk)
endif
$(foreach d,$(DEVICES),\
  $(if $($(d)_P4_SERIAL),,$(error $(d)_P4_SERIAL is not set in config.mk))\
  $(if $($(d)_C6_SERIAL),,$(error $(d)_C6_SERIAL is not set in config.mk)))

GENERATED = build/99-tanmatsu.rules \
            build/rfc2217proxy-p4@.service \
            build/rfc2217proxy-c6@.service \
            build/badgelinkproxy.service \
            build/tanmatsu-tunnel.service

# Unit names left over from earlier layouts, removed on install/uninstall
OBSOLETE_UNITS = rfc2217proxy.service \
                 rfc2217proxy@.service \
                 rfc2217proxy-p4.service \
                 rfc2217proxy-p6.service \
                 rfc2217proxy-c6.service

.PHONY: all install uninstall clean check stop-all retrigger

# Every USB serial number this project's rules claim a device by.
TRIGGER_SERIALS = $(foreach d,$(DEVICES),$($(d)_P4_SERIAL) $($(d)_C6_SERIAL))

all: $(GENERATED)

build:
	mkdir -p build

# Generate udev rules
#
# Devices are matched by USB serial number, not by kernel name: the P4 and
# the C6 are indistinguishable in their USB descriptors, and ttyACM
# numbering depends on enumeration order. Matching ttyACM0/ttyACM1 meant
# the C6 could be handed the P4's proxy port whenever the P4 was absent or
# in BadgeLink mode.
#
# Each tty starts a template instance named after the device node it
# actually got (%k), so the service can bind to the right .device unit.
#
# Every device in DEVICES gets the same set of rules and therefore the same
# services and ports; only one Tanmatsu may be connected at a time.
build/99-tanmatsu.rules: config.mk | build
	@echo "Generating udev rules..."
	@echo '# Tanmatsu USB devices, identified by USB serial number (MAC address).' > $@
	@echo '#' >> $@
	@echo '# P4 -> port $(P4_PORT), C6 -> port $(C6_PORT), BadgeLink -> port $(BADGELINK_PORT)' >> $@
	@echo '#' >> $@
	@echo '# Both chips enumerate as $(ESP_VID):$(ESP_PID) with identical descriptors, so the' >> $@
	@echo '# serial number is the only reliable discriminator. Each match also gets a' >> $@
	@echo '# stable /dev symlink for manual esptool use.' >> $@
	@echo '#' >> $@
	@echo '# All listed devices share the same ports: connect only one at a time.' >> $@
	@{ $(foreach d,$(DEVICES),\
		echo ''; \
		echo '# $(d): P4 $($(d)_P4_SERIAL), C6 $($(d)_C6_SERIAL)'; \
		echo 'ACTION=="add", SUBSYSTEM=="tty", ATTRS{idVendor}=="$(ESP_VID)", ATTRS{idProduct}=="$(ESP_PID)", ATTRS{serial}=="$($(d)_P4_SERIAL)", SYMLINK+="tanmatsu_p4", TAG+="systemd", ENV{SYSTEMD_WANTS}="rfc2217proxy-p4@%k.service"'; \
		echo 'ACTION=="add", SUBSYSTEM=="tty", ATTRS{idVendor}=="$(ESP_VID)", ATTRS{idProduct}=="$(ESP_PID)", ATTRS{serial}=="$($(d)_C6_SERIAL)", SYMLINK+="tanmatsu_c6", TAG+="systemd", ENV{SYSTEMD_WANTS}="rfc2217proxy-c6@%k.service"'; \
		echo '# $(d) BadgeLink (P4 in BadgeLink mode -- same chip, same serial number)'; \
		echo 'ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="$(BADGELINK_VID)", ATTR{idProduct}=="$(BADGELINK_PID)", ATTR{serial}=="$($(d)_P4_SERIAL)", TAG+="systemd", ENV{SYSTEMD_WANTS}="badgelinkproxy.service"'; \
	) } >> $@

# P4 service (template, instance = tty device name)
#
# Wants= pulls up the SSH tunnel: the tunnel follows whichever Tanmatsu
# device is present rather than being anchored to the C6.
build/rfc2217proxy-p4@.service: config.mk | build
	@echo "Generating P4 service..."
	@echo '[Unit]' > $@
	@echo 'Description=RFC2217 proxy for Tanmatsu P4 on %I' >> $@
	@echo 'BindsTo=dev-%i.device' >> $@
	@echo 'After=dev-%i.device' >> $@
	@echo 'Conflicts=badgelinkproxy.service' >> $@
	@echo 'Wants=tanmatsu-tunnel.service' >> $@
	@echo '' >> $@
	@echo '[Service]' >> $@
	@echo 'Type=simple' >> $@
	@echo 'ExecStart=/usr/local/bin/rfc2217proxy -d /dev/%i -p $(P4_PORT) -b $(P4_BAUD)' >> $@

# C6 service (template, instance = tty device name)
build/rfc2217proxy-c6@.service: config.mk | build
	@echo "Generating C6 service..."
	@echo '[Unit]' > $@
	@echo 'Description=RFC2217 proxy for Tanmatsu C6 on %I' >> $@
	@echo 'BindsTo=dev-%i.device' >> $@
	@echo 'After=dev-%i.device' >> $@
	@echo 'Wants=tanmatsu-tunnel.service' >> $@
	@echo '' >> $@
	@echo '[Service]' >> $@
	@echo 'Type=simple' >> $@
	@echo 'ExecStart=/usr/local/bin/rfc2217proxy -d /dev/%i -p $(C6_PORT) -b $(C6_BAUD)' >> $@

# Generate BadgeLink service
# BadgeLink is a raw USB device (no /dev node), so we can't use BindsTo.
# The service is started by udev and stopped when manually stopped or
# when badgelinkproxy exits (the device disconnects -> libusb fails -> exit).
#
# The reverse Conflicts= against the P4 proxy is declared by the P4
# template instead; systemd applies Conflicts= symmetrically, and the
# instance name is not known here.
build/badgelinkproxy.service: config.mk | build
	@echo "Generating BadgeLink service..."
	@echo '[Unit]' > $@
	@echo 'Description=BadgeLink USB-to-TCP proxy for Tanmatsu' >> $@
	@echo 'Wants=tanmatsu-tunnel.service' >> $@
	@echo '' >> $@
	@echo '[Service]' >> $@
	@echo 'Type=simple' >> $@
	@echo 'ExecStart=/usr/local/bin/badgelinkproxy -p $(BADGELINK_PORT)' >> $@

# Generate SSH tunnel service
#
# The tunnel is deliberately not bound to any single device. It used to
# BindsTo the C6's tty, which meant no tunnel at all whenever an
# application on the P4 powered the radio processor down. Instead every
# proxy service Wants= this unit, and StopWhenUnneeded= drops the tunnel
# once the last of them has gone away.
build/tanmatsu-tunnel.service: config.mk | build
	@echo "Generating SSH tunnel service..."
	@echo '[Unit]' > $@
	@echo 'Description=SSH reverse tunnel for Tanmatsu serial ports' >> $@
	@echo 'After=network-online.target' >> $@
	@echo 'Wants=network-online.target' >> $@
	@echo 'StopWhenUnneeded=yes' >> $@
	@echo '' >> $@
	@echo '[Service]' >> $@
	@echo 'User=$(LOCAL_USER)' >> $@
	@echo 'Environment=HOME=$(LOCAL_HOME)' >> $@
	@echo 'ExecStart=/usr/bin/ssh -R $(P4_PORT):127.0.0.1:$(P4_PORT) -R $(C6_PORT):127.0.0.1:$(C6_PORT) -R $(BADGELINK_PORT):127.0.0.1:$(BADGELINK_PORT) -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o BatchMode=yes $(REMOTE_USER)@$(REMOTE_HOST)' >> $@
	@echo 'Restart=on-failure' >> $@
	@echo 'RestartSec=5' >> $@

# Check prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v rfc2217proxy >/dev/null 2>&1 || { echo "ERROR: rfc2217proxy not installed (cd ~/src/badgefs && make && sudo make install)"; exit 1; }
	@command -v badgelinkproxy >/dev/null 2>&1 || { echo "ERROR: badgelinkproxy not installed (cd ~/src/badgefs && make && sudo make install)"; exit 1; }
	@echo "OK"

# Stop every unit this project has ever installed, current or obsolete
stop-all:
	@for u in 'rfc2217proxy-p4@*.service' 'rfc2217proxy-c6@*.service' \
	          badgelinkproxy.service tanmatsu-tunnel.service $(OBSOLETE_UNITS); do \
		systemctl stop "$$u" 2>/dev/null || true; \
	done

# Install (requires root)
install: check $(GENERATED)
	@if [ "$$(id -u)" -ne 0 ]; then echo "Error: run with sudo"; exit 1; fi
	@echo "=== Installing badgenet services ==="
	$(MAKE) stop-all
	# Clean up units and helpers from earlier layouts
	@for u in $(OBSOLETE_UNITS); do rm -f "/etc/systemd/system/$$u"; done
	rm -f /usr/local/bin/rfc2217proxy-start
	# Install
	install -m 644 build/99-tanmatsu.rules /etc/udev/rules.d/99-tanmatsu.rules
	install -m 644 'build/rfc2217proxy-p4@.service' /etc/systemd/system/
	install -m 644 'build/rfc2217proxy-c6@.service' /etc/systemd/system/
	install -m 644 build/badgelinkproxy.service /etc/systemd/system/
	install -m 644 build/tanmatsu-tunnel.service /etc/systemd/system/
	systemctl daemon-reload
	udevadm control --reload-rules
	# Re-evaluate the connected devices so they pick up the new rules.
	$(MAKE) retrigger
	@echo ""
	@echo "=== badgenet installation complete ==="
	@echo ""
	@echo "Services start/stop automatically when the Tanmatsu is"
	@echo "connected/disconnected. The SSH tunnel now follows any"
	@echo "Tanmatsu device, so it also runs when the C6 is powered down."
	@echo ""
	@echo "Configured devices (connect one at a time):"
	@$(foreach d,$(DEVICES),echo "  $(d): P4 $($(d)_P4_SERIAL), C6 $($(d)_C6_SERIAL)";)
	@echo ""
	@echo "On the remote server ($(REMOTE_USER)@$(REMOTE_HOST)), use:"
	@echo "  P4 serial:  rfc2217://localhost:$(P4_PORT)"
	@echo "  C6 serial:  rfc2217://localhost:$(C6_PORT)"
	@echo "  BadgeLink:  localhost:$(BADGELINK_PORT)"

# Uninstall (requires root)
uninstall:
	@if [ "$$(id -u)" -ne 0 ]; then echo "Error: run with sudo"; exit 1; fi
	@echo "=== Uninstalling badgenet services ==="
	$(MAKE) stop-all
	rm -f '/etc/systemd/system/rfc2217proxy-p4@.service'
	rm -f '/etc/systemd/system/rfc2217proxy-c6@.service'
	rm -f /etc/systemd/system/badgelinkproxy.service
	rm -f /etc/systemd/system/tanmatsu-tunnel.service
	@for u in $(OBSOLETE_UNITS); do rm -f "/etc/systemd/system/$$u"; done
	rm -f /etc/udev/rules.d/99-tanmatsu.rules
	rm -f /usr/local/bin/rfc2217proxy-start
	systemctl daemon-reload
	udevadm control --reload-rules
	# Deleting the rules file is not enough: udev leaves a plugged-in
	# device alone, so the state the BadgeLink rule gave it survives.
	$(MAKE) retrigger
	@echo "Done"

retrigger:
	# Replay remove+add for the Tanmatsu devices only, so udev rebuilds
	# their properties and tags from the rules that are actually installed
	# now. udevadm control --reload-rules only reloads the rule files; it
	# leaves a plugged-in device alone, so the TAG+="systemd" and
	# ENV{SYSTEMD_WANTS} that the BadgeLink rule gave it survive an
	# uninstall and keep their .device units loaded. A plain "change"
	# trigger would inherit those properties instead of dropping them.
	@for s in $(TRIGGER_SERIALS); do \
		udevadm trigger --action=remove --property-match=ID_SERIAL_SHORT=$$s || true; \
	done
	@udevadm settle --timeout=10 || true
	@# --action=add is required: the rules match ACTION=="add", and the
	@# default trigger action is "change", which would not fire them.
	@udevadm trigger --action=add --subsystem-match=tty
	@udevadm trigger --action=add --subsystem-match=usb
	@udevadm settle --timeout=10 || true

clean:
	rm -rf build
