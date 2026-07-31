#!/usr/bin/env sh

set -euo pipefail

missing=""
for var in SS_PORT SS_PASSWORD SS_ENCRYPT_METHOD SS_TIMEOUT SOCKS_PORT; do
  eval "value=\${$var:-}"
  [ -n "$value" ] || missing="$missing $var"
done

if [ -n "$missing" ]; then
  echo "[entrypoint] ERROR: required environment variables are not set:$missing" >&2
  exit 1
fi

sync_defaults() {
  src_dir=$1
  dst_dir=$2
  label=$3

  [ -d "$src_dir" ] && [ -d "$dst_dir" ] || return 0

  for src in "$src_dir"/*; do
    [ -e "$src" ] || continue
    name="$(basename "$src")"
    dst="$dst_dir/$name"
    [ -e "$dst" ] && continue
    echo "[entrypoint] Copying $label: $name"
    cp -a "$src" "$dst"
  done
}

sync_defaults "/opt/zapret2/lua.dist" "/opt/zapret2/lua" "lua script"
sync_defaults "/opt/zapret2/init.d/custom.d.examples.linux.dist" "/opt/zapret2/init.d/custom.d.examples.linux" "custom.d script"
sync_defaults "/opt/zapret2/files/fake.dist" "/opt/zapret2/files/fake" "fake file"

/opt/zapret2/init.d/sysv/zapret2 start

cleanup() {
  /opt/zapret2/init.d/sysv/zapret2 stop || true
  [ -n "${SS_SERVER_PID:-}" ] && kill "${SS_SERVER_PID}" 2>/dev/null || true
  [ -n "${SS_LOCAL_PID:-}" ] && kill "${SS_LOCAL_PID}" 2>/dev/null || true
}

trap cleanup EXIT TERM INT

SS_VERBOSE_FLAG=""
if [ "${SS_VERBOSE:-0}" = "1" ]; then
  SS_VERBOSE_FLAG="-v"
fi

# shadowsocks-rust конфигурируется через JSON, а не через флаги (в отличие от libev).
# Генерируем оба конфига на лету из тех же переменных окружения, что и раньше.
SSSERVER_CONFIG="/tmp/ssserver.json"
SSLOCAL_CONFIG="/tmp/sslocal.json"

# Необязательная переменная: DNS-сервер для резолвинга целевых доменов.
# Если не задана - используется системный резолвер по умолчанию.
NAMESERVER_FIELD=""
if [ -n "${DNS_SERVER:-}" ]; then
  NAMESERVER_FIELD="  \"nameserver\": \"${DNS_SERVER}\","
fi

cat > "${SSSERVER_CONFIG}" <<EOF
{
  ${NAMESERVER_FIELD}
  "server": "0.0.0.0",
  "server_port": ${SS_PORT},
  "password": "${SS_PASSWORD}",
  "method": "${SS_ENCRYPT_METHOD}",
  "timeout": ${SS_TIMEOUT},
  "mode": "tcp_and_udp"
}
EOF

cat > "${SSLOCAL_CONFIG}" <<EOF
{
  ${NAMESERVER_FIELD}
  "server": "127.0.0.1",
  "server_port": ${SS_PORT},
  "password": "${SS_PASSWORD}",
  "method": "${SS_ENCRYPT_METHOD}",
  "timeout": ${SS_TIMEOUT},
  "local_address": "0.0.0.0",
  "local_port": ${SOCKS_PORT},
  "mode": "tcp_and_udp"
}
EOF

ssserver ${SS_VERBOSE_FLAG} -c "${SSSERVER_CONFIG}" &
SS_SERVER_PID=$!

sslocal ${SS_VERBOSE_FLAG} -c "${SSLOCAL_CONFIG}" &
SS_LOCAL_PID=$!

wait