#!/system/bin/sh
# watchdog.sh  —  偷偷许下心愿
# “远处烟雨下的漓江每次都是匆匆而过”
#──────────────────────
# 看门狗：定期检测主服务存活，死亡时自动拉起
# 若模块已被 ROOT 框架禁用（disable 文件存在），则静默退出，不拉起服务

MODDIR="${MODDIR:-/data/adb/modules/file_redirector}"
. "$MODDIR/scripts/common.sh"

LOCK_FILE="${LOCK_FILE:-$MODDIR/.service.pid}"
LOG_FILE="${LOG_FILE:-$MODDIR/redirector.log}"

WATCH_INTERVAL=120

# ── 校验主服务是否存活（抢锁：拿到=死亡，拿不到=存活）──
# flock绑定fd生命周期，进程无论如何退出内核自动释放，无PID复用误判风险
_is_our_service() {
    exec 11>"${LOCK_FILE}.lock" 2>/dev/null || return 0  # 打不开锁文件，保守认为活着
    if flock -n 11 2>/dev/null; then
        flock -u 11 2>/dev/null  # 立即释放，只是探测
        return 1  # 抢到了，服务已死
    fi
    return 0  # 抢不到，服务持有锁，活着
}

# ── 检查并拉起主服务 ──
_check_and_revive() {
    # 模块已被禁用，不拉起服务，看门狗自身也退出
    if [ -f "$MODDIR/disable" ]; then
        log_msg "INFO" "SYS" "watchdog：模块已禁用，退出"
        exit 0
    fi

    _is_our_service && return 0

    # 二次确认，排除启动瞬间竞争（service.sh启动后立即拿锁，3秒足够）
    sleep 3
    _is_our_service && return 0

    # 再次检查 disable（3秒内可能刚被禁用）
    if [ -f "$MODDIR/disable" ]; then
        log_msg "INFO" "SYS" "watchdog：模块已禁用，退出"
        exit 0
    fi

    log_msg "WARN" "SYS" "watchdog：主服务已停止，尝试拉起"
    sh "$MODDIR/service.sh" 11>&- 2>>"$LOG_FILE" &

    # 等待并验证拉起结果，最多确认5次（每次3秒，共15秒）
    _i=0
    while [ "$_i" -lt 5 ]; do
        sleep 3
        if _is_our_service; then
            log_msg "INFO" "SYS" "watchdog：拉起成功"
            return 0
        fi
        _i=$(( _i + 1 ))
    done
    log_msg "WARN" "SYS" "watchdog：拉起后服务未就绪，下轮重试"
}

log_msg "INFO" "SYS" "watchdog 启动：PID=$$"
echo -1000 > "/proc/$$/oom_score_adj" 2>/dev/null || true

while true; do
    _check_and_revive
    sleep "$WATCH_INTERVAL" &
    wait $! 2>/dev/null || true
done
