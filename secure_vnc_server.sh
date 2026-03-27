#!/bin/bash

#########################################################
# Script de Sécurisation Post-Installation
# Bureau XFCE + VNC sur VPS OVH
# Par Bertrand - 2P FOOD
#########################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Sécurisation du Serveur VNC${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Vérification root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Ce script doit être exécuté en root${NC}"
    exit 1
fi

# 1. Configuration VNC en localhost uniquement
echo -e "${YELLOW}🔒 Configuration VNC en localhost (tunnel SSH obligatoire)...${NC}"
read -p "Activer VNC en localhost uniquement (nécessitera tunnel SSH) ? [y/N]: " LOCALHOST_ONLY

if [[ $LOCALHOST_ONLY =~ ^[Yy]$ ]]; then
    systemctl stop vncserver@1
    
    # Trouver le bon utilisateur VNC
    VNC_USER=$(grep "User=" /etc/systemd/system/vncserver@.service | cut -d'=' -f2)
    
    # Backup du fichier
    cp /etc/systemd/system/vncserver@.service /etc/systemd/system/vncserver@.service.backup
    
    # Modification pour localhost uniquement
    sed -i 's/-localhost no/-localhost yes/g' /etc/systemd/system/vncserver@.service
    
    systemctl daemon-reload
    systemctl start vncserver@1
    
    # Retirer le port VNC du pare-feu
    ufw delete allow 5901/tcp 2>/dev/null || true
    
    echo -e "${GREEN}✅ VNC configuré en localhost uniquement${NC}"
    echo -e "${YELLOW}📌 Connexion via tunnel SSH : ssh -L 5901:localhost:5901 $VNC_USER@$(hostname -I | awk '{print $1}')${NC}"
fi

