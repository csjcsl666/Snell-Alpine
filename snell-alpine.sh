#!/bin/sh
# Snell-Alpine
# Alpine Linux 原生 Snell v6 安装与管理脚本 (musl + gcompat + OpenRC, 无 Docker)
#
# 管理菜单, 交互设计及部分实现思路参考:
# https://github.com/passeway/Snell
# Original project: passeway/Snell
# License: AGPL-3.0
#
# 菜单结构与文案, 服务器配置模板及客户端示例格式沿用原项目, 脚本代码针对 Alpine 重新编写
# Menu layout and wording, the server config template and the client example format follow
# the original project; the script code itself is rewritten for Alpine Linux
#
# Snell 是 Surge 团队开发的代理协议, 本脚本为第三方非官方脚本
# Snell is a proxy protocol by the Surge team; this is an unofficial third-party script
#
# Copyright (C) 2026 csjcsl666
# This project is licensed under AGPL-3.0, see LICENSE

set -u

SCRIPT_VERSION="1.1.0"

# ---------------------------------------------------------------------------
# 管理命令自身
# ---------------------------------------------------------------------------
# 本脚本安装后的位置, 以后直接输入 snell 进入菜单 (与二进制 snell-server 不同名)
SELF_PATH="/usr/local/bin/snell"
# 管理脚本的下载地址, 可用环境变量 SNELL_ALPINE_SCRIPT_URL 指向镜像
SCRIPT_URL="${SNELL_ALPINE_SCRIPT_URL:-https://raw.githubusercontent.com/csjcsl666/Snell-Alpine/main/snell-alpine.sh}"
# 下面这一行是完整性校验用的标记, 不要修改
# shellcheck disable=SC2034
SNELL_ALPINE_SCRIPT=1

# ---------------------------------------------------------------------------
# 兼容范围
# ---------------------------------------------------------------------------
# 已确认范围: Alpine 3.21 到 3.24 (musl + apk + OpenRC + gcompat 1.1.0-r4)
# 新增 stable 分支并确认兼容后, 只需要修改 CONFIRMED_MAX
MIN_ALPINE="3.21"
CONFIRMED_MAX="3.24"

# ---------------------------------------------------------------------------
# Snell 官方来源
# ---------------------------------------------------------------------------
SNELL_DL_BASE="https://dl.nssurge.com/snell"
SNELL_KB_URL="https://kb.nssurge.com/surge-knowledge-base/release-notes/snell.md"
# 无法从官方页面解析最新版本时使用的版本, 可用环境变量 SNELL_VERSION 覆盖
SNELL_FALLBACK_VERSION="v6.0.0rc2"

# ---------------------------------------------------------------------------
# 本项目创建的路径 (卸载只允许删除这些)
# ---------------------------------------------------------------------------
BIN_FILE="/usr/local/bin/snell-server"
CONF_DIR="/etc/snell"
CONF_FILE="/etc/snell/snell-server.conf"
CLIENT_CONF_FILE="/etc/snell/snell-client.conf"
VERSION_FILE="/etc/snell/version"
USER_MARK_FILE="/etc/snell/.created-user"
INIT_FILE="/etc/init.d/snell"
LOG_FILE="/var/log/snell.log"
SERVICE_NAME="snell"
SERVICE_USER="snell"
SERVICE_ARGS="-l notify -c $CONF_FILE"

RUNTIME_PKGS="gcompat libstdc++ libgcc"
WORK_PARENT="/var/tmp"

# 运行期确定的变量
ALPINE_REL=""
ALPINE_MM=""
APK_ARCH=""
ASSET_ARCH=""
WORK_DIR=""
CHOICE=""
TARGET_TAG=""

if [ -t 1 ]; then
    C_RED=$(printf '\033[0;31m')
    C_GREEN=$(printf '\033[0;32m')
    C_YELLOW=$(printf '\033[0;33m')
    C_RESET=$(printf '\033[0m')
else
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_RESET=""
fi

# ---------------------------------------------------------------------------
# 输出与清理
# ---------------------------------------------------------------------------
say() { printf '%s\n' "$*"; }
ok() { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
err() { printf '%s%s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }

cleanup() {
    case "$WORK_DIR" in
        "$WORK_PARENT"/snell-alpine.??????)
            rm -rf -- "$WORK_DIR"
            ;;
    esac
    WORK_DIR=""
}

trap cleanup EXIT
trap 'printf "\n"; err "已取消操作"; exit 130' INT TERM

make_work_dir() {
    cleanup
    WORK_DIR=$(mktemp -d "$WORK_PARENT/snell-alpine.XXXXXX") || {
        err "无法在 $WORK_PARENT 创建临时目录"
        WORK_DIR=""
        return 1
    }
}

# 只允许删除本项目自己创建的路径
safe_rm() {
    for _p in "$@"; do
        case "$_p" in
            "$BIN_FILE" | "$BIN_FILE.bak" | "$BIN_FILE.new" | "$INIT_FILE" | "$CONF_DIR" | "$LOG_FILE" | "$LOG_FILE.1" | "$SELF_PATH" | "$SELF_PATH.new")
                rm -rf -- "$_p"
                ;;
            *)
                err "拒绝删除非本项目路径: $_p"
                return 1
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------
is_interactive() { [ -t 0 ]; }

