# badgenet - Remote serial access for Tanmatsu

Provides RFC2217 serial proxies and an SSH reverse tunnel for remote
flashing and debugging of Tanmatsu ESP32-P4/C6 devices via esptool.

## Setup

1. Build and install the proxy binaries from the badgefs project:

```bash
cd ~/src/badgefs && make && sudo make install
```

2. Edit `config.mk` with your local user, remote server, and port settings.

   You also need the USB serial numbers of your Tanmatsu's two chips. The
   P4 and the C6 both enumerate as `303a:1001` with byte-identical USB
   descriptors, so the serial number is the only way to tell them apart.
   List them with:

```bash
for d in /sys/bus/usb/devices/*/; do
    grep -qE '303a|16d0' "$d/idVendor" 2>/dev/null &&
    echo "$(cat $d/idVendor):$(cat $d/idProduct) $(cat $d/serial)"
done
```

   The P4 is the chip that appears as `16d0:0f9a` when it is in BadgeLink
   mode; it keeps the same serial number in both modes. Everything else on
   `303a:1001` is the C6.

3. Install the badgenet services:

```bash
make
sudo make install
```

Services start and stop automatically when the Tanmatsu is connected or
disconnected.

## How detection works

Devices are matched by USB serial number rather than by kernel name.
`ttyACM0`/`ttyACM1` numbering depends on enumeration order and shifts
whenever one chip is absent or the P4 is in BadgeLink mode, which could
otherwise hand the C6 the P4's proxy port.

Each serial-matched tty starts a template instance named after the device
node it actually received, so the proxy binds to the correct device:

```
rfc2217proxy-p4@ttyACM0.service
rfc2217proxy-c6@ttyACM1.service
```

Check what is running with:

```bash
systemctl status 'rfc2217proxy-p4@*' 'rfc2217proxy-c6@*' \
                 badgelinkproxy tanmatsu-tunnel
```

Each match also creates a stable symlink, `/dev/tanmatsu_p4` and
`/dev/tanmatsu_c6`, which is convenient for driving esptool locally.

### The SSH tunnel

The tunnel is not tied to any single device. Every proxy service declares
`Wants=tanmatsu-tunnel.service`, and the tunnel uses `StopWhenUnneeded=yes`,
so it runs whenever *any* Tanmatsu device is present and stops once the
last one disappears.

This matters when an application running on the P4 powers the C6 radio
processor down: the tunnel previously anchored itself to the C6's tty and
so did not come up at all in that case. It now follows the P4 — in serial
mode or in BadgeLink mode — just as well.

Two consequences worth knowing:

- When the P4 switches between serial and BadgeLink mode with the C6 powered
  down, there may briefly be no Tanmatsu device at all. The tunnel can stop
  and be restarted; it re-establishes itself within a few seconds.
- Starting `tanmatsu-tunnel.service` by hand with no Tanmatsu connected will
  not keep it running, since nothing needs it.

## Uninstall

```bash
sudo make uninstall
```

## Remote usage

On the remote server, set the PORT variable and flash:

```bash
export PORT='rfc2217://localhost:4001'
cd ~/src/tanmatsu/tanmatsu-launcher
make install
```

You can add the export to your `~/.bashrc` to make it permanent.
