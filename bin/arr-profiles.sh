#!/usr/bin/env bash
# Quality profiles available for the Add tab's profile picker.
#
# Usage: arr-profiles.sh <radarr|sonarr> <url> <apiKeyFile>
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./arr-common.sh
source "$DIR/arr-common.sh"

APP="${1:-}"; URL="${2:-}"; KEYFILE="${3:-}"

require_bins
validate_app "$APP"
validate_url "$URL"
APIKEY="$(load_apikey "$KEYFILE")"

raw=$(arr_curl GET "${URL%/}/api/v3/qualityprofile" "$APIKEY" 8) \
  || emit_error "unreachable: ${raw:0:160}"

printf '%s' "$raw" | jq -c '[.[] | {id: .id, name: .name}] | sort_by(.name)' \
  2>/dev/null || emit_error "unexpected qualityprofile payload"
