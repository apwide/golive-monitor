#!/bin/bash

: "${PERIOD:=}"

last_execution="./.last-execution"
date "+%Y-%m-%dT%H-%M-%S"

if [ "${PERIOD}" = "" ] || [ "${PERIOD}" = "0" ]; then
    bash /app/golive-monitor.sh
else
    now=$(date +"%s")
    ((threshold = now - PERIOD * 60 + 5 ))
    if [ ! -f "$last_execution" ] || [ "$(cat "${last_execution}")" -lt $threshold ]; then
        echo "$now" > $last_execution
        bash /app/golive-monitor.sh
    fi
fi
