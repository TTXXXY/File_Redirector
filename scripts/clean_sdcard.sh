#!/system/bin/sh
# clean_sdcard.sh  —  听闻人间十三月
# “远处烟雨下的漓江每次都是匆匆而过”
#──────────────────────
# 空目录清理：遍历外置存储，删除空目录（受保护目录除外）

MODDIR="${MODDIR:-/data/adb/modules/file_redirector}"
LOG_FILE="${LOG_FILE:-$MODDIR/redirector.log}"

_log() { printf '%s [%s] [手动清理] %s\n' "$(date '+%m-%d %H:%M:%S')" "$1" "$2" >> "$LOG_FILE" 2>/dev/null || true; }

[ "$(id -u)" = "0" ] || { _log "ERROR" "需要 root 权限"; exit 1; }

# ── 防多实例：flock 文件锁（进程退出时内核自动释放，无残留风险）──
LOCK="${MODDIR}/.clean_sdcard.lock"
exec 8>"$LOCK"
if ! flock -n 8 2>/dev/null; then
    _log "WARN" "清理已在进行中，跳过"
    printf 'RUNNING\n'
    exit 0
fi

# ── 受保护目录 ──
is_protected() {
    case "$1" in
        /storage/emulated/0|\
        /storage/emulated/0/Android|\
        /storage/emulated/0/Android/*|\
        /storage/emulated/0/DCIM|\
        /storage/emulated/0/Music|\
        /storage/emulated/0/Movies|\
        /storage/emulated/0/Download|\
        /storage/emulated/0/Pictures|\
        /storage/emulated/0/Documents) return 0 ;;
    esac
    return 1
}

if ls /storage/emulated/0/ >/dev/null 2>&1; then
    ROOT="/storage/emulated/0"
else
    _log "ERROR" "存储不可访问: /storage/emulated/0"
    exit 1
fi

_log "INFO" "开始全盘清理: $ROOT"

find "$ROOT" -mindepth 1 -depth -type d 2>/dev/null | sort -r | \
while IFS= read -r _d; do
    is_protected "$_d" && continue
    if rmdir "$_d" 2>/dev/null; then
        _log "INFO" "已删除: $_d"
        printf 'DEL\t%s\n' "$_d"
    fi
done

_log "INFO" "全盘清理完成"
