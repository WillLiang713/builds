DOCKER ?= docker
COMPOSE ?= $(DOCKER) compose
SERVICE ?= builder
RUN := $(COMPOSE) run --rm $(SERVICE)

.DEFAULT_GOAL := menu

.PHONY: menu init defconfig menuconfig build output shell clean distclean list-devices device packages help

menu:
	./scripts/menu.sh

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

list-devices:
	./scripts/list-devices.sh

device:
	./scripts/select-device.sh

packages:
	./scripts/select-packages.sh

help:
	@printf '%s\n' \
		'Run "make" for the interactive builder menu.' \
		'' \
		'Advanced targets:' \
		'  make init             Update source tree and feeds' \
		'  make device           Select a Filogic device profile' \
		'  make packages         Select optional firmware packages' \
		'  make build            Build firmware for the selected device' \
		'  make menuconfig       Open OpenWrt menuconfig' \
		'  make clean            Run OpenWrt clean' \
		'  make distclean        Remove generated build state under source/' \
		'  make shell            Open a shell in the builder container'
