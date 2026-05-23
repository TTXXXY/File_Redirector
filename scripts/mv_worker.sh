#!/system/bin/sh
# mv_worker.sh  —  偷偷许下心愿
# “远处烟雨下的漓江每次都是匆匆而过”
#──────────────────────
# 搬运工：执行单个文件的移动（同分区 mv / 跨分区 cp+校验）

[ -f "$1" ] || exit 0
. "$MODDIR/scripts/common.sh"

SRC="$1"
DST_DIR="$2"
FNAME=$(basename "$SRC")

# ── 写入稳定性检测：大小 + ctime 连续2轮不变才放行，防止搬走下载中的文件 ──
# ctime（inode change time）在任何写操作后都会更新，比 mtime 更保险
# 超时返回 exit 1，由 dispatcher 放入 retry 队列下轮重试
_wait_stable() {
    _prev_size=-1
    _prev_ctime=-1
    _stable=0
    _try=0
    _limit="${FILE_STABLE_WAIT:-20}"
    case "$_limit" in *[!0-9]*|'') _limit=20 ;; esac
    [ "$_limit" -lt 3 ] && _limit=3
    while [ "$_try" -lt "$_limit" ]; do
        [ -f "$SRC" ] || return 1
        _cur_size=$(wc -c < "$SRC" 2>/dev/null | tr -d ' ')
        _cur_ctime=$(stat -c '%Z' "$SRC" 2>/dev/null)
        if [ "$_cur_size" = "$_prev_size" ] && [ "$_cur_ctime" = "$_prev_ctime" ]; then
            _stable=$(( _stable + 1 ))
            if [ "$_stable" -ge 2 ]; then
                # 0B 文件天然稳定，但极可能是下载器尚未开始写入的空壳，拒绝放行
                [ "${_cur_size:-0}" = "0" ] && {
                    log_msg "WARN" "FILE" "文件稳定但大小为0，稍后重试: $FNAME"
                    return 1
                }
                return 0
            fi
        else
            _prev_size="$_cur_size"
            _prev_ctime="$_cur_ctime"
            _stable=0
        fi
        sleep 1
        _try=$(( _try + 1 ))
    done
    log_msg "WARN" "FILE" "写入超时（${_limit}s），稍后重试: $FNAME"
    return 1
}

_wait_stable || exit 1

[ -d "$DST_DIR" ] || mkdir -p "$DST_DIR" 2>/dev/null || \
    { log_msg "ERROR" "FILE" "创建目录失败: $DST_DIR"; exit 1; }

# 重名处理：目标存在且比源小（不完整副本）则直接覆盖，否则加 _n 后缀
DST="$DST_DIR/$FNAME"
if [ -e "$DST" ]; then
    _exist_size=$(wc -c < "$DST" 2>/dev/null | tr -d ' ')
    _src_size=$(wc -c < "$SRC" 2>/dev/null | tr -d ' ')
    if [ "${_exist_size:-0}" -ge "${_src_size:-0}" ]; then
        _n=1
        while [ -e "$DST" ] && [ "$_n" -lt 100 ]; do
            case "$FNAME" in
                *.*) DST="$DST_DIR/${FNAME%.*}_${_n}.${FNAME##*.}" ;;
                *)   DST="$DST_DIR/${FNAME}_${_n}" ;;
            esac
            _n=$(( _n + 1 ))
        done
        [ -e "$DST" ] && { log_msg "WARN" "FILE" "重名冲突，跳过: $FNAME"; exit 0; }
    fi
fi

# 同分区直接 mv
_src_dev=$(stat -c '%d' "$(dirname "$SRC")"  2>/dev/null || printf 'x')
_dst_dev=$(stat -c '%d' "$DST_DIR" 2>/dev/null || printf 'y')
if [ "$_src_dev" = "$_dst_dev" ]; then
    if mv "$SRC" "$DST" 2>/dev/null && [ -f "$DST" ]; then
        log_msg "INFO" "FILE" "mv: $SRC → $DST"
        sh "$VAR_MEDIA_FIX" move "$DST" "$SRC" 2>>"$LOG_FILE"
        exit 0
    fi
    log_msg "WARN" "FILE" "同分区 mv 失败，尝试 cp 兜底: $SRC"
fi

# 跨分区：cp → 大小+MD5校验 → rm，失败重试一次
_try=1
while [ "$_try" -le 2 ]; do
    [ -f "$SRC" ] || { log_msg "INFO" "FILE" "源文件已消失: $SRC"; exit 0; }
    [ "$_try" -eq 2 ] && sleep 2

    cp "$SRC" "$DST" 2>/dev/null || { rm -f "$DST" 2>/dev/null; _try=$(( _try + 1 )); continue; }

    _ss=$(wc -c < "$SRC" 2>/dev/null | tr -d ' ')
    _ds=$(wc -c < "$DST" 2>/dev/null | tr -d ' ')
    if [ "$_ss" != "$_ds" ]; then
        log_msg "ERROR" "FILE" "大小不符(第${_try}次): $FNAME"
        rm -f "$DST" 2>/dev/null; _try=$(( _try + 1 )); continue
    fi

    sync 2>/dev/null || true

    _sm=$(md5sum "$SRC" 2>/dev/null | cut -d' ' -f1)
    _dm=$(md5sum "$DST" 2>/dev/null | cut -d' ' -f1)
    if [ -z "$_sm" ] || [ "$_sm" != "$_dm" ]; then
        log_msg "ERROR" "FILE" "MD5不符(第${_try}次): $FNAME"
        rm -f "$DST" 2>/dev/null; _try=$(( _try + 1 )); continue
    fi

    # 还原源文件时间戳（mtime/atime），确保 MediaStore 扫描后 date_modified 正确
    # 必须在 rm 之前执行，rm 后源文件消失则无法引用
    touch -r "$SRC" "$DST" 2>/dev/null || true
    if rm "$SRC" 2>/dev/null; then
        log_msg "INFO" "FILE" "cp+校验(第${_try}次): $SRC → $DST"
        sh "$VAR_MEDIA_FIX" move "$DST" "$SRC" 2>>"$LOG_FILE"
        exit 0
    else
        # rm 失败（源文件被其他进程占用）：清理目标副本，交由 dispatcher 下轮重试
        rm -f "$DST" 2>/dev/null || true
        log_msg "WARN" "FILE" "源文件删除失败，下轮重试: $FNAME"
        exit 1
    fi
done

log_msg "ERROR" "FILE" "搬运失败: $SRC → $DST_DIR"
exit 1
