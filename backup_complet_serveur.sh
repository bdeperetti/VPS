#!/bin/bash

#########################################################
# Script de Sauvegarde Complète du Serveur
# VPS Ubuntu 24.04 - LAMP + n8n + Ollama + Open WebUI
# Par Bertrand - 2P FOOD
#########################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
BACKUP_ROOT="/root/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/full_backup_$DATE"
LOG_FILE="$BACKUP_DIR/backup.log"

# Fonction de log
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERREUR:${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ATTENTION:${NC} $1" | tee -a "$LOG_FILE"
}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SAUVEGARDE COMPLÈTE DU SERVEUR${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Vérification root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Ce script doit être exécuté en root${NC}"
    exit 1
fi

# Créer le répertoire de backup
mkdir -p "$BACKUP_DIR"
log "📁 Répertoire de backup créé : $BACKUP_DIR"

# Vérifier l'espace disque disponible
DISK_AVAILABLE=$(df -BG "$BACKUP_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
DISK_USED=$(du -sg / --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run 2>/dev/null | awk '{print $1}')

log "💾 Espace disque disponible : ${DISK_AVAILABLE} GB"
log "📊 Espace utilisé (estimation) : ${DISK_USED} GB"

if [ "$DISK_AVAILABLE" -lt "$((DISK_USED + 10))" ]; then
    warning "Espace disque faible ! Recommandé : Au moins $((DISK_USED + 10)) GB"
    read -p "Voulez-vous continuer quand même ? [y/N]: " CONTINUE
    if [[ ! $CONTINUE =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

echo ""
log "🚀 Début de la sauvegarde..."
echo ""

#########################################################
# 1. INFORMATIONS SYSTÈME
#########################################################

log "📋 Sauvegarde des informations système..."

cat > "$BACKUP_DIR/system_info.txt" << EOF
=== INFORMATIONS SYSTÈME ===
Date de sauvegarde : $(date)
Hostname : $(hostname)
IP : $(hostname -I)
OS : $(lsb_release -d | cut -f2)
Kernel : $(uname -r)
Uptime : $(uptime -p)

=== RESSOURCES ===
RAM : $(free -h | grep Mem | awk '{print $2}')
CPU : $(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
Disque : $(df -h / | awk 'NR==2 {print $2}')

=== SERVICES ACTIFS ===
$(systemctl list-units --state=running --type=service --no-pager)
EOF

log "✅ Informations système sauvegardées"

#########################################################
# 2. CONFIGURATION NGINX
#########################################################

log "🌐 Sauvegarde de Nginx..."

mkdir -p "$BACKUP_DIR/nginx"
cp -r /etc/nginx/* "$BACKUP_DIR/nginx/" 2>/dev/null || true
tar -czf "$BACKUP_DIR/nginx.tar.gz" -C /etc nginx 2>/dev/null

log "✅ Nginx sauvegardé"

#########################################################
# 3. BASES DE DONNÉES
#########################################################

log "🗄️  Sauvegarde des bases de données..."

mkdir -p "$BACKUP_DIR/databases"

# MySQL / MariaDB
if systemctl is-active --quiet mysql || systemctl is-active --quiet mariadb; then
    log "  → Dump de toutes les bases MySQL/MariaDB..."
    
    # MySQL sur port 3306
    if [ -f "/root/.my.cnf" ]; then
        mysqldump --all-databases --single-transaction --routines --triggers --events \
            > "$BACKUP_DIR/databases/mysql_all_databases.sql" 2>/dev/null || true
        
        # Compresser
        gzip "$BACKUP_DIR/databases/mysql_all_databases.sql"
        log "  ✅ MySQL (port 3306) sauvegardé"
    fi
    
    # MariaDB sur port 3307
    if [ -f "/root/.my-mariadb10.cnf" ]; then
        mysqldump --defaults-file=/root/.my-mariadb10.cnf --all-databases \
            --single-transaction --routines --triggers --events \
            > "$BACKUP_DIR/databases/mariadb_all_databases.sql" 2>/dev/null || true
        
        gzip "$BACKUP_DIR/databases/mariadb_all_databases.sql"
        log "  ✅ MariaDB (port 3307) sauvegardé"
    fi
    
    # Sauvegarder les credentials
    cp /root/.my.cnf "$BACKUP_DIR/databases/" 2>/dev/null || true
    cp /root/.my-mariadb10.cnf "$BACKUP_DIR/databases/" 2>/dev/null || true
    cp /root/database_credentials.txt "$BACKUP_DIR/databases/" 2>/dev/null || true
fi

log "✅ Bases de données sauvegardées"

#########################################################
# 4. SITES WEB
#########################################################

log "🌍 Sauvegarde des sites web..."

mkdir -p "$BACKUP_DIR/websites"
tar -czf "$BACKUP_DIR/websites/www.tar.gz" -C /var/www html 2>/dev/null

log "✅ Sites web sauvegardés"

#########################################################
# 5. PHP
#########################################################

log "🐘 Sauvegarde de la configuration PHP..."

mkdir -p "$BACKUP_DIR/php"

# Sauvegarder toutes les versions PHP
for php_version in /etc/php/*; do
    if [ -d "$php_version" ]; then
        version=$(basename "$php_version")
        tar -czf "$BACKUP_DIR/php/php${version}.tar.gz" -C /etc/php "$version" 2>/dev/null
    fi
done

log "✅ PHP sauvegardé"

#########################################################
# 6. n8n
#########################################################

if [ -d "/root/.n8n" ]; then
    log "⚙️  Sauvegarde de n8n..."
    
    mkdir -p "$BACKUP_DIR/n8n"
    
    # Arrêter n8n temporairement pour garantir la cohérence
    pm2 stop n8n 2>/dev/null || true
    sleep 2
    
    # Sauvegarder les données
    tar -czf "$BACKUP_DIR/n8n/n8n_data.tar.gz" -C /root .n8n 2>/dev/null
    
    # Sauvegarder les credentials
    cp /root/n8n_credentials.txt "$BACKUP_DIR/n8n/" 2>/dev/null || true
    
    # Redémarrer n8n
    pm2 start n8n 2>/dev/null || true
    
    log "✅ n8n sauvegardé"
fi

#########################################################
# 7. OLLAMA
#########################################################

if systemctl is-active --quiet ollama; then
    log "🤖 Sauvegarde d'Ollama..."
    
    mkdir -p "$BACKUP_DIR/ollama"
    
    # Arrêter Ollama temporairement
    systemctl stop ollama
    sleep 2
    
    # Sauvegarder les modèles et données
    tar -czf "$BACKUP_DIR/ollama/ollama_models.tar.gz" -C /usr/share/ollama models 2>/dev/null || true
    tar -czf "$BACKUP_DIR/ollama/ollama_root.tar.gz" -C ~/.ollama . 2>/dev/null || true
    
    # Configuration systemd
    cp -r /etc/systemd/system/ollama.service.d "$BACKUP_DIR/ollama/" 2>/dev/null || true
    
    # Redémarrer Ollama
    systemctl start ollama
    
    # Liste des modèles
    sleep 3
    ollama list > "$BACKUP_DIR/ollama/models_list.txt" 2>/dev/null || true
    
    log "✅ Ollama sauvegardé"
fi

#########################################################
# 8. OPEN WEBUI
#########################################################

if systemctl is-active --quiet open-webui; then
    log "💬 Sauvegarde d'Open WebUI..."
    
    mkdir -p "$BACKUP_DIR/open-webui"
    
    # Arrêter Open WebUI
    systemctl stop open-webui
    sleep 2
    
    # Sauvegarder les données
    tar -czf "$BACKUP_DIR/open-webui/open-webui_data.tar.gz" -C /opt open-webui 2>/dev/null
    
    # Redémarrer Open WebUI
    systemctl start open-webui
    
    log "✅ Open WebUI sauvegardé"
fi

#########################################################
# 9. UTILISATEURS ET GROUPES
#########################################################

log "👥 Sauvegarde des utilisateurs..."

mkdir -p "$BACKUP_DIR/users"

cp /etc/passwd "$BACKUP_DIR/users/"
cp /etc/shadow "$BACKUP_DIR/users/"
cp /etc/group "$BACKUP_DIR/users/"
cp /etc/gshadow "$BACKUP_DIR/users/"
cp /etc/sudoers "$BACKUP_DIR/users/" 2>/dev/null || true
cp -r /etc/sudoers.d "$BACKUP_DIR/users/" 2>/dev/null || true

log "✅ Utilisateurs sauvegardés"

#########################################################
# 10. SSH ET PARE-FEU
#########################################################

log "🔐 Sauvegarde SSH et pare-feu..."

mkdir -p "$BACKUP_DIR/security"

# SSH
cp -r /etc/ssh "$BACKUP_DIR/security/" 2>/dev/null

# UFW
cp -r /etc/ufw "$BACKUP_DIR/security/" 2>/dev/null || true
ufw status verbose > "$BACKUP_DIR/security/ufw_rules.txt" 2>/dev/null || true

# Fail2Ban
if systemctl is-active --quiet fail2ban; then
    cp -r /etc/fail2ban "$BACKUP_DIR/security/" 2>/dev/null || true
fi

log "✅ SSH et pare-feu sauvegardés"

#########################################################
# 11. CRON ET SERVICES
#########################################################

log "⏰ Sauvegarde des tâches planifiées..."

mkdir -p "$BACKUP_DIR/cron"

# Crontabs
cp -r /var/spool/cron "$BACKUP_DIR/cron/" 2>/dev/null || true
crontab -l > "$BACKUP_DIR/cron/root_crontab.txt" 2>/dev/null || true

# Services systemd personnalisés
mkdir -p "$BACKUP_DIR/systemd"
cp /etc/systemd/system/*.service "$BACKUP_DIR/systemd/" 2>/dev/null || true

log "✅ Tâches planifiées sauvegardées"

#########################################################
# 12. FTP (vsftpd)
#########################################################

if systemctl is-active --quiet vsftpd; then
    log "📁 Sauvegarde de vsftpd..."
    
    mkdir -p "$BACKUP_DIR/ftp"
    cp /etc/vsftpd.conf "$BACKUP_DIR/ftp/" 2>/dev/null
    cp /etc/vsftpd.userlist "$BACKUP_DIR/ftp/" 2>/dev/null || true
    
    log "✅ vsftpd sauvegardé"
fi

#########################################################
# 13. PM2 (n8n)
#########################################################

if command -v pm2 &> /dev/null; then
    log "📦 Sauvegarde PM2..."
    
    mkdir -p "$BACKUP_DIR/pm2"
    pm2 save 2>/dev/null || true
    cp -r /root/.pm2 "$BACKUP_DIR/pm2/" 2>/dev/null || true
    
    log "✅ PM2 sauvegardé"
fi

#########################################################
# 14. CERTIFICATS SSL
#########################################################

log "🔒 Sauvegarde des certificats SSL..."

mkdir -p "$BACKUP_DIR/ssl"

# Let's Encrypt
if [ -d "/etc/letsencrypt" ]; then
    tar -czf "$BACKUP_DIR/ssl/letsencrypt.tar.gz" -C /etc letsencrypt 2>/dev/null
fi

# Certificats auto-signés
cp -r /etc/ssl/certs "$BACKUP_DIR/ssl/certs_backup" 2>/dev/null || true
cp -r /etc/ssl/private "$BACKUP_DIR/ssl/private_backup" 2>/dev/null || true

log "✅ SSL sauvegardé"

#########################################################
# 15. PACKAGES INSTALLÉS
#########################################################

log "📦 Liste des paquets installés..."

dpkg --get-selections > "$BACKUP_DIR/packages_list.txt"
apt-mark showmanual > "$BACKUP_DIR/packages_manual.txt"

log "✅ Liste des paquets sauvegardée"

#########################################################
# 16. SCRIPTS PERSONNALISÉS
#########################################################

log "📝 Sauvegarde des scripts personnalisés..."

mkdir -p "$BACKUP_DIR/scripts"

cp /usr/local/bin/* "$BACKUP_DIR/scripts/" 2>/dev/null || true
cp /root/*.sh "$BACKUP_DIR/scripts/" 2>/dev/null || true

log "✅ Scripts sauvegardés"

#########################################################
# CRÉATION DE L'ARCHIVE FINALE
#########################################################

log ""
log "📦 Création de l'archive finale..."

cd "$BACKUP_ROOT"
tar -czf "full_backup_${DATE}.tar.gz" "full_backup_${DATE}" --remove-files

BACKUP_SIZE=$(du -sh "full_backup_${DATE}.tar.gz" | awk '{print $1}')

log "✅ Archive créée : full_backup_${DATE}.tar.gz"
log "📊 Taille : $BACKUP_SIZE"

#########################################################
# NETTOYAGE - Garder seulement les 5 derniers backups
#########################################################

log ""
log "🧹 Nettoyage des anciennes sauvegardes..."

cd "$BACKUP_ROOT"
ls -t full_backup_*.tar.gz 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true

BACKUP_COUNT=$(ls -1 full_backup_*.tar.gz 2>/dev/null | wc -l)
log "✅ Sauvegardes conservées : $BACKUP_COUNT"

#########################################################
# CRÉATION DU SCRIPT DE RESTAURATION
#########################################################

log ""
log "📝 Création du script de restauration..."

cat > "$BACKUP_ROOT/restore_backup.sh" << 'RESTORE_EOF'
#!/bin/bash

#########################################################
# Script de Restauration du Serveur
# ATTENTION : À utiliser avec précaution !
#########################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Ce script doit être exécuté en root${NC}"
    exit 1
fi

echo -e "${RED}========================================${NC}"
echo -e "${RED}⚠️  RESTAURATION DU SERVEUR${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}Ce script va restaurer une sauvegarde complète.${NC}"
echo -e "${YELLOW}Cela écrasera les configurations actuelles !${NC}"
echo ""

# Lister les backups disponibles
echo "Backups disponibles :"
echo ""
ls -lh /root/backups/full_backup_*.tar.gz 2>/dev/null || echo "Aucun backup trouvé"
echo ""

read -p "Entrez le nom du fichier de backup à restaurer (ex: full_backup_20260327_203000.tar.gz) : " BACKUP_FILE

if [ ! -f "/root/backups/$BACKUP_FILE" ]; then
    echo -e "${RED}❌ Fichier non trouvé : /root/backups/$BACKUP_FILE${NC}"
    exit 1
fi

echo ""
echo -e "${RED}⚠️  DERNIÈRE CHANCE !${NC}"
echo -e "Vous allez restaurer : ${GREEN}$BACKUP_FILE${NC}"
echo ""
read -p "Êtes-vous ABSOLUMENT SÛR ? Tapez 'OUI' en majuscules pour continuer : " CONFIRM

if [ "$CONFIRM" != "OUI" ]; then
    echo "Restauration annulée."
    exit 0
fi

echo ""
echo "🚀 Début de la restauration..."
echo ""

# Extraire le backup
cd /root/backups
RESTORE_DIR=$(basename "$BACKUP_FILE" .tar.gz)
tar -xzf "$BACKUP_FILE"

cd "$RESTORE_DIR"

echo "📋 Contenu du backup :"
ls -la
echo ""

# Arrêter les services
echo "⏸️  Arrêt des services..."
systemctl stop nginx 2>/dev/null || true
systemctl stop mysql 2>/dev/null || true
systemctl stop mariadb 2>/dev/null || true
pm2 stop all 2>/dev/null || true
systemctl stop ollama 2>/dev/null || true
systemctl stop open-webui 2>/dev/null || true

echo ""
echo "📝 ÉTAPES DE RESTAURATION MANUELLE :"
echo ""
echo "1. Bases de données :"
echo "   cd $PWD/databases"
echo "   gunzip -c mysql_all_databases.sql.gz | mysql"
echo ""
echo "2. Sites web :"
echo "   tar -xzf websites/www.tar.gz -C /var/www/"
echo ""
echo "3. Nginx :"
echo "   tar -xzf nginx.tar.gz -C /etc/"
echo "   systemctl restart nginx"
echo ""
echo "4. n8n :"
echo "   tar -xzf n8n/n8n_data.tar.gz -C /root/"
echo "   pm2 restart n8n"
echo ""
echo "5. Ollama :"
echo "   systemctl stop ollama"
echo "   tar -xzf ollama/ollama_models.tar.gz -C /usr/share/ollama/"
echo "   systemctl start ollama"
echo ""
echo "6. Open WebUI :"
echo "   systemctl stop open-webui"
echo "   tar -xzf open-webui/open-webui_data.tar.gz -C /opt/"
echo "   systemctl start open-webui"
echo ""
echo -e "${GREEN}✅ Extraction terminée${NC}"
echo -e "${YELLOW}⚠️  Suivez les étapes ci-dessus pour restaurer manuellement${NC}"

RESTORE_EOF

chmod +x "$BACKUP_ROOT/restore_backup.sh"

log "✅ Script de restauration créé : $BACKUP_ROOT/restore_backup.sh"

#########################################################
# RÉSUMÉ FINAL
#########################################################

clear
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ SAUVEGARDE TERMINÉE !${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${BLUE}📦 INFORMATIONS DE SAUVEGARDE${NC}"
echo ""
echo -e "  Fichier       : ${GREEN}$BACKUP_ROOT/full_backup_${DATE}.tar.gz${NC}"
echo -e "  Taille        : ${GREEN}$BACKUP_SIZE${NC}"
echo -e "  Date          : ${GREEN}$(date)${NC}"
echo -e "  Log           : ${GREEN}$BACKUP_DIR/backup.log${NC}"
echo ""

echo -e "${BLUE}📋 CONTENU DE LA SAUVEGARDE${NC}"
echo ""
echo "  ✅ Configuration système"
echo "  ✅ Nginx (tous les sites)"
echo "  ✅ Bases de données (MySQL/MariaDB)"
echo "  ✅ Sites web (/var/www/html)"
echo "  ✅ PHP (toutes versions)"
echo "  ✅ n8n (workflows + config)"
echo "  ✅ Ollama (modèles + config)"
echo "  ✅ Open WebUI (données + config)"
echo "  ✅ Utilisateurs et permissions"
echo "  ✅ SSH et pare-feu"
echo "  ✅ Tâches planifiées (cron)"
echo "  ✅ FTP (vsftpd)"
echo "  ✅ PM2"
echo "  ✅ Certificats SSL"
echo "  ✅ Scripts personnalisés"
echo ""

echo -e "${BLUE}🔧 RESTAURATION${NC}"
echo ""
echo -e "  Pour restaurer : ${GREEN}$BACKUP_ROOT/restore_backup.sh${NC}"
echo ""

echo -e "${BLUE}💾 BACKUPS CONSERVÉS${NC}"
echo ""
ls -lh "$BACKUP_ROOT"/full_backup_*.tar.gz 2>/dev/null || echo "Aucun"
echo ""

echo -e "${YELLOW}💡 RECOMMANDATIONS${NC}"
echo ""
echo "  1. Téléchargez cette sauvegarde sur votre PC"
echo "  2. Stockez-la dans un endroit sûr (cloud, disque externe)"
echo "  3. Testez la restauration sur un serveur de test"
echo "  4. Planifiez des backups réguliers (voir ci-dessous)"
echo ""

echo -e "${GREEN}🎉 Votre serveur est sauvegardé !${NC}"
echo ""
