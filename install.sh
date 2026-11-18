#!/usr/bin/env bash
# 在全新机器上恢复 pi 环境：Node.js -> pi -> packages.txt 里的扩展
# 用法：./install.sh [--omp]   （--omp 改装 oh-my-pi 的 omp，需要 bun）
set -euo pipefail
[ "${BASH_VERSINFO[0]}" -ge 4 ] || { printf '错误：需要 bash >= 4（mapfile/关联数组），当前 %s\n' "$BASH_VERSION" >&2; exit 1; }
cd "$(dirname "$0")"

CLI=pi
PI_PKG="${PI_PKG:-}"   # 空则按 CLI 取默认包（--omp 解析后赋值）
PKGS_FILE=packages.txt
NODE_MIN_MAJOR=22

SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"  # 容器里常是 root，没有 sudo

log() { printf '==> %s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --omp) CLI=omp; PI_PKG="${PI_PKG:-@oh-my-pi/pi-coding-agent}"; PKGS_FILE=packages-omp.txt ;;
    -h|--help) sed -n '3p' "$0"; exit 0 ;;
    *) die "未知参数：$1（可用：--omp）" ;;
  esac
  shift
done
[ -n "$PI_PKG" ] || PI_PKG=@earendil-works/pi-coding-agent

# 1. npm 不存在则安装 Node.js
if ! command -v npm >/dev/null 2>&1; then
  log "npm 不存在，安装 Node.js"
  if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update -y && $SUDO apt-get install -y nodejs npm
  elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf install -y nodejs npm
  elif command -v pacman >/dev/null 2>&1; then
    $SUDO pacman -Sy --noconfirm nodejs npm
  elif command -v apk >/dev/null 2>&1; then
    $SUDO apk add --no-cache nodejs npm
  elif command -v brew >/dev/null 2>&1; then
    brew install node
  else
    die "未识别的包管理器，请手动安装 Node.js >= $NODE_MIN_MAJOR"
  fi
fi
command -v npm >/dev/null 2>&1 || die "npm 安装失败"

node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)"
[ -n "$node_major" ] || die "node 不可用，请安装 Node.js >= $NODE_MIN_MAJOR"
[ "$node_major" -ge "$NODE_MIN_MAJOR" ] || die "Node.js v$(node -v) 过低，pi 需要 >= $NODE_MIN_MAJOR。建议：
  curl -fsSL https://deb.nodesource.com/setup_${NODE_MIN_MAJOR}.x | sudo -E bash -
  sudo apt-get install -y nodejs"

# 2. CLI 不存在则全局安装（omp 用 bun，pi 用 npm）
if ! command -v "$CLI" >/dev/null 2>&1; then
  log "$CLI 不存在，安装 $PI_PKG"
  if [ "$CLI" = omp ]; then
    # bun 缺失时用 npm 装（--allow-scripts 必要，bun 的 postinstall 要拉二进制）
    if ! command -v bun >/dev/null 2>&1; then
      log "bun 不存在，用 npm 安装"
      $SUDO npm install -g bun --allow-scripts=bun
    fi
    command -v bun >/dev/null 2>&1 || die "bun 安装失败，请确认 npm 全局 bin 目录在 PATH 中"
    bun install -g "$PI_PKG"
  else
    $SUDO npm install -g "$PI_PKG"
  fi
fi
command -v "$CLI" >/dev/null 2>&1 || die "$CLI 安装失败，请检查全局 bin 目录是否在 PATH 中"

# bash 补全（install -D 自动建 bash-completion 目录；失败不中断安装）
comp_tmp="$(mktemp)"
if [ "$CLI" = omp ]; then "$CLI" completions bash > "$comp_tmp"; else cp pi-completion "$comp_tmp"; fi
$SUDO install -D -m 644 "$comp_tmp" "/usr/share/bash-completion/completions/$CLI" || log "补全安装失败，跳过"
rm -f "$comp_tmp"

# 3. 依次安装扩展（pi 读 packages.txt，omp 读 packages-omp.txt，安装命令也不同）
[ -f "$PKGS_FILE" ] || die "$PKGS_FILE 不存在（$CLI 模式需要它）"
mapfile -t pkgs < <(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$PKGS_FILE" || true)
[ "${#pkgs[@]}" -gt 0 ] || die "$PKGS_FILE 里没有可安装的包"

# omp 插件名带 @marketplace 后缀时，需先添加对应 marketplace（后缀 -> 仓库）
# shortcut: 映射写在脚本里，新增 marketplace 要在这里补一行
declare -A MARKETPLACES=([casonadams-plugins]=casonadams/omp-plugins)
declare -A added_marketplaces=()   # 必须是 -A，否则下标会被当算术表达式

failed=()
for pkg in "${pkgs[@]}"; do
  # omp 用 plugin 子命令，pi 直接 install
  if [ "$CLI" = omp ]; then
    suffix="${pkg##*@}"
    if [ "$suffix" = "$pkg" ]; then suffix=""; fi   # 没有 @marketplace 后缀
    if [ -n "$suffix" ] && [ -z "${added_marketplaces[$suffix]:-}" ]; then
      mkt="${MARKETPLACES[$suffix]:-}"
      [ -n "$mkt" ] || die "$pkg 的 marketplace '$suffix' 没有映射，请在 install.sh 的 MARKETPLACES 里补上"
      log "$pkg 需要 marketplace $mkt"
      # 已安装就更新，未安装才添加
      mkt_list="$("$CLI" plugin marketplace list 2>/dev/null || true)"   # 先收结果，避 pipefail+grep -q 的 SIGPIPE 误判
      case "$mkt_list" in
        *"$mkt"*)
          log "marketplace $mkt 已存在，更新中"
          "$CLI" plugin marketplace update "$mkt" || log "marketplace $mkt 更新失败，继续" ;;
        *)
          log "marketplace $mkt 不存在，添加中"
          "$CLI" plugin marketplace add "$mkt" || log "marketplace $mkt 添加失败，继续" ;;
      esac
      added_marketplaces[$suffix]=1
    fi
    "$CLI" plugin install "$pkg" || failed+=("$pkg")
  else
    "$CLI" install "$pkg" || failed+=("$pkg")
  fi
