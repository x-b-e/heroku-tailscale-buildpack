#!/usr/bin/env bash

set -e

log_info() {
  echo "-----> $*"
}

readonly TAILSCALE_DISABLE="${TAILSCALE_DISABLE:-0}"
readonly TAILSCALE_DEBUG="${TAILSCALE_DEBUG:-false}"
case "${TAILSCALE_DEBUG}" in
  1,true) set -ux ;;
esac

if [ -z "${TAILSCALE_AUTH_KEY:-}" ]; then
  log_info "You need to add TAILSCALE_AUTH_KEY to your environment variables."
else
  case "${TAILSCALE_DISABLE}" in
    1,true)
      exit 0
    ;;
    *)
      log_info "Waiting to allow tailscale to finish set up."
      sleep 10
      log_info "Running `tailscale status` You should see your accessible machines on your tailnet."
      tailscale status

      log_info "Running `proxychains4 -f vendor/proxychains-ng/proxychains.conf curl hello.ts.net` "
      log_info 'Things are working if you see <a href="https://hello.ts.net">Found</a>.'
      proxychains4 -f vendor/proxychains-ng/proxychains.conf curl hello.ts.net
      log_info "If you didn't see the Found message, then you may need to add the hello.ts.net machine into your tailnet."
      log_info "Test complete. I hope you had your fingers crossed!"
    ;;
  esac
fi
