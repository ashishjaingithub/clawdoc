.PHONY: test lint check-deps install clean help

# Default target
help:
	@echo "clawdoc — agent session diagnostics"
	@echo ""
	@echo "Targets:"
	@echo "  make test         Run the full test suite (35 tests)"
	@echo "  make lint         Run shellcheck on all scripts"
	@echo "  make check-deps   Verify required tools are installed"
	@echo "  make install      Install to ~/.openclaw/skills/clawdoc"
	@echo "  make clean        Remove temp files"
	@echo "  make help         Show this help"

test:
	@bash tests/test-detection.sh

lint:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "shellcheck not found — install with: brew install shellcheck  OR  apt install shellcheck"; \
		exit 1; \
	fi
	@echo "Running shellcheck..."
	@shellcheck -x scripts/examine.sh
	@shellcheck -x scripts/diagnose.sh
	@shellcheck -x scripts/cost-waterfall.sh
	@shellcheck -x scripts/headline.sh
	@shellcheck -x scripts/prescribe.sh
	@shellcheck -x scripts/history.sh
	@shellcheck -x tests/test-detection.sh
	@echo "All scripts passed shellcheck."

check-deps:
	@bash scripts/check-deps.sh

install:
	@bash install.sh

clean:
	@rm -f /tmp/clawdoc_* 2>/dev/null || true
	@echo "Cleaned."
