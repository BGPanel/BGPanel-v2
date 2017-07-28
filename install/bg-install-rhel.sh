#!/bin/bash

# BGPanel RHEL/CentOS installer v.01

#------------------------------------------------------------#
#                  Variables & Functions                     #
#------------------------------------------------------------#

export PATH=$PATH:/sbin
RHOST='r.bgpanel.net'
CHOST='c.bgpanel.net'
REPO='cmmnt'
VERSION='rhel'
BGPANEL='/usr/local/bgpanel'
memory=$(grep 'MemTotal' /proc/meminfo |tr ' ' '\n' |grep [0-9])
arch=$(uname -i)
os=$(cut -f 1 -d ' ' /etc/redhat-release)
release=$(grep -o "[0-9]" /etc/redhat-release |head -n1)
codename="${os}_$release"
bgpanelrepo="http://$CHOST/$VERSION/$release"

if [ "$release" -eq 7 ]; then
	software="bgpanel-nginx bgpanel-php bgpanel"
else
	software="bgpanel-nginx bgpanel-php bgpanel"
fi

# Defining help function
help() {
	echo "Usage: $0 [OPTIONS]
	-v, --proftpd Install ProFTPD [yes|no] default: yes
	-d, --mariadb Install MariaDB [yes|no] default: yes
	-b, --fail2ban Install Fail2ban [yes|no] default: yes
	-c, --clamav Install ClamAV [yes|no] default: yes
	-i, --iptables Install Iptables [yes|no] default: yes
	-l, --lang Sets the default language
	-y, --interactive Interactive install [yes|no] default: yes
	-s, --hostname Set hostname
	-e, --email Set admin email
	-p, --password Set admin password
	-f, --force Force installation
	-h, --help Print this help
	
	Example: bash $0 -e demo@bgpanel.net -p p4ssw0rd --proftpd no"
	exit 1
}

# Defining password-gen function
gen_pass() {
    MATRIX='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    LENGTH=10
    while [ ${n:=1} -le $LENGTH ]; do
        PASS="$PASS${MATRIX:$(($RANDOM%${#MATRIX})):1}"
        let n+=1
    done
    echo "$PASS"
}

# Defning return code check function
check_result() {
    if [ $1 -ne 0 ]; then
        echo "Error: $2"
        exit $1
    fi
}

# Defining function to set default value
set_default_value() {
    eval variable=\$$1
    if [ -z "$variable" ]; then
        eval $1=$2
    fi
    if [ "$variable" != 'yes' ] && [ "$variable" != 'no' ]; then
        eval $1=$2
    fi
}

#----------------------------------------------------------#
#                    Verifications                         #
#----------------------------------------------------------#

# Creating temporary file
tmpfile=$(mktemp -p /tmp)

# Translating argument to --gnu-long-options
for arg; do
	delim=""
	case "$arg" in
		--proftpd) args="${args}-v " ;;
		--mariadb) args="${args}-d " ;;
		--fail2ban) args="${args}-b " ;;
		--clamav) args="${args}-c " ;;
		--iptables) args="${args}-i " ;;
		--lang) args="${args}-l " ;;
		--interactive) args="${args}-y " ;;
		--hostname) args="${args}-s " ;;
		--email) args="${args}-e " ;;
		--password) args="${args}-p " ;;
		--force) args="${args}-f " ;;
		--help) args="${args}-h " ;;
		*) [[ "${arg:0:1}" == "-" ]] || delim="\""
			args="${args}${delim}${arg}${delim} ";;	
	esac
done
eval set -- "$args"

# Parsing arguments
while getopts "v:d:b:c:i:l:y:s:e:p:f:h" Option; do
	case $Option in
		v) proftpd=$OPTARG ;; # ProFTPD
		d) mariadb=$OPTARG ;; # MariaDB
		b) fail2ban=$OPTARG ;; # Fail2ban
		c) clamd=$OPTARG ;; # ClamAV
		i) iptables=$OPTARG ;; # Iptables
		l) lang=$OPTARG ;; # Lanugage
		y) interactive=$OPTARG ;; # Interactive install
		s) servername=$OPTARG ;; # Hostname
		e) email=$OPTARG ;; # Admin Email
		p) adminpass=$OPTARG ;; # Admin Password
		f) force=$OPTARG ;; # Force Install
		h) help ;; # Help
		*) help ;; # Print help (default)
	esac