# 用法: confirm "问题" ; 默认否, 设置 SNELL_ALPINE_YES=1 时自动同意
confirm() {
    [ "${SNELL_ALPINE_YES:-0}" = "1" ] && return 0
    is_interactive || return 1
    printf '%s [y/N]: ' "$1"
    read -r _ans || return 1
    case "$_ans" in
        y | Y | yes | YES) return 0 ;;
        *) return 1 ;;
    esac
}

pause_menu() {
    is_interactive || return 0
    printf '按 Enter 键继续...'
    read -r _dummy || exit 0
}

# ---------------------------------------------------------------------------
# 系统检查
# ---------------------------------------------------------------------------
check_root() {
    if [ "$(id -u)" != "0" ]; then
        err "请以 root 权限运行此脚本"
        return 1
    fi
}

ver_num() {
    # "3.24" -> 324, 主版本与次版本各占位, 便于比较
    _maj=${1%%.*}
    _min=${1#*.}
    _min=${_min%%[!0-9]*}
    echo $((_maj * 100 + _min))
}

check_alpine() {
    if [ ! -r /etc/alpine-release ]; then
        err "未找到 /etc/alpine-release, 本脚本只支持 Alpine Linux"
        return 1
    fi
    read -r ALPINE_REL < /etc/alpine-release || ALPINE_REL=""
    ALPINE_MM=$(printf '%s\n' "$ALPINE_REL" | sed -n 's/^\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1.\2/p')
    if [ -z "$ALPINE_MM" ]; then
        err "无法识别 Alpine 版本: ${ALPINE_REL:-空}"
        err "edge 与开发快照不在支持范围内"
        return 1
    fi
    if ! command -v apk > /dev/null 2>&1; then
        err "未找到 apk 命令"
        return 1
    fi
    if ! command -v rc-service > /dev/null 2>&1 || ! command -v rc-update > /dev/null 2>&1; then
        err "未检测到 OpenRC (rc-service / rc-update)"
        err "请先执行: apk add openrc"
        return 1
    fi
}

check_alpine_range() {
    _cur=$(ver_num "$ALPINE_MM")
    if [ "$_cur" -lt "$(ver_num "$MIN_ALPINE")" ]; then
        err "Alpine $ALPINE_MM 低于本脚本支持的最低版本 $MIN_ALPINE"
        return 1
    fi
    if [ "$_cur" -gt "$(ver_num "$CONFIRMED_MAX")" ]; then
        warn "当前 Alpine 版本 $ALPINE_MM 高于脚本已确认兼容范围 ($MIN_ALPINE 到 $CONFIRMED_MAX)"
        warn "根据系统架构判断可能仍然兼容, 但尚未经过项目确认"
        warn "本脚本不会回退到 Docker, 若 Snell 无法启动会直接显示错误"
        if [ "${SNELL_ALPINE_FORCE:-0}" = "1" ]; then
            return 0
        fi
        is_interactive || {
            err "非交互模式下需设置 SNELL_ALPINE_FORCE=1 才会继续"
            return 1
        }
        confirm "仍要继续吗" || return 1
    fi
}

compat_label() {
    _cur=$(ver_num "$ALPINE_MM")
    if [ "$_cur" -gt "$(ver_num "$CONFIRMED_MAX")" ]; then
        echo "未确认, 高于 $CONFIRMED_MAX"
    else
        echo "已确认兼容"
    fi
}

detect_arch() {
    APK_ARCH=$(apk --print-arch 2> /dev/null) || APK_ARCH=""
    case "$APK_ARCH" in
        x86_64) ASSET_ARCH="amd64" ;;
        aarch64) ASSET_ARCH="aarch64" ;;
        x86) ASSET_ARCH="i386" ;;
        *)
            err "当前 CPU 架构 (${APK_ARCH:-未知}) 没有 Snell 官方 Server 二进制, 无法安装"
            err "Snell 官方 v6 只提供 amd64, aarch64, i386"
            return 1
            ;;
    esac
}

need_tool() {
    # 用法: need_tool 命令 apk包名
    command -v "$1" > /dev/null 2>&1 && return 0
    say "缺少 $1, 安装 $2"
    apk add --no-cache "$2" > /dev/null || {
        err "安装 $2 失败"
        return 1
    }
}

ensure_tools() {
    need_tool wget wget || return 1
    need_tool unzip unzip || return 1
    need_tool netstat net-tools || return 1
}

ensure_runtime_deps() {
    _missing=""
    for _pkg in $RUNTIME_PKGS; do
        apk info -e "$_pkg" > /dev/null 2>&1 || _missing="$_missing $_pkg"
    done
    if [ -z "$_missing" ]; then
        say "运行依赖已就绪: $RUNTIME_PKGS"
        return 0
    fi
    say "安装运行依赖:$_missing"
    # shellcheck disable=SC2086
    apk add --no-cache $_missing || {
        err "apk 安装依赖失败, 请检查网络与 /etc/apk/repositories"
        return 1
    }
}

# ---------------------------------------------------------------------------
# Snell 状态
# ---------------------------------------------------------------------------
snell_installed() { [ -x "$BIN_FILE" ] && [ -f "$INIT_FILE" ]; }

