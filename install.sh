#!/bin/bash
# UltraSync Installer — merged from the Ultrareader and SolarSync installers.
# Installs the unified app (GUI + TUI), its venv, and a launcher.
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PREFIX="${HOME}/.local"
APP_DIR="${HOME}/.local/share/ultrasync"
CONFIG_DIR="${HOME}/.config/ultrasync"
CACHE_DIR="${HOME}/.cache/ultrasync"
SKIP_DEPS=false
UNINSTALL=false

print_info()    { echo -e "${BLUE}➜${NC} $1"; }
print_success() { echo -e "${GREEN}✅${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠️${NC} $1"; }
print_error()   { echo -e "${RED}❌${NC} $1"; }

usage() {
    cat <<EOF
UltraSync Installer

Usage: ./install.sh [OPTIONS]

Options:
    --uninstall     Remove UltraSync (config and cache are kept)
    --no-deps       Skip Python dependency installation (use system python3;
                    requires fastapi + uvicorn to already be installed)
    --no-hue        Accepted for compatibility with the parent installers.
                    Hue support is built into the Python package now, so this
                    only skips writing the optional hue env hints file.
    --prefix DIR    Launcher directory (default: ~/.local/bin)
    --help          Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --uninstall) UNINSTALL=true ;;
        --no-deps)   SKIP_DEPS=true ;;
        --no-hue)    NO_HUE=true ;;
        --prefix)    PREFIX="$2"; shift ;;
        --help)      usage; exit 0 ;;
        *) print_error "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

BIN_DIR="${PREFIX}/bin"
LAUNCHER="${BIN_DIR}/ultrasync"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$UNINSTALL" = true ]; then
    print_info "Removing UltraSync…"
    rm -f "$LAUNCHER"
    rm -rf "$APP_DIR"
    print_success "Removed. Config (${CONFIG_DIR}) and cache (${CACHE_DIR}) were kept."
    exit 0
fi

echo "=========================================="
echo "  UltraSync 1.0.0 Installer"
echo "=========================================="

command -v python3 >/dev/null || { print_error "python3 not found"; exit 1; }
print_info "Installing application files to ${APP_DIR}"
mkdir -p "$APP_DIR" "$BIN_DIR" "$CONFIG_DIR" "$CACHE_DIR"
rm -rf "${APP_DIR}/ultrasync"
cp -r "${SRC_DIR}/ultrasync" "$APP_DIR/"
cp "${SRC_DIR}/app_entry.py" "${SRC_DIR}/requirements.txt" "$APP_DIR/"
find "$APP_DIR" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true

if [ "$SKIP_DEPS" = true ]; then
    PY="python3"
    python3 -c "import fastapi, uvicorn" 2>/dev/null || {
        print_error "--no-deps given but fastapi/uvicorn are not importable by system python3"
        exit 1
    }
    print_warning "Using system python3 (deps assumed present)"
else
    print_info "Creating virtual environment…"
    python3 -m venv "${APP_DIR}/venv"
    "${APP_DIR}/venv/bin/pip" install -q --upgrade pip
    "${APP_DIR}/venv/bin/pip" install -q -r "${APP_DIR}/requirements.txt"
    PY="${APP_DIR}/venv/bin/python"
    print_success "Dependencies installed"
fi

print_info "Writing launcher ${LAUNCHER}"
cat > "$LAUNCHER" <<EOF
#!/bin/bash
# UltraSync launcher (installed)
cd "${APP_DIR}"
exec ${PY} app_entry.py "\$@"
EOF
chmod +x "$LAUNCHER"

if [ "${NO_HUE:-false}" != true ]; then
    cat > "${CONFIG_DIR}/hue-env.example" <<'EOF'
# Optional: Hue credentials via environment instead of config.json
# export HUE_BRIDGE_IP=192.168.1.x
# export HUE_API_KEY=your-bridge-username
EOF
fi

print_success "UltraSync installed."
echo ""
echo "  Run the GUI:   ultrasync            → http://127.0.0.1:8077"
echo "  Terminal UI:   ultrasync --tui"
echo "  One frame:     ultrasync --once"
echo "  Config:        ${CONFIG_DIR}/config.json"
echo ""
case ":$PATH:" in
    *":${BIN_DIR}:"*) ;;
    *) print_warning "${BIN_DIR} is not on your PATH — add it or call ${LAUNCHER} directly." ;;
esac
