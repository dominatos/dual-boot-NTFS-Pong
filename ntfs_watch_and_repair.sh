#!/usr/bin/env bash
# Monitoring /mnt/ftp and automatically triggering Windows chkdsk if NTFS issues occur
# VERSION WITHOUT FILE RENAMING (no mv/rename used)

set -Eeuo pipefail

### ============ SETTINGS ============

# Default Configuration
CONFIG_FILE="/etc/ntfs-watch.conf"

# Load external config if available
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Fallback / Defaults (can be overridden by config)
: "${FTP_MOUNT_POINT:="/mnt/ftp"}"
: "${FTP_DISC:="/dev/sda1"}"
: "${WIN_DEV:="/dev/sdc3"}"
: "${WIN_MOUNT_POINT:="/mnt/win"}"
: "${GRUB_CFG:="${WIN_MOUNT_POINT}/grub2/grub.cfg"}"
: "${CHK_BAT_ON:="${WIN_MOUNT_POINT}/chkdisk.bat"}"

: "${STATE_FILE:="/var/lib/ntfs_repair_attempts"}"
: "${MAX_ATTEMPTS:=3}"

: "${LOG_FILE:="/var/log/ntfs_repair.log"}"

# Lock file to prevent parallel execution
: "${LOCK_FILE:="/run/ntfs_repair.lock"}"
: "${REBOOT_FLAG:="/mnt/win/reboot.txt"}"
# Number of log lines to send to Telegram (0 = send entire file)
: "${TG_TAIL_LINES:=200}"

### ===================================

### ===================================

log() {
    local msg="$*"
    echo "[$(date '+%F %T')] $msg" | tee -a "$LOG_FILE"
}

send_log_tg() {
    # Send log to Telegram if tg_send command is available and log exists
    if ! command -v tg_send >/dev/null 2>&1; then
        echo "[$(date '+%F %T')] INFO: tg_send not found in PATH, skipping Telegram notification." >> "$LOG_FILE"
        return 0
    fi

    [[ -f "$LOG_FILE" ]] || {
        echo "[$(date '+%F %T')] WARN: LOG_FILE not found, cannot send via tg_send: $LOG_FILE" >> "$LOG_FILE"
        return 0
    }

    if (( TG_TAIL_LINES > 0 )); then
        local tmp
        tmp="$(mktemp)"
        tail -n "$TG_TAIL_LINES" "$LOG_FILE" > "$tmp"
        tg_send "$tmp" || echo "[$(date '+%F %T')] WARN: tg_send failed with code $? " >> "$LOG_FILE"
        rm -f "$tmp"
    else
        tg_send "$LOG_FILE" || echo "[$(date '+%F %T')] WARN: tg_send failed with code $? " >> "$LOG_FILE"
    fi
}

die() {
    log "ERROR: $*"
    send_log_tg
    exit 1
}

on_error() {
    local exit_code=$?
    local line_no=${BASH_LINENO[0]:-?}
    local cmd=${BASH_COMMAND:-?}
    # Do not use die here to avoid infinite loops
    echo "[$(date '+%F %T')] ERROR: Exit code=$exit_code at line=$line_no cmd=$cmd" >> "$LOG_FILE"
    send_log_tg
    exit "$exit_code"
}
trap on_error ERR

# Create base directories
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$STATE_FILE")"
touch "$LOG_FILE" || true

# File Locking
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "INFO: Another instance is already running, exiting."
    exit 0
fi

# 1) Check if /mnt/ftp is mounted
if mountpoint -q "$FTP_MOUNT_POINT"; then
    log "OK: ${FTP_MOUNT_POINT} is mounted. Resetting attempt counter."
    rm -f "$STATE_FILE" || true

    exit 0
fi

log "WARN: ${FTP_MOUNT_POINT} is NOT mounted."
log "Trying ntfsfix first..."

ntfsfix  "$FTP_DISC" || log "ntfsfix failed (continuing)"

