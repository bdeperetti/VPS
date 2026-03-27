#!/bin/bash

#########################################################
# Installation Ollama + Open WebUI (sans Docker)
# Domaines: ollama.kair.fr + ui.kair.fr
# HTTP (pas de SSL pour l'instant)
# Par Bertrand - 2P FOOD
#########################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Ollama + Open WebUI${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Vérification root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Ce script doit être exécuté en root${NC}"
    exit 1
fi

# Configuration
OLLAMA_DOMAIN="ollama.kair.fr"
WEBUI_DOMAIN="ia.kair.fr"
OLLAMA_PORT="11434"
WEBUI_PORT="8080"

echo -e "${YELLOW}📋 Configuration :${NC}"
echo -e "  Ollama API   : ${GREEN}http://${OLLAMA_DOMAIN}${NC}"
echo -e "  Open WebUI   : ${GREEN}http://${WEBUI_DOMAIN}${NC}"
echo ""

# Vérifier l'espace disque disponible
DISK_AVAILABLE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
echo -e "${YELLOW}💾 Espace disque disponible : ${DISK_AVAILABLE} GB${NC}"

if [ "$DISK_AVAILABLE" -lt 40 ]; then
    echo -e "${RED}⚠️  ATTENTION : Espace disque faible !${NC}"
    echo -e "  Modèles choisis nécessitent ~36 GB"
    echo -e "  Disponible : ${DISK_AVAILABLE} GB"
    echo ""
    read -p "Voulez-vous continuer quand même ? [y/N]: " CONTINUE
    if [[ ! $CONTINUE =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Vérifier la RAM
RAM_TOTAL=$(free -g | awk 'NR==2 {print $2}')
echo -e "${YELLOW}🧠 RAM totale : ${RAM_TOTAL} GB${NC}"

if [ "$RAM_TOTAL" -lt 16 ]; then
    echo -e "${YELLOW}⚠️  Attention : Mixtral nécessite 16 GB de RAM${NC}"
    echo -e "  Vous avez : ${RAM_TOTAL} GB"
    echo -e "  Le modèle Mixtral pourrait ne pas fonctionner correctement"
    echo ""
fi

# Mise à jour système
echo ""
echo -e "${YELLOW}📦 Mise à jour du système...${NC}"
apt update && apt upgrade -y

#########################################################
# INSTALLATION OLLAMA
#########################################################

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Installation Ollama${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "${YELLOW}🤖 Installation d'Ollama...${NC}"

# Installation officielle d'Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Vérifier l'installation
if command -v ollama &> /dev/null; then
    echo -e "${GREEN}✅ Ollama installé${NC}"
    ollama --version
else
    echo -e "${RED}❌ Erreur lors de l'installation d'Ollama${NC}"
    exit 1
fi

# Configuration du service Ollama
echo -e "${YELLOW}🔧 Configuration du service Ollama...${NC}"

# Créer le fichier de configuration systemd
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf << EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:${OLLAMA_PORT}"
Environment="OLLAMA_ORIGINS=http://${WEBUI_DOMAIN},http://${OLLAMA_DOMAIN}"
EOF

# Recharger systemd et redémarrer Ollama
systemctl daemon-reload
systemctl restart ollama
systemctl enable ollama

echo -e "${GREEN}✅ Service Ollama configuré${NC}"

# Attendre que le service démarre
sleep 3

# Vérifier que le service tourne
if systemctl is-active --quiet ollama; then
    echo -e "${GREEN}✅ Ollama est actif${NC}"
else
    echo -e "${RED}❌ Ollama n'a pas démarré correctement${NC}"
    systemctl status ollama
    exit 1
fi

#########################################################
# TÉLÉCHARGEMENT DES MODÈLES
#########################################################

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Téléchargement des modèles IA${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${YELLOW}⚠️  Le téléchargement peut prendre 30-60 minutes${NC}"
echo ""

# Liste des modèles à installer
MODELS=("llama3.2" "mistral" "codellama" "mixtral")

for model in "${MODELS[@]}"; do
    echo ""
    echo -e "${CYAN}📥 Téléchargement du modèle : ${model}${NC}"
    
    case $model in
        "llama3.2")
            echo -e "  Taille : ~2 GB"
            ;;
        "mistral")
            echo -e "  Taille : ~4 GB"
            ;;
        "codellama")
            echo -e "  Taille : ~4 GB"
            ;;
        "mixtral")
            echo -e "  Taille : ~26 GB"
            ;;
    esac
    
    ollama pull $model
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ ${model} téléchargé${NC}"
    else
        echo -e "${RED}❌ Erreur lors du téléchargement de ${model}${NC}"
    fi
done

echo ""
echo -e "${GREEN}✅ Tous les modèles sont téléchargés${NC}"

# Lister les modèles installés
echo ""
echo -e "${CYAN}📋 Modèles installés :${NC}"
ollama list

#########################################################
# INSTALLATION OPEN WEBUI
#########################################################

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Installation Open WebUI${NC}"
echo -e "${BLUE}========================================${NC}"

