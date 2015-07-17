#!/bin/bash
# get some basica vars for later
BASE=$(pwd)
IP=$(ifconfig eth0 | awk '/inet /{print substr($2,1)}')
NUM=$(( ( RANDOM % 100 )  + 1 ))
DOMAIN="proxy$NUM.uphreak.com"
# add opensips user with no shell
useradd -s /bin/false opensips
# install required deps and build tools
yum -y install vim-enhanced libcurl-devel ncurses-devel ruby glib2 glib2-devel xmlrpc-c-devel xmlrpc-c sqlite sqlite-devel pcre pcre-devel openssl openssl-devel
yum -y group install "Development Tools"
# clone required repos
cd /usr/local/src
git clone https://github.com/OpenSIPS/opensips.git
git clone https://github.com/sipwise/rtpengine.git
git clone https://github.com/ralight/sqlite3-pcre.git
# build opensips
cd opensips
cp Makefile.conf.template Makefile.conf
sed -i -e 's/include_modules?=/include_modules?= db_sqlite/g' Makefile.conf 
sed -i -e 's/PREFIX=\/usr\/local\//PREFIX=\/usr\/local\/opensips\//g' Makefile.conf
make all && make all install
# set up our sqlite database
cd scripts/sqlite
mkdir /var/db/opensips && chown opensips:opensips /var/db/opensips
chown -R opensips:opensips /var/db/opensips
sudo -u opensips sqlite3 /var/db/opensips/opensips < standard-create.sql
sudo -u opensips sqlite3 /var/db/opensips/opensips < dialog-create.sql
sudo -u opensips sqlite3 /var/db/opensips/opensips < domain-create.sql
sudo -u opensips sqlite3 /var/db/opensips/opensips < auth_db-create.sql
sudo -u opensips sqlite3 /var/db/opensips/opensips < usrloc-create.sql
sudo -u opensips sqlite3 /var/db/opensips/opensips < $BASE/scripts/create_translations_table.sqlite
# set up opensipsctlrc to use our sqlite database
sed -i -e 's/# DBENGINE=MYSQL/DBENGINE=SQLITE/g' /usr/local/opensips/etc/opensips/opensipsctlrc
sed -i -e 's/# DB_PATH="\/usr\/local\/etc\/opensips\/dbtext"/DB_PATH=\/var\/db\/opensips\/opensips/g' /usr/local/opensips/etc/opensips/opensipsctlrc
# add our ip to our domain table
/usr/local/opensips/sbin/opensipsctl domain add $IP:5060
/usr/local/opensips/sbin/opensipsctl domain add $DOMAIN:5060
/usr/local/opensips/sbin/opensipsctl domain add $DOMAIN
# build rtpengine daemon
cd /usr/local/src/rtpengine/daemon && make
mkdir /usr/local/rtpengine && cp rtpengine /usr/local/rtpengine/
# start rtpengine
/usr/local/rtpengine/rtpengine -p /var/run/rtpengine.pid --interface $IP --listen-ng $IP:60000 -m 50000 -M 55000 -E -L 3 &
# build sqlite pcre extension
cd /usr/local/src/sqlite3-pcre
make && make install
# configure federated opensips.var.rb
cd $BASE/core
cp opensips.var.rb.sample opensips.var.rb
# disable tls and ipv6
sed -i -e 's/enable_tls      = true/enable_tls      = false/g' opensips.var.rb
sed -i -e 's/enable_ipv6     = true/enable_ipv6      = false/g' opensips.var.rb
# set our listening IP address
sed -i -e "s/listen_ip       = 'xxx.xxx.xxx.xxx'/listen_ip      = '$IP'/g" opensips.var.rb
# set our modules directory
sed -i -e 's#/usr/local/lib64/opensips/modules/#/usr/local/opensips/lib64/opensips/modules/#g' opensips.var.rb
./build.rb && cp opensips.cfg /usr/local/opensips/etc/opensips/opensips.cfg
cd /usr/local/opensips && sbin/opensips &
sbin/opensipsctl add user$NUM@$DOMAIN ilikeopensips$NUM
sleep 5;
echo ""
echo ""
echo ""
echo "AOR     : user$NUM@$DOMAIN"
echo "PASSWORD: ilikeopensips$NUM"
echo "PROXY   : $IP"