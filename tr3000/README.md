# Cudy TR3000 128M ImmortalWrt Builder

This project builds firmware from `padavanonly/immortalwrt-mt798x-6.6` inside Docker. The WSL side only runs the entry commands and stores the source tree, caches, and output files.

## What Runs Where

- WSL runs `make init`, `make defconfig`, `make build`, `make shell`.
- Docker runs the build dependencies, feeds update/install, OpenWrt config generation, and firmware compilation.
- No script installs packages into WSL, changes Linux user groups, or requires `sudo` by default.

The default Docker command is `docker`. If a different environment needs sudo, override it per command:

```bash
make DOCKER="sudo docker" build
```

## First Use

Optional environment overrides:

```bash
cp .env.example .env
```

Prepare the source tree and feeds:

```bash
make init
```

Generate the Cudy TR3000 128M config. This inherits the upstream
`defconfig/mt7981-ax3000.config` MTK closed-driver/HNAT/WARP defaults, filters
out its multi-device target selection, then applies the Cudy TR3000 target and
`configs/cudy_tr3000_128m.seed` package overlay:

```bash
make defconfig
```

Build firmware:

```bash
make build
```

Firmware and build metadata are copied to `output/<date>-<source-commit>/`.

## Default Firmware Features

- Cudy TR3000 profile auto-detection from the upstream MediaTek image definitions.
- LuCI, SSH-related base support, and common network tools.
- `luci-app-ttyd` for an internal LuCI web terminal.
- `luci-theme-argon`.
- `luci-app-turboacc-mtk` for MTK LuCI network acceleration controls.
- `luci-app-nikki` from the nikki feed.
- `luci-app-upnp` and `miniupnpd`.
- `luci-app-advanced-reboot`.
- ZTE F50 USB shared-network support through RNDIS, CDC Ethernet, and CDC NCM kernel modules.

The default profile is the stock Cudy TR3000 v1 profile:

```bash
DEVICE_PROFILE=cudy_tr3000-v1
```

Do not switch to `cudy_tr3000-v1-256mb` or `cudy_tr3000-v1-ubootmod` unless your exact hardware and bootloader layout match those variants.

## Main Targets

```text
make init        Clone/update source metadata, configure feeds, validate packages
make defconfig   Generate source/.config from the upstream MT7981 defconfig plus configs/cudy_tr3000_128m.seed
make menuconfig  Open OpenWrt menuconfig inside the container
make build       Compile firmware and collect output
make output      Collect existing build output
make shell       Enter the builder container
make clean       Run OpenWrt clean
make distclean   Remove generated build state under source/
```