snell_running() { rc-service "$SERVICE_NAME" status > /dev/null 2>&1; }

installed_version() {
    # -v 对 rc 版本只输出 v6.0.0, 所以安装时另外记录官方版本标签
    if [ -r "$VERSION_FILE" ]; then
        read -r _v < "$VERSION_FILE" && [ -n "$_v" ] && {
            echo "$_v"
            return 0
        }
    fi
    if [ -x "$BIN_FILE" ]; then
        "$BIN_FILE" -v 2>&1 | sed -n 's/.*snell-server \(v[0-9][^ ]*\).*/\1/p' | head -n1
    fi
}

conf_get() {
    [ -r "$CONF_FILE" ] || return 1
    sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" "$CONF_FILE" | head -n1
}

conf_ports() {
    # 从 listen 中取出所有端口
    conf_get listen | tr ',' '\n' | sed -n 's/.*:\([0-9][0-9]*\)[[:space:]]*$/\1/p'
}

is_listening() {
    netstat -ltn 2> /dev/null | awk -v p="$1" '$4 ~ ("[:.]" p "$") { f = 1 } END { exit !f }'
}

port_in_use() { is_listening "$1"; }

# gcompat 下进程名 (comm) 是 ld-musl-*, 所以按完整启动命令行匹配, 并排除 supervise-daemon 自身
snell_pids() {
    ps -o pid,args 2> /dev/null \
        | awk -v c="$BIN_FILE $SERVICE_ARGS" 'index($0, c) && !/supervise-daemon/ { print $1 }'
}

# ---------------------------------------------------------------------------
# 版本解析与下载
# ---------------------------------------------------------------------------
valid_tag() {
    case "$1" in
        v6.[0-9]*.[0-9]*)
            printf '%s\n' "$1" | grep -qE '^v6\.[0-9]+\.[0-9]+([a-z]+[0-9]*)?$'
            ;;
        *) return 1 ;;
    esac
}

asset_url() { echo "$SNELL_DL_BASE/snell-server-$1-linux-$ASSET_ARCH.zip"; }

url_exists() { wget -q -T 20 --spider "$1" > /dev/null 2>&1; }

# 从官方 KB 页面解析当前架构可用的最高 v6 版本 (正式版 > rc > beta)
latest_from_kb() {
    wget -q -T 20 -O - "$SNELL_KB_URL" 2> /dev/null \
        | grep -oE "snell-server-v6\.[0-9]+\.[0-9]+[a-z0-9]*-linux-$ASSET_ARCH\.zip" \
        | sed -e 's/^snell-server-//' -e "s/-linux-$ASSET_ARCH\\.zip\$//" \
        | sort -u \
        | awk '
            {
                t = $0; s = t; sub(/^v6\./, "", s)
                minor = s + 0; sub(/^[0-9]+\./, "", s)
                patch = s + 0; sub(/^[0-9]+/, "", s)
                stage = 0; n = 0
                if (s == "") stage = 9
                else if (s ~ /^rc/) { stage = 2; x = s; sub(/^rc/, "", x); n = x + 0 }
                else if (s ~ /^(b|beta)/) { stage = 1; x = s; sub(/^(b|beta)/, "", x); n = x + 0 }
                printf "%05d%05d%d%05d %s\n", minor, patch, stage, n, t
            }' \
        | sort | tail -n1 | awk '{ print $2 }'
}

resolve_target_version() {
    if [ -n "${SNELL_VERSION:-}" ]; then
        valid_tag "$SNELL_VERSION" || {
            err "SNELL_VERSION 格式无效: $SNELL_VERSION (示例: v6.0.0rc2)"
            return 1
        }
        TARGET_TAG="$SNELL_VERSION"
        return 0
    fi
    TARGET_TAG=$(latest_from_kb)
    if [ -n "$TARGET_TAG" ] && valid_tag "$TARGET_TAG" && url_exists "$(asset_url "$TARGET_TAG")"; then
        return 0
    fi
    warn "无法从官方页面确定最新版本, 使用脚本内置版本 $SNELL_FALLBACK_VERSION"
    TARGET_TAG="$SNELL_FALLBACK_VERSION"
    url_exists "$(asset_url "$TARGET_TAG")" || {
        err "官方下载地址不可用: $(asset_url "$TARGET_TAG")"
        return 1
    }
}

