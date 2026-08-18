#!/usr/bin/env bash
# Download queue, as tracked by Radarr/Sonarr itself — this already merges
# qBittorrent + NZBGet (or any other configured download client) into one
# view, per item, so there is no need to hit qBittorrent's/NZBGet's own
# APIs separately and merge them by hand.
#
# Usage: arr-queue.sh <radarr|sonarr> <url> <apiKeyFile>
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./arr-common.sh
source "$DIR/arr-common.sh"

APP="${1:-}"; URL="${2:-}"; KEYFILE="${3:-}"

require_bins
validate_app "$APP"
validate_url "$URL"
APIKEY="$(load_apikey "$KEYFILE")"

raw=$(arr_curl GET "${URL%/}/api/v3/queue?pageSize=200&includeSeries=true&includeEpisode=true" "$APIKEY" 8) \
  || emit_error "unreachable: ${raw:0:160}"

printf '%s' "$raw" | jq -c '[.records[] | {
  id: .id,
  title: (.title // (.series.title // .movie.title // "?")),
  status: .status,
  trackedStatus: (.trackedDownloadStatus // ""),
  downloadClient: (.downloadClient // "?"),
  protocol: (.protocol // "?"),
  size: (.size // 0),
  sizeleft: (.sizeleft // 0),
  progress: (if (.size // 0) > 0 then (100 - ((.sizeleft // 0) * 100.0 / .size)) else 0 end),
  errorMessage: (.errorMessage // ((.statusMessages // []) | map(.messages // []) | add | join("; ")) // "")
}]' 2>/dev/null || emit_error "unexpected queue payload"
