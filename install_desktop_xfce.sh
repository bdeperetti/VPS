#!/bin/bash

#########################################################
# Installation Bureau Graphique XFCE + VNC
# Pour VPS OVH Ubuntu 24.04
# Par Bertrand - 2P FOOD
#########################################################

set -e  # Arrêt en cas d'erreur

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Bureau Graphique XFCE${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Vérification root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Ce script doit être exécuté en root${NC}"
    exit 1
fi

# Mise à jour du système
echo -e "${YELLOW}📦 Mise à jour du système...${NC}"
apt update && apt upgrade -y

# Installation du bureau XFCE (léger et performant)
echo -e "${YELLOW}🖥️  Installation XFCE Desktop...${NC}"
apt install -y xfce4 xfce4-goodies

# Installation de TigerVNC Server
echo -e "${YELLOW}🔐 Installation TigerVNC Server...${NC}"
apt install -y tigervnc-standalone-server tigervnc-common

# Installation d'outils essentiels
echo -e "${YELLOW}🛠️  Installation des outils essentiels...${NC}"
apt install -y \
    firefox \
    thunar \
    xfce4-terminal \
    mousepad \
    ristretto \
    xarchiver \
    git \
    curl \
    wget \
    nano \
    vim \
    htop \
    net-tools \
    dbus-x11

# Création d'un utilisateur dédié (si nécessaire)
echo ""
echo -e "${GREEN}👤 Configuration utilisateur${NC}"
read -p "Nom d'utilisateur pour le bureau distant [default: vpsuser]: " VNC_USER
VNC_USER=${VNC_USER:-vpsuser}

if id "$VNC_USER" &>/dev/null; then
    echo -e "${YELLOW}⚠️  L'utilisateur $VNC_USER existe déjà${NC}"
else
    echo -e "${GREEN}✅ Création de l'utilisateur $VNC_USER${NC}"
    adduser --gecos "" $VNC_USER
    usermod -aG sudo $VNC_USER
fi

# Configuration VNC pour l'utilisateur
echo -e "${YELLOW}🔧 Configuration VNC...${NC}"

# Création du répertoire VNC
sudo -u $VNC_USER mkdir -p /home/$VNC_USER/.vnc

# Configuration du fichier xstartup
cat > /home/$VNC_USER/.vnc/xstartup << 'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1
export XDG_CURRENT_DESKTOP="XFCE"
export XDG_SESSION_DESKTOP="XFCE"

dbus-launch --exit-with-session startxfce4 &
EOF

chmod +x /home/$VNC_USER/.vnc/xstartup
chown -R $VNC_USER:$VNC_USER /home/$VNC_USER/.vnc

# Configuration du mot de passe VNC
echo ""
echo -e "${GREEN}🔑 Configuration du mot de passe VNC${NC}"
echo -e "${YELLOW}Vous allez définir le mot de passe VNC pour l'utilisateur $VNC_USER${NC}"
sudo -u $VNC_USER vncpasswd

# Création du service systemd pour VNC
echo -e "${YELLOW}⚙️  Création du service systemd...${NC}"

cat > /etc/systemd/system/vncserver@.service << EOF
[Unit]
Description=Start TigerVNC server at startup
After=syslog.target network.target

[Service]
Type=forking
User=$VNC_USER
Group=$VNC_USER
WorkingDirectory=/home/$VNC_USER

PIDFile=/home/$VNC_USER/.vnc/%H:%i.pid
ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver -depth 24 -geometry 1920x1080 -localhost no :%i
ExecStop=/usr/bin/vncserver -kill :%i

[Install]
WantedBy=multi-user.target
EOF

# Activation du service VNC sur le port :1 (5901)
systemctl daemon-reload
systemctl enable vncserver@1.service
systemctl start vncserver@1.service

# Configuration du pare-feu (UFW)
echo -e "${YELLOW}🔥 Configuration du pare-feu...${NC}"
if ! command -v ufw &> /dev/null; then
    apt install -y ufw
fi

ufw allow 22/tcp comment 'SSH'
ufw allow 5901/tcp comment 'VNC Server'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Activation UFW (avec confirmation)
echo -e "${YELLOW}⚠️  Activation du pare-feu UFW${NC}"
echo "y" | ufw enable

# Installation de NoVNC (optionnel - accès VNC via navigateur)
echo ""
read -p "Voulez-vous installer noVNC (accès VNC via navigateur web) ? [y/N]: " INSTALL_NOVNC

if [[ $INSTALL_NOVNC =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}🌐 Installation de noVNC...${NC}"
    
    apt install -y novnc python3-websockify
    
    # Création du service noVNC
    cat > /etc/systemd/system/novnc.service << EOF
[Unit]
Description=noVNC Service
After=network.target

[Service]
Type=simple
User=$VNC_USER
ExecStart=/usr/share/novnc/utils/novnc_proxy --vnc localhost:5901 --listen 6080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable novnc.service
    systemctl start novnc.service
    
    ufw allow 6080/tcp comment 'noVNC Web Access'
    
    echo -e "${GREEN}✅ noVNC installé et accessible sur le port 6080${NC}"
fi

# Résumé de l'installation
clear
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Installation terminée !${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}📋 Informations de connexion :${NC}"
echo ""
echo -e "  Utilisateur VNC : ${GREEN}$VNC_USER${NC}"
echo -e "  Serveur VNC     : ${GREEN}$(hostname -I | awk '{print $1}'):5901${NC}"
echo -e "  Résolution      : ${GREEN}1920x1080${NC}"
echo ""

if [[ $INSTALL_NOVNC =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}🌐 Accès Web (noVNC) :${NC}"
    echo -e "  URL : ${GREEN}http://$(hostname -I | awk '{print $1}'):6080/vnc.html${NC}"
    echo ""
fi

echo -e "${YELLOW}💡 Clients VNC recommandés :${NC}"
echo -e "  • Windows : RealVNC Viewer, TigerVNC Viewer"
echo -e "  • macOS   : RealVNC Viewer, Screen Sharing (intégré)"
echo -e "  • Linux   : Remmina, TigerVNC Viewer"
echo ""

echo -e "${YELLOW}🔧 Commandes utiles :${NC}"
echo -e "  Démarrer VNC  : ${GREEN}systemctl start vncserver@1${NC}"
echo -e "  Arrêter VNC   : ${GREEN}systemctl stop vncserver@1${NC}"
echo -e "  Statut VNC    : ${GREEN}systemctl status vncserver@1${NC}"
echo -e "  Changer mdp   : ${GREEN}su - $VNC_USER && vncpasswd${NC}"
echo ""

echo -e "${YELLOW}⚠️  SÉCURITÉ :${NC}"
echo -e "  1. Utilisez un mot de passe VNC FORT"
echo -e "  2. Envisagez un tunnel SSH pour plus de sécurité"
echo -e "  3. Limitez l'accès par IP si possible (ufw allow from IP to any port 5901)"
echo ""

echo -e "${GREEN}🚀 Connexion disponible !${NC}"
echo ""
