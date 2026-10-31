#!/usr/bin/env bash
#
# SchoolLink Hub — one-click installer for Linux
#
# Usage (from an extracted release directory):
#   sudo bash install-hub-linux.sh
#
# The release directory should contain:
#   install-hub-linux.sh
#   web/                         Flutter Web build
#   source/packages/protocol/    (or build a binary and omit this)
#   source/packages/hub/
#
# Or run from the development repository; the script will use
# apps/app/build/web and packages/*.
#
set -euo pipefail

SERVICE_NAME="schoollink-hub"
INSTALL_DIR="/opt/schoollink-hub"
DATA_DIR="/var/lib/schoollink-hub"
PORT="${SCHOLLINK_PORT:-8421}"
RUN_USER="schoollink"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_SRC=""
HUB_SRC=""

if [[ "${EUID}" -ne 0 ]]; then
  echo "请使用 root 运行：sudo bash $0"
  exit 1
fi

log() { printf '\033[1;32m[SchoolLink]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[SchoolLink]\033[0m %s\n' "$*"; }

# --- locate assets ---------------------------------------------------------
if [[ -d "${SCRIPT_DIR}/web" ]]; then
  WEB_SRC="${SCRIPT_DIR}/web"
elif [[ -d "${SCRIPT_DIR}/apps/app/build/web" ]]; then
  WEB_SRC="${SCRIPT_DIR}/apps/app/build/web"
fi

if [[ -d "${SCRIPT_DIR}/source/packages/hub" ]]; then
  HUB_SRC="${SCRIPT_DIR}/source/packages/hub"
elif [[ -d "${SCRIPT_DIR}/packages/hub" ]]; then
  HUB_SRC="${SCRIPT_DIR}/packages/hub"
fi

if [[ -z "${WEB_SRC}" || ! -f "${WEB_SRC}/index.html" ]]; then
  echo "找不到 web/index.html。请把 Flutter Web 构建产物放在本脚本同级的 web/ 目录。"
  exit 1
fi

# --- helpers ---------------------------------------------------------------
ensure_dart() {
  if command -v dart >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x /opt/dart-sdk/bin/dart ]]; then
    export PATH="/opt/dart-sdk/bin:${PATH}"
    return 0
  fi

  log "未找到 Dart SDK，正在安装（用于编译 Hub）..."
  apt-get update -y >/dev/null 2>&1 || true
  if ! command -v unzip >/dev/null 2>&1; then
    apt-get install -y unzip curl >/dev/null 2>&1 || true
  fi
  command -v curl >/dev/null 2>&1 || {
    echo "需要 curl 来下载 Dart SDK，请先安装 curl。"
    exit 1
  }
  local arch version url tmp
  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "暂不支持架构：$(uname -m)"; exit 1 ;;
  esac
  version="$(curl -fsSL 'https://storage.googleapis.com/dart-archive/channels/stable/release/latest/VERSION' | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  if [[ -z "${version}" ]]; then
    echo "无法查询 Dart SDK 版本，请手动安装 Dart。"
    exit 1
  fi
  url="https://storage.googleapis.com/dart-archive/channels/stable/release/${version}/sdk/dartsdk-linux-${arch}-release.zip"
  tmp="$(mktemp -d)"
  log "下载 Dart ${version} (${arch})..."
  curl -fL --retry 3 -o "${tmp}/dart.zip" "${url}"
  unzip -q "${tmp}/dart.zip" -d /opt
  rm -rf "${tmp}"
  ln -sf /opt/dart-sdk/bin/dart /usr/local/bin/dart
  export PATH="/opt/dart-sdk/bin:${PATH}"
  dart --version
}

