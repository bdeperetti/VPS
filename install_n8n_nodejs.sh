#!/bin/bash

#########################################################
# Installation n8n (sans Docker)
# Node.js + PM2 + Nginx + Let's Encrypt SSL
# Domaine: n8n.kair.fr
# Par Bertrand - 2P FOOD
#########################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation n8n (sans Docker)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Vérification root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Ce script doit être exécuté en root${NC}"
    exit 1
fi

# Configuration
DOMAIN="n8n.kair.fr"
N8N_PORT="5678"
EMAIL="bertrand@2pfood.fr"  # Pour Let's Encrypt

echo -e "${YELLOW}📋 Configuration :${NC}"
echo -e "  Domaine     : ${GREEN}${DOMAIN}${NC}"
echo -e "  Port interne: ${GREEN}${N8N_PORT}${NC}"
echo -e "  Email SSL   : ${GREEN}${EMAIL}${NC}"
echo ""

read -p "Voulez-vous changer l'email pour Let's Encrypt ? [y/N]: " CHANGE_EMAIL
if [[ $CHANGE_EMAIL =~ ^[Yy]$ ]]; then
    read -p "Nouvel email : " EMAIL
fi

echo ""
echo -e "${YELLOW}⚠️  IMPORTANT : Avant de continuer${NC}"
echo -e "Assurez-vous que le DNS de ${GREEN}${DOMAIN}${NC} pointe vers ${GREEN}137.74.12.199${NC}"
echo ""
read -p "Le DNS est-il configuré ? [y/N]: " DNS_OK

if [[ ! $DNS_OK =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}📝 Configuration DNS à faire :${NC}"
    echo -e "  1. Allez sur votre registrar (OVH, Gandi, etc.)"
    echo -e "  2. Créez un enregistrement A :"
    echo -e "     Nom  : ${GREEN}n8n${NC}"
    echo -e "     Type : ${GREEN}A${NC}"
    echo -e "     Valeur : ${GREEN}137.74.12.199${NC}"
    echo -e "  3. Attendez la propagation DNS (5-30 min)"
    echo ""
    read -p "Voulez-vous continuer quand même ? [y/N]: " FORCE_CONTINUE
    if [[ ! $FORCE_CONTINUE =~ ^[Yy]$ ]]; then
        echo "Installation annulée. Configurez le DNS et relancez le script."
        exit 0
    fi
fi

# Mise à jour système
echo ""
echo -e "${YELLOW}📦 Mise à jour du système...${NC}"
apt update && apt upgrade -y

#########################################################
# INSTALLATION NODE.JS (LTS)
#########################################################

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Installation Node.js${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "${YELLOW}📦 Installation Node.js 20.x LTS...${NC}"

# Installer Node.js via NodeSource
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Vérifier l'installation
echo -e "${GREEN}✅ Node.js installé :${NC}"
node -v
npm -v

#########################################################
# INSTALLATION PM2 (Process Manager)
#########################################################

echo ""
echo -e "${YELLOW}📦 Installation PM2...${NC}"
npm install -g pm2

# Configurer PM2 pour démarrer au boot
pm2 startup systemd -u root --hp /root
systemctl enable pm2-root

echo -e "${GREEN}✅ PM2 installé${NC}"
pm2 -v

#########################################################
# INSTALLATION n8n
#########################################################

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Installation n8n${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "${YELLOW}📦 Installation n8n globalement...${NC}"
npm install -g n8n

echo -e "${GREEN}✅ n8n installé${NC}"
n8n -v

#########################################################
# CONFIGURATION n8n
#########################################################

echo ""
echo -e "${YELLOW}🔧 Configuration de n8n...${NC}"

# Créer le répertoire de configuration
mkdir -p /root/.n8n

# Créer le fichier de configuration environnement
cat > /root/.n8n/n8n.env << EOF
# Configuration n8n
N8N_HOST=${DOMAIN}
N8N_PORT=${N8N_PORT}
N8N_PROTOCOL=https
WEBHOOK_URL=https://${DOMAIN}

# Timezone
GENERIC_TIMEZONE=Europe/Paris
TZ=Europe/Paris

# Sécurité
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=$(openssl rand -base64 16)

# Chemin de stockage
N8N_USER_FOLDER=/root/.n8n

# Logs
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console,file
N8N_LOG_FILE_LOCATION=/root/.n8n/logs/

# Performance
N8N_PAYLOAD_SIZE_MAX=16
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=336
EOF

# Créer le dossier logs
mkdir -p /root/.n8n/logs

# Sauvegarder les credentials
N8N_USER=$(grep N8N_BASIC_AUTH_USER /root/.n8n/n8n.env | cut -d'=' -f2)
N8N_PASS=$(grep N8N_BASIC_AUTH_PASSWORD /root/.n8n/n8n.env | cut -d'=' -f2)

cat > /root/n8n_credentials.txt << EOF
=== IDENTIFIANTS n8n ===
Date: $(date)

URL: https://${DOMAIN}
Utilisateur: ${N8N_USER}
Mot de passe: ${N8N_PASS}

Fichier config: /root/.n8n/n8n.env
Données n8n: /root/.n8n/

Note: Changez le mot de passe après la première connexion
EOF

chmod 600 /root/n8n_credentials.txt

echo -e "${GREEN}✅ Configuration créée${NC}"

#########################################################
# DÉMARRAGE n8n avec PM2
#########################################################

echo ""
echo -e "${YELLOW}🚀 Démarrage de n8n avec PM2...${NC}"

# Créer le fichier ecosystem PM2
cat > /root/.n8n/ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'n8n',
    script: 'n8n',
    cwd: '/root/.n8n',
    env_file: '/root/.n8n/n8n.env',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    error_file: '/root/.n8n/logs/pm2-error.log',
    out_file: '/root/.n8n/logs/pm2-out.log',
    log_file: '/root/.n8n/logs/pm2-combined.log',
    time: true,
    kill_timeout: 5000,
    restart_delay: 4000
  }]
};
EOF

