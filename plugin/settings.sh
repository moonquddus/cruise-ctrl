#!/bin/sh
file="$HERDR_PLUGIN_CONFIG_DIR/settings.toml"
mkdir -p "$HERDR_PLUGIN_CONFIG_DIR"
[ -f "$file" ] || cp "$HERDR_PLUGIN_ROOT/plugin/settings.toml" "$file"
exec ${EDITOR:-vi} "$file"