# 2. Limitation par IP (si VNC reste public)
if [[ ! $LOCALHOST_ONLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}🌍 Limitation d'accès VNC par IP${NC}"
    read -p "Voulez-vous limiter l'accès VNC à une IP spécifique ? [y/N]: " LIMIT_IP
    
    if [[ $LIMIT_IP =~ ^[Yy]$ ]]; then
        read -p "Entrez votre IP publique (ou 0.0.0.0/0 pour toutes) : " USER_IP
        
        if [ "$USER_IP" != "0.0.0.0/0" ]; then
            ufw delete allow 5901/tcp 2>/dev/null || true
            ufw allow from $USER_IP to any port 5901 comment 'VNC restricted access'
            echo -e "${GREEN}✅ Accès VNC limité à $USER_IP${NC}"
        fi
    fi
fi

# 3. Installation et configuration Fail2Ban
echo ""
echo -e "${YELLOW}🛡️  Installation de Fail2Ban...${NC}"
apt install -y fail2ban

# Configuration Fail2Ban pour SSH
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF

systemctl enable fail2ban
systemctl restart fail2ban

echo -e "${GREEN}✅ Fail2Ban configuré${NC}"

# 4. Mises à jour automatiques
echo ""
echo -e "${YELLOW}🔄 Configuration des mises à jour automatiques...${NC}"
apt install -y unattended-upgrades apt-listchanges

cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

echo -e "${GREEN}✅ Mises à jour automatiques activées${NC}"

# 5. Configuration SSH sécurisée
echo ""
echo -e "${YELLOW}🔑 Sécurisation SSH...${NC}"

# Backup de la config SSH
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Modifications sécurisées
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

echo ""
read -p "⚠️  Désactiver l'authentification SSH par mot de passe (clés SSH uniquement) ? [y/N]: " DISABLE_PASSWORD

if [[ $DISABLE_PASSWORD =~ ^[Yy]$ ]]; then
    echo -e "${RED}⚠️  ATTENTION : Assurez-vous d'avoir configuré vos clés SSH AVANT !${NC}"
    read -p "Confirmer la désactivation du mot de passe SSH ? [y/N]: " CONFIRM
    
    if [[ $CONFIRM =~ ^[Yy]$ ]]; then
        sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
        sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
        echo -e "${GREEN}✅ Authentification par mot de passe désactivée${NC}"
    fi
fi

systemctl restart sshd
echo -e "${GREEN}✅ SSH sécurisé${NC}"

# 6. Configuration d'un pare-feu restrictif
echo ""
echo -e "${YELLOW}🔥 Configuration du pare-feu...${NC}"

# Règles essentielles
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

read -p "Ouvrir les ports pour Docker/Portainer (9000, 9443) ? [y/N]: " DOCKER_PORTS
if [[ $DOCKER_PORTS =~ ^[Yy]$ ]]; then
    ufw allow 9000/tcp comment 'Portainer HTTP'
    ufw allow 9443/tcp comment 'Portainer HTTPS'
fi

read -p "Ouvrir le port pour Webmin (10000) ? [y/N]: " WEBMIN_PORT
if [[ $WEBMIN_PORT =~ ^[Yy]$ ]]; then
    ufw allow 10000/tcp comment 'Webmin'
fi

read -p "Ouvrir le port pour Cockpit (9090) ? [y/N]: " COCKPIT_PORT
if [[ $COCKPIT_PORT =~ ^[Yy]$ ]]; then
    ufw allow 9090/tcp comment 'Cockpit'
fi

ufw --force enable

echo -e "${GREEN}✅ Pare-feu configuré${NC}"

# 7. Monitoring basique
echo ""
echo -e "${YELLOW}📊 Installation d'outils de monitoring...${NC}"
apt install -y htop iotop nethogs ncdu

# 8. Création d'un script de backup
echo ""
echo -e "${YELLOW}💾 Création du script de backup...${NC}"

cat > /usr/local/bin/backup-vnc-config.sh << 'EOF'
#!/bin/bash
# Backup des configurations importantes

BACKUP_DIR="/root/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup des configs
tar -czf $BACKUP_DIR/vnc-config-$DATE.tar.gz \
    /etc/systemd/system/vncserver@.service \
    /etc/ssh/sshd_config \
    /etc/fail2ban/jail.local \
    /etc/ufw/ \
    2>/dev/null

echo "Backup créé : $BACKUP_DIR/vnc-config-$DATE.tar.gz"

# Garder seulement les 7 derniers backups
ls -t $BACKUP_DIR/vnc-config-*.tar.gz | tail -n +8 | xargs rm -f 2>/dev/null
EOF

chmod +x /usr/local/bin/backup-vnc-config.sh

# Création d'une tâche cron hebdomadaire
(crontab -l 2>/dev/null; echo "0 3 * * 0 /usr/local/bin/backup-vnc-config.sh") | crontab -

echo -e "${GREEN}✅ Script de backup créé (exécution hebdomadaire)${NC}"

# 9. Résumé final
clear
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Sécurisation terminée !${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${YELLOW}📋 Résumé des sécurités appliquées :${NC}"
echo ""

if [[ $LOCALHOST_ONLY =~ ^[Yy]$ ]]; then
    echo -e "  ✅ VNC en localhost uniquement (tunnel SSH requis)"
else
    echo -e "  ⚠️  VNC accessible depuis Internet (considérez le tunnel SSH)"
fi

echo -e "  ✅ Fail2Ban activé (protection brute-force)"
echo -e "  ✅ Mises à jour automatiques configurées"
echo -e "  ✅ SSH durci (max 3 tentatives)"

if [[ $DISABLE_PASSWORD =~ ^[Yy]$ ]]; then
    echo -e "  ✅ Authentification SSH par clés uniquement"
fi

echo -e "  ✅ Pare-feu UFW actif"
echo -e "  ✅ Backup automatique hebdomadaire"
echo ""

echo -e "${YELLOW}🔒 Recommandations supplémentaires :${NC}"
echo ""
echo -e "  1. Configurer des clés SSH si pas encore fait :"
echo -e "     ${GREEN}ssh-keygen -t ed25519 -C 'vps-xfce'${NC}"
echo -e "     ${GREEN}ssh-copy-id user@137.74.12.199${NC}"
echo ""
echo -e "  2. Tester la connexion VNC via tunnel SSH :"
echo -e "     ${GREEN}ssh -L 5901:localhost:5901 user@137.74.12.199${NC}"
echo -e "     Puis connecter VNC à : ${GREEN}localhost:5901${NC}"
echo ""
echo -e "  3. Vérifier régulièrement les logs :"
echo -e "     ${GREEN}sudo fail2ban-client status sshd${NC}"
echo -e "     ${GREEN}sudo journalctl -u vncserver@1 -f${NC}"
echo ""
echo -e "  4. Créer un backup manuel maintenant :"
echo -e "     ${GREEN}/usr/local/bin/backup-vnc-config.sh${NC}"
echo ""

echo -e "${GREEN}🎉 Votre serveur est maintenant sécurisé !${NC}"
echo ""
