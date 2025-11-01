.PHONY: help test install-deps

help:
	@echo "asdf-nim local testing commands:"
	@echo ""
	@echo "  make test              - Run Bats tests"
	@echo "  make install-deps      - Install testing dependencies"
	@echo ""
	@echo "Note: For mise plugin, see https://github.com/elijahr/mise-nim"
	@echo ""

install-deps:
	@echo "Installing testing dependencies..."
	@command -v npm >/dev/null 2>&1 || { echo "Node.js/npm required"; exit 1; }
	npm install --include=dev

# Bats tests (asdf bash plugin)
test:
	@echo "Running Bats tests..."
	npm install --include=dev
	npm run test
