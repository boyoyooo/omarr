#!/usr/bin/env bash
# Search Radarr/Sonarr's configured indexers (via /lookup, itself backed by
# Prowlarr) for something to add. Read-only — does not add anything.
#
# Usage: arr-lookup.sh <radarr|sonarr> <url> <apiKeyFile> <term>
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./arr-common.sh
source "$DIR/arr-common.sh"

APP="${1:-}"; URL="${2:-}"; KEYFILE="${3:-}"; TERM="${4:-}"

require_bins
validate_app "$APP"
validate_url "$URL"
APIKEY="$(load_apikey "$KEYFILE")"

[[ -n "$TERM" ]] || emit_error "empty search term"
[[ ${#TERM} -le 200 ]] || emit_error "search term too long"

# curl handles URL-encoding of the query param via --data-urlencode only in
# POST/GET-with-data mode; here we build the encoded string ourselves with
# jq (@uri) to keep it a plain GET, matching the arr_curl helper's contract.
ENC_TERM=$(printf '%s' "$TERM" | jq -Rr '@uri' 2>/dev/null) || emit_error "encoding failed"

if [[ "$APP" == "radarr" ]]; then
  raw=$(arr_curl GET "${URL%/}/api/v3/movie/lookup?term=${ENC_TERM}" "$APIKEY" 10) \
    || emit_error "unreachable: ${raw:0:160}"
  printf '%s' "$raw" | jq -c '[.[0:25][] | {
    tmdbId: .tmdbId,
    title: .title,
    year: .year,
    overview: (.overview // "" | .[0:600]),
    imdbId: (.imdbId // ""),
    poster: ((.images // [])[] | select(.coverType=="poster") | .remoteUrl) // "",
    alreadyAdded: (.id != null and .id > 0)
  }]' 2>/dev/null || emit_error "unexpected lookup payload"
else
  raw=$(arr_curl GET "${URL%/}/api/v3/series/lookup?term=${ENC_TERM}" "$APIKEY" 10) \
    || emit_error "unreachable: ${raw:0:160}"
  printf '%s' "$raw" | jq -c '[.[0:25][] | {
    tvdbId: .tvdbId,
    title: .title,
    year: .year,
    overview: (.overview // "" | .[0:600]),
    imdbId: (.imdbId // ""),
    poster: ((.images // [])[] | select(.coverType=="poster") | .remoteUrl) // "",
    alreadyAdded: (.id != null and .id > 0),
    seasons: [(.seasons // [])[] | select(.seasonNumber > 0) | {seasonNumber, monitored}]
  }]' 2>/dev/null || emit_error "unexpected lookup payload"
fi
