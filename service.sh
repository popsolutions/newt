#!/usr/bin/env bash
set -euo pipefail

echo "===> Instalador do agente Pangolin (newt) como serviço"
echo

# Precisa ser root
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Este script precisa ser executado como root (use sudo)." >&2
  exit 1
fi

# Detecta família de SO
OS_FAMILY=""
if command -v apk >/dev/null 2>&1; then
  OS_FAMILY="alpine"
elif command -v apt-get >/dev/null 2>&1; then
  OS_FAMILY="debian"
else
  echo "Sistema não suportado automaticamente. Apenas Debian/Ubuntu (apt-get) ou Alpine (apk)." >&2
  exit 1
fi

echo "Detectado sistema: ${OS_FAMILY}"
echo

# Garante curl instalado
if ! command -v curl >/dev/null 2>&1; then
  echo "Instalando curl..."
  if [ "$OS_FAMILY" = "alpine" ]; then
    apk update && apk add curl
  else
    apt-get update && apt-get install -y curl
  fi
  echo
fi

# Instala newt se ainda não estiver disponível
if ! command -v newt >/dev/null 2>&1; then
  echo "Instalando Pangolin newt..."
  curl -fsSL https://pangolin.net/get-newt.sh | bash
  echo
fi

if ! command -v newt >/dev/null 2>&1; then
  echo "Falha ao instalar o 'newt' (comando não encontrado após instalação)." >&2
  exit 1
fi

echo "newt instalado em: $(command -v newt)"
echo

# Pede o comando completo do newt
echo "Cole AGORA o comando COMPLETO do newt que você quer rodar como serviço."
echo "Exemplo:"
echo "  newt --id 4m9umjy04ch90eb --secret ivvzf70gi1b3qngmypujcwbeodvo9t9wy0nb27dwm2qn2ho8 --endpoint https://edge.pop.uy"
echo
printf "Comando newt> "

# lê linha inteira (sem interpretar backslashes)
read -r NEWT_CMD

if [ -z "${NEWT_CMD}" ]; then
  echo "Nenhum comando newt informado. Abortando." >&2
  exit 1
fi

WRAPPER="/usr/local/sbin/newt-agent.sh"
echo
echo "Criando wrapper em ${WRAPPER}..."

cat > "${WRAPPER}" <<EOF
#!/usr/bin/env bash
# Wrapper do agente Pangolin Newt
exec ${NEWT_CMD}
EOF

chmod +x "${WRAPPER}"

echo "Wrapper criado."
echo

if [ "$OS_FAMILY" = "debian" ]; then
  SERVICE_FILE="/etc/systemd/system/newt-agent.service"
  echo "Criando unidade systemd em ${SERVICE_FILE}..."

  cat > "${SERVICE_FILE}" <<'EOF'
[Unit]
Description=Pangolin Newt agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/newt-agent.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  echo "Recarregando systemd, habilitando e iniciando serviço..."
  systemctl daemon-reload
  systemctl enable newt-agent.service
  systemctl restart newt-agent.service || systemctl start newt-agent.service

  echo
  echo "Status do serviço:"
  systemctl --no-pager --full status newt-agent.service || true

elif [ "$OS_FAMILY" = "alpine" ]; then
  INIT_FILE="/etc/init.d/newt-agent"
  echo "Criando script OpenRC em ${INIT_FILE}..."

  cat > "${INIT_FILE}" <<'EOF'
#!/sbin/openrc-run

name="Pangolin Newt agent"
description="Pangolin Newt reverse-proxy agent"
command="/usr/local/sbin/newt-agent.sh"
command_background="yes"
pidfile="/run/${RC_SVCNAME}.pid"

depend() {
  need net
}
EOF

  chmod +x "${INIT_FILE}"

  echo "Adicionando serviço ao runlevel default e iniciando..."
  rc-update add newt-agent default
  rc-service newt-agent restart || rc-service newt-agent start

  echo
  echo "Status do serviço:"
  rc-service newt-agent status || true
fi

echo
echo "✅ Pronto! O agente Newt foi configurado como serviço (${OS_FAMILY})."
echo "  - Wrapper: /usr/local/sbin/newt-agent.sh"
if [ "$OS_FAMILY" = "debian" ]; then
  echo "  - systemd unit: /etc/systemd/system/newt-agent.service"
  echo "  - Comandos úteis:"
  echo "      systemctl status newt-agent"
  echo "      systemctl restart newt-agent"
else
  echo "  - OpenRC init: /etc/init.d/newt-agent"
  echo "  - Comandos úteis:"
  echo "      rc-service newt-agent status"
  echo "      rc-service newt-agent restart"
fi
