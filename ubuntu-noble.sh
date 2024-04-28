#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root."
  exit
fi

echo "
This script is designed to be run on a fresh Ubuntu Server 24.04 installation.
Running on an existing installation or different operating system / release may
provide unexpected results.

This script is in an alpha state and does not validate user inputs or
command exit codes for success/failure. Things might break.
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

https=invalid
while [ "$https" != "yes" -a "$https" != "no" ]; do
  if [ "$https" == "yes" ]; then
    https=1
  elif [ "$https" == "no" ]; then
    https=0
  else
    echo "Do you want to use HTTPs (with Let's Encrypt)? (yes or no)"
    read https
  fi;
done

if [ "$https" == "yes" ]; then
  echo "Which email address to use for Let's Encrypt notifications?"
  read certemail
fi;

echo "Here we go!
"

cd /root

add-apt-repository ppa:ondrej/php -y
add-apt-repository ppa:ondrej/nginx -y
apt update
apt -y upgrade

apt -y install npm nginx php8.3 php8.3-fpm php8.3-curl php8.3-gd php8.3-mbstring php8.3-mysql php8.3-xml php8.3-imagick php8.3-zip php8.3-bcmath php8.3-intl

php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php
php -r "unlink('composer-setup.php');"
mv composer.phar /usr/local/bin/composer

apt -y install ffmpeg vorbis-tools festival imagemagick
ln -s /usr/bin/ffmpeg /usr/local/bin/avconv
ln -s /usr/bin/ffprobe /usr/local/bin/avprobe

ufw allow http

if [ "$https" == "yes" ]; then
  ufw allow https
  snap install --classic certbot
fi;

systemctl enable nginx
rm /etc/nginx/sites-enabled/default
rm /etc/php/8.3/fpm/pool.d/www.conf

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
  
  client_max_body_size 1024m;

  location ~ /\.(?!well-known).* {
    deny all;
    return 404;
  }

  location / {
    try_files \$uri \$uri/ =404;
  }

  location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/var/run/php/php8.3-ob-fpm.sock;
  }
}" > /etc/nginx/sites-available/ob

ln -s /etc/nginx/sites-available/ob /etc/nginx/sites-enabled

echo "
[ob]
user = ob
group = ob
listen = /var/run/php/php8.3-ob-fpm.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
php_value[upload_max_filesize] = 1024M
php_value[post_max_size] = 1024M
" > /etc/php/8.3/fpm/pool.d/ob.conf

useradd -m --shell /bin/bash ob
chgrp www-data /home/ob
mkdir /home/ob/www/

systemctl restart php8.3-fpm
systemctl restart nginx

if [ "$https" == "yes" ]; then
  certbot --nginx -d $fqdn --agree-tos --no-eff-email -m $certemail
fi

cd /home/ob/www/
git clone https://github.com/openbroadcaster/observer.git ./
git checkout 5.3

/usr/local/bin/composer install -n
npm install

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
define('OB_THUMBNAILS', '/home/ob/files/thumbnails');
define('OB_EMAIL_REPLY','$email'); // emails to users come from this address
define('OB_EMAIL_FROM','OpenBroadcaster'); // emails to users come from this name
" > /home/ob/www/config.php

if [ "$https" == "yes" ]; then
  echo "define('OB_SITE','https://$fqdn/'); // where do you access OB?" >> /home/ob/www/config.php
else
  echo "define('OB_SITE','http://$fqdn/'); // where do you access OB?" >> /home/ob/www/config.php
fi

mkdir /home/ob/files
mkdir /home/ob/files/media
mkdir /home/ob/files/media/uploads
mkdir /home/ob/files/media/archive
mkdir /home/ob/files/cache
mkdir /home/ob/files/thumbnails
mkdir /home/ob/www/assets
mkdir /home/ob/www/assets/uploads
chown -R ob:ob /home/ob/files
chown -R ob:ob /home/ob/www

sudo -u ob /home/ob/www/tools/cli/ob updates run all
sudo -u ob /home/ob/www/tools/cli/ob passwd admin << EOF
$obpass
EOF

echo

if [ "$https" == "yes" ]; then
  echo https://$fqdn/
else
  echo http://$fqdn/
fi

echo Username: admin
echo Password: $obpass
echo

cd /home/ob/www
