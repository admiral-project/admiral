SHELL := /bin/bash
VERSION := 0.0.1beta14
ADMIRALD_COMMIT := 02d21661ac805fda52f36d86849aadc699e808bf
FLEET_COMMIT := 860c44c50aea575d32b98ea71ff7c4850eaebbaf
ADMIRALCTL_COMMIT := d4e4bf3d052199aea80f8dd057c80cd74f1bca5e
FLAGSHIP_COMMIT := 9c5396ada831521d95984baafc72f210a172ab88
HARBOR_COMMIT := f8161b5fd83f98cd9f0f7c90400c98f3909c4496
RPMDIR := $(CURDIR)/packaging/build
RPMTOPDIR := $(RPMDIR)
SPECSDIR := $(CURDIR)/packaging/rpm
CONFIGDIR := $(CURDIR)/packaging/config
SYSTEMDDIR := $(CURDIR)/packaging/systemd
BINDIR := $(CURDIR)/packaging/bin
SOURCEDIR := $(RPMTOPDIR)/SOURCES
BUILDID := $(shell date +%Y%m%d)

GO_MODULES := admirald admiral-fleet admiralctl
ALEMBIC_VERSION := 1.18.4
TYPING_EXTENSIONS_VERSION := 4.15.0
FLASK_SQLALCHEMY_VERSION := 3.1.1
FLASK_ALEMBIC_VERSION := 3.1.1
FLASK_LOGIN_VERSION := 0.6.3
MISTUNE_VERSION := 3.2.1

.PHONY: all clean rpm rpm-admiral rpmlint all-sources \
	srpm srpms \
	rpm-admiral-common rpm-admirald rpm-admiral-fleet \
	rpm-admiralctl rpm-admiral-flagship rpm-admiral-harbor \
	srpm-admiral-common srpm-admirald srpm-admiral-fleet \
	srpm-admiralctl srpm-admiral-flagship srpm-admiral-harbor \
	rpm-python-flask-sqlalchemy rpm-python-flask-alembic rpm-python-flask-login \
	rpm-python-mistune srpm-python-mistune

all: rpm

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

# -- Combined source tarball with submodule contents for Go builds -------
# Builds from superproject workspace so go.work resolves cross-references.

source-superproject: | $(SOURCEDIR)
	@echo "=== Generating superproject source tarball ==="
	git archive --format=tar \
		--prefix=admiral-v$(VERSION)/ \
		-o $(SOURCEDIR)/admiral-$(VERSION).tar HEAD
	for sm in admirald admiral-fleet admiralctl admiral-flagship admiral-harbor; do \
		echo "  Adding $$sm..."; \
		commit="HEAD"; \
		if [ "$$sm" = "admirald" ]; then commit="$(ADMIRALD_COMMIT)"; fi; \
		if [ "$$sm" = "admiral-fleet" ]; then commit="$(FLEET_COMMIT)"; fi; \
		if [ "$$sm" = "admiralctl" ]; then commit="$(ADMIRALCTL_COMMIT)"; fi; \
		if [ "$$sm" = "admiral-flagship" ]; then commit="$(FLAGSHIP_COMMIT)"; fi; \
		if [ "$$sm" = "admiral-harbor" ]; then commit="$(HARBOR_COMMIT)"; fi; \
		cd $$sm && git archive --format=tar \
			--prefix=admiral-v$(VERSION)/$$sm/ \
			-o $(SOURCEDIR)/$$sm-partial.tar $$commit && \
		cd $(CURDIR) && \
		tar --concatenate --file=$(SOURCEDIR)/admiral-$(VERSION).tar \
			$(SOURCEDIR)/$$sm-partial.tar && \
		rm -f $(SOURCEDIR)/$$sm-partial.tar; \
	done
	gzip -f $(SOURCEDIR)/admiral-$(VERSION).tar

# -- Source tarballs from each submodule (for non-Go components) ---------

source-admiral-flagship: | $(SOURCEDIR)
	cd admiral-flagship && git archive --format=tar.gz \
		--prefix=admiral-flagship-v$(VERSION)/ \
		-o $(SOURCEDIR)/admiral-flagship-$(VERSION).tar.gz $(FLAGSHIP_COMMIT)

source-admiral-harbor: | $(SOURCEDIR)
	cd admiral-harbor && git archive --format=tar.gz \
		--prefix=admiral-harbor-v$(VERSION)/ \
		-o $(SOURCEDIR)/admiral-harbor-$(VERSION).tar.gz $(HARBOR_COMMIT)

source-python-flask-sqlalchemy: | $(SOURCEDIR)
	curl -sL -o $(SOURCEDIR)/flask-sqlalchemy-$(FLASK_SQLALCHEMY_VERSION).tar.gz \
		https://github.com/pallets-eco/flask-sqlalchemy/archive/refs/tags/$(FLASK_SQLALCHEMY_VERSION)/flask-sqlalchemy-$(FLASK_SQLALCHEMY_VERSION).tar.gz