# 下载, 解压并试运行, 成功后新二进制位于 $WORK_DIR/snell-server
fetch_and_check() {
    _url=$(asset_url "$1")
    make_work_dir || return 1
    say "下载 $_url"
    wget -q -T 30 -O "$WORK_DIR/snell.zip" "$_url" || {
        err "下载失败: $_url"
        return 1
    }
    [ -s "$WORK_DIR/snell.zip" ] || {
        err "下载的文件为空"
        return 1
    }
    say "sha256: $(sha256sum "$WORK_DIR/snell.zip" | awk '{ print $1 }')"
    unzip -l "$WORK_DIR/snell.zip" > /dev/null 2>&1 || {
        err "压缩包损坏或格式无效"
        return 1
    }
    unzip -o -q "$WORK_DIR/snell.zip" snell-server -d "$WORK_DIR" || {
        err "解压失败"
        return 1
    }
    [ -f "$WORK_DIR/snell-server" ] || {
        err "压缩包内没有 snell-server"
        return 1
    }
    chmod 0755 "$WORK_DIR/snell-server" || return 1
    _out=$("$WORK_DIR/snell-server" -v 2>&1) || {
        err "新的 snell-server 无法执行, 输出如下"
        printf '%s\n' "$_out" >&2
        err "常见原因是缺少 gcompat / libstdc++ / libgcc, 或 /var/tmp 以 noexec 挂载"
        return 1
    }
    printf '%s\n' "$_out" | grep -q 'snell-server v6\.' || {
        err "下载的不是 Snell v6, 输出: $_out"
        return 1
    }
    say "$_out"
}

# ---------------------------------------------------------------------------
# 配置生成
# ---------------------------------------------------------------------------
rand_u16() { od -An -N2 -tu2 /dev/urandom | tr -d ' \n'; }

random_port() {
    # 取 10240 到 31999, 避开系统保留端口与 Linux 默认临时端口区间 (32768 起)
    _i=0
    while [ "$_i" -lt 30 ]; do
        _n=$(rand_u16)
        [ -n "$_n" ] || return 1
        _p=$((10240 + _n % 21760))
        port_in_use "$_p" || {
            echo "$_p"
            return 0
        }
        _i=$((_i + 1))
    done
    return 1
}

valid_port() {
    case "$1" in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1025 ] && [ "$1" -le 65535 ]
}

choose_port() {
    _want="${SNELL_PORT:-}"
    if [ -z "$_want" ] && is_interactive; then
        printf '监听端口 (1025-65535, NAT VPS 请填商家分配的内部端口, 直接回车随机): ' >&2
        read -r _want || _want=""
    fi
    if [ -z "$_want" ]; then
        random_port || {
            err "无法生成可用的随机端口"
            return 1
        }
        return 0
    fi
    valid_port "$_want" || {
        err "端口无效: $_want (需要 1025 到 65535)"
        return 1
    }
    port_in_use "$_want" && {
        err "端口 $_want 已被占用"
        return 1
    }
    echo "$_want"
}

choose_listen() {
    # 用法: choose_listen 端口 ; 输出 listen 行的值
    _dual="${SNELL_IPV6:-}"
    if [ -z "$_dual" ] && is_interactive; then
        printf '同时监听 IPv6? (需要系统已启用 IPv6) [y/N]: ' >&2
        read -r _a || _a=""
        case "$_a" in y | Y | yes | YES) _dual=1 ;; esac
    fi
    if [ "$_dual" = "1" ]; then
        if [ ! -e /proc/net/if_inet6 ]; then
            warn "系统未启用 IPv6, 回退为仅 IPv4" >&2
        else
            echo "0.0.0.0:$1,[::]:$1"
            return 0
        fi
    fi
    echo "0.0.0.0:$1"
}

gen_psk() {
    _psk=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
    [ "${#_psk}" -eq 32 ] || return 1
    echo "$_psk"
}

ensure_service_user() {
    if id "$SERVICE_USER" > /dev/null 2>&1; then
        say "用户 $SERVICE_USER 已存在, 直接使用"
        return 0
    fi
    addgroup -S "$SERVICE_USER" 2> /dev/null
    adduser -S -D -H -h /var/empty -s /sbin/nologin -G "$SERVICE_USER" "$SERVICE_USER" || {
        err "创建系统用户 $SERVICE_USER 失败"
        return 1
    }
    mkdir -p "$CONF_DIR" && : > "$USER_MARK_FILE"
}

write_server_conf() {
    # 用法: write_server_conf listen psk
    mkdir -p "$CONF_DIR" || return 1
    chown root:"$SERVICE_USER" "$CONF_DIR" && chmod 0750 "$CONF_DIR" || return 1
    (
        umask 077
        cat > "$CONF_FILE" << EOF
[snell-server]
mode = default
listen = $1
psk = $2
dns-ip-preference = default
EOF
    ) || return 1
    chown root:"$SERVICE_USER" "$CONF_FILE" && chmod 0640 "$CONF_FILE"
}

lookup_public_ip() {
    [ "${SNELL_NO_IP_LOOKUP:-0}" = "1" ] && return 1
    _ip=$(wget -q -T 5 -O - "https://checkip.amazonaws.com" 2> /dev/null | tr -d ' \r\n')
    case "$_ip" in
        '' | *[!0-9a-fA-F.:]*) return 1 ;;
    esac
    echo "$_ip"
}

write_client_conf() {
    _port=$(conf_ports | head -n1)
    _psk=$(conf_get psk)
    _mode=$(conf_get mode)
    _host=$(lookup_public_ip) || _host="<服务器公网IP或NAT域名>"
    (
        umask 077
        cat > "$CLIENT_CONF_FILE" << EOF
Snell = snell, $_host, $_port, psk=$_psk, version=6, mode=${_mode:-default}, reuse=true
EOF
    )
}

