SHELL := /bin/bash
VERSION := 0.0.1rc6
ADMIRAL_COMMON_COMMIT := ba59c45d647bd354c878d7e61497896746a88c2b
ADMIRALD_COMMIT := e0d3326406f315912e856ec7954757bb859cfe05
FLEET_COMMIT := b082934f908a4a33acf0fdd70c06974f0a29bb21
ADMIRALCTL_COMMIT := 90c30edb2b9f02b962874272dc6487bead990277
FLAGSHIP_COMMIT := b7325bbc71fc474a521496e593b2967e4d555ac1
HARBOR_COMMIT := dd4818b6e2bc53eea4495fc5e374a4893cfcb107
RPMDIR := $(CURDIR)/packaging/build
RPMTOPDIR := $(RPMDIR)
SPECSDIR := $(CURDIR)/packaging/rpm
CONFIGDIR := $(CURDIR)/packaging/config
SYSTEMDDIR := $(CURDIR)/packaging/systemd
BINDIR := $(CURDIR)/packaging/bin
SOURCEDIR := $(RPMTOPDIR)/SOURCES
BUILDID := $(shell date +%Y%m%d)
RPM_ARCH ?= $(shell rpm --eval '%{_target_cpu}')

GO_MODULES := admirald admiral-fleet admiralctl
ALEMBIC_VERSION := 1.20.1
TYPING_EXTENSIONS_VERSION := 4.16.0
FLASK_SQLALCHEMY_VERSION := 3.1.1
FLASK_ALEMBIC_VERSION := 3.3.0
FLASK_LOGIN_VERSION := 0.6.3
MISTUNE_VERSION := 3.4.0
FLASK_VERSION := 3.1.3
SQLALCHEMY_VERSION := 2.0.55
ALEMBIC_SHA256 := c2982961a193cca5ea19ff541637f002bb568a9bd1f45ae141216e86eb45e5e5
TYPING_EXTENSIONS_SHA256 := 4d569f4d4bcd3d26345e0d92cfd14ce1f1302cac2f62a5a7e337c06fb0fdc1ea
FLASK_SQLALCHEMY_SHA256 := 1989afdf046a935bd1ab98dbd9a2d68e5ba1c69d0cd3e3646df0876bf8d997d3
FLASK_ALEMBIC_SHA256 := 487c20d93e5ce1da1f9cf18d7b4e5c8d420e5588cf1ec6ca5eddbaab680a6f19
FLASK_LOGIN_SHA256 := 3b2489f46d854b5f1d7a55007271d2eae9f744e0935ca7b88ab584c770a7e4d2
MISTUNE_SHA256 := 121828b8bb4b9b8f0ace26e7574dab4d9a3f391e97e7f07b30aa3d34b9f5690a
FLASK_WHEEL_SHA256 := f4bcbefc124291925f1a26446da31a5178f9483862233b23c0c96a20701f670c
SQLALCHEMY_SHA256 := ae40c563bc10a8d56f1fd1f39f069aeb5eb85ca26913b2314dd8d190139258fa

.PHONY: all clean rpm rpm-admiral rpmlint validate-release-refs test-admiralctl-local local-rpm-repo all-sources \
	source-superproject source-admiral-flagship source-admiral-harbor \
	srpm srpms \
	rpm-admiral-common rpm-admirald rpm-admiral-fleet \
	rpm-admiralctl rpm-admiral-flagship rpm-admiral-harbor \
	rpm-admiral-no-test \
	srpm-admiral-common srpm-admirald srpm-admiral-fleet \
	srpm-admiralctl srpm-admiral-flagship srpm-admiral-harbor \
	rpm-python-flask rpm-python-flask-sqlalchemy rpm-python-flask-alembic rpm-python-flask-login \
	rpm-python-mistune rpm-python-sqlalchemy srpm-python-mistune srpm-python-flask \
	srpm-python-sqlalchemy

all: rpm

validate-release-refs:
	python3 scripts/validate-release-refs.py

