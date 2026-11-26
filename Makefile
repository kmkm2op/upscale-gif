PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
VERSION ?= 1.0.0

.PHONY: install uninstall check release release-linux release-windows clean

# Installs the script alone; it then uses ffmpeg and Upscayl from the system
install:
	install -Dm755 upscale-gif $(DESTDIR)$(BINDIR)/upscale-gif

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/upscale-gif

check:
	bash -n upscale-gif
	./upscale-gif -c

# Self-contained release packages in dist/ (see packaging/build.sh)
release:
	packaging/build.sh $(VERSION)

release-linux:
	packaging/build.sh $(VERSION) linux

release-windows:
	packaging/build.sh $(VERSION) windows

clean:
	rm -rf dist
