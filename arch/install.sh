#!/bin/bash
# UltraSync Arch installer — builds the package with makepkg from a
# tarball of this repo, or falls back to a manual /usr/share install
# when makepkg is unavailable.
set -e
cd "$(dirname "$0")/.."
VERSION="2.0.0"

if command -v makepkg >/dev/null; then
    BUILD_DIR="$(mktemp -d)"
    echo "Packaging ultrasync-${VERSION} in ${BUILD_DIR}…"
    mkdir -p "${BUILD_DIR}/ultrasync-${VERSION}"
    cp -r ultrasync app_entry.py requirements.txt README.md arch "${BUILD_DIR}/ultrasync-${VERSION}/"
    find "${BUILD_DIR}/ultrasync-${VERSION}" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
    tar -czf "${BUILD_DIR}/ultrasync-${VERSION}.tar.gz" -C "${BUILD_DIR}" "ultrasync-${VERSION}"
    cp arch/PKGBUILD "${BUILD_DIR}/"
    (cd "${BUILD_DIR}" && makepkg -si --noconfirm)
    echo "Installed. Enable the GUI service:"
    echo "  systemctl --user enable --now ultrasync.service"
else
    echo "makepkg not found — manual install (requires sudo):"
    sudo install -dm755 /usr/share/ultrasync
    sudo cp -r ultrasync app_entry.py requirements.txt /usr/share/ultrasync/
    sudo install -Dm755 arch/ultrasync.sh /usr/bin/ultrasync
    sudo install -Dm644 arch/ultrasync.service /usr/lib/systemd/user/ultrasync.service
    sudo pip install --break-system-packages -r requirements.txt || \
        echo "Install python-fastapi and python-uvicorn with pacman instead."
    echo "Installed. Enable the GUI service:"
    echo "  systemctl --user enable --now ultrasync.service"
fi