# Démarrer n8n via PM2
cd /root/.n8n
pm2 start ecosystem.config.js

# Sauvegarder la configuration PM2
pm2 save

echo -e "${GREEN}✅ n8n démarré${NC}"

# Attendre que n8n démarre
sleep 5

# Vérifier le statut
pm2 status

#########################################################
# INSTALLATION NGINX (si pas déjà installé)
#########################################################

if ! command -v nginx &> /dev/null; then
    echo ""
    echo -e "${YELLOW}🌐 Installation Nginx...${NC}"
    apt install -y nginx
    systemctl enable nginx
fi

#########################################################
# INSTALLATION CERTBOT (Let's Encrypt)
#########################################################

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Installation Certbot (Let's Encrypt)${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "${YELLOW}🔒 Installation Certbot...${NC}"
apt install -y certbot python3-certbot-nginx

#########################################################
# CONFIGURATION NGINX pour n8n
#########################################################

echo ""
echo -e "${YELLOW}🌐 Configuration Nginx pour ${DOMAIN}...${NC}"

# Créer la configuration Nginx (HTTP temporaire pour certbot)
cat > /etc/nginx/sites-available/n8n << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location / {
        return 301 https://\$server_name\$request_uri;
    }

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    # Logs
    access_log /var/log/nginx/n8n-access.log;
    error_log /var/log/nginx/n8n-error.log;

    # SSL (certbot remplira ces lignes)
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    # SSL moderne
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Proxy vers n8n
    location / {
        proxy_pass http://localhost:${N8N_PORT};
        proxy_http_version 1.1;
        
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        
        # Timeouts pour les workflows longs
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        send_timeout 600;
        
        # Buffer
        proxy_buffering off;
        client_max_body_size 100M;
    }
}
EOF

# Activer le site
ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/

# Tester la configuration
nginx -t

# Redémarrer Nginx
systemctl restart nginx

echo -e "${GREEN}✅ Nginx configuré${NC}"

