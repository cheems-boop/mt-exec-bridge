# 更新日志 Changelog

本项目所有对外可见的变更都记录在此文件中。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [v2.2] - 2026-11-03

### 修复

- **锁 fd 被孙进程继承，桥可能永久卡死（关键）**：`LOCKFILE` 用 `open()` 打开时没设 `O_CLOEXEC`，
  任务里只要拉起一个常驻后台进程（模块看门狗、`setsid` 守护、`nohup` 子进程），它就会把 `flock`
  一起带进自己的 fd 表。daemon 一旦退出/被杀，锁仍被孙进程撑着，新的 `execd` 永远拿不到锁——
  表现为 `history.log` 每 2 秒刷一行 `daemon exited, respawn in 2s`、新任务永不执行，只能重启手机。
  修复：锁用 `O_CLOEXEC` 打开，管道改 `pipe2(pfd, O_CLOEXEC)`（`dup2` 到 1/2 的副本不受影响）。
- **supervisor 重复拉起刷屏**：`service.sh` 被多次触发时会起多份 `supervisor.sh`，抢不到 flock 的那些
  每秒两行写 `history.log`，把真正的审计记录完全淹没（实测 11 分钟刷出 10KB 噪音）。
  修复：`out/supervisor.pid`（pid + `boot_id`）单实例；`execd` 若 2 秒内就退出即判定「锁被占」，
  主动让位并只记一行 `duplicate supervisor (lock busy), exit`。

### 新增

- `in/cmd.sh` 自救脚本：带健康检查（daemon 还活着就直接退出），只在桥挂掉时清残留进程、
  冒烟测试新二进制（`timeout -s KILL 1`）、重启单个 supervisor。
  注意：`cmd.sh` 是 v1 兼容入口，守护进程会把它当普通任务执行，所以健康检查是必需的（血泪教训）。

### 变更

- `module.prop` → v2.2 / versionCode 4；旧二进制保留为 `bin/execd.v21.bak`

## [v2.1] - 2026-10-25

### 修复

- **超时看门狗失效（关键）**：`run_sync` 排空子进程输出的循环使用阻塞 `read()`，当子进程静默（如 `sleep`）时父进程会卡死在排空循环里，永远走不到超时检查 —— `#!timeout` 形同虚设。
  修复：fork 后立即将管道设为 `O_NONBLOCK`，排空读到 `EAGAIN`/EOF 即止。
  该缺陷由超时验收测试捕获（`#!timeout=1` + `sleep 5` 实测跑满 5037ms 未被击杀），修复后实测 1029ms 精确击杀。

### 文档

- README 新增「前置配置（MT 管理器 MCP 服务）」章节：启动服务、`/data` 文件权限放行、排障流程
- 新增文档索引、CHANGELOG、两代完整文档（docs/v1.md、docs/v2.md）

## [v2.0] - 2026-10-25

二代重写，v1.0 的全部结构性局限在本版本修复。

### 新增

- **任务队列**：`in/` 下任意 `*.sh` 按文件名排序依次执行，多客户端并发投递互不覆盖
- **超时看门狗**：`fork + exec + setpgid + waitpid`，超时 `kill(-pid, SIGKILL)` 清场整个进程组；首行指令 `#!timeout=N`（默认 600s，0 = 不限）
- **异步任务**：首行指令 `#!async`，双 fork + setsid 后台运行，日志写 `out/<任务名>.log`，不阻塞队列
- **审计日志**：`out/history.log` 记录时间/任务/来源uid/耗时/退出码/输出量/命令首行，超 4MB 自动轮转
- **单实例锁**：`flock(LOCK_EX | LOCK_NB)` + `out/execd.pid`，防止重复拉起
- **看门狗自愈**：`supervisor.sh` 常驻，守护进程崩溃 2 秒自动拉起
- **持久环境**：`in/env.sh` 每任务自动 source；内置 PATH/HOME/TMPDIR 合理默认（检测到 Termux 自动指向其目录）
- **降级方案重写**：`polld.sh` 与 execd 同目录协议（队列/超时/原子发布/审计）

### 修复（相对 v1.0）

- 命令静默 16KB 截断 → 动态读取全文件（上限 8MB），超限/读取竞态/空文件显式报错并隔离为 `out/rejected_*`
- 输出无上限 → 8MB 截断并标注 `[OUTPUT TRUNCATED]`
- 结果可能被读到半截 → `.tmp + rename` 原子发布
- 写入竞态 → 读取后 `fgetc` 二次探测文件是否增长，命中即拒收

### 变更

- module.prop 升级至 v2.0；service.sh/supervisor.sh/polld.sh/action.sh 全部重写

## [v1.0] - 2026-10-25

首个可用版本（一代）。

### 新增

- `execd`（C，仅依赖 bionic libc）：300ms 轮询单命令文件 `in/cmd.sh`，出现即以 root 执行
- `popen` 执行 + stderr 合并 + 退出码回写 `out/result.txt`
- KSU 模块化封装：module.prop / service.sh / action.sh（管理器「执行」按钮）/ customize.sh（权限配置）
- shell 兜底轮询 `polld.sh`

### 已知局限（在 v2.0 全部解决）

- 单命令文件无队列：多客户端同窗口写入互相覆盖，命令丢失
- 16KB 静默截断：超长脚本尾部丢失，执行残缺脚本
- 无超时保护：一条挂起命令永久卡死整个桥
- 输出无上限：`cat 大文件` 可撑爆存储
- 结果非原子发布：读者可能读到半截输出
- 无审计：无法追溯执行历史
- 无单实例/自愈：重复拉起或死亡后无人接管
- 环境裸：PATH/HOME/TMPDIR 需每条命令手动设置
- 长任务阻塞后续全部命令

[Unreleased]: https://github.com/cheems-boop/mt-exec-bridge/compare/v2.2...HEAD
[v2.2]: https://github.com/cheems-boop/mt-exec-bridge/compare/v2.1...v2.2
[v2.1]: https://github.com/cheems-boop/mt-exec-bridge/compare/v2.0...v2.1
[v2.0]: https://github.com/cheems-boop/mt-exec-bridge/compare/v1.0...v2.0
[v1.0]: https://github.com/cheems-boop/mt-exec-bridge/releases/tag/v1.0
