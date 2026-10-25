#!/usr/bin/env bash
set -euo pipefail
sudo systemd-run --quiet --collect --wait --pipe \
  --property=EnvironmentFile=/etc/admiral/harbor.env \
  /usr/bin/python3 /tmp/rc6-run-issue-181.py
