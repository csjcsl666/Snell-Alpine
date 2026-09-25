# Snell-Alpine

面向 Alpine Linux 的 Snell v6 原生一键安装与管理脚本，使用 gcompat + OpenRC，无需 Docker

Snell 是 Surge 团队开发的代理协议，本项目仅为第三方 Alpine Linux 安装管理脚本，与 Surge / Snell 官方无关

管理菜单与交互设计参考自 [passeway/Snell](https://github.com/passeway/Snell)，详见 [项目来源与致谢](#项目来源与致谢)

## 快速开始

以 root 在 Alpine 上执行

安装

```sh
wget -qO- https://raw.githubusercontent.com/csjcsl666/Snell-Alpine/main/snell-alpine.sh | sh
```

管理

```sh
snell
```

安装命令会把管理脚本装为 `/usr/local/bin/snell` 并打开菜单，在菜单里选 1 安装 Snell

以后任何时候输入 `snell` 即可回到菜单，日常管理使用本地命令，不需要再联网

## 这是什么

一个纯 POSIX sh（BusyBox ash 兼容）脚本，在 Alpine 上完成 Snell v6 服务端的安装，更新，启停，卸载与查看配置

```text
Alpine
 ├─ musl
 ├─ gcompat + libstdc++ + libgcc
 ├─ OpenRC
 └─ snell-server（Surge 官方二进制）
```

## 为什么做 Alpine 原生版

官方 Snell 二进制是 glibc 动态链接程序，而 Alpine 使用 musl，所以不少第三方脚本让 Alpine 用户套一层 Docker 或 Debian 容器

实测并不需要这样做

- 官方二进制的动态依赖只有 `libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 libstdc++.so.6 libgcc_s.so.1` 和 glibc 加载器
- Alpine 官方的 `gcompat` 提供 glibc 加载器与 libc 兼容层，`libstdc++` 与 `libgcc` 提供 C++ 运行库
- 只装 `gcompat` 不够，会报 `Error loading shared library libstdc++.so.6`，脚本会同时安装这三个包


## 不使用 Docker

整个项目不安装也不调用 Docker，containerd，Podman，不创建任何容器，不套 Debian 或 Ubuntu 环境

如果某个 Alpine 版本无法原生运行，脚本会直接报错并显示原因，不会偷偷回退到容器方案

## 支持的 Alpine 版本

已确认兼容范围为 Alpine 3.21 到 3.24，依据是官方发布信息与包仓库，这四个 stable 分支对 Snell 而言是同一运行模型

| Alpine | 官方 EOL | gcompat | musl | OpenRC |
| --- | --- | --- | --- | --- |
| 3.21 | 2026-11-01 | 1.1.0-r4 | 1.2.5 | 0.55 |
| 3.22 | 2027-05-01 | 1.1.0-r4 | 1.2.5 | 0.62 |
| 3.23 | 2027-11-01 | 1.1.0-r4 | 1.2.5 | 0.63 |
| 3.24 | 2028-06-01 | 1.1.0-r4 | 1.2.6 | 0.63 |

- 3.20 及更早版本不在支持范围，3.20 已于 2026-04-01 EOL
- 高于 3.24 的版本会提示 当前 Alpine 版本高于脚本已确认兼容范围，交互模式下询问是否继续，非交互模式需设置 `SNELL_ALPINE_FORCE=1`
- edge 与开发快照版本号无法归入稳定分支，不在支持范围
- 新 stable 分支验证后，只需修改脚本顶部的 `CONFIRMED_MAX`

## 支持的 CPU 架构

| `apk --print-arch` | Snell 官方二进制 |
| --- | --- |
| x86_64 | amd64 |
| aarch64 | aarch64 |
| x86 | i386 |

其他架构（如 armv7，armhf，riscv64，ppc64le，s390x）官方 v6 没有 Server 二进制，脚本会直接提示无法安装，不使用 QEMU，box64 等兼容方案

## 安装入口说明

推荐方式就是 [快速开始](#快速开始) 里的那一条命令，下面是它的工作方式和其他用法

安装命令做的事情

1. 检查 root，Alpine，OpenRC 与 CPU 架构，不满足时直接退出，不写入任何文件
2. 管道执行时拿不到脚本自身内容，所以重新下载一份完整脚本到临时目录
3. 校验下载内容 标记行存在，末行是入口，`sh -n` 语法检查通过，下载不完整时不做任何修改
4. 写入 `/usr/local/bin/snell`，先写临时文件再原子替换
5. 转交给本地的 `snell` 执行，菜单从终端读取输入

设计取舍

- 只依赖 Alpine 自带的 BusyBox wget，不需要 curl 或 bash
- 管理命令叫 `snell`，二进制叫 `snell-server`，OpenRC 服务在 `/etc/init.d/snell`，三者互不冲突
- `/usr/local/bin` 在 Alpine root 登录 shell 的默认 PATH 中，装好后当前会话就能直接用
- 联网只发生在首次安装，更新 Snell，更新管理脚本这三个时刻，平时运行的一直是本地脚本
- 脚本的所有逻辑都在函数里，最后一行才调用入口，所以下载中断时不会执行半截脚本
- BusyBox wget 即使加了 `-q` 也会打印下载失败的原因，例如 `bad address` 或 `404`

重复执行安装命令

- 会把 `snell` 更新到仓库中的最新版本，内容相同时提示已是最新，然后打开菜单
- 不会重装或改动 Snell Server，配置，端口和 PSK 都保持原样

其他用法

```sh
# 先下载再执行，可以先检查脚本内容，适合离线或手动分发
wget -O snell-alpine.sh https://raw.githubusercontent.com/csjcsl666/Snell-Alpine/main/snell-alpine.sh
sh snell-alpine.sh

# 无人值守安装，例如写在 cloud-init 里
wget -qO- https://raw.githubusercontent.com/csjcsl666/Snell-Alpine/main/snell-alpine.sh | SNELL_PORT=20000 sh -s -- install

# raw.githubusercontent.com 无法访问时改用镜像地址，之后执行 snell self-update 时也要带上同样的变量
wget -qO- <镜像地址> | SNELL_ALPINE_SCRIPT_URL=<镜像地址> sh
```

以本地文件运行时，安装的就是这份文件本身，不需要联网

## 菜单功能

```text
=== Snell Alpine 管理工具 ===

系统版本: Alpine Linux 3.24.2 (已确认兼容)
CPU 架构: x86_64 (Snell: amd64)
Snell 安装状态: 已安装
Snell 运行状态: 运行中
Snell 运行版本: v6.0.0rc2
管理脚本版本: 1.1.0

1. 安装 Snell 服务
2. 卸载 Snell 服务
3. 停止 Snell 服务
4. 更新 Snell
5. 重启 Snell 服务
6. 查看 Snell 状态
7. 查看 Snell 日志
8. 查看 Snell 配置
9. 更新管理脚本
0. 退出
```

第 3 项会根据运行状态在 启动 与 停止 之间切换

子命令与环境变量，适合脚本调用，`snell --help` 可查看同样的内容

| 子命令 | 说明 |
| --- | --- |
| `snell install` `snell uninstall` | 安装，卸载 Snell |
| `snell start` `snell stop` `snell restart` | 服务控制 |
| `snell status` `snell log` `snell config` | 状态，日志，配置 |
| `snell update` | 更新 Snell Server |
| `snell self-update` | 更新管理脚本，不影响 Snell Server |
| `snell self-uninstall` | 删除 `snell` 管理命令，需先卸载 Snell |

| 环境变量 | 说明 |
| --- | --- |
| `SNELL_ALPINE_SCRIPT_URL=地址` | 管理脚本的下载地址，用于镜像 |
| `SNELL_PORT=端口` | 安装时指定监听端口，默认随机 |
| `SNELL_IPV6=1` | 安装时同时监听 IPv6 |
| `SNELL_VERSION=v6.x.y` | 指定 Snell 版本，默认自动获取最新 v6 |
| `SNELL_ALPINE_YES=1` | 跳过确认提示 |
| `SNELL_ALPINE_FORCE=1` | 允许在高于已确认范围的 Alpine 上继续 |
| `SNELL_NO_IP_LOOKUP=1` | 不查询公网 IP |

## 安装做了什么

1. 检查 root，Alpine，OpenRC，CPU 架构与 Alpine 版本范围
2. 用 apk 安装 `gcompat libstdc++ libgcc`，缺少 wget 或 unzip 时才补装
3. 从 Surge 官方下载地址获取对应架构的 zip，解压后先试运行，确认是 Snell v6
4. 生成配置，端口默认取 10240 到 31999 的随机值，避开保留端口与 Linux 默认临时端口区间，PSK 为 32 位字母数字，来自 `/dev/urandom`
5. 创建无登录权限的系统用户 `snell`，服务以该用户运行
6. 写入 OpenRC 服务并加入默认运行级别，启动服务
7. 验证 进程存在 且 所有配置端口处于 LISTEN，验证失败会显示服务状态与日志并以失败退出，不会报告成功

Snell 官方没有提供 latest 接口，脚本从官方文档页面解析当前架构可用的最高 v6 版本（正式版优先于 rc，rc 优先于 beta），失败时回退到脚本内置的 `v6.0.0rc2`

## 路径

| 用途 | 路径 |
| --- | --- |
| 管理命令 | `/usr/local/bin/snell` |
| 二进制 | `/usr/local/bin/snell-server` |
| 服务器配置 | `/etc/snell/snell-server.conf` |
| 客户端示例 | `/etc/snell/snell-client.conf` |
| 已装版本记录 | `/etc/snell/version` |
| OpenRC 服务 | `/etc/init.d/snell` |
| 日志 | `/var/log/snell.log` |

`snell-server -v` 对 rc 版本也只显示 `v6.0.0`，所以脚本自己记录官方版本标签

## 服务管理

```sh
rc-service snell start
rc-service snell stop
rc-service snell restart
rc-service snell status
rc-update show default | grep snell
```

服务由 `supervise-daemon` 托管，异常退出会自动重启，5 次失败后放弃，开机自启通过 `rc-update add snell default` 实现

## 查看日志

```sh
tail -n 50 /var/log/snell.log
tail -f /var/log/snell.log
```

也可以在菜单中选 7，日志级别为 notify，每次启动时若日志超过 5 MiB 会轮转一次

## 更新

Snell Server 与管理脚本分开更新，互不影响，都不会自动执行，只在你手动触发时联网

更新 Snell Server，菜单选 4 或执行 `snell update`

1. 比较已装版本与目标版本，相同则提示无需更新
2. 下载到临时目录，检查压缩包，解压，试运行新二进制
3. 上述任一步失败都直接中止，旧版本原样保留
4. 停止服务，备份旧二进制，替换，启动并验证
5. 新版本启动失败时自动回滚到旧版本并重新启动

更新管理脚本，菜单选 9 或执行 `snell self-update`

1. 下载仓库中的最新脚本到临时目录并做完整性校验，校验失败不做任何修改
2. 与本地 `snell` 内容相同时提示无需更新
3. 原子替换 `/usr/local/bin/snell`，在菜单中更新后会用新版本重新打开菜单

重新执行安装命令与 `snell self-update` 效果相同

## 卸载

卸载 Snell，菜单选 2 或执行 `snell uninstall`

只删除本项目创建的内容 二进制，`/etc/snell`，`/etc/init.d/snell`，日志，OpenRC 注册，以及脚本自己创建的 `snell` 用户

不会删除 `gcompat libstdc++ libgcc`，它们可能被其他程序使用，确认不需要时可手动 `apk del`，也不会修改网络，防火墙，SSH 与其他代理程序

卸载 Snell 后 `snell` 管理命令会保留，方便以后重新安装，如果连管理命令也不要了

```sh
snell self-uninstall
```

它只删除 `/usr/local/bin/snell`，Snell 仍在安装状态时会拒绝执行，避免留下无人管理的服务

## NAT VPS 注意事项

- 安装时可以指定监听端口，请填商家分配的内部端口，不要用随机端口后再回头找映射
- 脚本不会修改商家的 NAT 或端口映射，也不会改防火墙
- 安装完成后会提示 Snell 当前监听端口，请自行确保商家面板中对应的公网端口已映射到该端口
- 客户端示例里的地址来自 `checkip.amazonaws.com` 的查询，NAT 场景下请以商家提供的公网地址与端口为准，可用 `SNELL_NO_IP_LOOKUP=1` 关闭查询
- 服务器端口只允许 1025 到 65535

## 验证情况

| 层级 | 内容 |
| --- | --- |
| 官方资料确认 | Alpine stable 分支与 EOL 来自 alpinelinux.org releases.json，gcompat 与 OpenRC 版本来自 dl-cdn.alpinelinux.org 的 APKINDEX，Snell 下载地址与配置项来自 Surge 官方文档与 `snell-server --help` |
| 静态验证 | shellcheck（busybox 与 dash 模式）无告警，BusyBox ash 语法检查通过，删除命令仅限本项目路径 |
| 沙盒运行验证 | 使用 Alpine 官方 minirootfs 在非特权用户命名空间 chroot 中，无 Docker，运行完整流程 安装，状态，重启，启停，更新，回滚，卸载 |

沙盒运行验证覆盖 Alpine 3.21.8，3.22.6，3.23.6，3.24.2 的 x86_64，以及 3.24.2 的 x86，均使用真实 OpenRC 与真实的 Surge 官方二进制

安装入口在 Alpine 3.24.2 x86_64 沙盒中另外验证了 管道安装后打开菜单，离线运行 `snell` 与子命令，重复执行安装命令，自更新，自更新遇到截断文件或 404 时保持原样，无终端时的管道执行，本地文件方式，非 root 拒绝，卸载后保留管理命令，`self-uninstall`

需要明确的局限

- 沙盒共用宿主机内核，不是真实的 Alpine 虚拟机或 VPS
- 没有验证重启后的开机自启是否生效，只验证了 `rc-update add` 成功
- aarch64 没有实际运行，仅确认官方下载地址存在，二进制依赖的加载器 `ld-linux-aarch64.so.1` 由 gcompat 提供
- Snell v6 目前只有 RC 版本，没有正式版

欢迎在真实 Alpine 机器上测试后反馈

## 与 Surge / Snell 官方的关系

Snell 是 Surge 团队开发的代理协议，本项目仅为第三方 Alpine Linux 安装管理脚本，与 Surge 团队无关，也不冒充官方项目

脚本不托管，不重新打包，不编译 Snell，二进制只从官方下载地址获取，官方文档也说明 Snell 为追求性能而做了取舍，例如没有前向保密与专门的重放保护，请阅读 [官方文档](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) 后自行评估

## 项目来源与致谢

本项目的 Snell 管理菜单，交互设计及部分实现思路参考了 [passeway/Snell](https://github.com/passeway/Snell)

参考并沿用的部分

- 菜单的整体结构与选项文案，包括 安装，卸载，启动或停止，更新，重启，查看状态，日志，配置，退出，以及顶部的安装状态，运行状态，运行版本显示
- 服务器配置文件的字段组织，以及 Surge 客户端示例的格式
- 安装，更新，卸载的整体管理流程

代码复用情况

- 本项目没有直接复制原项目的代码块，脚本代码是针对 Alpine Linux 重新编写的
- 菜单文案与配置模板沿用了原项目，因此在此明确标注来源，请不要理解为整个项目完全从零设计

许可证

- 原项目采用 AGPL-3.0 License，本项目同样采用 AGPL-3.0 License，并在 README 与脚本头部保留来源与许可证声明

在此基础上本项目针对 Alpine Linux 重新实现和适配，主要包括

- gcompat 运行环境，同时处理 libstdc++ 与 libgcc 依赖
- OpenRC 服务管理，使用 supervise-daemon 与降权运行的 `snell` 用户
- Alpine 版本检测与已确认兼容范围管理
- 无需 Docker 的原生 Snell 部署流程，含 CPU 架构严格识别，下载后试运行，安装后 LISTEN 验证，更新失败自动回滚

本项目与 passeway/Snell 的作者没有隶属关系，也未获得其背书，感谢原作者

## License

[AGPL-3.0](LICENSE)
