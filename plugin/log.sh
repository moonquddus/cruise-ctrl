#!/bin/sh
log="$HERDR_PLUGIN_STATE_DIR/approvals.log"
mkdir -p "$HERDR_PLUGIN_STATE_DIR"
touch "$log"
exec tail -n 100 -f "$log"
