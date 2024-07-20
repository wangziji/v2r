#!/bin/bash
# for debian system

export DOMIAN="***"
echo "DOMIAN: $DOMIAN"

# 安装uuidgen
apt-get update
apt-get install uuid-runtime -y
# 安装curl
apt-get install curl -y
# 安装socat
apt-get install socat -y
# 安装 netcat
apt-get install netcat -y

# procps
apt-get install procps -y

apt-get -y install nginx
# 安装acme.sh
# curl https://get.acme.sh | sh
# source ~/.bashrc


# 生成uuid
export UUID=$(uuidgen)
echo "UUID: $UUID"

# export password="mIgWq3oF6ewrSr"

# # 检测是否存在 /etc/v2ray/v2ray.crt 和 /etc/v2ray/v2ray.key
# new_cert=0
# if [ ! -f "/etc/v2ray/v2ray.crt" ] || [ ! -f "/etc/v2ray/v2ray.key" ]; then
#     new_cert=1
# fi

# # 如果new_cert=0, 检查证书有效期是否小于30天
# if [ $new_cert -eq 0 ]; then
#     cert_date=$(date -d "$(openssl x509 -in /etc/v2ray/v2ray.crt -noout -dates | grep notAfter | cut -d= -f2)" +%s)
#     now_date=$(date +%s)
#     if [ $((cert_date - now_date)) -lt 2592000 ]; then
#         new_cert=2
#     fi
# fi

# echo "new_cert: $new_cert"

# # 如果new_cert=1, 生成新证书，new_cert=2, 更新证书
# if [ $new_cert -eq 1 ]; then
#     # 生成证书
#     ~/.acme.sh/acme.sh --issue -d $DOMIAN --standalone -k ec-256
#     # 安装证书
#     ~/.acme.sh/acme.sh --installcert -d $DOMIAN --fullchainpath /etc/v2ray/v2ray.crt --keypath /etc/v2ray/v2ray.key --ecc
# elif [ $new_cert -eq 2 ]; then
#     # 更新证书
#     ~/.acme.sh/acme.sh --renew -d $DOMIAN --force --ecc
#     # 安装证书
#     ~/.acme.sh/acme.sh --installcert -d $DOMIAN --fullchainpath /etc/v2ray/v2ray.crt --keypath /etc/v2ray/v2ray.key --ecc
# fi

# 启动bbr
wget https://raw.githubusercontent.com/bannedbook/fanqiang/master/v2ss/server-cfg/sysctl.conf  -O -> /etc/sysctl.conf

# 拷贝nginx配置文件
mkdir -p /etc/nginx
cp ./etc/nginx/nginx.conf /etc/nginx/nginx.conf
# 测试nginx配置文件
nginx -t
# 重启nginx
systemctl restart nginx


# 安装v2ray
bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
# 拷贝v2ray配置文件
mkdir -p /usr/local/etc/v2ray
cp ./etc/v2ray/config.json /usr/local/etc/v2ray/config.json
# 将/etc/v2ray/config.json文件中的${UUID}替换为生成的uuid
sed -i "s/\${UUID}/$UUID/g" /usr/local/etc/v2ray/config.json
# 测试配置文件
/usr/local/bin/v2ray test -config /usr/local/etc/v2ray/config.json
# 重启v2ray
systemctl restart v2ray
