#!/bin/bash
# tools script emits boolean JSON.

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
"$root/scripts/tools" | jq -e '.aether == true or .aether == false' >/dev/null
"$root/scripts/tools" | jq -e 'has("sunwait") and has("uwsm")' >/dev/null
echo "tools ok"
