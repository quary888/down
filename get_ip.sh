#!/bin/bash
echo -n "IPV4 "
curl --connect-timeout 3 https://ipv4.icanhazip.com
echo -n "IPV6 "
curl --connect-timeout 3 https://ipv6.icanhazip.com
echo -n "默认 "
curl --connect-timeout 3 https://icanhazip.com