#########################################################
# OBTENTION CERTIFICAT SSL
#########################################################

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Obtention certificat SSL${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "${YELLOW}🔒 Obtention du certificat Let's Encrypt...${NC}"

# Ouvrir les ports nécessaires
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Obtenir le certificat
certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos --email ${EMAIL} --redirect

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Certificat SSL obtenu et configuré${NC}"
    
    # Configurer le renouvellement automatique
    systemctl enable certbot.timer
    systemctl start certbot.timer
    
    echo -e "${GREEN}✅ Renouvellement automatique activé${NC}"
else
    echo -e "${RED}❌ Erreur lors de l'obtention du certificat SSL${NC}"
    echo -e "${YELLOW}Vérifiez que le DNS pointe bien vers ce serveur${NC}"
    echo -e "${YELLOW}Vous pouvez réessayer avec: certbot --nginx -d ${DOMAIN}${NC}"
fi

# Redémarrer Nginx
systemctl restart nginx

#########################################################
# CONFIGURATION PARE-FEU
#########################################################

echo ""
echo -e "${YELLOW}🔥 Configuration du pare-feu...${NC}"

ufw allow ${N8N_PORT}/tcp comment 'n8n (direct access)'

echo -e "${GREEN}✅ Pare-feu configuré${NC}"

#########################################################
# SCRIPT DE BACKUP n8n
#########################################################

echo ""
echo -e "${YELLOW}💾 Création du script de backup...${NC}"

cat > /usr/local/bin/backup-n8n << 'EOF'
#!/bin/bash
# Backup n8n

BACKUP_DIR="/root/backups/n8n"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup des données n8n
tar -czf $BACKUP_DIR/n8n-data-$DATE.tar.gz /root/.n8n/

echo "Backup créé : $BACKUP_DIR/n8n-data-$DATE.tar.gz"

# Garder seulement les 7 derniers backups
ls -t $BACKUP_DIR/n8n-data-*.tar.gz | tail -n +8 | xargs rm -f 2>/dev/null
EOF

chmod +x /usr/local/bin/backup-n8n

# Créer une tâche cron hebdomadaire
(crontab -l 2>/dev/null; echo "0 3 * * 0 /usr/local/bin/backup-n8n") | crontab -

echo -e "${GREEN}✅ Script de backup créé (exécution hebdomadaire)${NC}"

#########################################################
# RÉSUMÉ FINAL
#########################################################

clear
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Installation n8n terminée !${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${BLUE}🌍 ACCÈS À n8n${NC}"
echo ""
echo -e "  URL            : ${GREEN}https://${DOMAIN}${NC}"
echo -e "  Utilisateur    : ${GREEN}${N8N_USER}${NC}"
echo -e "  Mot de passe   : ${GREEN}${N8N_PASS}${NC}"
echo ""
echo -e "${YELLOW}⚠️  Changez le mot de passe après la première connexion !${NC}"
echo ""

echo -e "${BLUE}📋 INFORMATIONS TECHNIQUES${NC}"
echo ""
echo -e "  Node.js        : $(node -v)"
echo -e "  npm            : $(npm -v)"
echo -e "  n8n            : $(n8n -v 2>/dev/null || echo 'Installé')"
echo -e "  PM2            : $(pm2 -v)"
echo ""

echo -e "${BLUE}🔧 COMMANDES UTILES${NC}"
echo ""
echo -e "  Statut n8n     : ${GREEN}pm2 status${NC}"
echo -e "  Logs n8n       : ${GREEN}pm2 logs n8n${NC}"
echo -e "  Redémarrer n8n : ${GREEN}pm2 restart n8n${NC}"
echo -e "  Arrêter n8n    : ${GREEN}pm2 stop n8n${NC}"
echo -e "  Démarrer n8n   : ${GREEN}pm2 start n8n${NC}"
echo ""
echo -e "  Logs détaillés : ${GREEN}tail -f /root/.n8n/logs/pm2-combined.log${NC}"
echo -e "  Config n8n     : ${GREEN}nano /root/.n8n/n8n.env${NC}"
echo ""

echo -e "${BLUE}💾 BACKUP${NC}"
echo ""
echo -e "  Backup manuel  : ${GREEN}/usr/local/bin/backup-n8n${NC}"
echo -e "  Backups auto   : ${GREEN}Tous les dimanches à 3h${NC}"
echo -e "  Dossier backup : ${GREEN}/root/backups/n8n/${NC}"
echo ""

echo -e "${BLUE}🔒 SSL${NC}"
echo ""
echo -e "  Certificat     : ${GREEN}Let's Encrypt${NC}"
echo -e "  Renouvellement : ${GREEN}Automatique${NC}"
echo -e "  Test renouvellement : ${GREEN}certbot renew --dry-run${NC}"
echo ""

echo -e "${BLUE}📁 FICHIERS IMPORTANTS${NC}"
echo ""
echo -e "  Credentials    : ${GREEN}/root/n8n_credentials.txt${NC}"
echo -e "  Config n8n     : ${GREEN}/root/.n8n/n8n.env${NC}"
echo -e "  Données n8n    : ${GREEN}/root/.n8n/${NC}"
echo -e "  Config Nginx   : ${GREEN}/etc/nginx/sites-available/n8n${NC}"
echo ""

echo -e "${YELLOW}📝 PROCHAINES ÉTAPES${NC}"
echo ""
echo -e "  1. Connectez-vous : ${GREEN}https://${DOMAIN}${NC}"
echo -e "  2. Changez le mot de passe admin"
echo -e "  3. Créez vos premiers workflows !"
echo ""

echo -e "${GREEN}🎉 n8n est prêt à l'emploi !${NC}"
echo ""

# Afficher les credentials
cat /root/n8n_credentials.txt
echo ""
