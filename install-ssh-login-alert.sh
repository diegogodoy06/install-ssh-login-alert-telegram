#!/bin/bash

set -e

echo "==== SSH Login Alert Installer ===="
echo "Requisitos: token e chat ID do seu bot do Telegram."
read -p "Informe o BOT_TOKEN: " BOT_TOKEN
read -p "Informe o CHAT_ID: " CHAT_ID


#timedatectl set-timezone America/Sao_Paulo

echo "[INFO] Instalando dependências (curl, jq)..."
apt update -qq
apt install -y curl jq

SSHRCPATH="/etc/ssh/sshrc"
BACKUPPATH="/etc/ssh/sshrc.bkp.$(date +%s)"

if [ -f "$SSHRCPATH" ]; then
    echo "[INFO] Fazendo backup do sshrc atual em $BACKUPPATH"
    cp "$SSHRCPATH" "$BACKUPPATH"
fi

echo "[INFO] Escrevendo novo sshrc..."
tee "$SSHRCPATH" > /dev/null <<EOF
#!/bin/bash

BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
#TOPIC_ID=""

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

MESSAGE="*New Login*
🖥️ Server: \$HOSTNAME
👤 User: \$USER
📍 IP: \$IP
🌎 Location: \$GEOINFO
📅 Date/Time: \$DATE"

curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \\
    -d chat_id="\$CHAT_ID" \\
    -d text="\$MESSAGE" \\
    #-d message_thread_id="\$TOPIC_ID" \\
    -d parse_mode="Markdown" > /dev/null 2>&1 &
EOF

echo "[INFO] Dando permissão de execução ao sshrc..."
chmod +x "$SSHRCPATH"

echo "[✅] Alerta de login SSH via Telegram instalado com sucesso!"
