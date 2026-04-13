#!/usr/bin/env bash
# watch_detection.sh — Host-side watcher that blocks on the detection FIFO and
# kills the Docker container as soon as the filesystem signals a detection.
#
# Usage: ./watch_detection.sh <container-name-or-id>
#
# The FIFO directory must be bind-mounted into the container as /signal (read-write).
# Example docker run flag:
#   --mount type=bind,source="$(pwd)/signal",target=/signal
#
# Security notes:
#   - The container can only WRITE to the FIFO; the host script only reads from it.
#   - No network port is opened. The only shared surface is the single FIFO file.
#   - Even if malware writes to the pipe, the only consequence is triggering its
#     own container kill — it cannot read host data or execute anything on the host.

set -euo pipefail

CONTAINER="${1:?Usage: $0 <container-name-or-id>}"
SIGNAL_DIR="$(dirname "$0")/signal"
SIGNAL_PIPE="$SIGNAL_DIR/kill_signal"

# Create the signal directory and FIFO if they do not exist yet.
mkdir -p "$SIGNAL_DIR"
if [ ! -p "$SIGNAL_PIPE" ]; then
    mkfifo "$SIGNAL_PIPE"
fi

# Restrict permissions: container user can write, host script (owner) can read.
chmod 220 "$SIGNAL_PIPE"

echo "[watcher] Listening on $SIGNAL_PIPE for container '$CONTAINER'..."

# Block until the filesystem writes to the pipe, then kill the container.
# 'read' returns as soon as the write end sends any data.
if read -r _ < "$SIGNAL_PIPE"; then
    echo "[watcher] Detection signal received — killing container '$CONTAINER'."
    docker kill "$CONTAINER"
fi
