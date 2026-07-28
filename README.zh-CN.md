# ImmortalWrt Builder（简体中文）

[English README](README.md)

这是一个面向 MediaTek Filogic 设备的 ImmortalWrt 固件构建器。建议从项目根目录执行所有命令。

## 环境要求与限制

Docker 是本项目的必需依赖。初始化源码、更新 feeds、生成 OpenWrt 配置、编译固件和清理操作，都会通过 docker-compose.yml 中的 builder 容器执行。宿主机不需要直接安装 OpenWrt 编译工具链。

开始前请安装并确认以下命令可用：

```bash
docker --version
docker compose version
make --version
bash --version
```

项目使用 Docker Compose v2 语法，也就是 docker compose。旧版 docker-compose 命令不是 Makefile 使用的命令。Docker 服务必须已经启动，并且当前用户有权限访问 Docker。

宿主机仍然需要 GNU Make 和 Bash，因为菜单、设备选择和可选软件包选择脚本会在宿主机启动。Windows 用户请使用 WSL2 或 Git Bash，并安装 GNU Make，同时运行 Docker Desktop；仅使用 PowerShell 不是受支持的 ./scripts/*.sh 运行方式。Docker Desktop 还必须允许访问项目所在目录。

首次初始化需要联网，用于克隆上游源码、更新 feeds 和下载外部仓库。后续编译也可能继续下载源码压缩包。source/、dl/、ccache/ 和 output/ 目录可能占用较多磁盘空间，这些目录已被 git 忽略。

脚本不会强制检查最低硬件配置。建议至少预留 30 GB 可用磁盘空间和 8 GB 内存；选择更多软件包时可能需要更多资源。Docker Desktop 资源不足时，请提高 CPU、内存和磁盘限制；内存较小时可以在 .env 中降低 JOBS。

本项目仅支持当前上游 filogic.mk 中存在的 MediaTek Filogic 设备 profile。自动识别基础 defconfig 当前处理 mt7981、mt7986 和 mt7988 DTS 名称；上游变更或其他 profile 可能需要手动设置 BASE_DEFCONFIG。本项目只负责构建固件，不负责刷写或救砖。

## 快速开始

在项目根目录执行：

```bash
cp .env.example .env
docker compose build
make
```

首次运行时，菜单会自动准备上游源码和 feeds。之后按照以下流程操作：

1. 选择设备 profile
2. 选择可选软件包
3. 编译固件

如果跳过可选软件包选择，编译时只使用默认软件包配置。

## 菜单

运行 make 后可以看到：

```text
1. Select device profile
2. Select optional packages
3. Build firmware
4. Show current configuration
5. Update upstream source and feeds
6. Clean build cache
7. Open builder shell
0. Exit
```

通常的使用顺序是：

```text
选择设备 -> 选择可选软件包 -> 编译固件
```

如果在没有选择设备时直接开始编译，脚本会先打开设备选择流程。设备列表来自当前上游文件：

```text
source/target/linux/mediatek/image/filogic.mk
```

## 配置

.env 保存当前设备选择和本地覆盖配置。可以从示例文件创建：

```bash
cp .env.example .env
```

常用变量包括：

```text
DEVICE_PROFILE=             已选择的设备 profile，由菜单写入
UPSTREAM_REPO=              上游源码仓库
UPSTREAM_REF=               分支、标签或 commit；为空时使用默认分支
BASE_DEFCONFIG=             手动指定基础 defconfig，通常留空
LOCAL_UID=                 容器内文件使用的宿主机用户 ID
LOCAL_GID=                 容器内文件使用的宿主机组 ID
JOBS=                       编译并行任务数
BUILD_VERBOSE=0             设置为 1 时输出详细编译日志
```

Linux 用户可以用 id -u 和 id -g 查看自己的用户和组 ID，并将结果填入 .env 的 LOCAL_UID 和 LOCAL_GID，避免容器生成的文件属于错误的用户。

默认软件包配置位于 configs/default.seed。设备专属配置可以放在 configs/devices/<DEVICE_PROFILE>.seed。菜单选择的软件包会写入 configs/custom.seed，该文件被 git 忽略，仅用于本地配置。

## 构建逻辑

OpenWrt .config 会按以下顺序生成：

1. 自动选择或手动指定的 BASE_DEFCONFIG
2. 选择的 Filogic 设备 profile
3. configs/default.seed
4. configs/devices/<DEVICE_PROFILE>.seed（如果存在）
5. configs/custom.seed（如果存在）

如果所选设备没有匹配的本地基础 defconfig，构建会停止并要求在 .env 中设置 BASE_DEFCONFIG。

## 输出

构建完成后，固件位于：

```text
output/<DEVICE_PROFILE>/<date>-<upstream-commit>/
```

## 常用命令

推荐的日常入口：

```bash
make
```

需要直接执行某个步骤时：

```bash
make init        # 更新源码和 feeds
make device      # 选择 Filogic 设备 profile
make packages    # 选择可选固件软件包
make build       # 编译当前设备固件
make menuconfig  # 打开 OpenWrt menuconfig
make clean       # 执行 OpenWrt clean
make distclean   # 删除 source/ 下生成的构建状态
make shell       # 打开 builder 容器 shell
```

旧的 make select-device 和 make select-packages 命令已经移除，请使用 make device 和 make packages。

## 常见问题

### 找不到 Docker

请先安装 Docker Engine 或 Docker Desktop，并确认 docker --version 可以执行。完整构建流程不能脱离 Docker。

### 找不到 docker compose

请安装或升级到包含 Compose v2 的 Docker 版本。项目使用 docker compose，而不是旧版 docker-compose。

### Docker 权限或 daemon 错误

启动 Docker 服务，并确认当前用户可以执行 docker ps。Linux 用户还需要加入 Docker 用户组或使用系统规定的 Docker 权限配置。

### 编译过程中内存或磁盘不足

降低 .env 中的 JOBS，清理不需要的构建缓存，或提高 Docker Desktop 的资源限制。不要在不了解后果的情况下删除 source/、dl/ 或 ccache/；这些目录可能包含可复用的源码和缓存。

### Windows 下脚本无法运行

请改用 WSL2 或 Git Bash，并确认 GNU Make 已安装。不要直接把 PowerShell 作为 Bash 脚本的运行环境。

## 文档

- [USB IPv6 配置](docs/f50-ipv6.md)
- [OpenWrt 使用说明](docs/openwrt.md)
- [去广告说明](docs/anti-ad.md)

## 许可证

本项目使用 MIT License，详见 [LICENSE](LICENSE)。
