#!/usr/bin/env bash
# Shared helpers for arr-*.sh scripts. Sourced, never executed directly.
#
# Contract for every script that sources this: always exit 0, always emit
# exactly one JSON object on stdout ({"error":"..."} on failure).

emit_error() {
  printf '{"error":%s}\n' "$(printf '%s' "$1" | jq -Rs . 2>/dev/null || echo '"internal"')"
  exit 0
}

require_bins() {
  command -v jq   >/dev/null 2>&1 || { printf '{"error":"jq is not installed"}\n'; exit 0; }
  command -v curl >/dev/null 2>&1 || emit_error "curl is not installed"
}

# validate_url <url> -> sets HOST_OK=1, prints nothing. https only, no query
# string, no auth-in-url — keeps the same discipline as pve-status.sh.
validate_url() {
  [[ "$1" =~ ^https?://[A-Za-z0-9._-]+(:[0-9]{1,5})?$ ]] \
    || emit_error "invalid url: expected http(s)://host[:port]"
}

# validate_app <radarr|sonarr>
validate_app() {
  [[ "$1" =~ ^(radarr|sonarr)$ ]] || emit_error "invalid app: $1"
}

# load_apikey <keyFile> -> prints the key on stdout (trimmed), or errors out.
# Kept in its own function so callers never interpolate it into a command
# line; it only ever goes into a curl --config stream over stdin.
load_apikey() {
  local keyFile="$1"
  [[ -r "$keyFile" ]] || emit_error "api key file not readable: $keyFile"
  local key
  key="$(tr -d '[:space:]' < "$keyFile")"
  [[ "$key" =~ ^[A-Za-z0-9]{20,64}$ ]] || emit_error "api key file has unexpected content"
  printf '%s' "$key"
}

# arr_curl <method> <url> <apikey> <max-time> [json-body-file]
# Key and URL are fed to curl over stdin (--config -), never as argv, so
# neither shows up in /proc/<pid>/cmdline for another process on the box.
arr_curl() {
  local method="$1" url="$2" apikey="$3" maxtime="$4" bodyfile="${5:-}"
  local cfg
  cfg=$(mktemp)
  {
    printf 'header = "X-Api-Key: %s"\n' "$apikey"
    printf 'max-time = %s\n' "$maxtime"
    printf 'request = "%s"\n' "$method"
    printf 'url = "%s"\n' "$url"
    printf 'silent\n'
    printf 'show-error\n'
    printf 'fail-with-body\n'
    if [[ -n "$bodyfile" ]]; then
      printf 'header = "Content-Type: application/json"\n'
      printf 'data-binary = @%s\n' "$bodyfile"
    fi
  } > "$cfg"
  curl --config "$cfg" 2>&1
  local rc=$?
  rm -f "$cfg"
  return $rc
}
