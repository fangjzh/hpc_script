#!/bin/sh

source ./env.sh
. /etc/profile.d/xcat.sh
##



##################### add nightingale ################

### prometheus

filelist=(
prometheus-2.28.0.linux-amd64.tar.gz
n9e-server-5.0.0-rc6.tar.gz
n9e-agentd-5.0.0-rc8.tar.gz
)

for ifile in ${filelist[@]}
do
  if [ ! -e ${package_dir}/${ifile} ] ; then
  echo "${ifile} is not exist!!!"
  exit
fi
done

echo "installing prometheus ...."
echo "webport:9090"

mkdir -p /opt/prometheus
# wget https://s3-gz01.didistatic.com/n9e-pub/prome/prometheus-2.28.0.linux-amd64.tar.gz -O prometheus-2.28.0.linux-amd64.tar.gz
tar xf ${package_dir}/prometheus-2.28.0.linux-amd64.tar.gz
cp -far prometheus-2.28.0.linux-amd64/*  /opt/prometheus/

# service 
cat <<EOF >/etc/systemd/system/prometheus.service
[Unit]
Description="prometheus"
Documentation=https://prometheus.io/
After=network.target

[Service]
Type=simple

ExecStart=/opt/prometheus/prometheus  --config.file=/opt/prometheus/prometheus.yml --storage.tsdb.path=/opt/prometheus/data --web.enable-lifecycle --enable-feature=remote-write-receiver --query.lookback-delta=2m 

Restart=on-failure
RestartSecs=5s
SuccessExitStatus=0
LimitNOFILE=65536
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=prometheus


[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable prometheus
systemctl restart prometheus
sleep 8
#systemctl status prometheus

########################################
### nightingale 
echo "installing nightingle...."
echo "webport:8000 user:root  password:root.2020"
# 安装 notify.py 依赖 
# pip install bottle

# 3.安装n9e-server
mkdir -p /opt/n9e
cd /opt/n9e
# wget 116.85.64.82/n9e-server-5.0.0-rc6.tar.gz
tar zxf ${package_dir}/n9e-server-5.0.0-rc6.tar.gz
mysql -uroot -p'78g*tw23.ysq' < /opt/n9e/server/sql/n9e.sql

mysql -uroot -p'78g*tw23.ysq' -e"CREATE USER 'n9e'@'localhost' IDENTIFIED BY 'n9e123456';"
mysql -uroot -p'78g*tw23.ysq' -e"REVOKE ALL PRIVILEGES ON *.* FROM 'n9e'@'localhost';"
mysql -uroot -p'78g*tw23.ysq' -e"GRANT ALL PRIVILEGES ON n9e.* TO 'n9e'@'localhost' IDENTIFIED BY 'n9e123456';"
mysql -uroot -p'78g*tw23.ysq' -e"FLUSH PRIVILEGES"
perl -pi -e "s/root:1234/n9e:n9e123456/" /opt/n9e/server/etc/server.yml

perl -pi -e "s/DEBUG/INFO/" /opt/n9e/server/etc/server.yml

/bin/cp /opt/n9e/server/etc/service/n9e-server.service /etc/systemd/system/
perl -ni -e 'print; print"After=network.target mariadb.service prometheus.service\n" if $. == 2' /etc/systemd/system/n9e-server.service
## equal to this
# perl -pi -e 'print"After=network.target prometheus.service\n" if $. == 2' /etc/systemd/system/n9e-server.service
systemctl daemon-reload
systemctl enable n9e-server
systemctl restart n9e-server
##systemctl status n9e-server

## n9e agentd
mkdir -p /opt/n9e
cd /opt/n9e
tar zxf ${package_dir}/n9e-agentd-5.0.0-rc8.tar.gz

perl -pi -e "s/localhost/${sms_ip}/" /opt/n9e/agentd/etc/agentd.yaml
/bin/cp /opt/n9e/agentd/systemd/n9e-agentd.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable n9e-agentd
systemctl restart n9e-agentd
##systemctl status n9e-agentd

## add nightingale agent to compute node
mkdir -p /opt/repo/other
/bin/cp ${package_dir}/n9e-agentd-5.0.0-rc8.tar.gz /opt/repo/other
cat <<EOF >>/install/postscripts/mypostboot

mkdir -p /opt/n9e
cd /opt/n9e
wget http://${sms_ip}:80//opt/repo/other/n9e-agentd-5.0.0-rc8.tar.gz
tar zxf n9e-agentd-5.0.0-rc8.tar.gz
rm -f n9e-agentd-5.0.0-rc8.tar.gz

perl -pi -e "s/localhost/${sms_ip}/" /opt/n9e/agentd/etc/agentd.yaml
/bin/cp /opt/n9e/agentd/systemd/n9e-agentd.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable n9e-agentd
systemctl restart n9e-agentd
##systemctl status n9e-agentd
chown -R root.root /opt/n9e

EOF

### recover prometheus ###
# systemctl stop n9e-agentd.service
# systemctl stop prometheus.service
# rm -rf /opt/prometheus/data/chunks_head/* 
# rm -rf /opt/prometheus/data/wal/*
# systemctl start prometheus.service
# systemctl start n9e-agentd.service

chown -R root.root /opt/prometheus /opt/n9e

################################################################
## add prometheus slurm exporter
filelist=(
prometheus-slurm-exporter
)

for ifile in ${filelist[@]}
do
  if [ ! -e ${package_dir}/${ifile} ] ; then
  echo "${ifile} is not exist!!!"
  exit
fi
done

mkdir -p /opt/prometheus/exporters
/bin/cp ${package_dir}/prometheus-slurm-exporter /opt/prometheus/exporters
chmod 555 /opt/prometheus/exporters/prometheus-slurm-exporter

########################
cat <<EOF > /usr/lib/systemd/system/prometheus-slurm-exporter.service
[Unit]
Description=prometheus-slurm-exporter
After=network.target 

[Service]
User=slurm
Group=slurm
ExecStart=/opt/prometheus/exporters/prometheus-slurm-exporter \
          -listen-address=:8082 \
#            -gpus-acct
[Install]
WantedBy=multi-user.target
EOF
#########################
cat <<EOF >> /opt/prometheus/prometheus.yml

#
# SLURM resource manager:
#
  - job_name: 'slurm_expor'

    scrape_interval:  30s
    scrape_timeout:   30s

    static_configs:
      - targets: ['localhost:8082']
EOF

#systemctl daemon-reload
systemctl enable prometheus-slurm-exporter
systemctl start prometheus-slurm-exporter
systemctl restart prometheus

################################################################
##  这个在repo里边有，可以直接yum install 到时替换一下
## install grafana-8.1.0-1.x86_64.rpm
filelist=(
grafana-8.1.0-1.x86_64.rpm
)

for ifile in ${filelist[@]}
do
  if [ ! -e ${package_dir}/${ifile} ] ; then
  echo "${ifile} is not exist!!!"
  exit
fi
done

rpm -i ${package_dir}/grafana-8.1.0-1.x86_64.rpm
systemctl daemon-reload
systemctl enable grafana-server.service


echo "ip:localhost port:3000 user and password:admin"
### You can start grafana-server by executing
systemctl start grafana-server.service


echo "======================================================="
echo "boot and wait the compute node install before stage 05!"
echo "======================================================="