#!/bin/bash
# 如果没有安装docker安装docker
if ! command -v docker &> /dev/null
then
    echo "docker not found, installing docker..."
    sudo yum update
    sudo yum install -y docker
    sudo systemctl start docker
    sudo systemctl enable docker
    echo "docker installed successfully"
else
    echo "docker already installed"
fi

# 如果没有安装uuidgen安装uuidgen
if ! command -v uuidgen &> /dev/null
then
    echo "uuidgen not found, installing uuidgen..."
    sudo yum update
    sudo yum install -y util-linux
    echo "uuidgen installed successfully"
else
    echo "uuidgen already installed"
fi

# 如果没有安装ufw安装ufw
if ! command -v ufw &> /dev/null
then
    echo "ufw not found, installing ufw..."
    sudo yum update
    sudo yum install -y ufw
    echo "ufw installed successfully"
else
    echo "ufw already installed"
fi

# 如果没有安装curl安装curl
if ! command -v curl &> /dev/null
then
    echo "curl not found, installing curl..."
    sudo yum update
    sudo yum install -y curl
    echo "curl installed successfully"
else
    echo "curl already installed"
fi

# 如果没有安装shuf安装shuf
if ! command -v shuf &> /dev/null
then
    echo "shuf not found, installing shuf..."
    sudo yum update
    sudo yum install -y coreutils
    echo "shuf installed successfully"
else
    echo "shuf already installed"
fi



# 拉取v2ray镜像
docker pull v2fly/v2fly-core

# 生成uuid
uuid=$(uuidgen)

# 生成一个10000-60000之间的随机端口，确认端口未被占用，如果被占用则重新生成
port=0
while [ $port -lt 10000 ] || [ $port -gt 60000 ]
do
    port=$(shuf -i 10000-60000 -n 1)
    netstat -an | grep $port
    if [ $? -eq 0 ]
    then
        port=0
    fi
done

# 防火墙开放端口
sudo ufw allow $port

# 将/etc/v2ray/config.json文件中的${UUID}替换为生成的uuid
sed -i "s/\${UUID}/$uuid/g" /etc/v2ray/config.json

# 获取本机ip
ip=$(curl -s ifconfig.me)

# 获取ip所在地
location=$(curl -s https://ipapi.co/$ip/json/ | jq .country_name)