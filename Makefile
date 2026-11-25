PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

.PHONY: install uninstall check

install:
	install -Dm755 upscale-gif $(DESTDIR)$(BINDIR)/upscale-gif

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/upscale-gif

check:
	bash -n upscale-gif
	./upscale-gif -c
