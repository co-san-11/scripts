#!/bin/bash
set -e

echo "=============================="
echo " Installing Jenkins"
echo "=============================="

# Java
apt update -y
apt install -y openjdk-17-jdk curl gnupg

# Jenkins repo
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
  | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/ \
  | tee /etc/apt/sources.list.d/jenkins.list > /dev/null

apt update -y
apt install -y jenkins

systemctl enable --now jenkins

echo "=============================="
echo " Jenkins installed"
echo " Access: http://<this-ip>:8080"
echo "=============================="
