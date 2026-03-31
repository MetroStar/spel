SHELL := /bin/bash

ISO_URL_CENTOS9STREAM_BASE ?= http://mirror.facebook.net/centos-stream/9-stream/BaseOS/x86_64/iso
ISO_URL_CENTOS9STREAM_FILTER ?= grep -Po '(?<=href=")CentOS-Stream-9-latest-x86_64-boot.iso(?=")' | sort -r | head -1

CODEBUILD_SOURCE_REPO_URL ?= https://github.com/MetroStar/chimera.git
CODEBUILD_SOURCE_VERSION  ?= dependabot/docker/MetroStar/master

CHIMERA_CI ?= false
CHIMERA_IDENTIFIER ?= chimera

export PATH := $(HOME)/bin:$(PATH)

.PHONY: all install pre_build build post_build
.EXPORT_ALL_VARIABLES:

# Set CHIMERA_VERSION if CHIMERA_CI is "true"
ifeq ($(CHIMERA_CI),true)
CHIMERA_VERSION := $(or $(CHIMERA_VERSION),$(shell date +%Y.%m.dev%s))
endif

# Exit with error if CHIMERA_VERSION is not set
ifndef CHIMERA_VERSION
$(error [make]: Must set one of CHIMERA_VERSION, or CHIMERA_CI=true!)
endif

$(info CHIMERA_IDENTIFIER=$(CHIMERA_IDENTIFIER))
$(info CHIMERA_VERSION=$(CHIMERA_VERSION))

all: build

install:
	$(MAKE) -f ../../Makefile packer/install

build: export PACKER_LOG = 1
build: export PACKER_LOG_PATH = .chimera/$(CHIMERA_VERSION)/packer.build-chimera-vagrant.log
build: export PACKER_LOG_DIR = $(dir $(PACKER_LOG_PATH))
build: export PKR_VAR_aws_temporary_security_group_source_cidrs = ["$(shell curl -sSL https://checkip.amazonaws.com)/32"]
build: export PKR_VAR_virtualbox_iso_url_centos9stream ?= $(ISO_URL_CENTOS9STREAM_BASE)/$(shell curl -sSL $(ISO_URL_CENTOS9STREAM_BASE) | $(ISO_URL_CENTOS9STREAM_FILTER))

build:
	mkdir -p "$(PACKER_LOG_DIR)"
	packer init build-chimera-vagrant.pkr.hcl
	packer build \
		-var chimera_ci=$(CHIMERA_CI) \
		-var chimera_identifier=$(CHIMERA_IDENTIFIER) \
		-var chimera_repo_url=$(CODEBUILD_SOURCE_REPO_URL) \
		-var chimera_repo_commit=$(CODEBUILD_SOURCE_VERSION) \
		-var chimera_version=$(CHIMERA_VERSION) \
		-var packer_version=$(PACKER_VERSION) \
		build-chimera-vagrant.pkr.hcl
	@if [[ "$(CHIMERA_CI)" = "true" ]]; then \
		echo "Moving "$(PACKER_LOG_DIR)" to .chimera/ci" ;\
		mkdir -p .chimera/ci ;\
		rm -rf .chimera/ci/$(CHIMERA_VERSION); \
		mv "$(PACKER_LOG_DIR)" .chimera/ci ;\
	fi