source-python-alembic: | $(SOURCEDIR)
	curl -sL -o $(SOURCEDIR)/alembic-$(ALEMBIC_VERSION).tar.gz \
		https://github.com/sqlalchemy/alembic/archive/refs/tags/rel_$(subst .,_,$(ALEMBIC_VERSION))/alembic-$(ALEMBIC_VERSION).tar.gz

source-python-typing-extensions: | $(SOURCEDIR)
	curl -sL -o $(SOURCEDIR)/typing_extensions-$(TYPING_EXTENSIONS_VERSION).tar.gz \
		https://github.com/python/typing_extensions/archive/refs/tags/$(TYPING_EXTENSIONS_VERSION)/typing_extensions-$(TYPING_EXTENSIONS_VERSION).tar.gz

source-python-flask-alembic: | $(SOURCEDIR)
	curl -sL -o $(SOURCEDIR)/flask-alembic-$(FLASK_ALEMBIC_VERSION).tar.gz \
		https://github.com/pallets-eco/flask-alembic/archive/refs/tags/$(FLASK_ALEMBIC_VERSION)/flask-alembic-$(FLASK_ALEMBIC_VERSION).tar.gz

source-python-flask-login: | $(SOURCEDIR)
	curl -sL -o $(SOURCEDIR)/flask-login-$(FLASK_LOGIN_VERSION).tar.gz \
		https://github.com/maxcountryman/flask-login/archive/refs/tags/$(FLASK_LOGIN_VERSION)/flask-login-$(FLASK_LOGIN_VERSION).tar.gz

source-python-mistune: | $(SOURCEDIR)
	curl -sL -o $(SOURCEDIR)/mistune-$(MISTUNE_VERSION).tar.gz \
		https://github.com/lepture/mistune/archive/refs/tags/v$(MISTUNE_VERSION)/mistune-$(MISTUNE_VERSION).tar.gz

all-sources: source-superproject \
	source-admiral-flagship source-admiral-harbor \
	source-python-alembic source-python-typing-extensions \
	source-python-flask-sqlalchemy source-python-flask-alembic \
	source-python-flask-login source-python-mistune

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
	cp $(CONFIGDIR)/admirald.ini $(SOURCEDIR)/
	cp $(CONFIGDIR)/fleet.env $(SOURCEDIR)/
	cp $(CONFIGDIR)/admiralctl.yaml $(SOURCEDIR)/
	cp $(CONFIGDIR)/flagship.env $(SOURCEDIR)/
	cp $(CONFIGDIR)/harbor.env $(SOURCEDIR)/
	cp $(BINDIR)/harborctl $(SOURCEDIR)/
	cp $(BINDIR)/harbor-gunicorn $(SOURCEDIR)/
	cp $(SPECSDIR)/admiral-common.sysusers $(SOURCEDIR)/

# -- RPM build flags -----------------------------------------------------

RPMFLAGS := --define '_topdir $(RPMTOPDIR)' \
            --define '_sourcedir $(SOURCEDIR)' \
            --define '_specdir $(RPMTOPDIR)/SPECS' \
            --define '_builddir $(RPMTOPDIR)/BUILD' \
            --define '_rpmdir $(RPMTOPDIR)/RPMS' \
            --define '_srcrpmdir $(RPMTOPDIR)/SRPMS' \
            --define '_tmppath $(RPMTOPDIR)/tmp'

# -- RPM targets ---------------------------------------------------------

rpm-admiral-common: source-superproject source-support-files
	cp $(SPECSDIR)/$(@:rpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admiral-common.spec

rpm-admirald: source-superproject source-support-files
	cp $(SPECSDIR)/$(@:rpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admirald.spec

rpm-admiral-fleet: source-superproject source-support-files
	cp $(SPECSDIR)/$(@:rpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admiral-fleet.spec

rpm-admiralctl: source-superproject source-support-files
	cp $(SPECSDIR)/$(@:rpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admiralctl.spec

rpm-admiral-flagship: source-admiral-flagship source-support-files
	cp $(SPECSDIR)/$(@:rpm-%=%).spec $(RPMTOPDIR)/SPECS/
	rpmbuild -ba $(RPMFLAGS) $(RPMTOPDIR)/SPECS/admiral-flagship.spec

rpm-admiral-harbor: source-admiral-harbor source-support-files
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

# -- Build all RPMs in dependency order ----------------------------------

rpm: all-sources source-support-files
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
	@echo "=== Building admiral-harbor ==="
	$(MAKE) rpm-admiral-harbor
	@echo "=== All RPMs built ==="
	@find $(RPMDIR)/RPMS -name '*.rpm' -exec basename {} \;

rpm-admiral: all-sources source-support-files
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
	@echo "=== Building python-typing-extensions SRPM ==="
	$(MAKE) srpm-python-typing-extensions
	@echo "=== Building python-flask-alembic SRPM ==="
	$(MAKE) srpm-python-flask-alembic
	@echo "=== Building python-flask-login SRPM ==="
	$(MAKE) srpm-python-flask-login
	@echo "=== Building python-mistune SRPM ==="
	$(MAKE) srpm-python-mistune
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