write_init_script() {
    cat > "$INIT_FILE" << EOF
#!/sbin/openrc-run
# Generated by snell-alpine.sh

name="Snell"
description="Snell proxy server"

command="$BIN_FILE"
command_args="$SERVICE_ARGS"
command_user="$SERVICE_USER:$SERVICE_USER"
supervisor="supervise-daemon"
respawn_delay=5
respawn_max=5
respawn_period=60
output_log="$LOG_FILE"
error_log="$LOG_FILE"
required_files="$CONF_FILE"

depend() {
	need net
	after firewall
}

start_pre() {
	# 日志超过 5 MiB 时轮转一次, 避免占满小硬盘
	if [ -f "\$output_log" ] && [ "\$(wc -c < "\$output_log")" -gt 5242880 ]; then
		mv -f "\$output_log" "\$output_log.1"
	fi
	# 降权后的进程需要能写日志, 否则会静默启动失败
	checkpath -f -m 0640 -o $SERVICE_USER:$SERVICE_USER "\$output_log"
}
EOF
    chmod 0755 "$INIT_FILE"
}

# ---------------------------------------------------------------------------
# 服务控制与验证
# ---------------------------------------------------------------------------
show_failure_context() {
    err "服务状态:"
    rc-service "$SERVICE_NAME" status 2>&1 | sed 's/^/    /' >&2
    if [ -f "$LOG_FILE" ]; then
        err "最近日志 ($LOG_FILE):"
        tail -n 20 "$LOG_FILE" | sed 's/^/    /' >&2
    fi
    if [ -x "$BIN_FILE" ]; then
        err "直接执行 snell-server -v 的结果:"
        "$BIN_FILE" -v 2>&1 | sed 's/^/    /' >&2
    fi
}

# 等待进程存在并且所有配置端口处于 LISTEN
verify_running() {
    _ports=$(conf_ports)
    [ -n "$_ports" ] || {
        err "无法从 $CONF_FILE 读取监听端口"
        return 1
    }
    _t=0
    while [ "$_t" -lt 15 ]; do
        _all=1
        [ -n "$(snell_pids)" ] || _all=0
        for _p in $_ports; do
            is_listening "$_p" || _all=0
        done
        if [ "$_all" = "1" ]; then
            return 0
        fi
        sleep 1
        _t=$((_t + 1))
    done
    err "服务在 15 秒内没有进入 LISTEN 状态 (端口: $(echo "$_ports" | tr '\n' ' '))"
    show_failure_context
    return 1
}

start_service() {
    rc-service "$SERVICE_NAME" start || {
        err "rc-service $SERVICE_NAME start 失败"
        show_failure_context
        return 1
    }
    verify_running
}

stop_service() {
    rc-service "$SERVICE_NAME" stop || {
        err "rc-service $SERVICE_NAME stop 失败"
        return 1
    }
}

restart_service() {
    rc-service "$SERVICE_NAME" restart || {
        err "rc-service $SERVICE_NAME restart 失败"
        show_failure_context
        return 1
    }
    verify_running
}

print_summary() {
    say ""
    say "Snell 当前监听端口: $(conf_ports | tr '\n' ' ')"
    say "如果这是 NAT VPS, 请确保商家面板中对应的公网端口已映射到该端口"
    say "服务器配置: $CONF_FILE"
    say "客户端示例 (Surge):"
    [ -f "$CLIENT_CONF_FILE" ] && cat "$CLIENT_CONF_FILE"
    say ""
    say "以后输入 snell 即可打开管理菜单"
}

# ---------------------------------------------------------------------------
# 功能: 安装
# ---------------------------------------------------------------------------
do_install() {
    if snell_installed; then
        warn "Snell 已安装, 如需升级请使用更新, 如需重装请先卸载"
        return 1
    fi
    if [ -e "$CONF_FILE" ] || [ -e "$INIT_FILE" ]; then
        err "检测到残留文件 ($CONF_FILE 或 $INIT_FILE), 为避免覆盖已停止安装"
        err "确认无用后请先执行卸载"
        return 1
    fi

    say "[1/6] 检查并安装依赖"
    ensure_tools || return 1
    ensure_runtime_deps || return 1

    say "[2/6] 解析版本并下载官方 Snell"
    resolve_target_version || return 1
    say "目标版本: $TARGET_TAG"
    fetch_and_check "$TARGET_TAG" || return 1

    say "[3/6] 生成配置"
    _port=$(choose_port) || return 1
    _listen=$(choose_listen "$_port") || return 1
    _psk=$(gen_psk) || {
        err "生成 PSK 失败 (/dev/urandom 不可用?)"
        return 1
    }
    ensure_service_user || return 1
    write_server_conf "$_listen" "$_psk" || {
        err "写入 $CONF_FILE 失败"
        return 1
    }

    say "[4/6] 安装二进制与 OpenRC 服务"
    install -m 0755 -o root -g root "$WORK_DIR/snell-server" "$BIN_FILE" || {
        err "安装 $BIN_FILE 失败"
        return 1
    }
    echo "$TARGET_TAG" > "$VERSION_FILE" || return 1
    write_init_script || {
        err "写入 $INIT_FILE 失败"
        return 1
    }
    rc-update add "$SERVICE_NAME" default > /dev/null || {
        err "rc-update add $SERVICE_NAME default 失败"
        return 1
    }

    say "[5/6] 启动服务"
    start_service || {
        err "安装未完成: Snell 没有正常运行"
        err "文件已保留以便排查, 不需要时请使用菜单中的卸载"
        return 1
    }

    say "[6/6] 生成客户端示例"
    write_client_conf
    ok "Snell 安装完成并已验证: 进程存在, 端口处于 LISTEN"
    print_summary
}

