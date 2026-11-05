#!/usr/bin/env bash
# 在全新机器上恢复 pi 环境：Node.js -> pi -> packages.txt 里的扩展
set -euo pipefail
cd "$(dirname "$0")"

PI_PKG="${PI_PKG:-@earendil-works/pi-coding-agent}"
NODE_MIN_MAJOR=22

SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"  # 容器里常是 root，没有 sudo

log() { printf '==> %s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

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

node_major="$(node -p 'process.versions.node.split(".")[0]')"
[ "$node_major" -ge "$NODE_MIN_MAJOR" ] || die "Node.js v$(node -v) 过低，pi 需要 >= $NODE_MIN_MAJOR。建议：
  curl -fsSL https://deb.nodesource.com/setup_${NODE_MIN_MAJOR}.x | sudo -E bash -
  sudo apt-get install -y nodejs"

# 2. pi 不存在则用 npm 全局安装
if ! command -v pi >/dev/null 2>&1; then
  log "pi 不存在，安装 $PI_PKG"
  $SUDO npm install -g "$PI_PKG"
fi
command -v pi >/dev/null 2>&1 || die "pi 安装失败，请检查 npm 全局 bin 目录是否在 PATH 中"

# 3. 依次安装 packages 中的扩展
# shortcut: 只在 packages.txt 缺失时才从 settings.json 反推，不会自动回写，换机器前记得先 jq 导出
if [ ! -f packages.txt ]; then
  log "packages.txt 不存在，从 settings.json 读取 packages"
  node -e 'const p=JSON.parse(require("fs").readFileSync("settings.json","utf8")).packages||[];console.log(p.join("\n"))' > packages.txt
fi

mapfile -t pkgs < <(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' packages.txt || true)
[ "${#pkgs[@]}" -gt 0 ] || die "packages.txt 里没有可安装的包"

failed=()
for pkg in "${pkgs[@]}"; do
  pi install "$pkg" || failed+=("$pkg")
done

if [ "${#failed[@]}" -gt 0 ]; then
  printf '以下包安装失败，可重试：\n' >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi
log "完成：$((${#pkgs[@]} - ${#failed[@]}))/${#pkgs[@]} 个包"

# 4 rtk 是 extensions/rtk.ts 的硬依赖：缺失或过旧（需 >= 0.23.0 的 rtk rewrite）时
#     该扩展只是静默禁用，所以这里必须显式报出来
if ! command -v rtk >/dev/null 2>&1; then
  printf '警告：PATH 中没有 rtk，extensions/rtk.ts 将被禁用（命令不再自动改写为 rtk）\n' >&2
else
  rtk_rc=0; rtk rewrite ls >/dev/null 2>&1 || rtk_rc=$?
  case $rtk_rc in
    0 | 1 | 3) log "$(rtk --version 2>/dev/null | head -1) 可用" ;;
    *) printf '警告：rtk 不支持 rewrite 子命令（需 >= 0.23.0），extensions/rtk.ts 将被禁用\n' >&2 ;;
  esac
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
