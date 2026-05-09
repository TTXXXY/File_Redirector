v4.0.51
do_cleanup 和 _start_monitor 补加 pkill monitor.sh，修复主服务被强杀后孤儿 monitor 进程无法清理导致 inotify 实例泄漏的问题。

v4.0.50
启动 watchdog 和 monitor 时加 9>&- 关闭锁文件描述符，修复强杀主服务后 flock 被子进程持有导致看门狗永远无法拉起新实例的死锁问题。

v4.0.49
do_cleanup 补杀看门狗残留实例（kill $WATCHDOG_PID 之后追加 pkill -f "$MODDIR/scripts/watchdog.sh" 2>/dev/null || true）

v4.0.48
单实例锁由 mkdir 目录锁改为 flock 文件锁，进程意外死亡时内核自动释放，彻底根治锁残留导致看门狗永远无法拉起主服务的问题。
看门狗检测间隔由 1800 秒缩短为 120 秒，拉起主服务后新增最长 15 秒的存活验证，成功与失败均有日志记录。
修复 dispatcher 锁超时强制清除后未递增计数器导致的忙等死循环。

v4.0.47
_start_monitor 日志逻辑重构：原来只有「监控进程已启动」，现在区分三种情况——有旧进程且存活打「清理旧监控进程 PID=xxx」，PID 为空打「无旧监控进程」，进程已死静默。
看门狗启动日志补全：原来 pkill 和拉起均无日志，现在加了「清理旧看门狗实例」/「无旧看门狗实例」以及「看门狗已启动 PID=xxx」。

v4.0.46
后端 service.sh：
注释更新说明 STARTUP_SCAN 控制所有事件驱动补扫；规则变更热重载后新增判断，命中才触发被动扫描并打日志。
新增 .rescan_trigger 触发文件检测，主循环每轮检查一次，发现即删文件、全量扫描入队，不受 STARTUP_SCAN 约束。
后端 monitor.sh：
inotifywait 建立后补扫（场景二三）加 ${STARTUP_SCAN:-1} 判断，关闭开关后不再无条件补扫。
看门狗目录出现后补扫（场景四）同样加判断，行为与场景二三保持一致，三处注释均说明读取了该变量。
前端 WebUI：
"初始化扫描"改名"被动扫描"，描述更新为覆盖四种场景的完整说明。
新增"主动扫描"卡片，蓝色"执行"按钮点击后 touch .rescan_trigger，toast 提示已触发。

v4.0.45
1.修复parse_rules 中 | 未转义导致 /system/bin/sh 脚本模式下规则全部解析失败的问题
2.内联 canon_path 消除嵌套 $() 子shell，增强跨 sh 实现兼容性
3.新增主服务拉起时清理看门狗旧实例