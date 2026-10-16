#!/bin/bash
cd "$(dirname "$0")" || exit 1
littlelift_status=0
python3 scripts/run_simulators.py || littlelift_status=$?
echo
read -r -p 'Press Return to close this window… ' littlelift_reply
exit "$littlelift_status"
