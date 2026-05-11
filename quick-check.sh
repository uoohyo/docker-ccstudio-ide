#!/bin/bash
# Quick status check for v7.1.0.00016

echo "=== Quick Status Check ==="
echo ""

files=$(docker exec ccs-v7-7.1.0.00016 bash -c 'find /opt/ti/ccsv7 -type f 2>/dev/null | wc -l')
echo "Files: $files / 42268"

disk=$(docker exec ccs-v7-7.1.0.00016 bash -c 'du -sh /opt/ti/ccsv7 2>/dev/null | cut -f1')
echo "Disk: $disk"

echo ""
echo "Processes:"
docker exec ccs-v7-7.1.0.00016 bash -c "ps aux | grep -E 'ti_dspack|ccs_setup' | grep -v grep | awk '{print \$2, \$3\"%\", \$11}'"

echo ""
if docker exec ccs-v7-7.1.0.00016 bash -c "pgrep -f ti_dspack" >/dev/null 2>&1; then
    echo "ti_dspack status:"
    docker exec ccs-v7-7.1.0.00016 bash -c "ps -eo pid,wchan:20,comm | grep ti_dspack | head -3"
else
    echo "ti_dspack: not started yet"
fi