done

# Defining default software stack
set_default_value 'proftpd' 'yes'
set_default_value 'mariadb' 'yes'
set_default_value 'fail2ban' 'yes'
if [ $memory -lt 1500000 ]; then
	set_default_value 'clamd' 'no'
else
	set_default_value 'clamd' 'yes'
fi
set_default_value 'iptables' 'yes'
set_default_value 'fail2ban'  'yes'
set_default_value 'lang' 'en'
set_default_value 'interactive' 'yes'

# Checking root permissions
if [ "x$(id -u)" != 'x0' ]; then
    check_error 1 "Script can be run executed only by root"
fi

# Checking wget
if [ ! -e '/usr/bin/wget' ]; then
    yum -y install wget
    check_result $? "Can't install wget"
fi

#----------------------------------------------------------#
#                       Brief Info                         #
#----------------------------------------------------------#

# Print nice ascii as logo
clear
echo
echo "___  ____ ___  ____ _  _ ____ _    ";
echo "|__] | __ |__] |__| |\ | |___ |    ";
echo "|__] |__] |    |  | | \| |___ |___ ";
echo "                                   ";
echo
echo "Bright Game Panel"
echo -e "\n\n"

echo "The following software will be installed on your system:"

if [ "$proftpd" == 'yes']; then
	echo '   - ProFTPD FTP Server'
fi

if [ "$mariadb" == 'yes']; then
	echo '   - MariaDB Database Server'
fi

# Firewall stack
if [ "$iptables" = 'yes' ]; then
    echo -n '   - Iptables Firewall'
fi

if [ "$iptables" = 'yes' ] && [ "$fail2ban" = 'yes' ]; then
    echo -n ' + Fail2Ban'
fi

echo -e "\n\n"

# Asking for confirmation to proceed
if [ "$interactive" = 'yes' ]; then
	read -p 'Would you like to continue [y/n]: ' answer
    if [ "$answer" != 'y' ] && [ "$answer" != 'Y'  ]; then
        echo 'Goodbye'
        exit 1
    fi

    # Asking for contact email
    if [ -z "$email" ]; then
        read -p 'Please enter admin email address: ' email
    fi

    # Asking to set FQDN hostname
    if [ -z "$servername" ]; then
        read -p "Please enter FQDN hostname [$(hostname)]: " servername
    fi
fi

# Generating admin password if it wasn't set
if [ -z "$adminpass" ]; then
    adminpass=$(gen_pass)
fi

# Set hostname if it wasn't set
if [ -z "$servername" ]; then
    servername=$(hostname -f)
fi

# Set FQDN if it wasn't set
mask1='(([[:alnum:]](-?[[:alnum:]])*)\.)'
mask2='*[[:alnum:]](-?[[:alnum:]])+\.[[:alnum:]]{2,}'
if ! [[ "$servername" =~ ^${mask1}${mask2}$ ]]; then
    if [ ! -z "$servername" ]; then
        servername="$servername.example.com"
    else
        servername="example.com"
    fi
    echo "127.0.0.1 $servername" >> /etc/hosts
fi

# Set email if it wasn't set
if [ -z "$email" ]; then
    email="admin@$servername"
fi

# Printing start message and sleeping for 5 seconds
echo -e "\n\n\n\nInstallation will take about 30 minutes ...\n"
sleep 5

#----------------------------------------------------------#
#                      Checking swap                       #
#----------------------------------------------------------#

# Checking swap on small instances
if [ -z "$(swapon -s)" ] && [ $memory -lt 1000000 ]; then
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile   none    swap    sw    0   0" >> /etc/fstab
fi

#----------------------------------------------------------#
#                  Install repositories                    #
#----------------------------------------------------------#

# Updating system packages
yum -y update
check_result $? 'yum update failed'

# Installing EPEL repository
yum -y install epel-release
check_result $? "Can't install EPEL repository"

#----------------------------------------------------------#
#                     Configure system                     #
#----------------------------------------------------------#

