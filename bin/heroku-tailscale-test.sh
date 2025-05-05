#!/usr/bin/env bash

set -e

function log() {
  echo "-----> $*"
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

if [ -z "$TAILSCALE_AUTH_KEY" ]; then
  log "You need to add TAILSCALE_AUTH_KEY to your environment variables."
else
  log "Waiting to allow tailscale to finish set up."
  wait_for_tailscale_running
  log "Running `tailscale status` You should see your accessible machines on your tailnet."
  tailscale status
  if tailscale status | grep hello; then
    log "SUCCESS: hello.ts.net is connected"
  else
    log "FAILURE: hello.ts.net is not connected"
  fi
  # log 'Things are working if you see <a href="https://hello.ts.net">Found</a>.'
  # proxychains4 -f vendor/proxychains-ng/proxychains.conf curl hello.ts.net
  # log "If you didn't see the Found message, then you may need to add the hello.ts.net machine into your tailnet."
  # log "Test complete. I hope you had your fingers crossed!"
fi
