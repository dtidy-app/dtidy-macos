# dtidy - build, install, and man page tasks. See README.md.
#
#   make                       build the release binary and completion scripts
#   sudo make install          install under PREFIX (default /usr/local)
#   sudo make uninstall        remove what install put there
#   make man                   regenerate docs/man/dtidy.1 from the help text
#   make check-man             fail if docs/man/dtidy.1 is out of date

PREFIX ?= /usr/local
DESTDIR ?=

BINDIR  = $(DESTDIR)$(PREFIX)/bin
MANDIR  = $(DESTDIR)$(PREFIX)/share/man/man1
ZSHDIR  = $(DESTDIR)$(PREFIX)/share/zsh/site-functions
BASHDIR = $(DESTDIR)$(PREFIX)/share/bash-completion/completions
FISHDIR = $(DESTDIR)$(PREFIX)/share/fish/vendor_completions.d

BIN         = .build/release/dtidy
MANPAGE     = docs/man/dtidy.1
GENERATED   = .build/plugins/GenerateManual/outputs/dtidy/dtidy.1
COMPLETIONS = .build/completions/_dtidy .build/completions/dtidy .build/completions/dtidy.fish
SOURCES    := Package.swift Package.resolved $(shell find Sources -name '*.swift')

.PHONY: all build completions install uninstall man check-man

all: build completions

# A file target, so `sudo make install` after `make` reuses the build instead of rebuilding as root.
build: $(BIN)

$(BIN): $(SOURCES)
	swift build -c release

completions: $(COMPLETIONS)

.build/completions/_dtidy: $(BIN)
	mkdir -p .build/completions
	$(BIN) --generate-completion-script zsh > $@

.build/completions/dtidy: $(BIN)
	mkdir -p .build/completions
	$(BIN) --generate-completion-script bash > $@

.build/completions/dtidy.fish: $(BIN)
	mkdir -p .build/completions
	$(BIN) --generate-completion-script fish > $@

install: all
	install -d $(BINDIR) $(MANDIR) $(ZSHDIR) $(BASHDIR) $(FISHDIR)
	install -m 755 $(BIN) $(BINDIR)/dtidy
	install -m 644 $(MANPAGE) $(MANDIR)/dtidy.1
	install -m 644 .build/completions/_dtidy $(ZSHDIR)/_dtidy
	install -m 644 .build/completions/dtidy $(BASHDIR)/dtidy
	install -m 644 .build/completions/dtidy.fish $(FISHDIR)/dtidy.fish

uninstall:
	rm -f $(BINDIR)/dtidy $(MANDIR)/dtidy.1 $(ZSHDIR)/_dtidy $(BASHDIR)/dtidy $(FISHDIR)/dtidy.fish

man:
	swift package generate-manual
	mkdir -p docs/man
	cp $(GENERATED) $(MANPAGE)

# The generated page carries today's date on its .Dd line, so that line is left out of the diff.
check-man:
	swift package generate-manual
	@grep -v '^\.Dd ' $(MANPAGE) > .build/dtidy.1.committed
	@grep -v '^\.Dd ' $(GENERATED) > .build/dtidy.1.current
	@diff -u .build/dtidy.1.committed .build/dtidy.1.current \
		|| { echo "$(MANPAGE) is out of date: run 'make man' and commit the result." >&2; exit 1; }
	@echo "$(MANPAGE) is up to date."
