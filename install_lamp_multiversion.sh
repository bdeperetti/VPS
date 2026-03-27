#!/bin/bash

#########################################################
# Installation LAMP Multi-Versions + FTP
# PHP 7.4, 8.0, 8.1, 8.2, 8.3, 8.4
# MySQL 8.0 + MariaDB 10.11 + MariaDB 11.4
# Pour VPS OVH Ubuntu 24.04
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
echo -e "${GREEN}Installation LAMP Multi-Versions${NC}"
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

#########################################################
# INSTALLATION MULTI-VERSIONS PHP
#########################################################

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Installation MULTI-VERSIONS PHP${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Ajouter le dépôt PPA Ondřej Surý
echo -e "${YELLOW}📦 Ajout du dépôt PHP multi-versions...${NC}"
apt install -y software-properties-common
add-apt-repository ppa:ondrej/php -y
apt update

# Liste des versions PHP à installer
PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3" "8.4")

echo ""
echo -e "${CYAN}Versions PHP qui seront installées :${NC}"
for version in "${PHP_VERSIONS[@]}"; do
    echo -e "  • PHP ${version}"
done
echo ""

read -p "Voulez-vous installer TOUTES ces versions ? [Y/n]: " INSTALL_ALL_PHP
INSTALL_ALL_PHP=${INSTALL_ALL_PHP:-Y}

if [[ ! $INSTALL_ALL_PHP =~ ^[Yy]$ ]]; then
    echo ""
    echo "Sélectionnez les versions à installer (séparées par des espaces):"
    echo "Ex: 7.4 8.1 8.3"
    read -p "Versions : " SELECTED_VERSIONS
    PHP_VERSIONS=($SELECTED_VERSIONS)
fi

# Installation de chaque version PHP
for version in "${PHP_VERSIONS[@]}"; do
    echo ""
    echo -e "${YELLOW}🐘 Installation PHP ${version}...${NC}"
    
    apt install -y \
        php${version} \
        php${version}-cli \
        php${version}-fpm \
        php${version}-mysql \
        php${version}-curl \
        php${version}-gd \
        php${version}-mbstring \
        php${version}-xml \
        php${version}-xmlrpc \
        php${version}-zip \
        php${version}-intl \
        php${version}-bcmath \
        php${version}-soap \
        php${version}-opcache \
        php${version}-readline
    
    # Extensions supplémentaires (pas dispo pour toutes versions)
    apt install -y php${version}-imagick 2>/dev/null || true
    apt install -y php${version}-redis 2>/dev/null || true
    
    # Configuration PHP
    if [ -f "/etc/php/${version}/fpm/php.ini" ]; then
        cp /etc/php/${version}/fpm/php.ini /etc/php/${version}/fpm/php.ini.backup
        
        sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 64M/' /etc/php/${version}/fpm/php.ini
        sed -i 's/post_max_size = 8M/post_max_size = 64M/' /etc/php/${version}/fpm/php.ini
        sed -i 's/memory_limit = 128M/memory_limit = 256M/' /etc/php/${version}/fpm/php.ini
        sed -i 's/max_execution_time = 30/max_execution_time = 300/' /etc/php/${version}/fpm/php.ini
        sed -i 's/;date.timezone =/date.timezone = Europe\/Paris/' /etc/php/${version}/fpm/php.ini
        sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/${version}/fpm/php.ini
    fi
    
    # Activer et démarrer PHP-FPM
    systemctl enable php${version}-fpm
    systemctl start php${version}-fpm
    
    echo -e "${GREEN}✅ PHP ${version} installé${NC}"
done

# Définir la version par défaut
echo ""
echo -e "${YELLOW}🔧 Configuration de la version PHP par défaut...${NC}"
echo "Versions installées :"
for version in "${PHP_VERSIONS[@]}"; do
    echo "  • PHP ${version}"
done
echo ""

# Utiliser la dernière version comme défaut
DEFAULT_PHP="${PHP_VERSIONS[-1]}"
read -p "Version PHP par défaut [${DEFAULT_PHP}]: " CHOSEN_DEFAULT
CHOSEN_DEFAULT=${CHOSEN_DEFAULT:-$DEFAULT_PHP}

update-alternatives --set php /usr/bin/php${CHOSEN_DEFAULT}
update-alternatives --set phar /usr/bin/phar${CHOSEN_DEFAULT}
update-alternatives --set phar.phar /usr/bin/phar.phar${CHOSEN_DEFAULT}

echo -e "${GREEN}✅ PHP ${CHOSEN_DEFAULT} défini par défaut${NC}"
echo ""
php -v

#########################################################
# INSTALLATION MULTI-VERSIONS MySQL/MariaDB
#########################################################

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Installation MULTI-VERSIONS MySQL/MariaDB${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${CYAN}⚠️  IMPORTANT :${NC}"
echo "Vous pouvez installer plusieurs bases de données sur des ports différents :"
echo "  • MySQL 8.0      (port 3306 par défaut)"
echo "  • MariaDB 10.11  (port 3307)"
echo "  • MariaDB 11.4   (port 3308)"
echo ""

read -p "Voulez-vous installer MySQL 8.0 ? [Y/n]: " INSTALL_MYSQL
INSTALL_MYSQL=${INSTALL_MYSQL:-Y}

read -p "Voulez-vous installer MariaDB 10.11 ? [y/N]: " INSTALL_MARIADB_10
INSTALL_MARIADB_10=${INSTALL_MARIADB_10:-N}

read -p "Voulez-vous installer MariaDB 11.4 ? [y/N]: " INSTALL_MARIADB_11
INSTALL_MARIADB_11=${INSTALL_MARIADB_11:-N}

# Fichier pour stocker les credentials
CREDS_FILE="/root/database_credentials.txt"
echo "=== IDENTIFIANTS BASES DE DONNÉES ===" > $CREDS_FILE
echo "Date: $(date)" >> $CREDS_FILE
echo "" >> $CREDS_FILE

#########################################################
# INSTALLATION MySQL 8.0
#########################################################

if [[ $INSTALL_MYSQL =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}🗄️  Installation MySQL 8.0...${NC}"
    
    apt install -y mysql-server mysql-client
    
    systemctl start mysql
    systemctl enable mysql
    
    # Générer mot de passe sécurisé
    MYSQL_ROOT_PASSWORD=$(openssl rand -base64 16)
    
    # Configuration sécurisée
    mysql --user=root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    
    # Créer fichier de config
    cat > /root/.my.cnf << EOF
[client]
user=root
password=$MYSQL_ROOT_PASSWORD
EOF
    chmod 600 /root/.my.cnf
    
    # Sauvegarder credentials
    echo "MySQL 8.0:" >> $CREDS_FILE
    echo "  Port: 3306" >> $CREDS_FILE
    echo "  User: root" >> $CREDS_FILE
    echo "  Password: $MYSQL_ROOT_PASSWORD" >> $CREDS_FILE
    echo "  Config: /root/.my.cnf" >> $CREDS_FILE
    echo "" >> $CREDS_FILE
    
    echo -e "${GREEN}✅ MySQL 8.0 installé (port 3306)${NC}"
    mysql --version
fi

#########################################################
# INSTALLATION MariaDB 10.11
#########################################################

if [[ $INSTALL_MARIADB_10 =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}🗄️  Installation MariaDB 10.11...${NC}"
    
    # Ajouter le dépôt MariaDB
    curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash -s -- --mariadb-server-version="mariadb-10.11"
    
    # Installer sur port alternatif
    apt install -y mariadb-server-10.11 mariadb-client-10.11
    
    # Configuration port alternatif
    cat > /etc/mysql/mariadb.conf.d/60-port-3307.cnf << 'EOF'
[mysqld]
port = 3307
socket = /var/run/mysqld/mysqld-3307.sock

[client]
port = 3307
socket = /var/run/mysqld/mysqld-3307.sock
EOF
    
    # Créer répertoire socket
    mkdir -p /var/run/mysqld
    chown mysql:mysql /var/run/mysqld
    
    systemctl restart mariadb
    systemctl enable mariadb
    
    # Générer mot de passe
    MARIADB10_ROOT_PASSWORD=$(openssl rand -base64 16)
    
    # Configuration sécurisée
    mysql -P 3307 --protocol=tcp --user=root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MARIADB10_ROOT_PASSWORD';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    
    # Créer fichier config
    cat > /root/.my-mariadb10.cnf << EOF
[client]
port=3307
user=root
password=$MARIADB10_ROOT_PASSWORD
EOF
    chmod 600 /root/.my-mariadb10.cnf
    
    # Sauvegarder credentials
    echo "MariaDB 10.11:" >> $CREDS_FILE
    echo "  Port: 3307" >> $CREDS_FILE
    echo "  User: root" >> $CREDS_FILE
    echo "  Password: $MARIADB10_ROOT_PASSWORD" >> $CREDS_FILE
    echo "  Config: /root/.my-mariadb10.cnf" >> $CREDS_FILE
    echo "  Connexion: mysql --defaults-file=/root/.my-mariadb10.cnf" >> $CREDS_FILE
    echo "" >> $CREDS_FILE
    
    echo -e "${GREEN}✅ MariaDB 10.11 installé (port 3307)${NC}"
fi

#########################################################
# INSTALLATION MariaDB 11.4
#########################################################

if [[ $INSTALL_MARIADB_11 =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}🗄️  Installation MariaDB 11.4...${NC}"
    echo -e "${RED}⚠️  Note: MariaDB 11.4 avec port alternatif nécessite configuration avancée${NC}"
    echo "Pour l'instant, installation annulée pour éviter les conflits."
    echo "Utilisez Docker pour MariaDB 11.4 si nécessaire."
fi

chmod 600 $CREDS_FILE

#########################################################
# INSTALLATION Nginx
#########################################################

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Installation Nginx${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "${YELLOW}🌐 Installation Nginx...${NC}"
apt install -y nginx

# Configuration Nginx multi-PHP
cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.php index.html index.htm;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }

    # PHP par défaut (utilise la version par défaut du système)
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

nginx -t
systemctl restart nginx
systemctl enable nginx

echo -e "${GREEN}✅ Nginx installé${NC}"

# Ouvrir ports
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

#########################################################
# INSTALLATION vsftpd
#########################################################

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Installation FTP (vsftpd)${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "${YELLOW}📁 Installation vsftpd...${NC}"
apt install -y vsftpd

cp /etc/vsftpd.conf /etc/vsftpd.conf.backup

cat > /etc/vsftpd.conf << 'EOF'
listen=NO
listen_ipv6=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
xferlog_std_format=YES
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
ssl_enable=NO
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=50000
userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO
utf8_filesystem=YES
EOF

mkdir -p /var/run/vsftpd/empty
touch /etc/vsftpd.userlist

systemctl restart vsftpd
systemctl enable vsftpd

echo -e "${GREEN}✅ vsftpd installé${NC}"

ufw allow 20/tcp comment 'FTP Data'
ufw allow 21/tcp comment 'FTP Control'
ufw allow 40000:50000/tcp comment 'FTP Passive'

#########################################################
# PAGE DE TEST PHP MULTI-VERSIONS
#########################################################

echo -e "${YELLOW}📄 Création page de test multi-versions...${NC}"

cat > /var/www/html/index.php << 'PHPEOF'
<?php
// Fonction pour tester la connexion à une base de données
function testDBConnection($host, $port, $user, $pass, $name) {
    try {
        $pdo = new PDO("mysql:host=$host;port=$port", $user, $pass);
        $version = $pdo->query('SELECT VERSION()')->fetchColumn();
        return ['status' => 'success', 'version' => $version];
    } catch (PDOException $e) {
        return ['status' => 'error', 'message' => $e->getMessage()];
    }
}

// Détecter les versions PHP installées
$phpVersions = [];
foreach (glob('/usr/bin/php[0-9].[0-9]') as $bin) {
    if (preg_match('/php(\d+\.\d+)$/', $bin, $matches)) {
        $phpVersions[] = $matches[1];
    }
}

// Tester les bases de données
$databases = [];

// MySQL 8.0
if (file_exists('/root/.my.cnf')) {
    $databases['MySQL 8.0'] = testDBConnection('localhost', 3306, 'root', '', 'MySQL 8.0');
}

// MariaDB 10.11
if (file_exists('/root/.my-mariadb10.cnf')) {
    $databases['MariaDB 10.11'] = testDBConnection('localhost', 3307, 'root', '', 'MariaDB 10.11');
}
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Serveur LAMP Multi-Versions - 2P FOOD</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            padding: 40px;
            max-width: 1200px;
            margin: 0 auto;
        }
        h1 {
            color: #667eea;
            margin-bottom: 10px;
            font-size: 2.5em;
        }
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            font-size: 1.1em;
        }
        .section {
            margin: 30px 0;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 10px;
        }
        .section h2 {
            color: #333;
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 2px solid #667eea;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px;
            margin-top: 15px;
        }
        .item {
            background: white;
            padding: 15px;
            border-radius: 8px;
            border-left: 4px solid #667eea;
        }
        .item h3 {
            color: #333;
            font-size: 1em;
            margin-bottom: 8px;
        }
        .version {
            color: #28a745;
            font-weight: bold;
            font-size: 1.1em;
        }
        .error {
            color: #dc3545;
            font-size: 0.9em;
        }
        .badge {
            display: inline-block;
            padding: 5px 10px;
            background: #667eea;
            color: white;
            border-radius: 5px;
            font-size: 0.85em;
            margin: 5px 5px 5px 0;
        }
        .badge.default {
            background: #28a745;
        }
        .links {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 2px solid #eee;
        }
        .links a {
            display: inline-block;
            margin: 5px 10px 5px 0;
            padding: 10px 20px;
            background: #667eea;
            color: white;
            text-decoration: none;
            border-radius: 5px;
            transition: background 0.3s;
        }
        .links a:hover {
            background: #764ba2;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        table th, table td {
            padding: 10px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        table th {
            background: #667eea;
            color: white;
        }
        .footer {
            margin-top: 30px;
            text-align: center;
            color: #999;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>✅ Serveur Multi-Versions opérationnel</h1>
        <p class="subtitle">LAMP Stack avec versions multiples PHP et Bases de données</p>
        
        <!-- PHP Versions -->
        <div class="section">
            <h2>🐘 Versions PHP Installées</h2>
            <div class="grid">
                <?php foreach ($phpVersions as $ver): ?>
                <div class="item">
                    <h3>PHP <?php echo $ver; ?></h3>
                    <p class="version">
                        <?php
                        $output = shell_exec("/usr/bin/php$ver -v");
                        preg_match('/PHP ([\d.]+)/', $output, $matches);
                        echo $matches[1] ?? $ver;
                        ?>
                    </p>
                    <?php if ($ver == phpversion()): ?>
                    <span class="badge default">Par défaut</span>
                    <?php endif; ?>
                </div>
                <?php endforeach; ?>
            </div>
            <p style="margin-top:15px;color:#666;font-size:0.9em;">
                Version active actuellement : <strong>PHP <?php echo phpversion(); ?></strong>
            </p>
        </div>

        <!-- Databases -->
        <div class="section">
            <h2>🗄️ Bases de Données</h2>
            <table>
                <thead>
                    <tr>
                        <th>Base de données</th>
                        <th>Port</th>
                        <th>Version</th>
                        <th>Statut</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($databases as $name => $info): ?>
                    <tr>
                        <td><strong><?php echo $name; ?></strong></td>
                        <td><?php echo strpos($name, 'MySQL') !== false ? '3306' : '3307'; ?></td>
                        <td><?php echo $info['status'] == 'success' ? $info['version'] : '-'; ?></td>
                        <td>
                            <?php if ($info['status'] == 'success'): ?>
                                <span style="color:#28a745;">✓ Connecté</span>
                            <?php else: ?>
                                <span class="error">✗ Erreur</span>
                            <?php endif; ?>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>

        <!-- Server Info -->
        <div class="section">
            <h2>🌐 Informations Serveur</h2>
            <div class="grid">
                <div class="item">
                    <h3>Serveur Web</h3>
                    <p class="version"><?php echo $_SERVER['SERVER_SOFTWARE']; ?></p>
                </div>
                <div class="item">
                    <h3>IP Serveur</h3>
                    <p class="version"><?php echo $_SERVER['SERVER_ADDR']; ?></p>
                </div>
                <div class="item">
                    <h3>Hostname</h3>
                    <p class="version"><?php echo gethostname(); ?></p>
                </div>
                <div class="item">
                    <h3>FTP</h3>
                    <p class="version">vsftpd actif</p>
                </div>
            </div>
        </div>

        <!-- Quick Links -->
        <div class="links">
            <a href="info.php" target="_blank">📊 PHPInfo</a>
            <a href="/phpmyadmin" target="_blank">🗄️ phpMyAdmin</a>
            <a href="https://<?php echo $_SERVER['HTTP_HOST']; ?>:10000" target="_blank">⚙️ Webmin</a>
            <a href="http://<?php echo $_SERVER['HTTP_HOST']; ?>:6080/vnc.html" target="_blank">🖥️ noVNC</a>
        </div>

        <div class="footer">
            <p>2P FOOD - VPS Ubuntu 24.04 LTS - LAMP Multi-Versions</p>
            <p>Bertrand - Consultant Digital & IA</p>
        </div>
    </div>
</body>
</html>
PHPEOF

cat > /var/www/html/info.php << 'EOF'
<?php phpinfo(); ?>
EOF

chmod 644 /var/www/html/index.php
chmod 644 /var/www/html/info.php

#########################################################
# SCRIPT DE CHANGEMENT DE VERSION PHP
#########################################################

cat > /usr/local/bin/switch-php << 'EOF'
#!/bin/bash
# Script pour changer la version PHP par défaut

if [ "$#" -ne 1 ]; then
    echo "Usage: switch-php <version>"
    echo "Exemple: switch-php 8.1"
    echo ""
    echo "Versions disponibles:"
    ls /usr/bin/php[0-9].[0-9] 2>/dev/null | sed 's/.*php/  - /'
    exit 1
fi

VERSION=$1

if [ ! -f "/usr/bin/php${VERSION}" ]; then
    echo "Erreur: PHP ${VERSION} n'est pas installé"
    exit 1
fi

update-alternatives --set php /usr/bin/php${VERSION}
update-alternatives --set phar /usr/bin/phar${VERSION} 2>/dev/null || true
update-alternatives --set phar.phar /usr/bin/phar.phar${VERSION} 2>/dev/null || true

echo "✅ PHP ${VERSION} est maintenant la version par défaut"
php -v
EOF

chmod +x /usr/local/bin/switch-php

#########################################################
# INSTALLATION phpMyAdmin
#########################################################

echo ""
read -p "Voulez-vous installer phpMyAdmin ? [Y/n]: " INSTALL_PMA
INSTALL_PMA=${INSTALL_PMA:-Y}

if [[ $INSTALL_PMA =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}📊 Installation phpMyAdmin...${NC}"
    
    # Récupérer le mot de passe MySQL root
    if [ -f "/root/.my.cnf" ]; then
        MYSQL_PASS=$(grep password /root/.my.cnf | cut -d'=' -f2)
    else
        MYSQL_PASS=""
    fi
    
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/app-password-confirm password $MYSQL_PASS" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/admin-pass password $MYSQL_PASS" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/mysql/app-pass password $MYSQL_PASS" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect nginx" | debconf-set-selections
    
    apt install -y phpmyadmin php-mbstring php-zip php-gd php-json php-curl
    
    ln -sf /usr/share/phpmyadmin /var/www/html/phpmyadmin
    
    echo -e "${GREEN}✅ phpMyAdmin installé${NC}"
fi

#########################################################
# RÉSUMÉ FINAL
#########################################################

clear
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Installation Multi-Versions terminée !${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${BLUE}📋 VERSIONS PHP INSTALLÉES${NC}"
for version in "${PHP_VERSIONS[@]}"; do
    echo -e "  • PHP ${version} ✓"
done
echo ""
echo -e "  Version par défaut : ${GREEN}PHP $(php -v | head -1 | awk '{print $2}')${NC}"
echo -e "  Changer de version : ${CYAN}switch-php 8.1${NC}"
echo ""

echo -e "${BLUE}📋 BASES DE DONNÉES${NC}"
if [[ $INSTALL_MYSQL =~ ^[Yy]$ ]]; then
    echo -e "  • MySQL 8.0 (port 3306) ✓"
fi
if [[ $INSTALL_MARIADB_10 =~ ^[Yy]$ ]]; then
    echo -e "  • MariaDB 10.11 (port 3307) ✓"
fi
echo ""

echo -e "${BLUE}🌍 ACCÈS WEB${NC}"
echo -e "  Page d'accueil : ${GREEN}http://137.74.12.199/${NC}"
echo -e "  PHPInfo        : ${GREEN}http://137.74.12.199/info.php${NC}"
if [[ $INSTALL_PMA =~ ^[Yy]$ ]]; then
    echo -e "  phpMyAdmin     : ${GREEN}http://137.74.12.199/phpmyadmin${NC}"
fi
echo -e "  Webmin         : ${GREEN}https://137.74.12.199:10000${NC}"
echo -e "  noVNC          : ${GREEN}http://137.74.12.199:6080/vnc.html${NC}"
echo ""

echo -e "${BLUE}📁 SERVEUR FTP${NC}"
echo -e "  Serveur : ${GREEN}ftp://137.74.12.199${NC}"
echo -e "  Port    : ${GREEN}21${NC}"
echo ""

echo -e "${BLUE}🔑 IDENTIFIANTS${NC}"
echo -e "  Fichier : ${GREEN}$CREDS_FILE${NC}"
cat $CREDS_FILE
echo ""

echo -e "${YELLOW}📝 COMMANDES UTILES${NC}"
echo ""
echo -e "  Changer version PHP : ${GREEN}switch-php 8.2${NC}"
echo -e "  MySQL 8.0           : ${GREEN}mysql${NC}"
if [[ $INSTALL_MARIADB_10 =~ ^[Yy]$ ]]; then
    echo -e "  MariaDB 10.11       : ${GREEN}mysql --defaults-file=/root/.my-mariadb10.cnf${NC}"
fi
echo -e "  Ajouter user FTP    : ${GREEN}adduser nom && echo 'nom' >> /etc/vsftpd.userlist${NC}"
echo ""

echo -e "${GREEN}🎉 Votre serveur multi-versions est prêt !${NC}"
echo ""
