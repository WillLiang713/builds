DOCKER ?= docker
COMPOSE ?= $(DOCKER) compose
SERVICE ?= builder
RUN := $(COMPOSE) run --rm $(SERVICE)

.PHONY: help init defconfig menuconfig build output shell clean distclean

help:
	@printf '%s\n' \
		'Targets:' \
		'  make init        Prepare source tree, feeds, and package checks' \
		'  make defconfig   Generate source/.config from configs/cmcc_rax3000m_nand.seed' \
		'  make menuconfig  Open OpenWrt menuconfig inside the builder container' \
		'  make build       Compile firmware and collect output files' \
		'  make output      Collect already-built firmware files into output/' \
		'  make shell       Open a shell in the builder container' \
		'  make clean       Run OpenWrt clean' \
		'  make distclean   Remove generated build state under source/' \
		'' \
		'Default Docker command is "docker". If needed, run:' \
		'  make DOCKER="sudo docker" build'

init:
	$(RUN) ./scripts/init.sh

defconfig:
	$(RUN) ./scripts/defconfig.sh

menuconfig:
	$(RUN) ./scripts/menuconfig.sh

build:
	$(RUN) ./scripts/build.sh

output:
	$(RUN) ./scripts/collect-output.sh

shell:
	$(COMPOSE) run --rm $(SERVICE) /bin/bash

clean:
	$(RUN) ./scripts/clean.sh clean

distclean:
	$(RUN) ./scripts/clean.sh distclean
