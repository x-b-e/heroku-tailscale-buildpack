#!/usr/bin/env bash

set -e

if [ -z "$TAILSCALE_AUTH_KEY" ]; then
  echo "[tailscale]: Will not be available because TAILSCALE_AUTH_KEY is not set"
  exit 0
fi

wait_for_tailscale_running() {
  local timeout
  timeout=5     # Timeout in seconds
  local interval
  interval=0.5  # Interval between checks
  local elapsed
  elapsed=0

  while [ "$elapsed" -lt "$timeout" ]; do
    if tailscale status -json | grep -q 'Running'; then
      return 0
    fi
    sleep "$interval"
    elapsed=$(echo "$elapsed + $interval" | bc)
  done

  return 1
}

if [ -z "$TAILSCALE_HOSTNAME" ]; then
  if [ -z "$HEROKU_APP_NAME" ]; then
    TAILSCALE_HOSTNAME=$(hostname)
  else
    # Only use the first 8 characters of the commit sha.
    # Swap the . and _ in the dyno with a - since tailscale doesn't
    # allow for periods.
    DYNO=${DYNO//./-}
    DYNO=${DYNO//_/-}
    TAILSCALE_HOSTNAME="heroku-$HEROKU_APP_NAME-${HEROKU_SLUG_COMMIT:0:8}-$DYNO"
  fi
fi
# see https://tailscale.com/kb/1107/heroku
echo "[tailscale]: tailscaled -cleanup"
tailscaled -cleanup
echo "[tailscale]: tailscaled --tun --socks5-server &"
ALL_PROXY_IP_PORT="localhost:1055"
tailscaled -verbose "${TAILSCALED_VERBOSE:--1}" --tun=userspace-networking --socks5-server=$ALL_PROXY_IP_PORT &
echo "[tailscale]: tailscale up"
tailscale up \
  --auth-key="${TAILSCALE_AUTH_KEY}" \
  --hostname="${TAILSCALE_HOSTNAME}" \
  --advertise-tags="${TAILSCALE_ADVERTISE_TAGS:-}" \
  "${TAILSCALE_ADDITIONAL_ARGS:---timeout=15s}"
echo "[tailscale]: tailscale started"

export ALL_PROXY="socks5://${ALL_PROXY_IP_PORT}/"

if wait_for_tailscale_running; then
  echo "[tailscale]: Connected to tailnet as hostname=$TAILSCALE_HOSTNAME; SOCKS5 proxy available at ${ALL_PROXY_IP_PORT}"
else
  echo "[tailscale]: Warning - Backend did not reach 'Running' state within timeout"
fi
