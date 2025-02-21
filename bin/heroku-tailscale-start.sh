#!/usr/bin/env bash

set -eo pipefail

readonly TAILSCALE_DISABLE="${TAILSCALE_DISABLE:-0}"
readonly TAILSCALE_DEBUG="${TAILSCALE_DEBUG:-false}"
if [ "${TAILSCALE_DEBUG}" = "true" ]; then
  set -ux
fi
readonly TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
readonly ALL_PROXY_IP_PORT="localhost:1055"
readonly TAILSCALED_CLEANUP="${TAILSCALED_CLEANUP:-}"
readonly TAILSCALED_VERBOSE="${TAILSCALED_VERBOSE:--1}"
readonly TAILSCALE_ADVERTISE_TAGS="${TAILSCALE_ADVERTISE_TAGS:-}"
readonly TAILSCALE_ADDITIONAL_ARGS="${TAILSCALE_ADDITIONAL_ARGS:---timeout=15s}"
#  --accept-dns=true
#  --accept-routes=false
#  --advertise-exit-node=false
#  --shields-up=false
#  --timeout=15s

# Usage:
#   cmd="$(stringify_args $*)"
stringify_args() {
  local old_ifs; old_ifs="$IFS" IFS=' ';
  local args; args="$*"; IFS="$old_ifs"
  echo "$args"
}
topic()    { echo "-----> $(stringify_args "$@")" >&2 ; }
info()     { echo "       $(stringify_args "$@")" >&2 ; }
debug()    { if [ "$TAILSCALE_DEBUG" = "true" ]; then echo -e "[DEBUG]       $(stringify_args "$@")" >&2 ; fi ; }
error()    { echo " !     $(stringify_args "$@")" ;  >&2 exit 1  ; }
indent() {
  local command; command='s/^/       /'
  case $(uname) in
    Darwin) sed -l "$command";;
    *)      sed -u "$command";;
  esac
}

if [ "${TAILSCALE_DISABLE}" = "1" ]; then
  info "[tailscale]: Is disabled via TAILSCALE_DISABLE"
  exit 0
fi
if [ -z "${TAILSCALE_AUTH_KEY}" ]; then
  info "[tailscale]: Will not be available because TAILSCALE_AUTH_KEY is not set"
  exit 0
fi

build_tailscale_hostname() {
  if [ -z "$HEROKU_APP_NAME" ]; then
    hostname
  else
    # Only use the first 8 characters of the commit sha.
    # Swap the . and _ in the dyno with a - since tailscale doesn't
    # allow for periods.
    local dyno="${DYNO:-}"
    dyno=${dyno//./-}
    dyno=${dyno//_/-}
    echo "heroku-$HEROKU_APP_NAME-${HEROKU_SLUG_COMMIT:0:8}-$dyno"
  fi
}

readonly TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-"$(build_tailscale_hostname)"}"

run_cmd() {
  local cmd
  cmd="$*"
  debug "cmd=${cmd}"
  eval "$cmd"
}

wait_for_tailscale_running() {
  local timeout
  timeout=50    # Timeout in tenths of a second
  local interval
  interval=5    # 0.5 second intervals (expressed in tenths)
  local elapsed
  elapsed=0

  while [ "$elapsed" -lt "$timeout" ]; do
    if tailscale status -json | grep -q 'Running' &> /dev/null; then
      return 0
    fi
    sleep 0.5 # fake decimal math
    elapsed=$((elapsed + interval))
  done

  return 1
}

main() {
  topic "[tailscale] starting up"
  # see https://tailscale.com/kb/1107/heroku
  if [ "${TAILSCALED_CLEANUP}" = "true" ]; then
    echo "[tailscale]: tailscaled -cleanup"
    run_cmd tailscaled -cleanup
  fi

  debug "[tailscale]: tailscaled --tun --socks5-server &"
  # https://tailscale.com/kb/1111/ephemeral-nodes#faq
  run_cmd tailscaled \
    -verbose "${TAILSCALED_VERBOSE}" \
    --tun=userspace-networking \
    --socks5-server=$ALL_PROXY_IP_PORT \
    --state=mem \
    &
  debug "[tailscale]: tailscale up"
  run_cmd tailscale up \
    --auth-key="${TAILSCALE_AUTH_KEY}" \
    --hostname="${TAILSCALE_HOSTNAME}" \
    --advertise-tags="${TAILSCALE_ADVERTISE_TAGS}" \
    "${TAILSCALE_ADDITIONAL_ARGS}"
  debug "[tailscale]: tailscale started"

  export ALL_PROXY="socks5://${ALL_PROXY_IP_PORT}/"

  if wait_for_tailscale_running; then
    info "[tailscale]: Connected to tailnet as hostname=$TAILSCALE_HOSTNAME; SOCKS5 proxy available at ${ALL_PROXY_IP_PORT}"
  else
    info "[tailscale]: Warning - Backend did not reach 'Running' state within timeout"
  fi
}

main