# Disabling SELinux
if [ -e '/etc/sysconfig/selinux' ]; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0 2>/dev/null
fi

#------------------------------------------------------------#
#                     Configure BGPanel                      #
#------------------------------------------------------------#

# Configuring system env
echo "export BGPanel='$BGPanel'" > /etc/profile.d/bgpanel.sh
chmod 755 /etc/profile.d/bgpanel.sh
source /etc/profile.d/bgpanel.sh
echo 'PATH=$PATH:'$BGPANEL'/bin' >> /root/.bash_profile
echo 'export PATH' >> /root/.bash_profile
source /root/.bash_profile

# Buidling directory tree and creating some blank files for BGPanel
mkdir -p $BGPANEL/conf $BGPANEL/log $BGPANEL/ssl $BGPANEL/data/queue \
	$BGPANEL/data/users $BGPANEL/data/firewall $BGPANEL/data/sessions \
	$BGPANEL/data/ips $BGPANEL/bin $BGPANEL/func
touch $BGPANEL/data/queue/backup.pipe $BGPANEL/data/queue/disk.pipe \
	$BGPANEL/data/queue/webstats.pipe $BGPANEL/data/queue/restart.pipe \
	$BGPANEL/data/queue/traffic.pipe $BGPANEL/log/system.log \
	$BGPANEL/log/nginx-error.log $BGPANEL/log/auth.log
chmod 750 $BGPANEL/conf $BGPANEL/data/users $BGPANEL/data/ips $BGPANEL/log
chmod -R 750 $BGPANEL/data/queue
chmod 600 $BGPANEL/log/*
rm -f /var/log/bgpanel
ln -s $BGPANEL/log /var/log/bgpanel
chown bgpanel:bgpanel $BGPANEL/data/sessions
chmod 770 $BGPANEL/data/sessions

# Generating BGPanel configuration
rm -f $BGPANEL/conf/bgpanel.conf 2>/dev/null
touch $BGPANEL/conf/bgpanel.conf
chmod 600 $BGPANEL/conf/bgpanel.conf

# BGPanel Web Stack
echo "WEB_PORT='4082'" >> $BGPANEL/conf/bgpanel.conf

# BGPanel Daemon Stack
echo "MASTER_SERVER='false'" >> $BGPANEL/conf/bgpanel.conf

# Firewall stack
if [ "$iptables" = 'yes' ]; then
    echo "FIREWALL_SYSTEM='iptables'" >> $BGPANEL/conf/bgpanel.conf
fi

if [ "$iptables" = 'yes' ] && [ "$fail2ban" = 'yes' ]; then
    echo "FIREWALL_EXTENSION='fail2ban'" >> $BGPANEL/conf/bgpanel.conf
fi

# Language
echo "LANGUAGE='$lang'" >> $BGPANEL/conf/bgpanel.conf

# Version
echo "VERSION='0.1.0'" >> $BGPANEL/conf/bgpanel.conf

# Download Bin Scripts
wget https://raw.githubusercontent.com/BGPanel/BGPanel-v2/master/func/main.sh -O $BGPANEL/func/main.sh
wget https://raw.githubusercontent.com/BGPanel/BGPanel-v2/master/bin/bg-generate-cert -O $BGPANEL/bin/bg-generate-cert

# Generating SSL certificate
$BGPANEL/bin/bg-generate-cert $(hostname) $email 'US' 'Michigan' \
     'Sterling Heights' 'Bright Game Panel' 'IT' > /tmp/bgp.pem

# Parsing certificate file
crt_end=$(grep -n "END CERTIFICATE-" /tmp/bgp.pem |cut -f 1 -d:)
key_start=$(grep -n "BEGIN RSA" /tmp/bgp.pem |cut -f 1 -d:)
key_end=$(grep -n  "END RSA" /tmp/bgp.pem |cut -f 1 -d:)

# Adding SSL certificate
cd $BGPANEL/ssl
sed -n "1,${crt_end}p" /tmp/bgp.pem > certificate.crt
sed -n "$key_start,${key_end}p" /tmp/bgp.pem > certificate.key
chown root:mail $BGPANEL/ssl/*
chmod 660 $BGPANEL/ssl/*
rm /tmp/bgp.pem	 
	 
