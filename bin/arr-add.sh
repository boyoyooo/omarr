#!/usr/bin/env bash
# Add a movie (Radarr) or series (Sonarr) picked from arr-lookup.sh.
#
# Usage (radarr): arr-add.sh radarr <url> <apiKeyFile> <tmdbId> <qualityProfileId> <rootFolderPath> <monitored:true|false>
# Usage (sonarr): arr-add.sh sonarr <url> <apiKeyFile> <tvdbId> <qualityProfileId> <rootFolderPath> <monitored:true|false> <seasonFolder:true|false> <seasonsCsv|_all>
#   seasonsCsv: comma-separated season numbers to monitor (e.g. "1,2,3"), or
#   the literal "_all" to monitor every season (default addOptions.monitor=all).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./arr-common.sh
source "$DIR/arr-common.sh"

APP="${1:-}"; URL="${2:-}"; KEYFILE="${3:-}"; EXTID="${4:-}"
QPID="${5:-}"; ROOT="${6:-}"; MONITORED="${7:-}"
SEASON_FOLDER="${8:-true}"; SEASONS_CSV="${9:-_all}"

require_bins
validate_app "$APP"
validate_url "$URL"
APIKEY="$(load_apikey "$KEYFILE")"

[[ "$EXTID" =~ ^[0-9]+$ ]]        || emit_error "invalid id: $EXTID"
[[ "$QPID"  =~ ^[0-9]+$ ]]        || emit_error "invalid qualityProfileId: $QPID"
[[ "$ROOT" == /* ]]               || emit_error "invalid rootFolderPath: $ROOT"
[[ "$MONITORED" =~ ^(true|false)$ ]] || emit_error "invalid monitored: $MONITORED"
[[ "$SEASON_FOLDER" =~ ^(true|false)$ ]] || emit_error "invalid seasonFolder: $SEASON_FOLDER"
[[ "$SEASONS_CSV" =~ ^(_all|[0-9]+(,[0-9]+)*)$ ]] || emit_error "invalid seasonsCsv: $SEASONS_CSV"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

if [[ "$APP" == "radarr" ]]; then
  meta=$(arr_curl GET "${URL%/}/api/v3/movie/lookup/tmdb?tmdbId=${EXTID}" "$APIKEY" 10) \
    || emit_error "lookup unreachable: ${meta:0:160}"
  printf '%s' "$meta" | jq -c --argjson qp "$QPID" --arg root "$ROOT" --argjson mon "$MONITORED" '
    . + {
      qualityProfileId: $qp,
      rootFolderPath: $root,
      monitored: $mon,
      addOptions: { searchForMovie: $mon }
    }' > "$tmp" 2>/dev/null || emit_error "unexpected lookup payload"
  out=$(arr_curl POST "${URL%/}/api/v3/movie" "$APIKEY" 10 "$tmp") \
    || emit_error "add failed: ${out:0:200}"
else
  meta=$(arr_curl GET "${URL%/}/api/v3/series/lookup?term=tvdb:${EXTID}" "$APIKEY" 10) \
    || emit_error "lookup unreachable: ${meta:0:160}"

  if [[ "$SEASONS_CSV" == "_all" ]]; then
    # No explicit selection: keep every season as returned (specials off,
    # rest on, Sonarr's own default) and let addOptions.monitor drive it.
    printf '%s' "$meta" | jq -c --argjson qp "$QPID" --arg root "$ROOT" --argjson mon "$MONITORED" \
      --argjson sf "$SEASON_FOLDER" '
      .[0] + {
        qualityProfileId: $qp,
        rootFolderPath: $root,
        monitored: $mon,
        seasonFolder: $sf,
        addOptions: { monitor: "all", searchForMissingEpisodes: $mon }
      }' > "$tmp" 2>/dev/null || emit_error "unexpected lookup payload"
    out=$(arr_curl POST "${URL%/}/api/v3/series" "$APIKEY" 10 "$tmp") \
      || emit_error "add failed: ${out:0:200}"
  else
    # Explicit season selection from the UI. Sonarr does NOT support "only
    # monitor these specific seasons" as an addOptions.monitor strategy —
    # whatever strategy we pick ("all", "none", ...) gets asynchronously
    # re-applied to every season a moment after creation, silently
    # overwriting the seasons[].monitored array we submit in the POST body
    # (confirmed by testing: checking right after POST shows our values,
    # re-checking a few seconds later shows them overwritten). So instead:
    #   1) create with addOptions.monitor:"none" (avoids the "all" variant
    #      of this bug, which would monitor every season) and no auto-search
    #   2) once created, PUT (update, not add) the correct monitored flags —
    #      addOptions only applies to the add pipeline, so a plain update
    #      sticks with no further override
    #   3) explicitly trigger a SeasonSearch command per selected season,
    #      since the automatic search was disabled in step 1
    printf '%s' "$meta" | jq -c --argjson qp "$QPID" --arg root "$ROOT" \
      --argjson sf "$SEASON_FOLDER" '
      .[0] + {
        qualityProfileId: $qp,
        rootFolderPath: $root,
        monitored: false,
        seasonFolder: $sf,
        addOptions: { monitor: "none", searchForMissingEpisodes: false }
      }' > "$tmp" 2>/dev/null || emit_error "unexpected lookup payload"

    out=$(arr_curl POST "${URL%/}/api/v3/series" "$APIKEY" 10 "$tmp") \
      || emit_error "add failed: ${out:0:200}"
    new_id=$(printf '%s' "$out" | jq -r 'if type=="array" then empty else .id end' 2>/dev/null)
    if [[ -n "$new_id" && "$new_id" != "null" ]]; then
      sleep 2 # let Sonarr's post-add reconciliation job finish before overriding it

      current=$(arr_curl GET "${URL%/}/api/v3/series/${new_id}" "$APIKEY" 8) \
        || emit_error "post-add fetch failed: ${current:0:160}"
      printf '%s' "$current" | jq -c --argjson mon "$MONITORED" --arg seasons "$SEASONS_CSV" '
        ($seasons | split(",") | map(tonumber)) as $wanted |
        . + {
          monitored: $mon,
          seasons: (.seasons | map(.monitored = (.seasonNumber as $n | $wanted | index($n) != null)))
        }' > "$tmp" 2>/dev/null || emit_error "unexpected series payload"
      out=$(arr_curl PUT "${URL%/}/api/v3/series/${new_id}" "$APIKEY" 8 "$tmp") \
        || emit_error "post-add update failed: ${out:0:200}"

      if [[ "$MONITORED" == "true" ]]; then
        for season_num in ${SEASONS_CSV//,/ }; do
          cmd_tmp=$(mktemp)
          printf '{"name":"SeasonSearch","seriesId":%s,"seasonNumber":%s}' "$new_id" "$season_num" > "$cmd_tmp"
          arr_curl POST "${URL%/}/api/v3/command" "$APIKEY" 8 "$cmd_tmp" >/dev/null 2>&1
          rm -f "$cmd_tmp"
        done
      fi
    fi
  fi
fi

# Radarr/Sonarr echo the created resource back on success (an object with
# an "id"); validation errors come back as an array of {errorMessage:...}.
printf '%s' "$out" | jq -c 'if (type=="array") then {error: (map(.errorMessage // .) | join("; "))}
  elif .id then {ok: true, id: .id}
  else {error: "unexpected response"} end' 2>/dev/null || emit_error "unexpected add response"
