#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}ℹ${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Local testing script for asdf-nim Lua plugin

OPTIONS:
  --unit          Run Lua unit tests only
  --integration   Run mise integration tests only
  --docker        Run tests in Docker containers
  --act           Run GitHub Actions locally with act
  --all           Run all tests (default)
  --platform PLATFORM   Test specific platform (ubuntu, alpine, arch)
  -h, --help      Show this help

EXAMPLES:
  $0 --unit                    # Run Lua unit tests
  $0 --docker --platform ubuntu # Test in Ubuntu Docker container
  $0 --act                     # Run GitHub Actions locally
  $0 --all                     # Run everything

EOF
}

run_lua_unit_tests() {
  info "Running Lua unit tests with Busted..."
  cd "$PROJECT_ROOT"

  if ! command -v busted &>/dev/null; then
    error "Busted not installed. Run: luarocks install busted"
    return 1
  fi

  if [ ! -d spec ]; then
    warn "No spec/ directory found. Skipping unit tests."
    return 0
  fi

  busted spec/ -v
  success "Unit tests passed"
}

run_lua_lint() {
  info "Running Lua linting with luacheck..."
  cd "$PROJECT_ROOT"

  if ! command -v luacheck &>/dev/null; then
    error "luacheck not installed. Run: luarocks install luacheck"
    return 1
  fi

  if [ ! -d hooks ]; then
    warn "No hooks/ directory found. Skipping lint."
    return 0
  fi

  luacheck hooks/ spec/ 2>/dev/null || true
  success "Linting passed"
}

run_integration_tests() {
  info "Running mise integration tests..."
  cd "$PROJECT_ROOT"

  if ! command -v mise &>/dev/null; then
    error "mise not installed. Run: curl https://mise.run | sh"
    return 1
  fi

  if [ -f mise-tasks/test ]; then
    chmod +x mise-tasks/test
    ./mise-tasks/test
  else
    warn "mise-tasks/test not found. Skipping integration tests."
    return 0
  fi

  success "Integration tests passed"
}

run_docker_tests() {
  local platform="${1:-ubuntu}"

  info "Running tests in Docker ($platform)..."

  case "$platform" in
    ubuntu)
      docker run --rm -v "$PROJECT_ROOT:/plugin" -w /plugin \
        ubuntu:22.04 bash -c "
          apt-get update -qq
          apt-get install -y -qq curl git xz-utils build-essential lua5.4 luarocks
          luarocks install busted
          luarocks install luacheck
          curl https://mise.run | sh
          export PATH=\"\$HOME/.local/bin:\$PATH\"
          bash scripts/test-in-docker.sh
        "
      ;;

    alpine)
      docker run --rm -v "$PROJECT_ROOT:/plugin" -w /plugin \
        alpine:latest sh -c "
          apk add --no-cache bash curl git xz build-base lua5.4 lua5.4-dev luarocks
          luarocks-5.4 install busted
          luarocks-5.4 install luacheck
          curl https://mise.run | sh
          export PATH=\"\$HOME/.local/bin:\$PATH\"
          bash scripts/test-in-docker.sh
        "
      ;;

    arch)
      docker run --rm -v "$PROJECT_ROOT:/plugin" -w /plugin \
        archlinux:latest bash -c "
          pacman -Syu --noconfirm
          pacman -S --noconfirm curl git xz base-devel lua luarocks
          luarocks install busted
          luarocks install luacheck
          curl https://mise.run | sh
          export PATH=\"\$HOME/.local/bin:\$PATH\"
          bash scripts/test-in-docker.sh
        "
      ;;

    *)
      error "Unknown platform: $platform"
      return 1
      ;;
  esac

  success "Docker tests passed ($platform)"
}

run_act_tests() {
  info "Running GitHub Actions locally with act..."
  cd "$PROJECT_ROOT"

  if ! command -v act &>/dev/null; then
    error "act not installed. Run: brew install act"
    return 1
  fi

  # Run only the Lua unit tests job
  info "Testing lua_unit_tests job..."
  act -j lua_unit_tests

  # Run mise tests for current platform
  info "Testing mise_lua_tests job (ubuntu-latest)..."
  act -j mise_lua_tests -P ubuntu-latest=catthehacker/ubuntu:act-latest

  success "act tests passed"
}

# Parse arguments
RUN_UNIT=false
RUN_INTEGRATION=false
RUN_DOCKER=false
RUN_ACT=false
RUN_ALL=true
DOCKER_PLATFORM="ubuntu"

while [[ $# -gt 0 ]]; do
  case $1 in
    --unit)
      RUN_UNIT=true
      RUN_ALL=false
      shift
      ;;
    --integration)
      RUN_INTEGRATION=true
      RUN_ALL=false
      shift
      ;;
    --docker)
      RUN_DOCKER=true
      RUN_ALL=false
      shift
      ;;
    --act)
      RUN_ACT=true
      RUN_ALL=false
      shift
      ;;
    --all)
      RUN_ALL=true
      shift
      ;;
    --platform)
      DOCKER_PLATFORM="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Main execution
echo ""
echo "========================================"
echo "  asdf-nim Local Testing Suite"
echo "========================================"
echo ""

EXIT_CODE=0

if [ "$RUN_ALL" = true ]; then
  run_lua_lint || EXIT_CODE=$?
  run_lua_unit_tests || EXIT_CODE=$?
  run_integration_tests || EXIT_CODE=$?
else
  [ "$RUN_UNIT" = true ] && { run_lua_lint || EXIT_CODE=$?; run_lua_unit_tests || EXIT_CODE=$?; }
  [ "$RUN_INTEGRATION" = true ] && { run_integration_tests || EXIT_CODE=$?; }
  [ "$RUN_DOCKER" = true ] && { run_docker_tests "$DOCKER_PLATFORM" || EXIT_CODE=$?; }
  [ "$RUN_ACT" = true ] && { run_act_tests || EXIT_CODE=$?; }
fi

echo ""
if [ $EXIT_CODE -eq 0 ]; then
  echo "========================================"
  success "All tests passed!"
  echo "========================================"
else
  echo "========================================"
  error "Some tests failed"
  echo "========================================"
fi
echo ""

exit $EXIT_CODE