# Installer Python et pip si nécessaire
echo -e "${YELLOW}🐍 Installation de Python et dépendances...${NC}"
apt install -y python3 python3-pip python3-venv

# Créer un utilisateur dédié pour Open WebUI
echo -e "${YELLOW}👤 Création de l'utilisateur webui...${NC}"
if ! id -u webui &>/dev/null; then
    useradd -r -s /bin/bash -d /opt/open-webui webui
fi

# Créer le répertoire d'installation
mkdir -p /opt/open-webui
cd /opt/open-webui

# Créer un environnement virtuel Python
echo -e "${YELLOW}📦 Création de l'environnement virtuel Python...${NC}"
python3 -m venv venv

# Activer l'environnement virtuel et installer Open WebUI
echo -e "${YELLOW}📥 Installation d'Open WebUI...${NC}"
source venv/bin/activate
pip install --upgrade pip
pip install open-webui

echo -e "${GREEN}✅ Open WebUI installé${NC}"

# Créer le répertoire de données
mkdir -p /opt/open-webui/data
chown -R webui:webui /opt/open-webui

# Créer le fichier de configuration
cat > /opt/open-webui/.env << EOF
# Configuration Open WebUI
WEBUI_NAME=2P FOOD AI
WEBUI_URL=http://${WEBUI_DOMAIN}
OLLAMA_BASE_URL=http://localhost:${OLLAMA_PORT}

# Port
PORT=${WEBUI_PORT}

# Authentification
WEBUI_AUTH=true
WEBUI_SECRET_KEY=$(openssl rand -hex 32)

# Données
DATA_DIR=/opt/open-webui/data

# Timezone
TZ=Europe/Paris
EOF

chmod 600 /opt/open-webui/.env
chown webui:webui /opt/open-webui/.env

# Créer le service systemd pour Open WebUI
echo -e "${YELLOW}🔧 Création du service Open WebUI...${NC}"

cat > /etc/systemd/system/open-webui.service << 'EOF'
[Unit]
Description=Open WebUI Service
After=network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=webui
Group=webui
WorkingDirectory=/opt/open-webui
EnvironmentFile=/opt/open-webui/.env
ExecStart=/opt/open-webui/venv/bin/python -m open_webui serve
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Activer et démarrer le service
systemctl daemon-reload
systemctl enable open-webui
systemctl start open-webui

echo -e "${GREEN}✅ Service Open WebUI créé et démarré${NC}"

# Attendre que le service démarre
sleep 5

# Vérifier le statut
if systemctl is-active --quiet open-webui; then
    echo -e "${GREEN}✅ Open WebUI est actif${NC}"
else
    echo -e "${RED}❌ Open WebUI n'a pas démarré correctement${NC}"
    systemctl status open-webui
fi

#########################################################
# CONFIGURATION NGINX
#########################################################

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Configuration Nginx${NC}"
echo -e "${BLUE}========================================${NC}"

# Configuration pour Ollama API
echo -e "${YELLOW}🌐 Configuration Nginx pour Ollama...${NC}"

cat > /etc/nginx/sites-available/ollama << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${OLLAMA_DOMAIN};

    access_log /var/log/nginx/ollama-access.log;
    error_log /var/log/nginx/ollama-error.log;

    location / {
        proxy_pass http://localhost:${OLLAMA_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts pour les requêtes IA longues
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        send_timeout 600;
        
        client_max_body_size 100M;
    }
}
EOF

# Configuration pour Open WebUI
echo -e "${YELLOW}🌐 Configuration Nginx pour Open WebUI...${NC}"

cat > /etc/nginx/sites-available/open-webui << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${WEBUI_DOMAIN};

    access_log /var/log/nginx/webui-access.log;
    error_log /var/log/nginx/webui-error.log;

    location / {
        proxy_pass http://localhost:${WEBUI_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts
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

# Activer les sites
ln -sf /etc/nginx/sites-available/ollama /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/open-webui /etc/nginx/sites-enabled/

# Tester la configuration
nginx -t

# Redémarrer Nginx
systemctl restart nginx

echo -e "${GREEN}✅ Nginx configuré${NC}"

#########################################################
# PARE-FEU
#########################################################

echo ""
echo -e "${YELLOW}🔥 Configuration du pare-feu...${NC}"

ufw allow ${OLLAMA_PORT}/tcp comment 'Ollama API'
ufw allow ${WEBUI_PORT}/tcp comment 'Open WebUI'

echo -e "${GREEN}✅ Pare-feu configuré${NC}"

#########################################################
# SCRIPT DE GESTION DES MODÈLES
#########################################################

echo ""
echo -e "${YELLOW}📝 Création du script de gestion...${NC}"

cat > /usr/local/bin/ollama-manager << 'EOF'
#!/bin/bash
# Script de gestion Ollama

case "$1" in
    list)
        echo "📋 Modèles installés :"
        ollama list
        ;;
    pull)
        if [ -z "$2" ]; then
            echo "Usage: ollama-manager pull <model>"
            echo "Exemples: llama3.2, mistral, codellama, mixtral"
            exit 1
        fi
        echo "📥 Téléchargement de $2..."
        ollama pull $2
        ;;
    remove)
        if [ -z "$2" ]; then
            echo "Usage: ollama-manager remove <model>"
            exit 1
        fi
        echo "🗑️  Suppression de $2..."
        ollama rm $2
        ;;
    status)
        echo "🔍 Statut des services :"
        echo ""
        echo "Ollama :"
        systemctl status ollama --no-pager -l
        echo ""
        echo "Open WebUI :"
        systemctl status open-webui --no-pager -l
        ;;
    restart)
        echo "🔄 Redémarrage des services..."
        systemctl restart ollama
        systemctl restart open-webui
        echo "✅ Services redémarrés"
        ;;
    logs)
        if [ "$2" == "ollama" ]; then
            journalctl -u ollama -f
        elif [ "$2" == "webui" ]; then
            journalctl -u open-webui -f
        else
            echo "Usage: ollama-manager logs [ollama|webui]"
        fi
        ;;
    *)
        echo "Script de gestion Ollama + Open WebUI"
        echo ""
        echo "Usage: ollama-manager <commande>"
        echo ""
        echo "Commandes :"
        echo "  list              - Liste les modèles installés"
        echo "  pull <model>      - Télécharge un modèle"
        echo "  remove <model>    - Supprime un modèle"
        echo "  status            - Affiche le statut des services"
        echo "  restart           - Redémarre les services"
        echo "  logs [ollama|webui] - Affiche les logs en temps réel"
        ;;
