#!/usr/bin/env bash
# =============================================================================
# plex_metrics.sh — Polls Plex Media Server API for session + library metrics
# Called by Telegraf [[inputs.exec]] every 30s
# Requires: PLEX_TOKEN env var — injected by Telegraf exec environment block.
#           Never hardcode the token here; set it in .env.
#
# Implementation: pure bash + curl + awk — no Python/jq dependency.
# Plex JSON API returns flat-ish JSON; we use regex extraction via grep/sed/awk.
#
# Metrics:
#   plex_up                     — server reachable (1/0)
#   plex_active_streams         — total active sessions (from MediaContainer.size)
#   plex_transcoding_streams    — sessions with a TranscodeSession block
#   plex_direct_streams         — sessions without TranscodeSession
#   plex_stream_info            — per-session gauge (value=1) with labels:
#                                   user, player, device, platform, state,
#                                   media_type, video_resolution, decision
#   plex_stream_bitrate_kbps    — per-session bitrate, same label set
#   plex_library_section        — 1 per library section (section, type, key labels)
# =============================================================================

# PLEX_HOST and PLEX_PORT are injected by Telegraf exec environment block (from .env)
# On Mac Pro: host.docker.internal resolves to the host -- but this is macOS-only.
# Using explicit IP (default 192.168.1.30) works on both Mac and Pi.
PLEX_URL="http://${PLEX_HOST:-192.168.1.30}:${PLEX_PORT:-32400}"
HOST="${HOST_HOSTNAME:-macpro}"

# ---------------------------------------------------------------------------
# Helper: extract a JSON string value by key name (simple, single-line safe)
# Usage: json_val KEY <<< "$json_fragment"
# ---------------------------------------------------------------------------
json_val() {
    grep -oP "\"${1}\"\\s*:\\s*\"\\K[^\"]*" | head -1 | sed 's/["\n]//g'
}

json_int() {
    grep -oP "\"${1}\"\\s*:\\s*\\K[0-9]+" | head -1
}

sanitize() {
    # Safe label value: collapse whitespace, strip quotes & parens
    echo "$1" | tr -d '"()' | sed 's/[[:space:]]/_/g' | tr -cd 'a-zA-Z0-9_.-'
}

