#!/bin/bash

set -e # Sair imediatamente se um comando falhar
# set -u # Tratar variáveis não definidas como erro (opcional, mas bom para debugging)
# set -o pipefail # Sair se um comando em um pipe falhar (opcional)

echo "==== SSH Login Alert Installer ===="

# Verifica se o script está sendo executado como root
if [ "$(id -u)" -ne 0 ]; then
  echo "[ERRO] Este script precisa ser executado como root ou com sudo."
  exit 1
fi

echo "Requisitos: token e chat ID do seu bot do Telegram."
read -p "Informe o BOT_TOKEN: " BOT_TOKEN
read -p "Informe o CHAT_ID: " CHAT_ID
read -p "Informe o TOPIC_ID (opcional, deixe em branco se não usar tópicos): " TOPIC_ID

# Validação básica das entradas
if [ -z "$BOT_TOKEN" ]; then
    echo "[ERRO] BOT_TOKEN não pode ser vazio."
    exit 1
fi
if [ -z "$CHAT_ID" ]; then
    echo "[ERRO] CHAT_ID não pode ser vazio."
    exit 1
fi

#timedatectl set-timezone America/Sao_Paulo # Descomente se precisar ajustar o timezone

echo "[INFO] Atualizando lista de pacotes..."
apt update -qq

echo "[INFO] Instalando dependências (curl, jq)..."
if ! dpkg -s curl >/dev/null 2>&1 || ! dpkg -s jq >/dev/null 2>&1; then
    apt install -y curl jq
else
    echo "[INFO] Dependências já instaladas."
fi

SSHRCPATH="/etc/ssh/sshrc"
# Using $(...) for command substitution is standard and preferred over backticks ``.
# Ensure this line is exactly as written, no stray backticks.
BACKUPPATH="/etc/ssh/sshrc.bkp.$(date +%Y%m%d-%H%M%S)"

if [ -f "$SSHRCPATH" ]; then
    echo "[INFO] Fazendo backup do sshrc atual em $BACKUPPATH"
    cp "$SSHRCPATH" "$BACKUPPATH"
fi

echo "[INFO] Escrevendo novo sshrc em $SSHRCPATH..."
# Using cat > is generally cleaner than tee <<EOF >/dev/null
cat > "$SSHRCPATH" <<EOF
#!/bin/sh
# IMPORTANT: /etc/ssh/sshrc is executed by sh, not bash. POSIX sh syntax only.

# Só executa para sessões SSH interativas (com TTY alocado)
if [ -z "\$SSH_TTY" ]; then
    exit 0
fi

BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
TOPIC_ID="${TOPIC_ID}" # Pode ser vazio

USER=\$(whoami)
IP=\$(echo \$SSH_CONNECTION | cut -d " " -f 1)

if [ -z "\$IP" ]; then
    IP=\$(last -i -n 1 "\$USER" | awk '{print \$(NF-2)}' | grep -Eo '([0-9]{1,3}\\.){3}[0-9]{1,3}')
fi

DATE=\$(date "+%d/%m/%Y %H:%M:%S")
HOSTNAME=\$(hostname)

if [ ! -z "\$IP" ]; then
    GEOINFO=\$(curl -s "http://ip-api.com/json/\$IP?fields=country,regionName,city,isp" | jq -r '.country + ", " + .regionName + " - " + .city + " (" + .isp + ")"' 2>>
else
    GEOINFO="Geolocation not found"
fi

MESSAGE="*⚠️ Novo Login SSH Detectado ⚠️*
🖥️ *Server:* \$HOSTNAME
*User:* \$USER
*IP:* \$IP
*Location:* \$GEOINFO
*Date/Time:* \$DATE"

curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \\
    -d chat_id="\$CHAT_ID" \\
    -d text="\$MESSAGE" \\
    #-d message_thread_id="\$TOPIC_ID" \\
    -d parse_mode="Markdown" > /dev/null 2>&1 &
EOF

echo "[INFO] Dando permissão de execução ao sshrc..."
chmod +x "$SSHRCPATH"

echo "[INFO] Verificando a sintaxe do script $SSHRCPATH com sh..."
# Use sh -n to check POSIX compatibility
if sh -n "$SSHRCPATH"; then
    echo "[INFO] Sintaxe do $SSHRCPATH está OK para sh."
else
    echo "[AVISO] Problema de sintaxe detectado em $SSHRCPATH. Verifique o arquivo."
    echo "[DEBUG] Conteúdo gerado para $SSHRCPATH:"
    cat "$SSHRCPATH"
    # Consider exiting if syntax is bad, as it will likely fail.
    # exit 1
fi

echo "[✅] Alerta de login SSH via Telegram instalado com sucesso!"
echo "[INFO] Para testar, saia e faça login novamente neste servidor via SSH."
echo "[NOTA] Se os alertas não chegarem, verifique:"
echo "       1. Se o BOT_TOKEN e CHAT_ID (e TOPIC_ID se usado) estão corretos."
echo "       2. Se o servidor tem acesso à internet (especialmente à api.telegram.org)."
echo "       3. Logs do sistema (ex: /var/log/auth.log) para erros relacionados ao sshrc."
echo "       4. O arquivo $SSHRCPATH para erros (pode adicionar 'set -x' no topo do sshrc para debug)."