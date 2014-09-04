#!/usr/bin/env bash

apt-get update
apt-get install -y postgresql redis-server

# postgresql
cp -f /vagrant/config/vagrant/postgresql.conf /etc/postgresql/9.3/main/postgresql.conf
cp -f /vagrant/config/vagrant/pg_hba.conf /etc/postgresql/9.3/main/pg_hba.conf
service postgresql restart
sudo -u postgres psql -c "ALTER ROLE postgres WITH PASSWORD 'postgres'"
sudo -u postgres createdb toshi_test
sudo -u postgres createdb toshi_development

# redis
cp -f /vagrant/config/vagrant/redis.conf /etc/redis/redis.conf
service redis-server restart
