SHELL := /bin/bash

PACKER_LOG ?= '1'
PACKER_LOG_PATH = .chimera/$(CHIMERA_VERSION)/packer.log
CHECKPOINT_DISABLE ?= '1'
BUILDER_REGION = $(or $(PKR_VAR_aws_region),$(AWS_REGION))

export PKR_VAR_chimera_deprecation_lifetime ?= 8760h

.PHONY: build
.EXPORT_ALL_VARIABLES:

$(info CHIMERA_IDENTIFIER=$(CHIMERA_IDENTIFIER))
$(info CHIMERA_VERSION=$(CHIMERA_VERSION))

ifndef CHIMERA_IDENTIFIER
$(error CHIMERA_IDENTIFIER is not set)
endif

ifndef CHIMERA_VERSION
$(error CHIMERA_VERSION is not set)
else
$(shell mkdir -p ".chimera/$(CHIMERA_VERSION)")
endif

build: export AWS_DEFAULT_REGION := $(BUILDER_REGION)
build: export AWS_REGION := $(BUILDER_REGION)
build: export PKR_VAR_aws_temporary_security_group_source_cidrs = ["$(shell curl -sSL https://checkip.amazonaws.com)/32"]
build:
	bash ./build/build.sh
