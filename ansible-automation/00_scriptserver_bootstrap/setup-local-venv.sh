#!/usr/bin/env bash
# Superseded. Collection 00 now runs ON the script server, not on a laptop.
cat >&2 <<'EOF'
This script built a venv on the student laptop, which is no longer part of the
lab flow. The script server stages itself instead:

  ssh cisco@198.18.134.12
  git clone https://github.com/imanassypov/cisco-one-experience-lab-automation.git
  cd cisco-one-experience-lab-automation/ansible-automation/00_scriptserver_bootstrap
  ./stage-script-server.sh

EOF
exit 1
