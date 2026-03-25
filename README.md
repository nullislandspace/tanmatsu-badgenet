# badgenet - Remote serial access for Tanmatsu

Provides RFC2217 serial proxies and an SSH reverse tunnel for remote
flashing and debugging of Tanmatsu ESP32-P4/P6 devices via esptool.

## Setup

1. Build and install the proxy binaries from the badgefs project:

```bash
cd ~/src/badgefs && make && sudo make install
```

2. Edit `config.mk` with your local user, remote server, and port settings.

3. Install the badgenet services:

```bash
make
sudo make install
```

Services start and stop automatically when a Tanmatsu is connected or
disconnected. No serial number configuration needed — works with any
Tanmatsu device.

## Uninstall

```bash
sudo make uninstall
```

## Remote usage

On the remote server, set the PORT variable and flash:

```bash
export PORT='rfc2217://localhost:4000'
cd ~/src/tanmatsu/tanmatsu-launcher
make install
```

You can add the export to your `~/.bashrc` to make it permanent.
