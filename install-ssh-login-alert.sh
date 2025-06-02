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
BACKUPPATH="/etc/ssh/sshrc.bkp.$(date +%Y%m%d-%H%M%S)"

if [ -f "$SSHRCPATH" ]; then
    echo "[INFO] Fazendo backup do sshrc atual em $BACKUPPATH"
    cp "$SSHRCPATH" "$BACKUPPATH"
fi

echo "[INFO] Escrevendo novo sshrc em $SSHRCPATH..."
# As variáveis BOT_TOKEN, CHAT_ID, TOPIC_ID do script instalador
# são inseridas diretamente no sshrc.
cat > "$SSHRCPATH" <<EOF
#!/bin/sh
# IMPORTANT: /etc/ssh/sshrc is executed by sh, not bash. POSIX sh syntax only.

# Só executa para sessões SSH interativas (com TTY alocado)
if [ -z "\$SSH_TTY" ]; then
    exit 0
fi

# Estes valores são fixados durante a instalação do script
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
TOPIC_ID="${TOPIC_ID}" # Pode ser vazio

USER=\$(whoami)
# Tenta obter o IP da conexão SSH direta
IP=\$(echo \$SSH_CONNECTION | cut -d " " -f 1)

# Fallback para obter o IP se SSH_CONNECTION não estiver disponível ou o IP estiver vazio
if [ -z "\$IP" ]; then
    IP_CANDIDATE=\$(last -i -n 1 "\$USER" | awk 'NF>1 {print \$(NF-2)}')
    # Verifica se o candidato parece um IP antes de usá-lo
    if echo "\$IP_CANDIDATE" | grep -E '^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\$' >/dev/null; then
        IP="\$IP_CANDIDATE"
    else
        IP="Unknown (fallback IP parse failed)"
    fi
fi

DATE=\$(date "+%d/%m/%Y %H:%M:%S")
HOSTNAME=\$(hostname)

GEOINFO_JSON=""
# Só tenta buscar geoip se IP for válido e não for "Unknown"
if [ -n "\$IP" ] && [ "\$IP" != "Unknown (fallback IP parse failed)" ]; then
    # Adicionado fields=status,message para melhor depuração da API de geolocalização
    GEOINFO_JSON=\$(curl -s "http://ip-api.com/json/\$IP?fields=status,message,country,regionName,city,isp" 2>/dev/null)
fi

if [ -n "\$GEOINFO_JSON" ]; then
    # Verifica o status da resposta da API de geolocalização
    API_STATUS=\$(echo "\$GEOINFO_JSON" | jq -r '.status // "error"')
    if [ "\$API_STATUS" = "success" ]; then
        GEOINFO=\$(echo "\$GEOINFO_JSON" | jq -r '(.country // "N/A") + ", " + (.regionName // "N/A") + " - " + (.city // "N/A") + " (" + (.isp // "N/A") + ")"')
    else
        API_MESSAGE=\$(echo "\$GEOINFO_JSON" | jq -r '.message // "API error"')
        GEOINFO="Geolocation API error: \$API_MESSAGE (IP: \$IP)"
    fi
else
    GEOINFO="Geolocation lookup failed or IP not available"
fi

MESSAGE="*⚠️ Novo Login SSH Detectado ⚠️*
🖥️ Server: \$HOSTNAME
👤 User: \$USER
📍 IP: \$IP
🌎 Location: \$GEOINFO
📅 Date/Time: \$DATE"

URL_API="https://api.telegram.org/bot\${BOT_TOKEN}/sendMessage"

# Envia a mensagem para o Telegram
# Usar --data-urlencode para cada parâmetro é mais seguro e lida com caracteres especiais.
# O comando é executado em um subshell e em background para não bloquear o login.
if [ -n "\$TOPIC_ID" ]; then
    (curl -s -X POST "\$URL_API" \
        --data-urlencode "chat_id=\${CHAT_ID}" \
        --data-urlencode "text=\${MESSAGE}" \
        --data-urlencode "message_thread_id=\${TOPIC_ID}" \
        --data-urlencode "parse_mode=Markdown" > /dev/null 2>&1 &)
else
    (curl -s -X POST "\$URL_API" \
        --data-urlencode "chat_id=\${CHAT_ID}" \
        --data-urlencode "text=\${MESSAGE}" \
        --data-urlencode "parse_mode=Markdown" > /dev/null 2>&1 &)
fi

EOF

echo "[INFO] Dando permissão de execução ao sshrc..."
chmod +x "$SSHRCPATH"

echo "[INFO] Verificando a sintaxe do script $SSHRCPATH com sh..."
if sh -n "$SSHRCPATH"; then
    echo "[INFO] Sintaxe do $SSHRCPATH está OK para sh."
else
    echo "[AVISO] Problema de sintaxe detectado em $SSHRCPATH. Verifique o arquivo."
    echo "[DEBUG] Conteúdo gerado para $SSHRCPATH:"
    cat "$SSHRCPATH"
    # exit 1 # Considere sair se a sintaxe estiver ruim
fi

echo "[✅] Alerta de login SSH via Telegram instalado com sucesso!"
echo "[INFO] Para testar, saia e faça login novamente neste servidor via SSH."
echo "[NOTA] Se os alertas não chegarem, verifique:"
echo "       1. Se o BOT_TOKEN e CHAT_ID (e TOPIC_ID se usado) estão corretos no arquivo $SSHRCPATH."
echo "       2. Se o servidor tem acesso à internet (especialmente à api.telegram.org)."
echo "       3. Logs do sistema (ex: /var/log/auth.log ou journalctl -u sshd) para erros relacionados ao sshrc."
echo "       4. O arquivo $SSHRCPATH para erros (pode adicionar 'set -x' no topo do sshrc para debug, mas cuidado com informações sensíveis nos logs)."