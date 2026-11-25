PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
VERSION ?= 1.0.0
WINPKG = upscale-gif-$(VERSION)-windows
WINFILES = upscale-gif.ps1 install.ps1 Install.cmd README.txt

.PHONY: install uninstall check windows clean

install:
	install -Dm755 upscale-gif $(DESTDIR)$(BINDIR)/upscale-gif

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/upscale-gif

check:
	bash -n upscale-gif
	./upscale-gif -c

# Windows zip: CRLF line endings, LICENSE as LICENSE.txt, version stamped into the installer
windows:
	rm -rf dist/$(WINPKG) dist/$(WINPKG).zip
	mkdir -p dist/$(WINPKG)
	for f in $(WINFILES) "Upscale GIF.cmd"; do sed 's/\r*$$/\r/' "windows/$$f" >"dist/$(WINPKG)/$$f"; done
	sed -i "s/^\$$Version = 'dev'/\$$Version = '$(VERSION)'/" dist/$(WINPKG)/install.ps1
	sed 's/\r*$$/\r/' LICENSE >dist/$(WINPKG)/LICENSE.txt
	cd dist && python3 -m zipfile -c $(WINPKG).zip $(WINPKG)
	@echo "Built dist/$(WINPKG).zip"

clean:
	rm -rf dist
