#!/usr/bin/env bash
# =============================================================================
# plex_metrics.sh — Polls Plex Media Server API for active session metrics
# Called by Telegraf [[inputs.exec]] every 30s
# Requires: PLEX_TOKEN env var or set inline below
# Get your token: open Plex Web → any media item → Get Info → View XML
# The token appears in the URL as ?X-Plex-Token=XXXXXX
# =============================================================================

PLEX_URL="http://host.docker.internal:32400"
PLEX_TOKEN="${PLEX_TOKEN}"  # Injected by Telegraf exec environment block — set PLEX_TOKEN in .env
HOST="macpro"

# Active sessions
response=$(curl -s -m 5 \
    -H "Accept: application/json" \
    "${PLEX_URL}/status/sessions?X-Plex-Token=${PLEX_TOKEN}" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$response" ]; then
    echo "plex_up{host=\"$HOST\"} 0"
    exit 0
fi

echo "plex_up{host=\"$HOST\"} 1"

# Total active streams
total=$(echo "$response" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('MediaContainer',{}).get('size',0))
" 2>/dev/null || echo 0)
echo "plex_active_streams{host=\"$HOST\"} $total"

# Transcode vs direct play
transcodes=$(echo "$response" | python3 -c "
import json,sys
d=json.load(sys.stdin)
sessions=d.get('MediaContainer',{}).get('Metadata',[])
print(sum(1 for s in sessions if s.get('TranscodeSession')))
" 2>/dev/null || echo 0)
echo "plex_transcoding_streams{host=\"$HOST\"} $transcodes"

direct=$(( total - transcodes ))
echo "plex_direct_streams{host=\"$HOST\"} $direct"
