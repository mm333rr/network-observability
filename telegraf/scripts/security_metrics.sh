#!/usr/bin/env bash
# =============================================================================
# security_metrics.sh — Polls macOS Unified Log for security events
# Called by Telegraf [[inputs.exec]] every 60s
# NOTE: Must run inside the container via host binary available via /Volumes mount,
# or more accurately this is designed to fail gracefully inside Linux container —
# it uses `log` which doesn't exist in Linux, so outputs 0 for all metrics safely.
# =============================================================================

HOST="macpro"
WINDOW="2m"

# Helper: safely count log entries; returns 0 if command unavailable (Linux container)
safe_log_count() {
    local predicate="$1"
    local grep_pattern="$2"
    local count
    count=$(log show --predicate "$predicate" --last "$WINDOW" 2>/dev/null \
        | grep -c "$grep_pattern" 2>/dev/null)
    # grep -c exits 1 on no match; treat as 0
    echo "${count:-0}"
}

ssh_ok=$(safe_log_count 'process == "sshd" && eventMessage contains "Accepted"' "Accepted")
echo "security_ssh_logins_ok{host=\"$HOST\"} $ssh_ok"

ssh_fail=$(safe_log_count 'process == "sshd" && eventMessage contains "Failed"' "Failed")
echo "security_ssh_logins_failed{host=\"$HOST\"} $ssh_fail"

console_logins=$(safe_log_count 'subsystem == "com.apple.loginwindow" && eventMessage contains "Login"' "Login")
echo "security_console_logins{host=\"$HOST\"} $console_logins"

sudo_events=$(safe_log_count 'process == "sudo"' "sudo")
echo "security_sudo_events{host=\"$HOST\"} $sudo_events"

screen_locked=$(safe_log_count 'process == "loginwindow" && eventMessage contains "locked"' "locked")
echo "security_screen_lock_events{host=\"$HOST\"} $screen_locked"

auth_fail=$(safe_log_count 'subsystem == "com.apple.opendirectoryd" && messageType == "error"' ".")
echo "security_auth_failures{host=\"$HOST\"} $auth_fail"
