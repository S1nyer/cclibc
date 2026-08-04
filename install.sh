#!/usr/bin/env bash
# ============================================================================
# cclibc 安装脚本
#   1. 系统依赖 (patchelf/binutils/gcc 等)
#   2. glibc-all-in-one + glibc-aio
#   3. cclibc 软链接到 /usr/local/bin (PATH)
#   4. (可选) 下载 libc:
#      standard - 仅 LTS 版 amd64 libc, 不下载 old (推荐)
#      advanced - 全量所有 libc 版本 (含 old-releases 补全)
#   两种模式对同一 glibc 主版本都只下载最新修订
# ============================================================================
set -euo pipefail

CCLIBC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIO_DIR="${CCLIBC_AIO:-$HOME/glibc-all-in-one}"

# ----------------------------- 颜色 / 输出 -----------------------------
if [ -t 1 ]; then
  C_YEL=$'\033[33m'; C_GRN=$'\033[32m'; C_RED=$'\033[31m'; C_BLU=$'\033[36m'; C_RST=$'\033[0m'
else
  C_YEL=""; C_GRN=""; C_RED=""; C_BLU=""; C_RST=""
fi
info() { echo -e "${C_BLU}[*]${C_RST} $*"; }
ok()   { echo -e "${C_GRN}[+]${C_RST} $*"; }
warn() { echo -e "${C_YEL}[!]${C_RST} $*"; }
die()  { echo -e "${C_RED}[-]${C_RST} $*" >&2; exit 1; }

# [Y/n] 提问; $1=提示文字, $2=默认值(y/n); 输入 EOF/回车 时用默认值
ask_yes() {
  local ans d="$2"
  read -r -p "$1 [$([ "$d" = y ] && echo Y/n || echo y/N)] " ans || ans="$d"
  ans="${ans:-$d}"
  case "$ans" in
    [yY]*) return 0 ;;
    *) return 1 ;;
  esac
}

# 在 AIO_DIR 下执行 glibc-aio (libs/list 均为相对路径, 必须切目录)
aio_cmd() {
  if command -v glibc-aio >/dev/null 2>&1; then
    (cd "$AIO_DIR" && glibc-aio "$@")
  else
    (cd "$AIO_DIR" && python3 -m glibc_aio.cli.main "$@")
  fi
}