done

if [ "${#failed[@]}" -gt 0 ]; then
  printf '以下包安装失败，可重试：\n' >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi
log "完成：$((${#pkgs[@]} - ${#failed[@]}))/${#pkgs[@]} 个包"

# 4  安装extensions/rtk.ts
if ! command -v rtk >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
    $SUDO cp "$HOME/.local/bin/rtk" /usr/local/bin/
    $SUDO chown root:root /usr/local/bin/rtk
fi
rtk init -g --agent "$CLI"   # pi -> pi，omp -> omp

# 4.5 omp 需要在 ~/.omp/agent/config.yml 里显式挂 rtk 扩展
# shortcut: 按 YAML 列表处理，若 extensions 写成内联数组（[a, b]）会漏处理，需手改
omp_config_add() {
  local key="$1" item="$2" file="$HOME/.omp/agent/config.yml"
  if [ ! -e "$file" ]; then
    touch "$file"
  fi
  if grep -qxF "  - $item" "$file"; then
    log "$file 已有 $key: $item"
    return 0
  fi
  [ -z "$(tail -c1 "$file")" ] || printf '\n' >> "$file"   # 补行尾换行
  if grep -qE "^${key}:" "$file"; then
    # 块列表：插到 key 下；空内联数组 key: []：展开成块列表；其他内联写法不动，告警
    if awk -v k="$key" -v i="  - $item" '
        $0 ~ "^" k ":[ ]*$"             { print; print i; found = 1; next }
        $0 ~ "^" k ":[ ]*\\[[ ]*\\][ ]*$" { print k ":"; print i; found = 1; next }
        { print }
        END { exit found ? 0 : 3 }
      ' "$file" > "$file.tmp"; then
      mv "$file.tmp" "$file"
    else
      rm -f "$file.tmp"
      log "警告：$file 的 $key 是内联写法，未自动修改，请手动加 $item"
      return 0
    fi
  else
    printf '%s:\n  - %s\n' "$key" "$item" >> "$file"
  fi
  log "已写入 $file: $key -> $item"
}

if [ "$CLI" = omp ]; then
  mkdir -p "$HOME/.omp/agent"
  cp mcp-omp.json "$HOME/.omp/agent/mcp.json"
  if [ -e "$HOME/.omp/agent/extensions/rtk.ts" ]; then
    omp_config_add disabledExtensions extension-module:rtk
    omp_config_add extensions "$HOME/.omp/agent/extensions/rtk.ts"
  fi
  # codebase-memory-mcp 缺失不是致命错误，否则 set -e 会中断后续步骤
  if command -v codebase-memory-mcp >/dev/null 2>&1; then
    codebase-memory-mcp install --clients=omp -y || log "codebase-memory-mcp 配置失败，跳过"
  else
    log "codebase-memory-mcp 未安装，跳过 omp 客户端配置"
  fi
fi

# 5. 扩展行为所需的环境变量写入 ~/.bashrc（按变量幂等，已存在则不覆盖）
# shortcut: 只写 ~/.bashrc（bash 专用）；换 zsh/fish 需手动补
BASHRC="$HOME/.bashrc"
ensure_export() {
  local key="$1" value="$2" note="$3"
  if grep -qE "^[[:space:]]*export[[:space:]]+${key}=" "$BASHRC" 2>/dev/null; then
    log "$key 已在 $BASHRC，跳过"
    return 0
  fi
  printf '\n# %s\nexport %s=%s\n' "$note" "$key" "$value" >> "$BASHRC"
  log "已写入 $key=$value -> $BASHRC"
}

# pi-cache-optimizer 会把 <available_skills> XML 压成 markdown，导致 pi-permission-system
# 的 skill 权限判定（含 skill 目录内文件读取）静默失效；关掉 skill 压缩即可恢复。
ensure_export PI_CACHE_OPTIMIZER_NO_SKILL_COMPRESSION 1 "pi-cache-optimizer: keep native <available_skills> XML for pi-permission-system"
