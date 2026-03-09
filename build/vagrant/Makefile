SHELL := /bin/bash

ISO_URL_CENTOS9STREAM_BASE ?= http://mirror.facebook.net/centos-stream/9-stream/BaseOS/x86_64/iso
ISO_URL_CENTOS9STREAM_FILTER ?= grep -Po '(?<=href=")CentOS-Stream-9-latest-x86_64-boot.iso(?=")' | sort -r | head -1

CODEBUILD_SOURCE_REPO_URL ?= https://github.com/MetroStar/granite.git
CODEBUILD_SOURCE_VERSION  ?= dependabot/docker/MetroStar/master

GRANITE_CI ?= false
GRANITE_IDENTIFIER ?= granite

export PATH := $(HOME)/bin:$(PATH)

.PHONY: all install pre_build build post_build
.EXPORT_ALL_VARIABLES:

# Set GRANITE_VERSION if GRANITE_CI is "true"
ifeq ($(GRANITE_CI),true)
GRANITE_VERSION := $(or $(GRANITE_VERSION),$(shell date +%Y.%m.dev%s))
endif

# Exit with error if GRANITE_VERSION is not set
ifndef GRANITE_VERSION
$(error [make]: Must set one of GRANITE_VERSION, or GRANITE_CI=true!)
endif

$(info GRANITE_IDENTIFIER=$(GRANITE_IDENTIFIER))
$(info GRANITE_VERSION=$(GRANITE_VERSION))

all: build

install:
	$(MAKE) -f ../../Makefile packer/install

build: export PACKER_LOG = 1
build: export PACKER_LOG_PATH = .granite/$(GRANITE_VERSION)/packer.build-granite-vagrant.log
build: export PACKER_LOG_DIR = $(dir $(PACKER_LOG_PATH))
build: export PKR_VAR_aws_temporary_security_group_source_cidrs = ["$(shell curl -sSL https://checkip.amazonaws.com)/32"]
build: export PKR_VAR_virtualbox_iso_url_centos9stream ?= $(ISO_URL_CENTOS9STREAM_BASE)/$(shell curl -sSL $(ISO_URL_CENTOS9STREAM_BASE) | $(ISO_URL_CENTOS9STREAM_FILTER))

build:
	mkdir -p "$(PACKER_LOG_DIR)"
	packer init build-granite-vagrant.pkr.hcl
	packer build \
		-var granite_ci=$(GRANITE_CI) \
		-var granite_identifier=$(GRANITE_IDENTIFIER) \
		-var granite_repo_url=$(CODEBUILD_SOURCE_REPO_URL) \
		-var granite_repo_commit=$(CODEBUILD_SOURCE_VERSION) \
		-var granite_version=$(GRANITE_VERSION) \
		-var packer_version=$(PACKER_VERSION) \
		build-granite-vagrant.pkr.hcl
	@if [[ "$(GRANITE_CI)" = "true" ]]; then \
		echo "Moving "$(PACKER_LOG_DIR)" to .granite/ci" ;\
		mkdir -p .granite/ci ;\
		rm -rf .granite/ci/$(GRANITE_VERSION); \
		mv "$(PACKER_LOG_DIR)" .granite/ci ;\
	fi
