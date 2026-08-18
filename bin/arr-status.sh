#!/usr/bin/env bash
# Lightweight counts for the bar badge (polled every `interval` seconds).
#
# Usage: arr-status.sh <radarr|sonarr> <url> <apiKeyFile>
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./arr-common.sh
source "$DIR/arr-common.sh"

APP="${1:-}"; URL="${2:-}"; KEYFILE="${3:-}"

require_bins
validate_app "$APP"
validate_url "$URL"
APIKEY="$(load_apikey "$KEYFILE")"

if [[ "$APP" == "radarr" ]]; then
  ITEMS_PATH="/api/v3/movie"
else
  ITEMS_PATH="/api/v3/series"
fi

items_raw=$(arr_curl GET "${URL%/}${ITEMS_PATH}" "$APIKEY" 8) \
  || emit_error "unreachable: ${items_raw:0:160}"

queue_raw=$(arr_curl GET "${URL%/}/api/v3/queue?pageSize=1" "$APIKEY" 5) \
  || emit_error "queue unreachable: ${queue_raw:0:160}"

if [[ "$APP" == "radarr" ]]; then
  summary=$(printf '%s' "$items_raw" | jq -c '{
    total: length,
    monitored: [.[] | select(.monitored)] | length,
    missing: [.[] | select(.monitored and (.hasFile|not))] | length
  }' 2>/dev/null) || emit_error "unexpected movie payload"
else
  summary=$(printf '%s' "$items_raw" | jq -c '{
    total: length,
    monitored: [.[] | select(.monitored)] | length,
    missing: [.[] | select(.monitored) | .statistics.episodeCount - .statistics.episodeFileCount] | add // 0
  }' 2>/dev/null) || emit_error "unexpected series payload"
fi

queue_total=$(printf '%s' "$queue_raw" | jq -c '.totalRecords // 0' 2>/dev/null) || queue_total=0

printf '%s' "$summary" | jq -c --argjson q "$queue_total" '. + {queue: $q}'
