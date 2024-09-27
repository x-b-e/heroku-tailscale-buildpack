#!/usr/bin/env bash

set -e

if [ -z "$TAILSCALE_AUTH_KEY" ]; then
  echo "[tailscale]: Will not be available because TAILSCALE_AUTH_KEY is not set"

else
  if [ -z "$TAILSCALE_HOSTNAME" ]; then
    if [ -z "$HEROKU_APP_NAME" ]; then
      tailscale_hostname=$(hostname)
    else
      # Only use the first 8 characters of the commit sha.
      # Swap the . and _ in the dyno with a - since tailscale doesn't
      # allow for periods.
      DYNO=${DYNO//./-}
      DYNO=${DYNO//_/-}
      tailscale_hostname=${HEROKU_SLUG_COMMIT:0:8}"-$DYNO-$HEROKU_APP_NAME"
    fi
  else
    tailscale_hostname="$TAILSCALE_HOSTNAME"
  fi
  tailscaled -cleanup > /dev/null 2>&1
  (tailscaled -verbose ${TAILSCALED_VERBOSE:--1} --tun=userspace-networking --socks5-server=localhost:1055 > /dev/null 2>&1 &)  
  tailscale up \
    --authkey="${TAILSCALE_AUTH_KEY}?preauthorized=true&ephemeral=true" \
    --hostname="$tailscale_hostname" \                    
    --advertise-tags=${TAILSCALE_ADVERTISE_TAGS:-} \
    --timeout=15s \
    ${TAILSCALE_ADDITIONAL_ARGS}

  export ALL_PROXY=socks5://localhost:1055/
  echo "[tailscale]: Connected to tailnet as hostname=$tailscale_hostname; SOCKS5 proxy available at localhost:1055"
fi