# ---------------------------------------------------------------------------
# Fetch sessions
# ---------------------------------------------------------------------------
sessions_json=$(curl -s -m 8 \
    -H "Accept: application/json" \
    "${PLEX_URL}/status/sessions?X-Plex-Token=${PLEX_TOKEN}" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$sessions_json" ]; then
    echo "plex_up{host=\"${HOST}\"} 0"
    exit 0
fi

echo "plex_up{host=\"${HOST}\"} 1"

# Total from the container attribute "size"
total=$(echo "$sessions_json" | grep -oP '"size"\s*:\s*\K[0-9]+' | head -1)
total=${total:-0}
echo "plex_active_streams{host=\"${HOST}\"} ${total}"

# ---------------------------------------------------------------------------
# Per-session parsing
# Plex returns each session as a JSON object inside "Metadata": [...]
# We split on the pattern that starts each session object by detecting
# the "sessionKey" field which is present in every session.
# ---------------------------------------------------------------------------
transcodes=0
directs=0

# Extract the Metadata array contents (everything between outer [ and ])
meta_block=$(echo "$sessions_json" | grep -oP '"Metadata"\s*:\s*\[\K.*(?=\]\s*})' | head -1)

if [ -n "$meta_block" ]; then
    # Split on "},{"  — crude but effective for flat Plex session objects
    # We process each segment as a session chunk
    IFS='' read -r -d '' _ <<< ""  # reset IFS
    
    # Use awk to split on top-level object boundaries
    echo "$meta_block" | awk '
    BEGIN { depth=0; chunk="" }
    {
        for (i=1; i<=length($0); i++) {
            c = substr($0,i,1)
            if (c=="{") { depth++; chunk=chunk c }
            else if (c=="}") { depth--; chunk=chunk c; if(depth==0){ print chunk; chunk="" } }
            else { if(depth>0) chunk=chunk c }
        }
    }
    ' | while IFS= read -r session_obj; do
        [ -z "$session_obj" ] && continue

        # Extract fields with grep -oP
        user=$(echo "$session_obj" | grep -oP '"User"\s*:\s*\{"id"[^}]+\}' | grep -oP '"title"\s*:\s*"\K[^"]+' | head -1)
        player_title=$(echo "$session_obj" | grep -oP '"Player"\s*:\s*\{[^}]+\}' | grep -oP '"title"\s*:\s*"\K[^"]+' | head -1)
        device=$(echo "$session_obj" | grep -oP '"Player"\s*:\s*\{[^}]+\}' | grep -oP '"device"\s*:\s*"\K[^"]+' | head -1)
        platform=$(echo "$session_obj" | grep -oP '"Player"\s*:\s*\{[^}]+\}' | grep -oP '"platform"\s*:\s*"\K[^"]+' | head -1)
        state=$(echo "$session_obj" | grep -oP '"Player"\s*:\s*\{[^}]+\}' | grep -oP '"state"\s*:\s*"\K[^"]+' | head -1)
        mtype=$(echo "$session_obj" | grep -oP '"type"\s*:\s*"\K(movie|episode|track|clip)' | head -1)
        vres=$(echo "$session_obj" | grep -oP '"videoResolution"\s*:\s*"\K[^"]+' | head -1)
        bitrate=$(echo "$session_obj" | grep -oP '"bitrate"\s*:\s*\K[0-9]+' | head -1)

        # Decision: presence of TranscodeSession key signals transcode
        if echo "$session_obj" | grep -q '"TranscodeSession"'; then
            decision="transcode"
            transcodes=$((transcodes+1))
        else
            decision="direct"
            directs=$((directs+1))
        fi

        # Sanitize label values
        user=$(sanitize "${user:-unknown}")
        player_title=$(sanitize "${player_title:-unknown}")
        device=$(sanitize "${device:-unknown}")
        platform=$(sanitize "${platform:-unknown}")
        state=$(sanitize "${state:-unknown}")
        mtype=$(sanitize "${mtype:-unknown}")
        vres=$(sanitize "${vres:-unknown}")
        bitrate=${bitrate:-0}

        lbl="host=\"${HOST}\",user=\"${user}\",player=\"${player_title}\",device=\"${device}\",platform=\"${platform}\",state=\"${state}\",media_type=\"${mtype}\",video_resolution=\"${vres}\",decision=\"${decision}\""
        echo "plex_stream_info{${lbl}} 1"
        echo "plex_stream_bitrate_kbps{${lbl}} ${bitrate}"
    done
fi

echo "plex_transcoding_streams{host=\"${HOST}\"} ${transcodes}"
echo "plex_direct_streams{host=\"${HOST}\"} ${directs}"

# ---------------------------------------------------------------------------
# Library section counts (best-effort)
# ---------------------------------------------------------------------------
libs_json=$(curl -s -m 8 \
    -H "Accept: application/json" \
    "${PLEX_URL}/library/sections?X-Plex-Token=${PLEX_TOKEN}" 2>/dev/null)

if [ -n "$libs_json" ]; then
    # Pure awk JSON extraction — POSIX-safe, works in Telegraf Debian container
    # Extracts "key", "type", "title" fields from each Directory object
    echo "$libs_json" | awk -v host="$HOST" '
    function unquote(s,   r) { gsub(/^"|"$/, "", s); return s }
    {
        # Extract all "field":"value" pairs from this line
        line = $0
        while (match(line, /"([a-zA-Z]+)":"([^"]*)"/, arr)) {
            # awk does not support named groups — use split approach
            line = substr(line, RSTART + RLENGTH)
        }
    }
    ' 2>/dev/null || true
    # Fallback: simpler field-by-field extraction using sed (POSIX)
    echo "$libs_json" | sed 's/},{/}\n{/g' | while IFS= read -r seg; do
        echo "$seg" | grep -q '"type"' || continue
        sec_key=$(echo   "$seg" | sed -n 's/.*"key":"\([^"]*\)".*/\1/p' | head -1)
        sec_type=$(echo  "$seg" | sed -n 's/.*"type":"\([^"]*\)".*/\1/p' | head -1)
        sec_title=$(echo "$seg" | sed -n 's/.*"title":"\([^"]*\)".*/\1/p' | head -1)
        [ -z "$sec_title" ] && continue
        sec_title=$(sanitize "${sec_title:-unknown}")
        sec_type=$(sanitize "${sec_type:-unknown}")
        sec_key=$(sanitize "${sec_key:-0}")
        echo "plex_library_section{host=\"${HOST}\",section=\"${sec_title}\",type=\"${sec_type}\",key=\"${sec_key}\"} 1"
    done
fi
