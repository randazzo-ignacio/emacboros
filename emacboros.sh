#!/usr/bin/env bash

# Emacboros --- Agent orchestration in Emacs
# Copyright (C) 2026 Ignacio Agustín Randazzo
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -euo pipefail

# =============================================================================
# Agentic Emacs -- Container Management Script
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="emacboros"
CONTAINER_NAME="emacboros"

# =============================================================================
# Build the container image from Containerfile
# =============================================================================
build() {
    echo "[emacboros] Building ${IMAGE_NAME} from ${SCRIPT_DIR}/Containerfile..."
    podman build -t "${IMAGE_NAME}" -f "${SCRIPT_DIR}/Containerfile"
    echo "[emacboros] Build complete."
}

# =============================================================================
# Run the container with .emacs.d mounted
# =============================================================================
run() {
    echo "[emacboros] Starting ${CONTAINER_NAME}..."
    podman run \
        --rm -it --name "${CONTAINER_NAME}" \
	-v "$(dirname ${BASH_SOURCE[0]})/agents.d:/root/.emacs.d/agents.d:Z" \
	-v "$(dirname ${BASH_SOURCE[0]})/.git:/root/.emacs.d/.git:ro" \
        "${IMAGE_NAME}"
}

# =============================================================================
# Rebuild and run
# =============================================================================
rebuild() {
    build
    run
}

# =============================================================================
# Entrypoint
# =============================================================================
case "${1:-rebuild}" in
    build)
        build
        ;;
    run)
        run
        ;;
    rebuild)
        rebuild
        ;;
    *)
        echo "Usage: $0 {build|run|rebuild}"
        echo "  build    - Build the container image from Containerfile"
        echo "  run      - Run the container (default)"
        echo "  rebuild  - Build and run"
        exit 1
        ;;
esac
