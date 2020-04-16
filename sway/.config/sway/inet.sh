#!/bin/sh

_localip=$(ifconfig tun0 |grep -v inet6 |grep inet|awk '{print $2}')
_publicip=$(curl -s ifconfig.co)

notify-send -u low "VPN Connected" "Local IP:  $_localip\nPublic IP: $_publicip"
