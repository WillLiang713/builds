# Build Workspace

This repository stores router firmware build projects and helper scripts.

## Projects

- `tr3000/` - Cudy TR3000 v1 U-Boot mod ImmortalWrt builder.

## TR3000 Quick Start

```bash
cd tr3000
make init
make build
```

Build outputs are copied to:

```text
tr3000/output/
```

## Ignored Build Data

The following generated or cache directories are intentionally ignored:

```text
tr3000/source/
tr3000/dl/
tr3000/ccache/
tr3000/output/
```

Do not commit these directories. They contain upstream source checkouts,
download caches, compiler caches, and firmware output files.
