#!/bin/bash
# Smoke-test ThemeBook catalog JSON.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out=$("$root/scripts/catalog")
echo "$out" | jq -e 'type == "array" and length > 0' >/dev/null
echo "$out" | jq -e 'all(.[]; has("slug") and has("name") and has("source") and has("colors"))' >/dev/null
echo "$out" | jq -e 'any(.[]; .current == true)' >/dev/null
echo "catalog ok ($("$root/scripts/catalog" | jq 'length') themes)"
