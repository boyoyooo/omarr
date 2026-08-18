#!/usr/bin/env bash
# Full library with audio language + subtitles, for the panel's Library tab.
# Fetched on-demand (panel open / refresh), not on the polling interval.
#
# Usage: arr-library.sh <radarr|sonarr> <url> <apiKeyFile>
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
  raw=$(arr_curl GET "${URL%/}/api/v3/movie" "$APIKEY" 10) \
    || emit_error "unreachable: ${raw:0:160}"
  printf '%s' "$raw" | jq -c '[.[] | {
    id: .id,
    title: .title,
    year: .year,
    monitored: .monitored,
    hasFile: .hasFile,
    sizeOnDisk: (.sizeOnDisk // 0),
    added: (.added // ""),
    poster: ((.images // [])[] | select(.coverType=="poster") | .remoteUrl) // "",
    overview: (.overview // "" | .[0:600]),
    imdbId: (.imdbId // ""),
    audioLanguages: [(.movieFile.languages // [])[] | .name],
    subtitles: (.movieFile.mediaInfo.subtitles // "" | select(. != "") | split(" / ")) // []
  }] | sort_by(.title | ascii_downcase)' 2>/dev/null || emit_error "unexpected movie payload"
else
  raw=$(arr_curl GET "${URL%/}/api/v3/series" "$APIKEY" 10) \
    || emit_error "unreachable: ${raw:0:160}"
  # Per-episode audio/subtitle language isn't fetched here: it would need
  # one extra API call per series (N+1 on 500+ series). Episode/file counts
  # only at this level; language detail would need a per-series drill-down
  # (out of scope for v1 — see manifest description).
  printf '%s' "$raw" | jq -c '[.[] | {
    id: .id,
    title: .title,
    year: .year,
    monitored: .monitored,
    hasFile: ((.statistics.episodeFileCount // 0) > 0),
    added: (.added // ""),
    poster: ((.images // [])[] | select(.coverType=="poster") | .remoteUrl) // "",
    overview: (.overview // "" | .[0:600]),
    imdbId: (.imdbId // ""),
    episodeCount: (.statistics.episodeCount // 0),
    episodeFileCount: (.statistics.episodeFileCount // 0),
    seasonFolder: .seasonFolder
  }] | sort_by(.title | ascii_downcase)' 2>/dev/null || emit_error "unexpected series payload"
fi