# 按模式筛选要下载的版本: 每个 glibc 主版本只取最新修订
# 注意: 排序前必须去掉 _amd64 后缀, 否则 ".6_amd64" < "._amd64" 导致排序错误
pick_versions() {
  local mode="$1" list="$AIO_DIR/list" m v out=""
  [ -f "$list" ] || return 1
  if [ "$mode" = "advanced" ]; then
    out=$(grep -E '^2\.' "$list" | grep "_amd64$" | sed 's/_amd64$//' \
      | sort -V | awk -F'-' 'prev != $1 { if (prev != "") print last; prev = $1 }
                             { last = $0 } END { print last }' \
      | sed 's/$/_amd64/' || true)
  else
    for m in 2.23 2.27 2.31 2.35 2.39; do  # Ubuntu LTS 对应 glibc
      v=$(grep -E "^${m}-" "$list" | grep "_amd64$" | sed 's/_amd64$//' \
          | sort -V | tail -1 || true)
      [ -n "$v" ] && out="$out ${v}_amd64"
    done
  fi
  echo "$out"
}

# ----------------------------- 1. 欢迎 -----------------------------
echo
echo "=============================================="
echo "  cclibc 安装"
echo "=============================================="
echo "  目录: $CCLIBC_DIR"
echo "  glibc-all-in-one: $AIO_DIR"
echo

# ----------------------------- 2. 系统依赖 -----------------------------
info "检查系统依赖 ..."
MISSING=""
declare -A DEP_PKG=(
  [patchelf]=patchelf [readelf]=binutils [ar]=binutils
  [tar]=tar [gcc]=gcc [zstd]=zstd
)
for cmd in patchelf readelf ar tar gcc zstd; do
  command -v "$cmd" >/dev/null 2>&1 || MISSING="$MISSING ${DEP_PKG[$cmd]}"
done
if [ -n "$MISSING" ]; then
  PKGS=$(echo "$MISSING" | tr ' ' '\n' | awk '!seen[$0]++' | tr '\n' ' ')
  warn "缺少依赖包: $PKGS"
  if ask_yes "  是否用 sudo apt 安装?" y; then
    sudo apt-get update || true
    sudo apt-get install -y $PKGS || die "apt 安装失败"
  else
    die "请先手动安装: sudo apt-get install -y $PKGS"
  fi
else
  ok "依赖就绪"
fi

# ----------------------------- 3. glibc-all-in-one + glibc-aio -----------------------------
if [ ! -d "$AIO_DIR" ]; then
  if ask_yes "未找到 glibc-all-in-one, 是否 clone 到 $AIO_DIR?" y; then
    git clone https://github.com/matrix1001/glibc-all-in-one.git "$AIO_DIR" \
      || die "git clone 失败 (检查网络)"
  else
    die "cclibc 依赖 glibc-all-in-one, 无法继续"
  fi
else
  ok "glibc-all-in-one 已存在: $AIO_DIR"
fi

info "安装 glibc-aio (Python 包) ..."
_pip_install() {
  # Kali 默认启用 PEP 668 externally-managed, pip 拒绝安装系统级包。
  # 先尝试普通安装, 失败则加 --break-system-packages 重试。
  (cd "$AIO_DIR" && python3 -m pip install -e . "$@") && return 0
  (cd "$AIO_DIR" && python3 -m pip install --break-system-packages -e . "$@") && return 0
  return 1
}
if ! _pip_install; then
  warn "pip 安装失败 (Kali 限制), 可手动: cd $AIO_DIR && pip install --break-system-packages -e ."
  warn "缺少 pyelftools 时 libc 下载后的索引会跳过 (不影响解包, cclibc 仍可用)"
fi

info "拉取可用 libc 版本列表 ..."
aio_cmd mirror update || warn "mirror update 失败 (可稍后手动执行)"

# ----------------------------- 4. PATH: 创建软链接 -----------------------------
if command -v cclibc >/dev/null 2>&1; then
  ok "cclibc 已在 PATH: $(command -v cclibc)"
else
  info "将 cclibc 软链接到 /usr/local/bin (所有用户可用)"
  if [ -w /usr/local/bin ]; then
    ln -sf "$CCLIBC_DIR/cclibc" /usr/local/bin/cclibc
    ok "已创建 /usr/local/bin/cclibc"
  elif ask_yes "  /usr/local/bin 不可写, 用 sudo 创建软链接?" y; then
    if sudo ln -sf "$CCLIBC_DIR/cclibc" /usr/local/bin/cclibc; then
      ok "已创建 /usr/local/bin/cclibc"
    else
      warn "软链接创建失败, 可手动执行: sudo ln -sf $CCLIBC_DIR/cclibc /usr/local/bin/cclibc"
    fi
  else
    warn "跳过 PATH 配置, 使用: $CCLIBC_DIR/cclibc"
  fi
fi

# ----------------------------- 5. (可选) 下载 libc -----------------------------
if ask_yes "是否需要下载 libc 版本?" y; then
  echo "  请选择下载模式:"
  echo "    1) standard  - 仅 LTS 版 amd64 libc [2.23/2.27/2.31/2.35/2.39] (推荐)"
  echo "    2) advanced  - 全量所有 libc 版本 (含 old-releases 补全)"
  MODE="standard"
  read -r -p "  请选择 [1/2] (默认 1): " ans || ans=1
  [ "${ans:-1}" = "2" ] && MODE="advanced"
  info "下载模式: $MODE"

  VERSIONS=$(pick_versions "$MODE" || true)
  if [ -z "$VERSIONS" ]; then
    warn "没有可下载的版本 (list 文件缺失? 先运行 glibc-aio mirror update)"
  else
    echo "  将下载以下版本 (已存在的自动跳过):"
    for v in $VERSIONS; do echo "    - $v"; done
    if ask_yes "  开始下载?" y; then
      for v in $VERSIONS; do
        if [ -d "$AIO_DIR/libs/$v" ]; then
          info "跳过(已存在) $v"
          continue
        fi
        info "下载 $v ..."
        if aio_cmd download "$v"; then
          :
        elif [ -d "$AIO_DIR/libs/$v" ]; then
          warn "$v: 索引失败 (缺少 pyelftools), 但 libc 已解包, 不影响使用"
        else
          warn "下载 $v 失败"
        fi
      done
      ok "libc 下载完成"
    else
      info "跳过下载, 之后可用: cclibc download <版本>"
    fi
  fi
else
  info "跳过下载, 之后可用: cclibc download <版本>"
fi

# ----------------------------- 6. 完成 -----------------------------
echo
ok "安装完成!"
N=$(ls "$AIO_DIR/libs/" 2>/dev/null | grep -c "_amd64" || true)
[ "$N" -gt 0 ] && info "已下载 $N 个 amd64 libc 环境: $AIO_DIR/libs/"
if command -v cclibc >/dev/null 2>&1; then
  cclibc -v
else
  "$CCLIBC_DIR/cclibc" -v
fi
info "快速开始: cclibc switch ./pwn ./libc.so.6"