esac
EOF

chmod +x /usr/local/bin/ollama-manager

echo -e "${GREEN}✅ Script de gestion créé${NC}"

#########################################################
# RÉSUMÉ FINAL
#########################################################

clear
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Installation terminée !${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${BLUE}🌍 ACCÈS${NC}"
echo ""
echo -e "  Open WebUI (Interface) : ${GREEN}http://${WEBUI_DOMAIN}${NC}"
echo -e "  Ollama API             : ${GREEN}http://${OLLAMA_DOMAIN}${NC}"
echo ""
echo -e "${YELLOW}📝 Créez votre compte sur Open WebUI lors de la première connexion${NC}"
echo ""

echo -e "${BLUE}🤖 MODÈLES INSTALLÉS${NC}"
echo ""
ollama list
echo ""

echo -e "${BLUE}💾 ESPACE DISQUE UTILISÉ${NC}"
echo ""
OLLAMA_SIZE=$(du -sh ~/.ollama 2>/dev/null | awk '{print $1}' || echo "N/A")
echo -e "  Modèles Ollama : ${GREEN}${OLLAMA_SIZE}${NC}"
echo ""

echo -e "${BLUE}🔧 COMMANDES UTILES${NC}"
echo ""
echo -e "  Gestion globale    : ${GREEN}ollama-manager status${NC}"
echo -e "  Liste modèles      : ${GREEN}ollama-manager list${NC}"
echo -e "  Ajouter modèle     : ${GREEN}ollama-manager pull llama2${NC}"
echo -e "  Supprimer modèle   : ${GREEN}ollama-manager remove mixtral${NC}"
echo -e "  Redémarrer         : ${GREEN}ollama-manager restart${NC}"
echo -e "  Logs Ollama        : ${GREEN}ollama-manager logs ollama${NC}"
echo -e "  Logs WebUI         : ${GREEN}ollama-manager logs webui${NC}"
echo ""

echo -e "${BLUE}🔍 SERVICES${NC}"
echo ""
echo -e "  Statut Ollama      : ${GREEN}systemctl status ollama${NC}"
echo -e "  Statut Open WebUI  : ${GREEN}systemctl status open-webui${NC}"
echo ""

echo -e "${BLUE}📁 FICHIERS IMPORTANTS${NC}"
echo ""
echo -e "  Config Ollama      : ${GREEN}/etc/systemd/system/ollama.service.d/override.conf${NC}"
echo -e "  Config Open WebUI  : ${GREEN}/opt/open-webui/.env${NC}"
echo -e "  Données WebUI      : ${GREEN}/opt/open-webui/data${NC}"
echo -e "  Modèles Ollama     : ${GREEN}~/.ollama/models${NC}"
echo ""

echo -e "${YELLOW}⚡ PERFORMANCES${NC}"
echo ""
echo -e "  • llama3.2  : Rapide, léger (recommandé pour débuter)"
echo -e "  • mistral   : Bon compromis qualité/vitesse"
echo -e "  • codellama : Optimisé pour le code"
echo -e "  • mixtral   : Puissant mais lent (nécessite 16GB RAM)"
echo ""

echo -e "${YELLOW}📝 PROCHAINES ÉTAPES${NC}"
echo ""
echo -e "  1. Allez sur ${GREEN}http://${WEBUI_DOMAIN}${NC}"
echo -e "  2. Créez votre compte administrateur"
echo -e "  3. Testez les différents modèles"
echo -e "  4. Configurez vos préférences"
echo ""

echo -e "${GREEN}🎉 Votre serveur IA est opérationnel !${NC}"
echo ""
