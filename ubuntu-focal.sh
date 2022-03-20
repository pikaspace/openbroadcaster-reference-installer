#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root."
  exit
fi

echo "
This script is designed to be run on a fresh Ubuntu Server 20.04 installation.
Running on an existing installation or different operating system / release may
provide unexpected results.
"

read -p "Are you sure you want to do this? Type install: " confirmation

if [ "$confirmation" != "install" ]; then
  echo "
Okay, quitting.
"
  exit;
fi

echo  "What is the FQDN? I.e., ob.example.com. Do not include http://, https://, or trailing slash."
read fqdn

echo  "What email address should OpenBroadcaster emails come from?"
read email

echo "Which email address to use for Let's Encrypt notifications?"
read certemail

echo "Here we go!
"

add-apt-repository ppa:ondrej/php -y
add-apt-repository ppa:ondrej/nginx -y
apt update
apt -y upgrade

apt -y install nginx php8.0 php8.0-fpm php8.0-curl php8.0-gd php8.0-mbstring php8.0-mysql php8.0-xml php8.0-imagick php8.0-zip php8.0-bcmath php8.0-intl

ufw allow http
ufw allow https
snap install --classic certbot
rm /etc/nginx/sites-enabled/default
rm /etc/php/8.0/fpm/pool.d/www.conf

apt -y install mariadb-server
mysql_secure_installation << EOF

n
y
y
y
y
EOF

echo "server {
  server_name $fqdn;

  root /home/ob/www;
  index index.php;

  location ~ /\.(?!well-known).* {
    deny all;
    return 404;
  }

  location / {
    try_files \$uri \$uri/ =404;
  }

  location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/var/run/php/php8.0-ob-fpm.sock;
  }
}" > /etc/nginx/sites-available/ob

ln -s /etc/nginx/sites-available/ob /etc/nginx/sites-enabled

echo "
[ob]
user = ob
group = ob
listen = /var/run/php/php8.0-ob-fpm.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
" > /etc/php/8.0/fpm/pool.d/ob.conf

useradd -m --shell /bin/bash ob
mkdir /home/ob/www/

systemctl restart php8.0-fpm
systemctl restart nginx

certbot --nginx -d $fqdn --agree-tos --no-eff-email -m $certemail

cd /home/ob/www/
git clone https://github.com/openbroadcaster/server.git ./
git checkout testing

sqlpass=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 32 | head -n 1)
obpass=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 32 | head -n 1)
obhash=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 32 | head -n 1)

mysql -e "CREATE DATABASE ob"
mysql -e "CREATE USER ob@localhost IDENTIFIED BY '$sqlpass'"
mysql -e "GRANT ALL PRIVILEGES ON ob.* TO ob@localhost"
mysql ob < /home/ob/www/db/dbclean.sql

echo "<?php
define('OB_DB_USER','ob');
define('OB_DB_PASS','$sqlpass');
define('OB_DB_HOST','localhost');
define('OB_DB_NAME','ob');
define('OB_HASH_SALT','$obhash');
define('OB_MEDIA','/home/ob/files/media');
define('OB_MEDIA_UPLOADS','/home/ob/files/media/uploads');
define('OB_MEDIA_ARCHIVE','/home/ob/files/media/archive');
define('OB_CACHE','/home/ob/files/cache');
define('OB_SITE','https://$fqdn/'); // where do you access OB?
define('OB_EMAIL_REPLY','$email'); // emails to users come from this address
define('OB_EMAIL_FROM','OpenBroadcaster'); // emails to users come from this name
" > /home/ob/www/config.php

mkdir /home/ob/files
mkdir /home/ob/files/media
mkdir /home/ob/files/media/uploads
mkdir /home/ob/files/media/archive
mkdir /home/ob/files/cache
mkdir /home/ob/www/assets
mkdir /home/ob/www/assets/uploads
chown -R ob:ob /home/ob/files
chown -R ob:ob /home/ob/www

sudo -u ob php /home/ob/www/updates/index.php force-update
sudo -u ob php /home/ob/www/tools/password_change.php admin $obpass

echo
echo http://$fqdn/
echo Username: admin
echo Password: $obhash
echo

cd /home/ob/www