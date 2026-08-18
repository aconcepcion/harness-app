APP      = Harness
VERSION  = 3.1.0
BUILD    = build
APPDIR   = $(BUILD)/$(APP).app
SRC      = src/main.m src/HAEnvironment.m src/HAServer.m src/HAUpdater.m src/HAPreferencesWindow.m src/HASleepGuard.m src/HAInstaller.m
LIBSRC   = src/HAEnvironment.m src/HAServer.m src/HAUpdater.m src/HASleepGuard.m src/HAInstaller.m
HDR      = $(wildcard src/*.h)
ARCHS   ?= -arch arm64 -arch x86_64
CFLAGS   = -fobjc-arc -Os -Wl,-dead_strip -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=13.0
FW       = -framework Cocoa -framework WebKit -framework IOKit
TESTS    = $(patsubst tests/%.m,$(BUILD)/%,$(wildcard tests/test_*.m))

.PHONY: all app install test smoke clean
all: app
app: $(APPDIR)

$(BUILD)/$(APP): $(SRC) $(HDR) | $(BUILD)
	clang $(CFLAGS) $(ARCHS) -o $@ $(SRC) $(FW)

$(BUILD)/icontool: src/icon.m | $(BUILD)
	clang -fobjc-arc -O2 -o $@ src/icon.m -framework AppKit

$(BUILD)/AppIcon.icns: $(BUILD)/icontool scripts/make-icon.sh $(wildcard Resources/AppIcon-1024.png)
	scripts/make-icon.sh $(BUILD)/icontool $@

$(APPDIR): $(BUILD)/$(APP) $(BUILD)/AppIcon.icns Resources/Info.plist.in
	rm -rf $(APPDIR)
	mkdir -p $(APPDIR)/Contents/MacOS $(APPDIR)/Contents/Resources
	sed 's/@VERSION@/$(VERSION)/g' Resources/Info.plist.in > $(APPDIR)/Contents/Info.plist
	cp $(BUILD)/$(APP) $(APPDIR)/Contents/MacOS/$(APP)
	strip -x $(APPDIR)/Contents/MacOS/$(APP)
	cp $(BUILD)/AppIcon.icns $(APPDIR)/Contents/Resources/AppIcon.icns
	codesign --force -s - $(APPDIR)
	@echo "built $(APPDIR)"; lipo -info $(APPDIR)/Contents/MacOS/$(APP)

install: app
	rm -rf "/Applications/$(APP).app"
	cp -R $(APPDIR) "/Applications/$(APP).app"
	@echo "installed /Applications/$(APP).app"

$(BUILD)/fakedsh: tests/fakedsh.c | $(BUILD)
	clang -O2 -o $@ tests/fakedsh.c

$(BUILD)/test_%: tests/test_%.m $(LIBSRC) $(HDR) tests/HATest.h | $(BUILD)
	clang $(CFLAGS) -Isrc -o $@ $< $(LIBSRC) -framework Foundation -framework AppKit -framework IOKit

test: $(TESTS) $(BUILD)/fakedsh
	@rc=0; for t in $(TESTS); do FAKEDSH=$(abspath $(BUILD)/fakedsh) $$t || rc=1; done; exit $$rc

smoke: app $(BUILD)/fakedsh
	scripts/smoke.sh $(abspath $(APPDIR)) $(abspath $(BUILD)/fakedsh)

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
