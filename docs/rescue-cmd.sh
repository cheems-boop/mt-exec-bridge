#!/system/bin/sh
# mt_exec_bridge 自救/保养脚本（v2.2）
# 用法：复制到 in/cmd.sh 后点模块「执行」，或在 MT 终端直接 sh 本文件。
# 安全阀：daemon 本来就在跑（健康）时直接退出——因为 in/cmd.sh 是 v1 兼容入口，
# 守护进程会把它当普通任务自动执行，不能在那种情况下自相残杀。
MOD=/data/adb/modules/mt_exec_bridge
PMOD=/data/adb/modules/petpal
DPID=$(cat $MOD/out/execd.pid 2>/dev/null)
if [ -n "$DPID" ] && kill -0 "$DPID" 2>/dev/null; then
    echo "bridge healthy (execd pid=$DPID), nothing to do"
    tail -3 $MOD/out/history.log
    exit 0
fi

echo "== bridge is DOWN, repairing =="

# 不 fork 的扫描（逐 fd readlink 要 fork 上万次，实测能跑 5 分钟）
holders() {
    ls -l /proc/[0-9]*/fd/* 2>/dev/null | grep 'execd.lock' | awk '{print "  holder " $9 " -> " $NF}' | sort -u
}

echo "== 1) 锁持有者 =="
holders

echo "== 2) 现有 execd / supervisor =="
ps -A -o pid,args 2>/dev/null | grep -E 'execd|supervisor' | grep -v grep

echo "== 3) 杀掉 petpal 看门狗（历史上的锁泄漏源）=="
if [ -f $PMOD/watchdog.pid ]; then
    read WP BO < $PMOD/watchdog.pid
    echo "watchdog.pid=$WP"
    [ -n "$WP" ] && kill -9 "$WP" 2>/dev/null && echo "killed watchdog $WP"
fi

echo "== 4) 清掉残留 execd / supervisor =="
ps -A -o pid,args 2>/dev/null | awk '/supervisor\.sh$/ {print $1}' | while read p; do kill -9 "$p" 2>/dev/null && echo "killed sup $p"; done
ps -A -o pid,args 2>/dev/null | awk '/execd$/ {print $1}' | while read p; do kill -9 "$p" 2>/dev/null && echo "killed execd $p"; done
sleep 1

echo "== 5) 复查锁持有者 =="
holders

echo "== 6) 二进制冒烟（rc=137 正常）=="
ls -l $MOD/bin/execd
ls -l $MOD/bin/execd.v21.bak 2>/dev/null
timeout -s KILL 1 $MOD/bin/execd >/dev/null 2>&1
echo "smoke rc=$?"

echo "== 7) 重启桥 =="
rm -f $MOD/out/execd.pid $MOD/out/supervisor.pid $MOD/out/execd.lock
nohup sh $MOD/supervisor.sh >/dev/null 2>&1 &
sleep 3
echo "sup.pid=$(cat $MOD/out/supervisor.pid 2>/dev/null)"
echo "execd.pid=$(cat $MOD/out/execd.pid 2>/dev/null)"
ps -A -o pid,args 2>/dev/null | grep -E 'execd|supervisor' | grep -v grep

echo "== 8) history 尾部 =="
tail -4 $MOD/out/history.log

echo "== done =="
