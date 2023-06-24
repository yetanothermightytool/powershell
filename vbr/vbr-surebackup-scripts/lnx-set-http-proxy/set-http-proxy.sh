#!/bin/bash
# Read the default gateway from the ip route command
gateway=$(ip route | awk '/default/ {print $3; exit}')
# Set the proxy port
proxy_port="8080"
# Set the proxy environment variables
export http_proxy="http://${gateway}:${proxy_port}"
export https_proxy="https://${gateway}:${proxy_port}"
# Set the proxy for wget
echo "export http_proxy=${http_proxy}" >> /home/administrator/.bashrc
echo "export https_proxy=${http_proxy}" >> /home/administrator/.bashrc
source ~/.bashrc
# Update the apt-get configuration
sudo tee /etc/apt/apt.conf.d/99proxy <<EOF
Acquire::http::Proxy "${http_proxy}";
Acquire::https::Proxy "${https_proxy}";
EOF
