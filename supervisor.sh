#!/system/bin/sh
# 守护进程看门狗：execd 崩溃 2 秒后自动拉起（execd 内部 flock 保证全局单实例）
# v2.2:
#  - pidfile + boot_id 单实例，重复 service.sh 不会再拉出第二份
#  - execd 若在 2 秒内就退出，说明 flock 被占（已有实例在跑），本 supervisor 主动让位
#    而不是每秒两行刷 history.log（那会把真正的审计记录完全淹没）
MODDIR=${0%/*}
PIDF="$MODDIR/out/supervisor.pid"
BOOTID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)

if [ -f "$PIDF" ]; then
    read OPID OBOOT < "$PIDF"
    if [ -n "$OPID" ] && [ "$OBOOT" = "$BOOTID" ] && kill -0 "$OPID" 2>/dev/null; then
        exit 0
    fi
fi

echo "$$ $BOOTID" > "$PIDF"
trap 'rm -f "$PIDF"' EXIT INT TERM

while true; do
    T0=$(date +%s)
    if [ -x "$MODDIR/bin/execd" ]; then
        "$MODDIR/bin/execd"
    else
        sh "$MODDIR/polld.sh"
    fi
    T1=$(date +%s)
    if [ $((T1 - T0)) -lt 2 ]; then
        echo "$(date +%s) | duplicate supervisor (lock busy), exit" >> "$MODDIR/out/history.log"
        rm -f "$PIDF"
        exit 0
    fi
    echo "$(date +%s) | daemon exited, respawn in 2s" >> "$MODDIR/out/history.log"
    sleep 2
done
