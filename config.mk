# Tanmatsu remote serial proxy configuration
#
# Edit these values to match your setup, then run:
#   sudo make install

# Local user account (for SSH tunnel service)
LOCAL_USER     = cavac
LOCAL_HOME     = /home/cavac

# Remote server for SSH reverse tunnel
REMOTE_USER    = cavac
REMOTE_HOST    = cavac.at

# USB serial numbers identifying each chip.
#
# The P4 and the C6 both enumerate as 303a:1001 with byte-identical USB
# descriptors -- bcdDevice, product and manufacturer strings are the same
# on both -- so the serial number (the chip's MAC address) is the only
# reliable way to tell them apart. Kernel names (ttyACM0/ttyACM1) are not:
# they depend on enumeration order and shift around whenever one chip is
# absent or the P4 is in BadgeLink mode.
#
# List the serials of your own Tanmatsu with:
#   ls /dev/serial/by-id/
# or, to see both chips including BadgeLink mode:
#   for d in /sys/bus/usb/devices/*/; do \
#       grep -qE '303a|16d0' $d/idVendor 2>/dev/null && \
#       echo "$(cat $d/idVendor):$(cat $d/idProduct) $(cat $d/serial)"; done
#
# The P4 keeps the same serial in BadgeLink mode (16d0:0f9a), so P4_SERIAL
# identifies it in both modes.
P4_SERIAL      = 30:ED:A0:E2:F4:65
C6_SERIAL      = 10:51:DB:03:73:10

# ESP32-P4 (application processor)
P4_PORT        = 4001
P4_BAUD        = 115200

# ESP32-C6 (radio processor) -- may be powered down by an application
# running on the P4, so nothing else may depend on it being present.
C6_PORT        = 4002
C6_BAUD        = 115200

# BadgeLink USB proxy port
BADGELINK_PORT = 4003

# BadgeLink USB IDs
BADGELINK_VID  = 16d0
BADGELINK_PID  = 0f9a

# ESP32 USB JTAG/Serial debug unit IDs (shared by P4 and C6)
ESP_VID        = 303a
ESP_PID        = 1001
