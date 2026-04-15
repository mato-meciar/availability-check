#!/usr/bin/env sh
set -eu

BASE_URL="https://wondamobile.com"
HANDLE="oppo-find-n6-5g-global-version-dual-sim"
VARIANT_ID="43880446001240"   # Orange
VARIANT_NAME="16+512GB / Orange"

: "${DISCORD_WEBHOOK:?DISCORD_WEBHOOK is required}"

LOG_FILE="${LOG_FILE:-/tmp/oppo_find_n6_orange_check.log}"
TMP_PRODUCT_JSON="${TMP_PRODUCT_JSON:-/tmp/oppo_find_n6_orange_product.json}"
TMP_CART_PROBE="${TMP_CART_PROBE:-/tmp/oppo_find_n6_orange_cart_probe.json}"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$1" >> "$LOG_FILE"
}

json_escape() {
  printf '%s' "$1" \
    | sed 's/\\/\\\\/g' \
    | sed 's/"/\\"/g'
}

send_discord() {
  message="$1"
  payload='{"content":"'"$(json_escape "$message")"'"}'

  curl -fsS -X POST "$DISCORD_WEBHOOK" \
    -H 'Content-Type: application/json' \
    --data "$payload" >/dev/null
}

get_product_json() {
  curl -fsS "${BASE_URL}/products/${HANDLE}.js" -o "$TMP_PRODUCT_JSON"
}

extract_available_from_json() {
  tr -d '\n' < "$TMP_PRODUCT_JSON" \
  | sed 's/},{/}\n{/g' \
  | grep "\"id\":${VARIANT_ID}" \
  | grep -Eo '"available":(true|false)' \
  | head -n1 \
  | cut -d: -f2
}

probe_cart_add() {
  http_code="$(curl -sS -o "$TMP_CART_PROBE" -w '%{http_code}' \
    "${BASE_URL}/cart/add.js" \
    -H 'Content-Type: application/json' \
    --data "{\"items\":[{\"id\":${VARIANT_ID},\"quantity\":1}]}" || true)"

  case "$http_code" in
    200) printf 'true' ;;
    422) printf 'false' ;;
    *)   printf 'unknown' ;;
  esac
}

main() {
  current_state="UNKNOWN"
  available="unknown"

  get_product_json

  available="$(extract_available_from_json || true)"
  if [ -z "$available" ]; then
    available="unknown"
  fi

  if [ "$available" = "unknown" ]; then
    available="$(probe_cart_add)"
  fi

  case "$available" in
    true)  current_state="AVAILABLE" ;;
    false) current_state="UNAVAILABLE" ;;
    *)     current_state="UNKNOWN" ;;
  esac

  log "${VARIANT_NAME}: ${current_state}"

  if [ "$current_state" = "AVAILABLE" ]; then
    msg="[$(timestamp)] Oppo Find N6 Orange is AVAILABLE: ${BASE_URL}/products/${HANDLE}"
    printf '%s\n' "$msg"
    send_discord "$msg"
    exit 0
  fi

  if [ "$current_state" = "UNAVAILABLE" ]; then
    printf '[%s] %s is unavailable\n' "$(timestamp)" "$VARIANT_NAME"
    exit 0
  fi

  printf '[%s] Unable to determine availability for %s\n' "$(timestamp)" "$VARIANT_NAME" >&2
  exit 1
}

main "$@"
