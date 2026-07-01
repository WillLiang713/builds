# CMCC RAX3000M NAND ImmortalWrt Builder

This project builds firmware from `padavanonly/immortalwrt-mt798x-6.6` inside Docker. It is configured for the CMCC RAX3000M NAND target with the OpenWrt U-Boot layout.

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

Generate the CMCC RAX3000M NAND config. This inherits the upstream
`defconfig/mt7981-ax3000.config` MTK closed-driver/HNAT/WARP defaults, filters
out its multi-device target selection, then applies the `cmcc_rax3000m` target
and `configs/cmcc_rax3000m_nand.seed` package overlay:

```bash
make defconfig
```

Build firmware:

```bash
make build
```

Firmware and build metadata are copied to `output/<date>-<source-commit>/`.

## Default Firmware Features

- CMCC RAX3000M `cmcc_rax3000m` profile, validated from the upstream MediaTek image definitions.
- LuCI, SSH-related base support, and common network tools.
- `luci-app-ttyd` for an internal LuCI web terminal.
- `luci-theme-argon`.
- `luci-app-turboacc-mtk` for MTK LuCI network acceleration controls.
- `luci-app-nikki` from the nikki feed.
- `luci-app-upnp` and `miniupnpd`.
- USB shared-network support through RNDIS, CDC Ethernet, and CDC NCM kernel modules.

The default profile is the CMCC RAX3000M NAND OpenWrt U-Boot profile:

```bash
DEVICE_PROFILE=cmcc_rax3000m
```

Do not use `cmcc_rax3000me` unless the hardware is explicitly RAX3000Me. Do not use `cmcc_rax3000m-nand-mtk` for a device that already has the OpenWrt U-Boot layout.

Use the generated sysupgrade firmware for normal upgrades. Do not flash `bl2`, `preloader`, `fip`, or U-Boot artifacts unless you have separately confirmed the hardware and have backups.

## Main Targets

```text
make init        Clone/update source metadata, configure feeds, validate packages
make defconfig   Generate source/.config from the upstream MT7981 defconfig plus configs/cmcc_rax3000m_nand.seed
make menuconfig  Open OpenWrt menuconfig inside the container
make build       Compile firmware and collect output
make output      Collect existing build output
make shell       Enter the builder container
make clean       Run OpenWrt clean
make distclean   Remove generated build state under source/
```
