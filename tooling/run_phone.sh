#!/usr/bin/env bash
set -euo pipefail

mac_ip="${MAC_IP:-$(ipconfig getifaddr en0)}"
device_id="${1:-}"

if [[ -z "${mac_ip}" ]]; then
  echo "Could not detect Mac IP on en0. Set MAC_IP manually and retry."
  exit 1
fi

if [[ -z "${device_id}" ]]; then
  echo "Usage: tooling/run_phone.sh <device-id>"
  echo "Find device ids with: flutter devices"
  exit 1
fi

flutter run \
  -d "${device_id}" \
  --dart-define="AI_PROXY_URL=http://${mac_ip}:8787/api/analyze-outfit"