install_binary() {
  local candidate=""
  for name in SchoolLinkHub-linux-x64 SchoolLinkHub; do
    if [[ -x "${SCRIPT_DIR}/${name}" ]]; then candidate="${SCRIPT_DIR}/${name}"; break; fi
  done
  if [[ -n "${candidate}" ]]; then
    install -m 0755 "${candidate}" "${INSTALL_DIR}/SchoolLinkHub"
    log "已使用预编译 Hub：${candidate}"
    return 0
  fi
  if [[ -z "${HUB_SRC}" || ! -f "${HUB_SRC}/bin/server.dart" ]]; then
    echo "没有预编译 Hub，也没有找到 source/packages/hub 源码。"
    exit 1
  fi
  ensure_dart
  log "正在编译 Hub（首次需要下载 pub 依赖）..."
  (
    cd "${HUB_SRC}"
    export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
    export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
    dart pub get
    dart compile exe bin/server.dart -o "${INSTALL_DIR}/SchoolLinkHub"
  )
}

# --- install ---------------------------------------------------------------
log "安装目录：${INSTALL_DIR}"
log "数据目录：${DATA_DIR}"
mkdir -p "${INSTALL_DIR}" "${DATA_DIR}"
install_binary

rm -rf "${INSTALL_DIR}/web"
cp -a "${WEB_SRC}" "${INSTALL_DIR}/web"

if ! id -u "${RUN_USER}" >/dev/null 2>&1; then
  useradd --system --home-dir "${DATA_DIR}" --shell /usr/sbin/nologin "${RUN_USER}"
fi
chown -R "${RUN_USER}:${RUN_USER}" "${DATA_DIR}"
chmod 0755 "${INSTALL_DIR}/SchoolLinkHub"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=SchoolLink Hub (LAN file sharing and notices)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/SchoolLinkHub --port ${PORT} --data ${DATA_DIR} --web-root ${INSTALL_DIR}/web
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" >/dev/null
systemctl restart "${SERVICE_NAME}"
sleep 1

if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
  echo "Hub 启动失败，请查看：journalctl -u ${SERVICE_NAME} -n 80 --no-pager"
  exit 1
fi

# --- firewall --------------------------------------------------------------
if command -v ufw >/dev/null 2>&1 && ufw status | grep -qi 'Status: active'; then
  log "配置 ufw 防火墙端口..."
  ufw allow "${PORT}/tcp" comment 'SchoolLink Hub' >/dev/null || true
  ufw allow "${PORT}/udp" comment 'SchoolLink discovery' >/dev/null || true
  ufw allow 8422/tcp comment 'SchoolLink peer' >/dev/null || true
  ufw allow 8424/udp comment 'SchoolLink peer discovery' >/dev/null || true
elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  log "配置 firewalld 防火墙端口..."
  for rule in "${PORT}/tcp" "${PORT}/udp" 8422/tcp 8424/udp; do
    firewall-cmd --permanent --add-port="${rule}" >/dev/null || true
  done
  firewall-cmd --reload >/dev/null || true
else
  warn "未检测到 active 的 ufw/firewalld；如有其他防火墙请手动放行 ${PORT}/tcp+udp、8422/tcp、8424/udp。"
fi

# --- report ----------------------------------------------------------------
IPS="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9.]+$' | head -5 || true)"
log "Hub 已启动并设置为开机自启。"
echo
echo "  管理地址（任选一个）："
if [[ -n "${IPS}" ]]; then
  while IFS= read -r ip; do echo "    http://${ip}:${PORT}/"; done <<< "${IPS}"
else
  echo "    http://<本机局域网 IP>:${PORT}/"
fi
echo
echo "  默认管理员 PIN：246810"
echo "  默认学校注册码：SCHOOL26"
echo "  数据目录：${DATA_DIR}"
echo "  服务管理：systemctl status|restart|stop ${SERVICE_NAME}"
echo "  日志：journalctl -u ${SERVICE_NAME} -f"
echo
warn "首次部署后请在 Hub 管理台修改管理员 PIN 和学校注册码。"
warn "如果客户端在不同子网，请确保防火墙/路由允许上述端口。"