# ---------------------------------------------------------------------------
# 功能: 更新
# ---------------------------------------------------------------------------
do_update() {
    snell_installed || {
        err "Snell 尚未安装"
        return 1
    }
    ensure_tools || return 1
    resolve_target_version || return 1
    _cur=$(installed_version)
    say "当前版本: ${_cur:-未知}"
    say "目标版本: $TARGET_TAG"
    if [ "$_cur" = "$TARGET_TAG" ]; then
        ok "已经是最新版本, 无需更新"
        return 0
    fi
    ensure_runtime_deps || return 1
    # 先下载并试运行, 失败时旧版本保持不动
    fetch_and_check "$TARGET_TAG" || {
        err "更新已中止, 现有版本未改动"
        return 1
    }
    _was_running=0
    snell_running && _was_running=1

    say "备份旧版本并替换"
    cp -p "$BIN_FILE" "$BIN_FILE.bak" || {
        err "备份失败, 更新已中止"
        return 1
    }
    [ "$_was_running" = "1" ] && { stop_service || return 1; }
    if ! { install -m 0755 -o root -g root "$WORK_DIR/snell-server" "$BIN_FILE.new" \
        && mv -f "$BIN_FILE.new" "$BIN_FILE"; }; then
        err "替换二进制失败, 恢复旧版本"
        safe_rm "$BIN_FILE.new"
        mv -f "$BIN_FILE.bak" "$BIN_FILE"
        if [ "$_was_running" = "1" ]; then start_service; fi
        return 1
    fi
    if start_service; then
        echo "$TARGET_TAG" > "$VERSION_FILE"
        safe_rm "$BIN_FILE.bak"
        ok "更新完成并已验证: ${_cur:-未知} -> $TARGET_TAG"
        return 0
    fi
    err "新版本启动失败, 回滚到旧版本"
    rc-service "$SERVICE_NAME" stop > /dev/null 2>&1
    if mv -f "$BIN_FILE.bak" "$BIN_FILE" && start_service; then
        warn "已回滚并恢复运行: ${_cur:-未知}"
    else
        err "回滚后仍无法启动, 请查看日志"
    fi
    return 1
}

# ---------------------------------------------------------------------------
# 功能: 卸载
# ---------------------------------------------------------------------------
do_uninstall() {
    if ! snell_installed && [ ! -e "$CONF_DIR" ] && [ ! -e "$INIT_FILE" ]; then
        warn "Snell 尚未安装"
        return 1
    fi
    confirm "将停止并删除 Snell 服务, 配置 ($CONF_DIR) 与日志, 确认卸载" || {
        say "已取消"
        return 1
    }
    _created_user=0
    [ -f "$USER_MARK_FILE" ] && _created_user=1

    rc-service "$SERVICE_NAME" stop > /dev/null 2>&1
    rc-update del "$SERVICE_NAME" default > /dev/null 2>&1
    safe_rm "$INIT_FILE" "$BIN_FILE" "$BIN_FILE.bak" "$BIN_FILE.new" "$CONF_DIR" "$LOG_FILE" "$LOG_FILE.1" || return 1
    if [ "$_created_user" = "1" ]; then
        deluser "$SERVICE_USER" > /dev/null 2>&1
        delgroup "$SERVICE_USER" > /dev/null 2>&1
    fi
    ok "Snell 已卸载"
    say "未移除依赖包 ($RUNTIME_PKGS), 它们可能被其他程序使用"
    say "确认不再需要时可自行执行: apk del $RUNTIME_PKGS"
    say "管理命令 snell 已保留, 可随时重新安装; 如需一并删除请执行: snell self-uninstall"
}

# ---------------------------------------------------------------------------
# 功能: 管理命令自身的安装 / 更新 / 删除
# ---------------------------------------------------------------------------
# 完整性校验: 标记行存在, 末行是入口 (排除下载不完整), 语法正确
valid_script() {
    grep -qx 'SNELL_ALPINE_SCRIPT=1' "$1" 2> /dev/null \
        && [ "$(tail -n 1 "$1")" = 'main "$@"' ] \
        && sh -n "$1" 2> /dev/null
}

script_version_of() { sed -n 's/^SCRIPT_VERSION="\(.*\)"$/\1/p' "$1" | head -n1; }

# 下载管理脚本到 $WORK_DIR/snell.sh 并校验, 失败时不改动任何文件
fetch_script() {
    make_work_dir || return 1
    say "获取管理脚本: $SCRIPT_URL"
    wget -q -T 30 -O "$WORK_DIR/snell.sh" "$SCRIPT_URL" || {
        err "下载管理脚本失败: $SCRIPT_URL"
        return 1
    }
    valid_script "$WORK_DIR/snell.sh" || {
        err "下载的管理脚本不完整或无效, 未做任何修改"
        return 1
    }
}

