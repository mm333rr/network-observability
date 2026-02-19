#!/usr/bin/env bash
# =============================================================================
# smb_metrics.sh — Polls active SMB sessions via smbutil and outputs metrics
# Called by Telegraf [[inputs.exec]] every 60s
# =============================================================================

HOST="macpro"

# Count active SMB sessions — smbutil not available in Linux container, returns 0 safely
session_count=$(smbutil statshares -a 2>/dev/null | grep -c "SHARE" 2>/dev/null)
echo "smb_active_sessions{host=\"$HOST\"} ${session_count:-0}"

# Auth failures from Unified Log (last 2 minutes)
auth_failures=$(log show --predicate 'process == "smbd" && messageType == "error"' \
    --last 2m 2>/dev/null | grep -c "auth" 2>/dev/null)
echo "smb_auth_failures_2m{host=\"$HOST\"} ${auth_failures:-0}"
