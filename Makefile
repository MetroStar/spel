SHELL := /bin/bash

PACKER_LOG ?= '1'
PACKER_LOG_PATH = .crucible/$(CRUCIBLE_VERSION)/packer.log
CHECKPOINT_DISABLE ?= '1'
BUILDER_REGION = $(or $(PKR_VAR_aws_region),$(AWS_REGION))

export PKR_VAR_crucible_deprecation_lifetime ?= 8760h

.PHONY: build
.EXPORT_ALL_VARIABLES:

$(info CRUCIBLE_IDENTIFIER=$(CRUCIBLE_IDENTIFIER))
$(info CRUCIBLE_VERSION=$(CRUCIBLE_VERSION))

nifndef CRUCIBLE_IDENTIFIER
$(error CRUCIBLE_IDENTIFIER is not set)
endif

nifndef CRUCIBLE_VERSION
$(error CRUCIBLE_VERSION is not set)
else
$(shell mkdir -p ".crucible/$(CRUCIBLE_VERSION)")
endif

build: export AWS_DEFAULT_REGION := $(BUILDER_REGION)
build: export AWS_REGION := $(BUILDER_REGION)
build: export PKR_VAR_aws_temporary_security_group_source_cidrs = ["$(shell curl -sSL https://checkip.amazonaws.com)/32"]
build:
	bash ./build.sh