# 用法: install_self 已校验的脚本文件 ; 先写临时文件再 mv 原子替换, 不影响正在运行的旧脚本
install_self() {
    _new_ver=$(script_version_of "$1")
    if [ -f "$SELF_PATH" ] && cmp -s "$1" "$SELF_PATH"; then
        say "管理命令 $SELF_PATH 已是最新 ($_new_ver)"
        return 0
    fi
    _old_ver=""
    [ -f "$SELF_PATH" ] && _old_ver=$(script_version_of "$SELF_PATH")
    if ! { install -m 0755 -o root -g root "$1" "$SELF_PATH.new" && mv -f "$SELF_PATH.new" "$SELF_PATH"; }; then
        err "写入 $SELF_PATH 失败"
        safe_rm "$SELF_PATH.new"
        return 1
    fi
    if [ -n "$_old_ver" ]; then
        ok "管理命令已更新: ${_old_ver} -> ${_new_ver}"
    else
        ok "管理命令已安装: $SELF_PATH ($_new_ver)"
    fi
}

# 不是以 $SELF_PATH 运行时 (管道执行或临时下载的文件), 先把脚本安装为 snell 命令, 再交给本地命令执行
bootstrap() {
    _self=$(readlink -f "$0" 2> /dev/null) || _self=""
    [ "$_self" = "$SELF_PATH" ] && return 0

    if [ -f "$_self" ] && grep -qx 'SNELL_ALPINE_SCRIPT=1' "$_self" 2> /dev/null; then
        # 以本地文件运行: 安装的就是这份文件, 不需要联网; 与已装命令相同时直接转交, 不重复提示
        valid_script "$_self" || {
            err "脚本文件 $_self 不完整或有语法错误, 请重新下载"
            exit 1
        }
        if ! { [ -f "$SELF_PATH" ] && cmp -s "$_self" "$SELF_PATH"; }; then
            install_self "$_self" || exit 1
            say "以后输入 snell 即可打开管理菜单"
            say ""
        fi
    else
        # 管道执行 (wget -qO- URL | sh): 拿不到自身内容, 重新下载一份完整的再安装
        fetch_script || exit 1
        install_self "$WORK_DIR/snell.sh" || exit 1
        cleanup
        say "以后输入 snell 即可打开管理菜单"
        say ""
    fi

    # exec 不会触发 EXIT trap, 上面已手动清理临时文件
    if [ -t 0 ]; then
        exec "$SELF_PATH" "$@"
    fi
    # 管道执行时标准输入是脚本本身, 改从终端读取菜单输入
    if (: < /dev/tty) 2> /dev/null; then
        exec "$SELF_PATH" "$@" < /dev/tty
    fi
    if [ "$#" -gt 0 ]; then
        exec "$SELF_PATH" "$@" < /dev/null
    fi
    say "当前没有可交互的终端, 请在终端中输入 snell 打开管理菜单"
    exit 0
}

do_self_update() {
    fetch_script || return 1
    if cmp -s "$WORK_DIR/snell.sh" "$SELF_PATH"; then
        ok "管理脚本已是最新 ($SCRIPT_VERSION), 无需更新"
        return 2
    fi
    install_self "$WORK_DIR/snell.sh" || return 1
    say "只更新了管理脚本, Snell Server 未改动 (更新 Snell 请使用: snell update)"
}

do_self_uninstall() {
    if snell_installed; then
        err "Snell 仍处于安装状态, 请先执行 snell uninstall, 再删除管理命令"
        return 1
    fi
    confirm "将删除管理命令 $SELF_PATH, 确认" || {
        say "已取消"
        return 1
    }
    safe_rm "$SELF_PATH" || return 1
    ok "管理命令已删除, 需要时重新执行安装命令即可"
}

# ---------------------------------------------------------------------------
# 功能: 状态 / 日志 / 配置
# ---------------------------------------------------------------------------
do_status() {
    snell_installed || {
        err "Snell 尚未安装"
        return 1
    }
    rc-service "$SERVICE_NAME" status
    if rc-update show default 2> /dev/null | grep -q "^[[:space:]]*${SERVICE_NAME}[[:space:]]"; then
        say "开机自启: 已启用"
    else
        say "开机自启: 未启用"
    fi
    for _p in $(conf_ports); do
        if is_listening "$_p"; then
            say "端口 $_p: LISTEN"
        else
            say "端口 $_p: 未监听"
        fi
    done
    _pids=$(snell_pids | tr '\n' ' ')
    if [ -n "$_pids" ]; then
        say "进程: 存在 (PID $_pids)"
    else
        say "进程: 不存在"
    fi
}

do_log() {
    [ -f "$LOG_FILE" ] || {
        err "日志文件不存在: $LOG_FILE"
        return 1
    }
    tail -n 50 "$LOG_FILE"
    is_interactive || return 0
    confirm "实时跟踪日志? (Ctrl+C 返回)" || return 0
    trap ':' INT
    (
        trap - INT
        exec tail -n 0 -f "$LOG_FILE"
    )
    trap 'printf "\n"; err "已取消操作"; exit 130' INT TERM
    printf '\n'
}

