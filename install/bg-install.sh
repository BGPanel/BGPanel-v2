#!/bin/bash
# BGPanel installation wrapper
# http://bgpanel.net

#
# Currently Supported Operating Systems:
#
#   RHEL 6 - 7
#   CentOS 6 - 7
#   Debian 7, 8
#   Ubuntu 12.04 - 16.04
#

# Am I root?
if [ "x$(id -u)" != 'x0' ]; then
    echo 'Error: this script can only be executed by root'
    exit 1
fi

# Detect OS
case $(head -n1 /etc/issue | cut -f 1 -d ' ') in
    Debian)     type="debian" ;;
    Ubuntu)     type="ubuntu" ;;
    *)          type="rhel" ;;
esac

# Fallback to Ubuntu
if [ ! -e "/etc/redhat-release" ]; then
    type='ubuntu'
fi

# Check wget
if [ -e '/usr/bin/wget' ]; then
    wget https://raw.githubusercontent.com/BGPanel/BGPanel-v2/master/install/bg-install-$type.sh -O bg-install-$type.sh
    if [ "$?" -eq '0' ]; then
        bash bg-install-$type.sh $*
        exit
    else
        echo "Error: bg-install-$type.sh download failed."
        exit 1
    fi
fi

# Check curl
if [ -e '/usr/bin/curl' ]; then
    curl -O https://raw.githubusercontent.com/BGPanel/BGPanel-v2/master/install/bg-install-$type.sh
    if [ "$?" -eq '0' ]; then
        bash bg-install-$type.sh $*
        exit
    else
        echo "Error: bg-install-$type.sh download failed."
        exit 1
    fi
fi

exit