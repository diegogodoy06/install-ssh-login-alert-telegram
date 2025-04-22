# 🚨 SSH Login Alert via Telegram

This Bash script sends notifications to a Telegram chat every time a user logs in via SSH on the server.

## 🔧 Requirements

- **Operating System**: Linux (Debian/Ubuntu)
- **Dependencies**:
  - `curl`
  - `jq`
- **Telegram Credentials**:
  - Bot Token
  - Chat ID

## ⚙️ Installation

1. **Clone the Repository**:

   ```bash
   git clone https://github.com/diegogodoy06/install-ssh-login-alert-telegram.git
   cd install-ssh-login-alert-telegram
   
2. Grant Execution Permissions to the Script:
   
   ```bash
    chmod +x install-ssh-login-alert.sh

3. Run the Script:
    ```bash
      ./install-ssh-login-alert.sh
    ```

## 📩 Example Notification
  ```bash
*New SSH Login*
🖥️ Server: server.example.com
👤 User: user
📍 IP: 192.168.1.100
📅 Date/Time: 22/04/2025 14:30:00
  ```