do_config() {
    [ -f "$CONF_FILE" ] || {
        err "配置文件不存在: $CONF_FILE"
        return 1
    }
    say "服务器配置 ($CONF_FILE):"
    cat "$CONF_FILE"
    say ""
    if [ -f "$CLIENT_CONF_FILE" ]; then
        say "客户端配置 ($CLIENT_CONF_FILE):"
        cat "$CLIENT_CONF_FILE"
    fi
    say ""
    say "如果这是 NAT VPS, 客户端的地址与端口请填商家分配的公网地址与映射端口"
}

do_toggle() {
    snell_installed || {
        err "Snell 尚未安装"
        return 1
    }
    if snell_running; then
        stop_service && ok "Snell 已停止"
    else
        start_service && ok "Snell 已启动"
    fi
}

do_restart() {
    snell_installed || {
        err "Snell 尚未安装"
        return 1
    }
    restart_service && ok "Snell 已重启"
}

# ---------------------------------------------------------------------------
# 菜单
# ---------------------------------------------------------------------------
show_menu() {
    is_interactive && command -v clear > /dev/null 2>&1 && clear
    if snell_installed; then
        _inst="${C_GREEN}已安装${C_RESET}"
        _ver=$(installed_version)
        [ -n "$_ver" ] || _ver="未知"
        if snell_running; then
            _run="${C_GREEN}运行中${C_RESET}"
            _toggle="停止"
        else
            _run="${C_RED}未运行${C_RESET}"
            _toggle="启动"
        fi
    else
        _inst="${C_RED}未安装${C_RESET}"
        _run="${C_RED}未运行${C_RESET}"
        _ver="-"
        _toggle="启动"
    fi
    ok "=== Snell Alpine 管理工具 ==="
    say ""
    say "系统版本: Alpine Linux $ALPINE_REL ($(compat_label))"
    say "CPU 架构: $APK_ARCH (Snell: $ASSET_ARCH)"
    say "Snell 安装状态: $_inst"
    say "Snell 运行状态: $_run"
    say "Snell 运行版本: $_ver"
    say "管理脚本版本: $SCRIPT_VERSION"
    say ""
    say "1. 安装 Snell 服务"
    say "2. 卸载 Snell 服务"
    say "3. ${_toggle} Snell 服务"
    say "4. 更新 Snell"
    say "5. 重启 Snell 服务"
    say "6. 查看 Snell 状态"
    say "7. 查看 Snell 日志"
    say "8. 查看 Snell 配置"
    say "9. 更新管理脚本"
    say "0. 退出"
    ok "============================="
    printf '请输入选项编号: '
    read -r CHOICE || {
        printf '\n'
        exit 0
    }
    say ""
}

run_menu() {
    while true; do
        show_menu
        case "$CHOICE" in
            1) do_install ;;
            2) do_uninstall ;;
            3) do_toggle ;;
            4) do_update ;;
            5) do_restart ;;
            6) do_status ;;
            7) do_log ;;
            8) do_config ;;
            9)
                if do_self_update; then
                    pause_menu
                    # 用新版本脚本重新打开菜单
                    cleanup
                    exec "$SELF_PATH"
                fi
                ;;
            0)
                ok "已退出 Snell Alpine 管理工具"
                exit 0
                ;;
            *) err "无效的选项" ;;
        esac
        pause_menu
    done
}

usage() {
    cat << EOF
Snell Alpine 管理工具 $SCRIPT_VERSION

用法: snell [命令]

命令:
  (无)            进入交互菜单
  install         安装 Snell
  uninstall       卸载 Snell (保留 snell 管理命令)
  start           启动服务
  stop            停止服务
  restart         重启服务
  update          更新 Snell Server
  status          查看状态
  log             查看日志
  config          查看配置
  self-update     更新管理脚本 (不影响 Snell Server)
  self-uninstall  删除 snell 管理命令 (需先卸载 Snell)

环境变量:
  SNELL_PORT=端口          安装时指定监听端口 (默认随机)
  SNELL_IPV6=1             安装时同时监听 IPv6
  SNELL_VERSION=v6.x.y     指定 Snell 版本 (默认自动获取最新 v6)
  SNELL_ALPINE_YES=1       跳过确认提示
  SNELL_ALPINE_FORCE=1     允许在高于已确认范围的 Alpine 上继续
  SNELL_NO_IP_LOOKUP=1     不查询公网 IP
EOF
}

main() {
    case "${1:-}" in
        -h | --help | help)
            usage
            exit 0
            ;;
    esac

    check_root || exit 1
    check_alpine || exit 1
    detect_arch || exit 1
    bootstrap "$@"
    check_alpine_range || exit 1

    case "${1:-}" in
        "") run_menu ;;
        install) do_install ;;
        uninstall) do_uninstall ;;
        start | stop)
            snell_installed || {
                err "Snell 尚未安装"
                exit 1
            }
            if [ "$1" = "start" ]; then start_service; else stop_service; fi
            ;;
        restart) do_restart ;;
        update) do_update ;;
        status) do_status ;;
        log) do_log ;;
        config) do_config ;;
        self-update)
            do_self_update
            [ "$?" -ne 1 ]
            ;;
        self-uninstall) do_self_uninstall ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