# Пробуем mount после ntfsfix
if mount -o remount "$FTP_MOUNT_POINT" 2>/dev/null; then
    log "SUCCESS: ntfsfix fixed ${FTP_MOUNT_POINT}!"
    rm -f "$STATE_FILE"
    exit 0
fi
if command -v chkntfs >/dev/null 2>&1; then
    log "Trying Paragon chkntfs..."
    chkntfs -f "$FTP_DISC" || log "chkntfs failed (continuing)"
    
    if mount -o remount "$FTP_MOUNT_POINT" 2>/dev/null; then
        log "SUCCESS: chkntfs fixed ${FTP_MOUNT_POINT}!"
        rm -f "$STATE_FILE"
        exit 0
    fi
fi
log "ntfsfix failed, escalating to Windows chkdsk..."
# 2) Read attempt counter
attempts=0
if [[ -f "$STATE_FILE" ]]; then
    if grep -qE '^[0-9]+$' "$STATE_FILE"; then
        attempts=$(<"$STATE_FILE")
    else
        log "WARN: STATE_FILE contains garbage, resetting: $STATE_FILE"
        attempts=0
    fi
fi

log "INFO: Current repair attempt count: ${attempts} (MAX=${MAX_ATTEMPTS})"

if (( attempts >= MAX_ATTEMPTS )); then
    log "ERROR: Maximum attempts reached (${MAX_ATTEMPTS}). Stopping automatic repair to avoid reboot-loop."
    send_log_tg
    exit 0
fi

# 3) Mount Windows partition
log "INFO: Mounting Windows partition ${WIN_DEV} to ${WIN_MOUNT_POINT}..."
mkdir -p "$WIN_MOUNT_POINT"

if ! mountpoint -q "$WIN_MOUNT_POINT"; then
    mount "$WIN_DEV" "$WIN_MOUNT_POINT" || die "Failed to mount ${WIN_DEV} to ${WIN_MOUNT_POINT}."
else
    log "INFO: ${WIN_MOUNT_POINT} is already mounted."
fi

# 4) Verify grub.cfg and chkdisk.bat existence
[[ -f "$GRUB_CFG" ]] || die "grub.cfg not found: ${GRUB_CFG}."
[[ -f "$CHK_BAT_ON" ]] || die "File ${CHK_BAT_ON} not found. Please place chkdisk.bat manually."

# 4.1) Check write permissions (important after mount)
if [[ ! -w "$GRUB_CFG" ]]; then
    die "grub.cfg exists but is NOT writable (read-only?). Check Windows fast startup/hibernation or mount options: $GRUB_CFG"
fi

# 5) Edit grub.cfg: set default=0 (Windows entry)
log "INFO: Updating ${GRUB_CFG}: setting set default -> 0."

cp -a "$GRUB_CFG" "${GRUB_CFG}.bak_$(date +%F_%H-%M-%S)"

# If "set default" isn't found, stop to avoid an blind reboot
if ! grep -qE '^[[:space:]]*set[[:space:]]+default' "$GRUB_CFG"; then
    die "'set default ...' not found in ${GRUB_CFG}. Cannot guarantee Windows boot. Stopping."
fi
echo "1" > "$REBOOT_FLAG"
# Replace value with 0 in the first matching line
sed -i -E '0,/^[[:space:]]*set[[:space:]]+default[[:space:]]*=/s//set default=0\n# (autofix) original line was replaced by ntfs_repair script\n# &/' "$GRUB_CFG"

# Final verification of the change
if ! grep -qE '^[[:space:]]*set[[:space:]]+default[[:space:]]*=[[:space:]]*0' "$GRUB_CFG"; then
    die "Failed to set default=0 in ${GRUB_CFG} (post-sed verification failed)."
fi

sync

# 6) Increment attempt counter
attempts=$((attempts + 1))
echo "$attempts" > "$STATE_FILE"
log "INFO: New attempt count: ${attempts}"

# Send log before rebooting
send_log_tg

# 7) Reboot
log "INFO: Initiating reboot for NTFS repair via Windows..."
sleep 3
systemctl reboot || reboot
exit 0

