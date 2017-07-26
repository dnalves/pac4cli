SHELL = /bin/bash
OS = $(shell uname)

PYTHON ?= "$(shell which python3 )"
TESTPORT ?= 23128

prefix = /usr/local
ifeq ($(OS), Linux)
	bindir := $(prefix)/bin
else
	bindir := $(prefix)/libexec
endif

libdir := $(prefix)/lib
pythonsitedir = "$(shell $(PYTHON) -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())" )"

default:
	@echo Nothing to build\; run make install.

pacparser:
	curl -L https://github.com/pacparser/pacparser/archive/1.3.7.tar.gz | tar -xz
	mv pacparser-1.3.7 pacparser

@ifeg ($(OS),Linux)
install-python-deps: requirements.txt pacparser
	pip3 install -r requirements.txt
	PYTHON=$(PYTHON) make -C pacparser/src install-pymod
endif

env: requirements.txt pacparser
	virtualenv -p $(PYTHON) env
	env/bin/pip install -r requirements.txt
	if [[ "$(OS)x" == "Linuxx" ]]; then 	\
		env/bin/pip install systemd &&		\
		env/bin/pip install txdbus;			\
	fi
	PYTHON=`pwd`/env/bin/python make -C pacparser/src install-pymod

run: env
	env/bin/python main.py -F DIRECT -p $(TESTPORT)

check: env
	./testrun.sh $(TESTPORT)

check-prev-proxies:
ifeq ($(OS),Linux)
	@RESULT=$$(grep -r --color -E '(http_proxy=)|(HTTP_PROXY=)|(https_proxy=)|(HTTPS_PROXY=)' $(DESTDIR)/etc/profile.d | cut -d' ' -f1 | sort | uniq) && \
	if [[ "x$$RESULT" != "x" ]];then \
		echo "Found these scripts setting the enviroment variables http_proxy & HTTP_PROXY:" && \
		while IFS=' ' read -ra FILES; do \
			for FILE in "$${FILES[@]}"; do \
				echo $${FILE::-1}; \
			done; \
		done  <<< "$$RESULT" && \
		echo "You have to either remove those definitions, or set them manually to 'localhost:3128'." && \
		echo "Otherwise, pac4cli may fail to work properly."; \
	fi
endif

install-service: check-prev-proxies
ifeq ($(OS),Linux)
	install -D -m 644 pac4cli.service $(DESTDIR)$(libdir)/systemd/system/pac4cli.service
	
	@sed -i -e 's@/usr/local/bin@'"$(bindir)"'@g' $(DESTDIR)$(libdir)/systemd/system/pac4cli.service

	install -D -m 755 trigger-pac4cli $(DESTDIR)/etc/NetworkManager/dispatcher.d/trigger-pac4cli
	install -D -m 755 pac4cli.sh $(DESTDIR)/etc/profile.d/pac4cli-proxy.sh
	install -D -m 644 pac4cli.config $(DESTDIR)/etc/pac4cli/pac4cli.config
else
	install -d $(DESTDIR)/Library/LaunchDaemons
	install -m 644 launchd/daemon.pac4cli.plist $(DESTDIR)/Library/LaunchDaemons/pac4cli.plist

	@sed -i -e 's@python@'"$(PYTHON)"'@g' $(DESTDIR)/Library/LaunchDaemons/pac4cli.plist

	install -d $(DESTDIR)/Library/LaunchAgents
	install -m 644 launchd/agent.pac4cli.plist $(DESTDIR)/Library/LaunchAgents/pac4cli.plist

	install -d $(DESTDIR)/Library/Preferences/.pac4cli
	install -m 644 pac4cli.config $(DESTDIR)/Library/Preferences/.pac4cli/pac4cli.config
endif

install-bin:
	install -d $(DESTDIR)$(bindir)
	install -m 755 main.py $(DESTDIR)$(bindir)/pac4cli
	@sed -i -e '1s+@PYTHON@+'$(PYTHON)'+' $(DESTDIR)$(bindir)/pac4cli

	install -d $(DESTDIR)$(pythonsitedir)
	install -m 644 pac4cli.py $(DESTDIR)$(pythonsitedir)/pac4cli.py
	install -m 644 wpad.py $(DESTDIR)$(pythonsitedir)/wpad.py
	install -m 644 servicemanager.py $(DESTDIR)$(pythonsitedir)/servicemanager.py

@ifeq ($(OS),Linux)
install: install-bin install-service
else
install: install-python-deps install-bin install-service
endif

uninstall:
	$(shell $(DESTDIR)/uninstall.sh $(DESTDIR)/)

clean:
	rm -rf env
	rm -rf pacparser
	rm -rf __pycache__