test-admiralctl-local:
	scripts/test-admiralctl-local.sh

local-rpm-repo:
	scripts/create-local-rpm-repo.sh

clean:
	rm -rf $(RPMDIR)

# -- RPM build directories -----------------------------------------------

$(SOURCEDIR):
	mkdir -p $(SOURCEDIR)
	mkdir -p $(RPMTOPDIR)/RPMS/noarch
	mkdir -p $(RPMTOPDIR)/RPMS/x86_64
	mkdir -p $(RPMTOPDIR)/SRPMS
	mkdir -p $(RPMTOPDIR)/SPECS
	mkdir -p $(RPMTOPDIR)/BUILD
	mkdir -p $(RPMTOPDIR)/tmp

# -- Pinned source archives used by the RPM specs ------------------------
# Stage each repository at the exact archive filename and root directory
# that its spec declares. This keeps rpmbuild independent of network fetches.

source-superproject: | $(SOURCEDIR)
	@echo "=== Generating pinned Admiral source archives ==="
	git archive --format=tar.gz \
		--prefix=admiral-$(ADMIRAL_COMMON_COMMIT)/ \
		-o $(SOURCEDIR)/$(ADMIRAL_COMMON_COMMIT).tar.gz $(ADMIRAL_COMMON_COMMIT)
	for sm in admirald admiral-fleet admiralctl; do \
		echo "  Adding $$sm..."; \
		commit="HEAD"; \
		if [ "$$sm" = "admirald" ]; then commit="$(ADMIRALD_COMMIT)"; fi; \
		if [ "$$sm" = "admiral-fleet" ]; then commit="$(FLEET_COMMIT)"; fi; \
		if [ "$$sm" = "admiralctl" ]; then commit="$(ADMIRALCTL_COMMIT)"; fi; \
		git -C $$sm archive --format=tar.gz \
			--prefix=$$sm-$$commit/ \
			-o $(SOURCEDIR)/$$commit.tar.gz $$commit || exit $$?; \
	done

# -- Source tarballs from each submodule (for non-Go components) ---------

define download_checked
	curl -fsSL -o $(1) $(2)
	echo '$(3)  $(1)' | sha256sum -c -
endef


source-admiral-flagship: | $(SOURCEDIR)
	git -C admiral-flagship archive --format=tar.gz \
		--prefix=admiral-flagship-$(FLAGSHIP_COMMIT)/ \
		-o $(SOURCEDIR)/$(FLAGSHIP_COMMIT).tar.gz $(FLAGSHIP_COMMIT)

source-admiral-harbor: | $(SOURCEDIR)
	git -C admiral-harbor archive --format=tar.gz \
		--prefix=admiral-harbor-$(HARBOR_COMMIT)/ \
		-o $(SOURCEDIR)/$(HARBOR_COMMIT).tar.gz $(HARBOR_COMMIT)

