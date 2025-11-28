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

###############################################################################
# OBTENDO O COMANDO NEWT
###############################################################################
NEWT_CMD=""

# 1) Se vierem argumentos, usamos todos os argumentos como comando
if [ "$#" -gt 0 ]; then
  # Junta todos os argumentos em uma única string
  NEWT_CMD="$*"
fi

# 2) Se não veio como argumento, tenta variável de ambiente NEWT_CMD
if [ -z "${NEWT_CMD}" ] && [ -n "${NEWT_CMD:-}" ]; then
  NEWT_CMD="${NEWT_CMD}"
fi

# 3) Se ainda estiver vazio e estivermos em TTY, pergunta interativamente
if [ -z "${NEWT_CMD}" ] && [ -t 0 ]; then
  echo "Cole AGORA o comando COMPLETO do newt que você quer rodar como serviço."
  echo "Exemplo:"
  echo "  newt --id 4m9umjy04ch90eb --secret ivvzf70gi1b3qngmypujcwbeodvo9t9wy0nb27dwm2qn2ho8 --endpoint https://edge.pop.uy"
  echo
  printf "Comando newt> "
  read -r NEWT_CMD
fi

# 4) Se mesmo assim continuar vazio, aborta
if [ -z "${NEWT_CMD}" ]; then
  echo "Nenhum comando newt informado."
  echo
  echo "Use, por exemplo:"
  echo "  curl -fsSL https://raw.githubusercontent.com/popsolutions/newt/refs/heads/main/service.sh \\"
  echo "    | bash -s -- \"newt --id SEU_ID --secret SEU_SECRET --endpoint https://edge.pop.uy\""
  exit 1
fi

echo
echo "Comando newt que será usado no serviço:"
echo "  ${NEWT_CMD}"
echo

###############################################################################
# CRIA WRAPPER
###############################################################################
WRAPPER="/usr/local/sbin/newt-agent.sh"
echo "Criando wrapper em ${WRAPPER}..."

cat > "${WRAPPER}" <<EOF
#!/usr/bin/env bash
# Wrapper do agente Pangolin Newt
exec ${NEWT_CMD}
EOF

chmod +x "${WRAPPER}"

echo "Wrapper criado."
echo

###############################################################################
# CRIA SERVIÇO
###############################################################################
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
