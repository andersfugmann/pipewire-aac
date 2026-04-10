# Makefile: Build PipeWire Debian packages with AAC (FDK-AAC) support

SHELL       := /bin/bash
REPO_DIR    := $(CURDIR)/repo
SRC_DIR     := $(CURDIR)/src
PKGS_ADDED  := .packages-added.list
SOURCES_LIST:= /etc/apt/sources.list.d/pipewire-aac-local.sources

PW_VERSION  := $(shell apt-cache policy pipewire 2>/dev/null | sed -n 's/.*Candidate: *//p')
PW_UPSTREAM := $(shell echo '$(PW_VERSION)' | sed 's/^[0-9]*://; s/-[^-]*$$//')
PW_SRC_DIR  := $(SRC_DIR)/pipewire-$(PW_UPSTREAM)

SOURCE_STAMP := .source-$(PW_VERSION).stamp
PATCH_STAMP  := .patch-$(PW_VERSION).stamp
BUILD_STAMP  := .build-$(PW_VERSION).stamp
REPO_PACKAGES:= $(REPO_DIR)/Packages.gz

AAC_BUILD_DEPS := libfdk-aac-dev
REPO_TOOLS     := dpkg-dev

.PHONY: all
all: ## Build packages and generate local apt repo
all: build repo

.PHONY: deps
deps: ## Install build dependencies and track additions
deps: $(PKGS_ADDED)

$(PKGS_ADDED):
	dpkg-query -W -f '$${Package}\n' | sort > .packages-before.list
	sudo apt-get build-dep -y pipewire
	sudo apt-get install -y $(AAC_BUILD_DEPS) $(REPO_TOOLS)
	dpkg-query -W -f '$${Package}\n' | sort > .packages-after.list
	comm -13 .packages-before.list .packages-after.list > $@
	rm -f .packages-before.list .packages-after.list
	@echo "$$(wc -l < $@) packages were added (see $@)"

.PHONY: source
source: ## Fetch PipeWire Debian source
source: $(SOURCE_STAMP)

$(SOURCE_STAMP): | $(SRC_DIR)
	cd $(SRC_DIR) && apt-get source pipewire=$(PW_VERSION)
	touch $@

.PHONY: patch
patch: ## Patch source to enable AAC codec
patch: $(PATCH_STAMP)

$(PATCH_STAMP): $(SOURCE_STAMP)
	sed -i 's/-Dbluez5-codec-aac=disabled/-Dbluez5-codec-aac=enabled/' \
	  "$(PW_SRC_DIR)/debian/rules"
	sed -i '/^Build-Conflicts:.*libfdk-aac-dev/d' \
	  "$(PW_SRC_DIR)/debian/control"
	sed -i '/^Build-Depends:/ s/$$/\n               libfdk-aac-dev,/' \
	  "$(PW_SRC_DIR)/debian/control"
	cd "$(PW_SRC_DIR)" && \
	  DEBFULLNAME="Local Build" DEBEMAIL="local@build" \
	  dch --local '~aac' 'Enable AAC codec support via libfdk-aac'
	touch $@

.PHONY: build
build: ## Build .deb packages with AAC support
build: $(BUILD_STAMP)

$(BUILD_STAMP): $(PATCH_STAMP) | $(REPO_DIR)
	cd "$(PW_SRC_DIR)" && DEB_BUILD_OPTIONS="nocheck" dpkg-buildpackage -us -uc -b -j$$(nproc)
	mv -v $(SRC_DIR)/*.deb $(REPO_DIR)/ 2>/dev/null; \
	mv -v $(SRC_DIR)/*.buildinfo $(REPO_DIR)/ 2>/dev/null; \
	mv -v $(SRC_DIR)/*.changes $(REPO_DIR)/ 2>/dev/null; true
	touch $@

.PHONY: repo
repo: ## Generate local apt repository metadata
repo: $(REPO_PACKAGES)

$(REPO_PACKAGES): $(BUILD_STAMP)
	cd $(REPO_DIR) && dpkg-scanpackages --multiversion . /dev/null | gzip -9c > Packages.gz
	cd $(REPO_DIR) && dpkg-scanpackages --multiversion . /dev/null > Packages
	@echo "Local repo ready. Run: sudo make install-repo"

.PHONY: install-repo
install-repo: ## Register local repo as apt source (needs sudo)
install-repo: $(SOURCES_LIST)

$(SOURCES_LIST): $(REPO_PACKAGES)
	@if [ "$$(id -u)" -ne 0 ]; then \
	  echo "ERROR: install-repo must be run as root (sudo make install-repo)" ; \
	  exit 1 ; \
	fi
	@printf 'Types: deb\nURIs: file://$(REPO_DIR)\nSuites: ./\nTrusted: yes\n' > $@
	@echo "Added apt source: $@"

.PHONY: clean
clean: ## Remove source and build artifacts
clean:
	rm -rf $(SRC_DIR) $(REPO_DIR)
	rm -f .source-*.stamp .patch-*.stamp .build-*.stamp

.PHONY: clean-deps
clean-deps: ## Remove packages added by 'make deps'
clean-deps:
	@if [ -f "$(PKGS_ADDED)" ]; then \
	  sudo apt-get purge -y $$(cat $(PKGS_ADDED)) ; \
	  rm -f $(PKGS_ADDED) ; \
	else \
	  echo "No tracked packages to remove. Run 'make deps' first." ; \
	fi

.PHONY: distclean
distclean: ## Full cleanup (artifacts + build deps)
distclean: clean clean-deps

$(SRC_DIR):
	mkdir -p $@

$(REPO_DIR):
	mkdir -p $@

.PHONY: help
help: ## Show available targets
help:
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
	  awk -F ':.*## ' '{printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