source-python-flask-sqlalchemy: | $(SOURCEDIR)
	$(call download_checked,$(SOURCEDIR)/flask-sqlalchemy-$(FLASK_SQLALCHEMY_VERSION).tar.gz,https://github.com/pallets-eco/flask-sqlalchemy/archive/refs/tags/$(FLASK_SQLALCHEMY_VERSION)/flask-sqlalchemy-$(FLASK_SQLALCHEMY_VERSION).tar.gz,$(FLASK_SQLALCHEMY_SHA256))

source-python-alembic: | $(SOURCEDIR)
	$(call download_checked,$(SOURCEDIR)/alembic-$(ALEMBIC_VERSION).tar.gz,https://github.com/sqlalchemy/alembic/archive/refs/tags/rel_$(subst .,_,$(ALEMBIC_VERSION))/alembic-$(ALEMBIC_VERSION).tar.gz,$(ALEMBIC_SHA256))

source-python-typing-extensions: | $(SOURCEDIR)
	$(call download_checked,$(SOURCEDIR)/typing_extensions-$(TYPING_EXTENSIONS_VERSION).tar.gz,https://github.com/python/typing_extensions/archive/refs/tags/$(TYPING_EXTENSIONS_VERSION)/typing_extensions-$(TYPING_EXTENSIONS_VERSION).tar.gz,$(TYPING_EXTENSIONS_SHA256))

source-python-flask-alembic: | $(SOURCEDIR)
	$(call download_checked,$(SOURCEDIR)/flask-alembic-$(FLASK_ALEMBIC_VERSION).tar.gz,https://github.com/pallets-eco/flask-alembic/archive/refs/tags/$(FLASK_ALEMBIC_VERSION)/flask-alembic-$(FLASK_ALEMBIC_VERSION).tar.gz,$(FLASK_ALEMBIC_SHA256))

source-python-flask-login: | $(SOURCEDIR)
	$(call download_checked,$(SOURCEDIR)/flask-login-$(FLASK_LOGIN_VERSION).tar.gz,https://github.com/maxcountryman/flask-login/archive/refs/tags/$(FLASK_LOGIN_VERSION)/flask-login-$(FLASK_LOGIN_VERSION).tar.gz,$(FLASK_LOGIN_SHA256))

source-python-mistune: | $(SOURCEDIR)
	$(call download_checked,$(SOURCEDIR)/mistune-$(MISTUNE_VERSION).tar.gz,https://github.com/lepture/mistune/archive/refs/tags/v$(MISTUNE_VERSION)/mistune-$(MISTUNE_VERSION).tar.gz,$(MISTUNE_SHA256))

source-python-flask: | $(SOURCEDIR)
	$(call download_checked,$(SOURCEDIR)/flask-$(FLASK_VERSION)-py3-none-any.whl,https://files.pythonhosted.org/packages/7f/9c/34f6962f9b9e9c71f6e5ed806e0d0ff03c9d1b0b2340088a0cf4bce09b18/flask-$(FLASK_VERSION)-py3-none-any.whl,$(FLASK_WHEEL_SHA256))

source-python-sqlalchemy: | $(SOURCEDIR)
	$(call download_checked,$(SOURCEDIR)/sqlalchemy-$(SQLALCHEMY_VERSION).tar.gz,https://files.pythonhosted.org/packages/a5/bd/08864ddfffbb8914ee13b0c887d84b4b13bc8dd8da3077c0dace5a87699c/sqlalchemy-$(SQLALCHEMY_VERSION).tar.gz,$(SQLALCHEMY_SHA256))

all-sources: source-superproject \
	source-admiral-flagship source-admiral-harbor \
	source-python-alembic source-python-typing-extensions \
	source-python-flask-sqlalchemy source-python-flask-alembic \
	source-python-flask-login source-python-mistune source-python-flask \
	source-python-sqlalchemy

# -- Copy packaging support files to SOURCES -----------------------------

source-support-files: | $(SOURCEDIR)
	cp $(SYSTEMDDIR)/admirald.service $(SOURCEDIR)/
	cp $(SYSTEMDDIR)/admiral-fleet.service $(SOURCEDIR)/
	cp $(SYSTEMDDIR)/admiral-flagship.service $(SOURCEDIR)/
	cp $(SYSTEMDDIR)/admiral-harbor.service $(SOURCEDIR)/
	cp $(SYSTEMDDIR)/admiral-harbor-worker.service $(SOURCEDIR)/
	cp $(SYSTEMDDIR)/admiral-harbor-worker.timer $(SOURCEDIR)/
	cp $(SYSTEMDDIR)/admiral-harbor-catalog-sync.service $(SOURCEDIR)/
	cp $(SYSTEMDDIR)/admiral-harbor-catalog-sync.timer $(SOURCEDIR)/
	cp $(SYSTEMDDIR)/admiral-control-plane-backup.service $(SOURCEDIR)/
	cp $(SYSTEMDDIR)/admiral-control-plane-backup.timer $(SOURCEDIR)/
	cp $(SYSTEMDDIR)/admiral-wireguard-peer-revoke.socket $(SOURCEDIR)/
	cp $(SYSTEMDDIR)/admiral-wireguard-peer-revoke@.service $(SOURCEDIR)/
	cp $(CONFIGDIR)/admirald.ini $(SOURCEDIR)/
	cp $(CONFIGDIR)/fleet.env $(SOURCEDIR)/
	cp $(CONFIGDIR)/admiralctl.yaml $(SOURCEDIR)/
	cp $(CONFIGDIR)/flagship.env $(SOURCEDIR)/
	cp $(CONFIGDIR)/harbor.env $(SOURCEDIR)/
	cp $(BINDIR)/harborctl $(SOURCEDIR)/
	cp $(BINDIR)/harbor-gunicorn $(SOURCEDIR)/
	cp $(BINDIR)/harbor-migrate $(SOURCEDIR)/
	cp $(SPECSDIR)/admiral-common.sysusers $(SOURCEDIR)/
	cp $(CURDIR)/scripts/admiral_letsencrypt_deploy_hook.sh $(SOURCEDIR)/

# -- RPM build flags -----------------------------------------------------

RPMFLAGS := --target $(RPM_ARCH) \
            --define '_topdir $(RPMTOPDIR)' \
            --define '_sourcedir $(SOURCEDIR)' \
            --define '_specdir $(RPMTOPDIR)/SPECS' \
            --define '_builddir $(RPMTOPDIR)/BUILD' \
            --define '_rpmdir $(RPMTOPDIR)/RPMS' \
            --define '_srcrpmdir $(RPMTOPDIR)/SRPMS' \
            --define '_tmppath $(RPMTOPDIR)/tmp'
RPMFLAGS += $(RPMFLAGS_EXTRA)

# -- RPM targets ---------------------------------------------------------

rpm-admiral-common: validate-release-refs source-superproject source-support-files
	cp $(SPECSDIR)/$(@:rpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admiral-common.spec

rpm-admirald: validate-release-refs source-superproject source-support-files
	cp $(SPECSDIR)/$(@:rpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admirald.spec

rpm-admiral-fleet: validate-release-refs source-superproject source-support-files
	cp $(SPECSDIR)/$(@:rpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admiral-fleet.spec

rpm-admiralctl: validate-release-refs source-superproject source-support-files
	cp $(SPECSDIR)/$(@:rpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admiralctl.spec

rpm-admiral-flagship: validate-release-refs source-admiral-flagship source-support-files
	cp $(SPECSDIR)/$(@:rpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admiral-flagship.spec

rpm-admiral-harbor: validate-release-refs source-admiral-harbor source-support-files
	cp $(SPECSDIR)/$(@:rpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admiral-harbor.spec

rpm-python-alembic: source-python-alembic source-python-typing-extensions
	cp $(SPECSDIR)/python-alembic.spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-alembic.spec

rpm-python-typing-extensions: source-python-typing-extensions
	cp $(SPECSDIR)/python-typing-extensions.spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-typing-extensions.spec

rpm-python-flask-sqlalchemy: source-python-flask-sqlalchemy
	cp $(SPECSDIR)/$(@:rpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-flask-sqlalchemy.spec

rpm-python-flask-alembic: source-python-flask-alembic
	cp $(SPECSDIR)/$(@:rpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-flask-alembic.spec

rpm-python-flask-login: source-python-flask-login
	cp $(SPECSDIR)/$(@:rpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-flask-login.spec

rpm-python-mistune: source-python-mistune
	cp $(SPECSDIR)/python-mistune.spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-mistune.spec

rpm-python-flask: source-python-flask
	cp $(SPECSDIR)/python-flask.spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-flask.spec

rpm-python-sqlalchemy: source-python-sqlalchemy
	cp $(SPECSDIR)/python-sqlalchemy.spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-sqlalchemy.spec

# -- SRPM targets --------------------------------------------------------

srpm-admiral-common: source-superproject source-support-files
	cp $(SPECSDIR)/$(@:srpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -bs $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admiral-common.spec

srpm-admirald: source-superproject source-support-files
	cp $(SPECSDIR)/$(@:srpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -bs $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admirald.spec

srpm-admiral-fleet: source-superproject source-support-files
	cp $(SPECSDIR)/$(@:srpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -bs $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admiral-fleet.spec

srpm-admiralctl: source-superproject source-support-files
	cp $(SPECSDIR)/$(@:srpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -bs $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admiralctl.spec

srpm-admiral-flagship: source-admiral-flagship source-support-files
	cp $(SPECSDIR)/$(@:srpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -bs $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admiral-flagship.spec

srpm-admiral-harbor: source-admiral-harbor source-support-files
	cp $(SPECSDIR)/$(@:srpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -bs $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admiral-harbor.spec

srpm-python-alembic: source-python-alembic source-python-typing-extensions
	cp $(SPECSDIR)/python-alembic.spec $(RPMTOPDIR)/SPECS/
	rpmbuild -bs $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-alembic.spec

srpm-python-typing-extensions: source-python-typing-extensions
	cp $(SPECSDIR)/python-typing-extensions.spec $(RPMTOPDIR)/SPECS/
	rpmbuild -bs $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-typing-extensions.spec

srpm-python-flask-sqlalchemy: source-python-flask-sqlalchemy
	cp $(SPECSDIR)/$(@:srpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -bs $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-flask-sqlalchemy.spec

srpm-python-flask-alembic: source-python-flask-alembic
	cp $(SPECSDIR)/$(@:srpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -bs $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-flask-alembic.spec

srpm-python-flask-login: source-python-flask-login
	cp $(SPECSDIR)/$(@:srpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -bs $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-flask-login.spec

srpm-python-mistune: source-python-mistune
	cp $(SPECSDIR)/python-mistune.spec $(RPMTOPDIR)/SPECS/
	rpmbuild -bs $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-mistune.spec

srpm-python-flask: source-python-flask
	cp $(SPECSDIR)/python-flask.spec $(RPMTOPDIR)/SPECS/
	rpmbuild -bs $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-flask.spec

srpm-python-sqlalchemy: source-python-sqlalchemy
	cp $(SPECSDIR)/python-sqlalchemy.spec $(RPMTOPDIR)/SPECS/
	rpmbuild -bs $(RPMFLAGS) $(RPMTOPDIR)/SPECS/python-sqlalchemy.spec

# -- Build all RPMs in dependency order ----------------------------------

rpm: validate-release-refs all-sources source-support-files
	@echo "=== Building admiral-common ==="
	$(MAKE) rpm-admiral-common
	@echo "=== Building admirald ==="
	$(MAKE) rpm-admirald
	@echo "=== Building admiral-fleet ==="
	$(MAKE) rpm-admiral-fleet
	@echo "=== Building admiralctl ==="
	$(MAKE) rpm-admiralctl
	@echo "=== Building admiral-flagship ==="
	$(MAKE) rpm-admiral-flagship
	@echo "=== Building python-typing-extensions ==="
	$(MAKE) rpm-python-typing-extensions
	@echo "=== Building python-sqlalchemy ==="
	$(MAKE) rpm-python-sqlalchemy
	@echo "=== Building python-alembic ==="
	$(MAKE) rpm-python-alembic
	@echo "=== Building python-flask-sqlalchemy ==="
	$(MAKE) rpm-python-flask-sqlalchemy
	@echo "=== Building python-flask-alembic ==="
	$(MAKE) rpm-python-flask-alembic
	@echo "=== Building python-flask-login ==="
	$(MAKE) rpm-python-flask-login
	@echo "=== Building python-mistune ==="
	$(MAKE) rpm-python-mistune
	@echo "=== Building patched python-flask for EL10 ==="
	$(MAKE) rpm-python-flask
	@echo "=== Building admiral-harbor ==="
	$(MAKE) rpm-admiral-harbor
	@echo "=== All RPMs built ==="
	@find $(RPMDIR)/RPMS -name '*.rpm' -exec basename {} \;

rpm-admiral: validate-release-refs all-sources source-support-files
	@echo "=== Building admiral-common ==="
	$(MAKE) rpm-admiral-common
	@echo "=== Building admirald ==="
	$(MAKE) rpm-admirald
	@echo "=== Building admiral-fleet ==="
	$(MAKE) rpm-admiral-fleet
	@echo "=== Building admiralctl ==="
	$(MAKE) rpm-admiralctl
	@echo "=== Building admiral-flagship ==="
	$(MAKE) rpm-admiral-flagship
	@echo "=== Building admiral-harbor ==="
	$(MAKE) rpm-admiral-harbor
	@echo "=== All 6 Admiral RPMs built ==="
	@find $(RPMDIR)/RPMS -name 'admiral*.rpm' -exec basename {} \;

rpm-admiral-no-test: validate-release-refs all-sources source-support-files
	@echo "=== Building admiral-common (no tests) ==="
	$(MAKE) rpm-admiral-common RPMFLAGS="$(RPMFLAGS) --nocheck"
	@echo "=== Building admirald (no tests) ==="
	$(MAKE) rpm-admirald RPMFLAGS="$(RPMFLAGS) --nocheck"
	@echo "=== Building admiral-fleet (no tests) ==="
	$(MAKE) rpm-admiral-fleet RPMFLAGS="$(RPMFLAGS) --nocheck"
	@echo "=== Building admiralctl (no tests) ==="
	$(MAKE) rpm-admiralctl RPMFLAGS="$(RPMFLAGS) --nocheck"
	@echo "=== Building admiral-flagship (no tests) ==="
	$(MAKE) rpm-admiral-flagship RPMFLAGS="$(RPMFLAGS) --nocheck"
	@echo "=== Building admiral-harbor (no tests) ==="
	$(MAKE) rpm-admiral-harbor RPMFLAGS="$(RPMFLAGS) --nocheck"
	@echo "=== All 6 Admiral RPMs built (no tests) ==="
	@find $(RPMDIR)/RPMS -name 'admiral*.rpm' -exec basename {} \;

srpms: all-sources source-support-files
	@echo "=== Building admiral-common SRPM ==="
	$(MAKE) srpm-admiral-common
	@echo "=== Building admirald SRPM ==="
	$(MAKE) srpm-admirald
	@echo "=== Building admiral-fleet SRPM ==="
	$(MAKE) srpm-admiral-fleet
	@echo "=== Building admiralctl SRPM ==="
	$(MAKE) srpm-admiralctl
	@echo "=== Building admiral-flagship SRPM ==="
	$(MAKE) srpm-admiral-flagship
	@echo "=== Building python-flask-sqlalchemy SRPM ==="
	$(MAKE) srpm-python-flask-sqlalchemy
	@echo "=== Building python-sqlalchemy SRPM ==="
	$(MAKE) srpm-python-sqlalchemy
	@echo "=== Building python-typing-extensions SRPM ==="
	$(MAKE) srpm-python-typing-extensions
	@echo "=== Building python-flask-alembic SRPM ==="
	$(MAKE) srpm-python-flask-alembic
	@echo "=== Building python-flask-login SRPM ==="
	$(MAKE) srpm-python-flask-login
	@echo "=== Building python-mistune SRPM ==="
	$(MAKE) srpm-python-mistune
	@echo "=== Building patched python-flask SRPM ==="
	$(MAKE) srpm-python-flask
	@echo "=== Building admiral-harbor SRPM ==="
	$(MAKE) srpm-admiral-harbor
	@echo "=== All SRPMs built ==="
	@find $(RPMDIR)/SRPMS -name '*.src.rpm' -exec basename {} \;

srpm: srpms

# -- Validation ----------------------------------------------------------

rpmlint:
	@if command -v rpmlint &>/dev/null; then \
		rpmlint $(SPECSDIR)/*.spec; \
	else \
		echo "rpmlint not available, skipping"; \
	fi
