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

# ESP32-P4 (application processor)
P4_DEV         = ttyACM0
P4_PORT        = 4001
P4_BAUD        = 115200

# ESP32-P6 (radio processor) — always present, used to anchor SSH tunnel
P6_DEV         = ttyACM1
P6_PORT        = 4002
P6_BAUD        = 115200

# BadgeLink USB proxy port
BADGELINK_PORT = 4003

# BadgeLink USB IDs
BADGELINK_VID  = 16d0
BADGELINK_PID  = 0f9a

# ESP32 USB JTAG/Serial debug unit IDs (shared by P4 and P6)
ESP_VID        = 303a
ESP_PID        = 1001
