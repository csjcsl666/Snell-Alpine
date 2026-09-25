# Snell-Alpine

面向 Alpine Linux 的 Snell v6 原生一键安装与管理脚本，使用 gcompat + OpenRC，无需 Docker

Snell 是 Surge 团队开发的代理协议，本项目仅为第三方 Alpine Linux 安装管理脚本，与 Surge / Snell 官方无关

管理菜单与交互设计参考自 [passeway/Snell](https://github.com/passeway/Snell)，详见 [项目来源与致谢](#项目来源与致谢)

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

## 安装方法

以 root 运行

```sh
wget -O snell-alpine.sh https://raw.githubusercontent.com/csjcsl666/Snell-Alpine/main/snell-alpine.sh
chmod +x snell-alpine.sh
./snell-alpine.sh
```

Alpine 自带 BusyBox wget 与 unzip，无需额外安装下载工具

也可以直接使用子命令，适合自动化

```sh
./snell-alpine.sh install
./snell-alpine.sh status
```

## 菜单功能

```text
=== Snell Alpine 管理工具 ===

系统版本: Alpine Linux 3.24.2 (已确认兼容)
CPU 架构: x86_64 (Snell: amd64)
Snell 安装状态: 已安装
Snell 运行状态: 运行中
Snell 运行版本: v6.0.0rc2

1. 安装 Snell 服务
2. 卸载 Snell 服务
3. 停止 Snell 服务
4. 更新 Snell
5. 重启 Snell 服务
6. 查看 Snell 状态
7. 查看 Snell 日志
8. 查看 Snell 配置
0. 退出
```

第 3 项会根据运行状态在 启动 与 停止 之间切换

子命令与环境变量

| 子命令 | 说明 |
| --- | --- |
| install uninstall update | 安装，卸载，更新 |
| start stop restart | 服务控制 |
| status log config | 状态，日志，配置 |

| 环境变量 | 说明 |
| --- | --- |
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

菜单选 4 或执行 `./snell-alpine.sh update`

1. 比较已装版本与目标版本，相同则提示无需更新
2. 下载到临时目录，检查压缩包，解压，试运行新二进制
3. 上述任一步失败都直接中止，旧版本原样保留
4. 停止服务，备份旧二进制，替换，启动并验证
5. 新版本启动失败时自动回滚到旧版本并重新启动

## 卸载

菜单选 2 或执行 `./snell-alpine.sh uninstall`

只删除本项目创建的内容 二进制，`/etc/snell`，`/etc/init.d/snell`，日志，OpenRC 注册，以及脚本自己创建的 `snell` 用户

不会删除 `gcompat libstdc++ libgcc`，它们可能被其他程序使用，确认不需要时可手动 `apk del`，也不会修改网络，防火墙，SSH 与其他代理程序

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
