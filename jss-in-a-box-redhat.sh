#!/bin/bash

##########################################################################################
#
# JSS in a Box
# (aka a script to initialise, create, configure and delete JSS instances on an Ubuntu 14.04 server.)
# (with apologies to Tom Bridge and https://github.com/tbridge/munki-in-a-box)
#
# The MIT License (MIT)
# Copyright (c) 2015 <contact@richard-purves.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify, 
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
# persons to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or
# substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
# PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
# FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
##########################################################################################

# RedHat 7 ONLY version!

# Author : Richard Purves <richard at richard-purves.com>

# Version 0.1 - 27th December 2015 - Initial Version
# Version 0.2 - 28th December 2015 - Completed structure and initialisation code
# Version 0.3 - 29th December 2015 - Completed all functions excluding database restoration
# Version 0.4 - 30th December 2015 - Interactive Mode complete. Code for SSL present but untested.
# Version 0.5 - 31st December 2015 - Implemented Ubuntu UFW rules for security
# 									 Implemented ability to talk to an external MySQL server.
#									 Now creates/deletes JSS log files with modification to the JSS log4j file
# Version 0.6 - 31st December 2015 - Extracts the DataBase.xml file from the provided ROOT.war file
# Version 0.7 - 1st January 2016   - Code simplification and clean up. Was getting messy.
#									 Can be invoked by parameter and skip the opening menu for specific functions.
# Version 0.8 - 1st January 2016   - HTTPS SSL code implemented and working. Usually. There's all sorts of things out of my control that go wrong with this :(
# Version 0.9 - 2nd January 2016   - Added menu option for SSL certificate update. Checks to see if server.xml is backed up before working on it.
#								   - Tomcat set to use a max of 3Gb of server memory.
#								   - cron job created to run an SSL cert refresh every month.
#								   - This is due to LE's cert lifetime of 90 days and cron's inability to run past daily, monthly or yearly.
# Version 1.0 - 4th January 2016   - RELEASE - LetsEncrypt is now an optional install. Log files repointed on JSS upgrades too.
#								   - Cleaned up Tomcat caching issues with deleted instances.
# Version 1.0 - 31st March 2016	   - Redhat compatible version. No new features so not a version increment.

# Set up variables to be used here

# These variables are user modifiable.

export useract="richardpurves"								# Server admin username. Used for home location.

export letsencrypt="FALSE"									# Set this to TRUE if you are going to use LetsEncrypt as your HTTPS Certificate Authority.
export sslTESTMODE="TRUE"									# Set this to FALSE when you're confident it's generating proper certs for you
export ssldomain="jssinabox.westeurope.cloudapp.azure.com"	# Domain name for the SSL certificates
export sslemail="richard at richard-purves.com"				# E-mail address for the SSL CA
export sslkeypass="changeit"								# Password to the keystore. Default is "changeit". Please change it!

export mysqluser="root"										# MySQL root account
export mysqlpw="changeit"									# MySQL root account password. Please change it!
export mysqlserveraddress="localhost" 						# IP/Hostname of MySQL server. Default is local server.

export dbuser="jamfsoftware"								# Database username for JSS
export dbpass="changeit"									# Database password for JSS. Default is "changeit". Please change it!

# These variables should not be tampered with or script functionality will be affected!

currentdir=$( pwd )
currentver="1.0"
currentverdate="31st March 2016"

export homefolder="/home/$useract"							# Home folder base path
export rootwarloc="$homefolder"								# Location of where you put the ROOT.war file
export logfiles="/var/log/JSS"								# Location of ROOT and instance JSS log files

export tomcatloc="/usr/share/tomcat"						# Tomcat's installation path
export server="$tomcatloc/conf/server.xml"					# Tomcat's server.xml based on install path
export webapploc="$tomcatloc/webapps"						# Tomcat's webapps folder based on install path

export DataBaseLoc="/WEB-INF/xml/"							# DataBase.xml location inside the JSS webapp
export DataBaseXML="$rootwarloc/DataBase.xml.original"		# Location of the tmp DataBase.xml file we use for reference

export sslkeystorepath="$tomcatloc/keystore"				# The path for the SSL keystore we'll use in Tomcat
export lepath="/etc/letsencrypt/live"						# LetsEncrypt's certificate storage location

# All functions to be set up here

WhichDistAmI()
{
	# This script is currently designed for Ubuntu only, so let's fail gracefully if we're running on anything else.

	# Check for version
	version=$( cat /etc/redhat-release | awk '{ print $7 }' | cut -c 1 )


	# Is this RedHat 7 server?
	if [[ $version != "7" ]];
	then
		echo -e "\nScript requires RedHat 7. Exiting."
		exit 1
	else
		echo -e "\nRedhat 7 detected. Proceeding."
	fi
}

AmIroot()
{
	# Get UID of current user
	uid=$(id -u)

	# Check for root, quit if not present with a warning.
	if [[ $uid -ne 0 ]];
	then
		echo -e "\nScript needs to be run as root."
		exit 1
	else
		# Confirm running as root level and proceed
		echo -e "\nScript running as root. Proceeding."
	fi
}

IsROOTwarPresent()
{
	# Check for presence of ROOT.war file or we can't upgrade at all!
	if [ ! -f "$rootwarloc/ROOT.war" ];
	then
		echo -e "\nMissing ROOT.war file from path: $rootwarloc \nPlease copy file to location and try again."
		exit 1
	else
		echo -e "\nROOT.war present at path: $rootwarloc. Proceeding."
	fi
}

UpdateYUM()
{
	# Now let's start by making sure the yum is up to date
	echo -e "\nInstalling Delta RPM functionality\n"
	yum install -y deltarpm
	
	echo -e "\nUpdating yum repository ...\n"
	yum -q -y update
}

InstallGit()
{
	# Is git present?
	git=$(yum -q list installed git &>/dev/null && echo "yes" || echo "no" )

	if [[ $git = "no" ]];
	then
		echo -e "\ngit not present. Installing."
		yum -q -y install git
	else
		echo -e "\ngit already present. Proceeding."
	fi
}

InstallWget()
{
	# Is wget present?
	wget=$(yum -q list installed wget &>/dev/null && echo "yes" || echo "no" )

	if [[ $wget = "no" ]];
	then
		echo -e "\nwget not present. Installing."
		yum -q -y install wget
	else
		echo -e "\nwget already present. Proceeding."
	fi
}

InstallUnzip()
{
	# Is unzip installed?
	unzip=$(yum -q list installed unzip &>/dev/null && echo "yes" || echo "no" )
	
	if [[ $unzip = "no" ]];
	then
		echo -e "\nunzip not present. Installing\n"
		yum -q -y install unzip
	else
		echo -e "\nunzip already present. Proceeding."
	fi
}

PrepDBfile()
{
	# Is unzip installed? Check by calling the unzip function.
	InstallUnzip
		
	# Check for presence of DataBase.xml.original file.
	# If missing, extract the DataBase.xml and place it in the $rootwarloc directory
	# Rename to DataBase.xml.original
	if [ ! -f "$rootwarloc/DataBase.xml.original" ];
	then
		echo -e "\nExtracting DataBase.xml from ROOT.war\n"
		unzip -j $rootwarloc/ROOT.war "WEB-INF/xml/DataBase.xml" -d $rootwarloc
		mv $rootwarloc/DataBase.xml $rootwarloc/DataBase.xml.original
	else
		echo -e "\nDataBase.xml.original found at path: $rootwarloc. Proceeding."
	fi
}

InstallFirewall()
{
	# Is firewalld installed?
	fwd=$(yum -q list installed firewalld &>/dev/null && echo "yes" || echo "no" )

	if [[ $fwd = "no" ]];
	then
		echo -e "\nFirewallD not present. Installing.\n"
		yum -q -y install firewalld
	else
		echo -e "\nFirewallD already installed. Proceeding."
	fi
}

InstallOpenSSH()
{
	# Is OpenSSH present?
	openssh=$(yum -q list installed openssh &>/dev/null && echo "yes" || echo "no" )

	if [[ $openssh = "no" ]];
	then
		echo -e "\nopenssh not present. Installing.\n"
		yum -q -y install openssh
	else
		echo -e "\nopenssh already installed. Proceeding."
	fi
}

InstallOpenVMTools()
{
	# Are the open-vm-tools present?
	openvmtools=$(yum -q list installed open-vm-tools &>/dev/null && echo "yes" || echo "no" )

	if [[ $openvmtools = "no" ]];
	then
		echo -e "\nopen vm tools not present. Installing."
		yum -q -y install open-vm-tools-deploypkg
	else
		echo -e "\nopen vm tools already installed. Proceeding."
	fi
}

InstallJava8()
{
	# Is OpenJDK Java 1.8 present?
	java8=$(yum -q list installed java-1.8.0-openjdk &>/dev/null && echo "yes" || echo "no" )

	if [[ $java8 = "no" ]];
	then
		echo -e "\nOpenJDK 8 not present. Installing."
		yum -q -y install java-1.8.0-openjdk
		
		echo -e "\nInstalling Java Cryptography Extension 8\n"
		curl -v -j -k -L -H "Cookie:oraclelicense=accept-securebackup-cookie" http://download.oracle.com/otn-pub/java/jce/8/jce_policy-8.zip  > $rootwarloc/jce_policy-8.zip
		unzip $rootwarloc/jce_policy-8.zip
		cp $rootwarloc/UnlimitedJCEPolicyJDK8/* /usr/lib/jvm/jre/lib/security
		rm $rootwarloc/jce_policy-8.zip
		rm -rf $rootwarloc/UnlimitedJCEPolicyJDK8

	else
		echo -e "\nOpenJDK 8 already installed. Proceeding."
	fi
}

InstallTomcat()
{
	# Is Tomcat 7 present?
	tomcat=$(yum -q list installed tomcat &>/dev/null && echo "yes" || echo "no" )

	if [[ $tomcat = "no" ]];
	then
		echo -e "\nTomcat 7 not present. Installing."
		yum -q -y install tomcat

#		echo -e "\nSetting Tomcat to use more system ram\n"
#		sed -i 's/$CATALINA_OPTS $JPDA_OPTS/$CATALINA_OPTS $JPDA_OPTS -server -Xms1024m -Xmx3052m -XX:MaxPermSize=128m/' /usr/share/tomcat/conf/tomcat.conf

		echo -e "\nEnabling Tomcat to start on system restart\n"
		systemctl enable tomcat

		echo -e "\nStarting Tomcat service."
		systemctl start tomcat
	else
		echo -e "\nTomcat already present. Proceeding."
	fi
}

InstallMySQL()
{
	# Is MySQL 5.6 present?
	mysql=$(yum -q list installed mysql-community-server &>/dev/null && echo "yes" || echo "no")

	if [[ $mysql = "no" ]];
	then
		echo -e "\nMySQL 5.6 not present. Installing."

		echo -e "\nAdding MySQL 5.6 to yum repo list\n"
		wget http://repo.mysql.com/mysql-community-release-el7-5.noarch.rpm -P $homefolder
		rpm -ivh mysql-community-release-el7-5.noarch.rpm
		rm $homefolder/mysql-community-release-el7-5.noarch.rpm
		
		echo -e "\nInstalling MySQL 5.6\n"
		yum -q -y install mysql-server
		
#		echo -e "\nConfiguring MySQL 5.6 ...\n"
#		sed -i "s/.*max_allowed_packet.*/max_allowed_packet	   = 256M/" /etc/mysql/my.cnf
#		sed -i '/#max_connections        = 100/c\max_connections         = 400' /etc/mysql/my.cnf

		echo -e "\nEnabling MySQL to start on system restart"
		systemctl enable mysqld

		echo -e "\nStarting MySQL 5.6"
		systemctl start mysqld
		
		echo -e "\nSecuring MySQL 5.6\n"
		mysqladmin -u root password $mysqlpw
		
	else
		echo -e "\nMySQL 5.6 already present. Proceeding."
	fi
}

SetupFirewall()
{	
	# It's time to harden the server firewall.
	# For RedHat, we're using FireWallD.

	echo -e "\nEnabling FirewallD service."
	systemctl start firewalld

	echo -e "\nConfiguring FirewallD service\n"
	firewall-cmd --permanent --add-service=ssh		
	firewall-cmd --permanent --add-service=http		
	firewall-cmd --permanent --add-service=smtp		
	firewall-cmd --permanent --add-service=ntp		
	#firewall-cmd --permanent --add-service=ldap
	#firewall-cmd --permanent --add-service=ldaps
	firewall-cmd --permanent --add-service=https	
	firewall-cmd --permanent --add-service=mysql	
	firewall-cmd --permanent --add-port=8080/tcp	# HTTP JSS (delete once you got SSL working)
	firewall-cmd --permanent --add-port=8443/tcp	# HTTPS JSS (delete 8080 once you got SSL working)
	firewall-cmd --permanent --add-port=2195/tcp	# Apple Push Notification Service
	firewall-cmd --permanent --add-port=2196/tcp	# Apple Push Notification Service
	firewall-cmd --permanent --add-port=5223/tcp	# Apple Push Notification Service
	firewall-cmd --permanent --add-port=5228/tcp	# Google Cloud Messaging

	echo -e "\nEnabling FirewallD rule changes\n"
	firewall-cmd --reload

	echo -e "\nEnabling FirewallD to start on system reboot"
	systemctl enable firewalld
}

SetupLogs()
{	
	# Check and create the JSS log file folder if missing with appropriate permissions.
	if [ ! -d $logfiles ];
	then
		mkdir $logfiles
		chown -R tomcat:tomcat $logfiles
	fi
}

InstallLetsEncrypt()
{
	# Is LetsEncrypt present?
	# This one is a git clone, rather than a apt-get installation. We'll be putting this in /usr/local/letsencrypt
	if [ ! -d "/usr/local/letsencrypt" ];
	then
		echo -e "\nLetsEncrypt not present. Cloning from GitHub.\n"
		cd /usr/local
		git clone https://github.com/letsencrypt/letsencrypt
		sudo -H /usr/local/letsencrypt/letsencrypt-auto 
		cd $currentdir
	else
		echo -e "\nLetsEncrypt is already installed. Proceeding."
		return
	fi

	# We'll be doing some work with Tomcat so let's stop the service to make sure we don't hurt anything.
	echo "\nStopping Tomcat service\n"
	systemctl stop tomcat

	# Get LetsEncrypt to generate the appropriate certificate files for later processing.
	# We're using sudo -H even as root because there's some weird errors that happen if you don't.
	echo -e "\nObtaining Certificate from LetsEncrypt Certificate Authority\n"
	if [[ $sslTESTMODE = "TRUE" ]];
	then
		sudo -H /usr/local/letsencrypt/letsencrypt-auto certonly --standalone -m $sslemail -d $ssldomain --agree-tos --test-cert
	else
		sudo -H /usr/local/letsencrypt/letsencrypt-auto certonly --standalone -m $sslemail -d $ssldomain --agree-tos
	fi

	# Code to generate a Java KeyStore for Tomcat from what's provided by LetsEncrypt
	# Based on work by Carmelo Scollo (https://melo.myds.me)
	# https://community.letsencrypt.org/t/how-to-use-the-certificate-for-tomcat/3677/9

	# Create a keystore folder for Tomcat with the correct permissions
	mkdir $sslkeystorepath
	chown tomcat:tomcat $sslkeystorepath
	chmod 755 $sslkeystorepath

	# Ok we got LetsEncrypt certificate files, let's make a PKCS12 combined key file from them.
	echo -e "\nMerging LetsEncrypt certificates into a PKCS12 file\n"
	openssl pkcs12 \
			-export \
			-in $lepath/$ssldomain/fullchain.pem \
			-inkey $lepath/$ssldomain/privkey.pem \
			-out $sslkeystorepath/fullchain_and_key.p12 \
			-password pass:$sslkeypass \
			-name tomcat
	
	# Now we convert our .p12 file into a java keystore that Tomcat likes better.
	echo -e "\nConverting PKCS12 file into a Java KeyStore\n"
	keytool -importkeystore \
			-deststorepass $sslkeypass \
			-destkeypass $sslkeypass \
			-destkeystore $sslkeystorepath/keystore.jks \
			-srckeystore $sslkeystorepath/fullchain_and_key.p12 \
			-srcstoretype PKCS12 \
			-srcstorepass $sslkeypass \
			-alias tomcat

	# Clean up on aisle three!
	rm $sslkeystorepath/fullchain_and_key.p12

	# Ok has Tomcat previously had it's server.xml altered by this script? Check for the backup.
	if [ ! -f "$server.backup" ];
	then
		# Configure the Tomcat server.xml. None of this stuff is pretty and could be better.
		# Let's start by backing up the server.xml file in case things go wrong.
		echo -e "\nBacking up $server file\n"
		cp $server $server.backup

		echo -e "\nDisabling HTTP service on Port 8080\n"
		sed -i '72i<!--' $server
		sed -i '77i-->' $server

		echo -e "\nEnabling HTTPS service\n"
		sed -i '89d' $server
		sed -i '92d' $server
		
		echo -e "\nConfiguring HTTPS connector to use keystore and more advanced TLS\n"
		sed -i '/clientAuth="false" sslProtocol="TLS"/i sslEnabledProtocols="TLSv1.2,TLSv1.1,TLSv1" keystoreFile="'"$sslkeystorepath/keystore.jks"'" keystorePass="'"$sslkeypass"'" keyAlias="tomcat" ' $server

		echo -e "\nConfiguring HTTPS to use more secure ciphers\n"
		sed -i '/clientAuth="false" sslProtocol="TLS"/i ciphers="TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDH_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDH_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDH_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDH_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA,TLS_ECDH_RSA_WITH_AES_256_CBC_SHA384,TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA384,TLS_ECDH_RSA_WITH_AES_256_CBC_SHA,TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA,TLS_ECDH_RSA_WITH_AES_128_CBC_SHA256,TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA256,TLS_ECDH_RSA_WITH_AES_128_CBC_SHA,TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA,TLS_RSA_WITH_AES_128_CBC_SHA/" ' $server
	else
		echo -e "\n$server appears to be already configured for HTTPS. Skipping\n"
	fi

	# We're done here. Start 'er up.
	systemctl start tomcat
	
	# Oh wait, we have to set up a periodic renewal since LetsEncrypt doesn't do that for Tomcat
	# (at time of coding - 2nd Jan 2016)
	# This should renew every couple months. LE certs last 90 days but quicker is fine.
	crontab -l | { echo "30	03	01	*/2	*	$homefolder/jss-in-a-box.sh -s"; } | crontab -
}

UpdateLeSSLKeys()
{
	# update SSL keys from LetsEncrypt

	# Is LetsEncrypt present?
	# This one is a git clone, rather than a apt-get installation. We'll be putting this in /usr/local/letsencrypt
	if [[ $letsencrypt = "FALSE" ]];
	then
		echo -e "\nLetsEncrypt option disabled in script. Cannot proceed.\n"
		return 1
	else
		# We'll be doing some work with Tomcat so let's stop the service to make sure we don't hurt anything.
		echo -e "\nStopping Tomcat service\n"
		systemctl stop tomcat

		# Get LetsEncrypt to generate the appropriate certificate files for later processing.
		# We're using sudo -H even as root because there's some weird errors that happen if you don't.
		echo -e "\nObtaining Certificate from LetsEncrypt Certificate Authority\n"
		if [[ $sslTESTMODE = "TRUE" ]];
		then
			sudo -H /usr/local/letsencrypt/letsencrypt-auto certonly --standalone -m $sslemail -d $ssldomain --agree-tos --test-cert
		else
			sudo -H /usr/local/letsencrypt/letsencrypt-auto certonly --standalone -m $sslemail -d $ssldomain --agree-tos
		fi

		# Clean up the old keystore and keys
		rm $sslkeystorepath/keystore.jks

		# Ok we got LetsEncrypt certificate files, let's make a PKCS12 combined key file from them.
		echo -e "\nMerging LetsEncrypt certificates into a PKCS12 file"
		openssl pkcs12 \
				-export \
				-in $lepath/$ssldomain/fullchain.pem \
				-inkey $lepath/$ssldomain/privkey.pem \
				-out $sslkeystorepath/fullchain_and_key.p12 \
				-password pass:$sslkeypass \
				-name tomcat
	
		# Now we convert our .p12 file into a java keystore that Tomcat likes better.
		echo -e "\nConverting PKCS12 file into a Java KeyStore"
		keytool -importkeystore \
				-deststorepass $sslkeypass \
				-destkeypass $sslkeypass \
				-destkeystore $sslkeystorepath/keystore.jks \
				-srckeystore $sslkeystorepath/fullchain_and_key.p12 \
				-srcstoretype PKCS12 \
				-srcstorepass $sslkeypass \
				-alias tomcat

		# Clean up on aisle three!
		rm $sslkeystorepath/fullchain_and_key.p12
	
		# We're done here. Start 'er up.
		echo -e "\nRestarting Tomcat server"
		systemctl start tomcat
	fi
}

InitialiseServer()
{
	# This is to make sure the appropriate services and software are installed and configured.
	UpdateYUM
	InstallGit
	InstallWget
	InstallUnzip
	InstallFirewall
	InstallOpenSSH
	InstallOpenVMTools
	InstallJava8		# This includes the Cryptography Extensions
	InstallTomcat
	InstallMySQL
	SetupLogs
	
	if [[ $letsencrypt = TRUE ]];
	then
		InstallLetsEncrypt
	fi
	
	SetupFirewall
}

CreateNewInstance()
{
	# Check for presence of Tomcat and MySQL before proceeding
	tomcat=$(yum -q list installed tomcat &>/dev/null && echo "yes" || echo "no" )
	mysql=$(yum -q list installed mysql-community-server &>/dev/null && echo "yes" || echo "no")
	
	if [[ $tomcat = "no" || $mysql = "no" ]];
	then
		echo -e "\nTomcat 7 / MySQL not present. Please install before trying again.\n"
		return 1
	fi
	
	# Call function to show all directory names in the tomcat webapps folder
	InstanceList

	# Prompt for new instance name
	echo -e "\nPlease enter a new instance name. (Or ROOT for a non-context JSS / enter key to skip)\n"
	read -p "Name : " instance

	# Check for the skip
	if [[ $instance = "" ]];
	then
		echo -e "\nSkipping instance creation.\n"
		return
	fi

	# Does this name already exist? If so, ask again.
	webapps=($(find $webapploc/* -maxdepth 0 -type d 2>/dev/null | sed -r 's/^.+\///'))
	[[ " ${webapps[@]} " =~ " $instance " ]] && found=true || found=false

	if [[ $found = true ]];
	then
		echo -e "\nInstance name already exists.\n"
		return 1
	fi

	# Create the new database
	echo -e "\nCreating new database for instance: $instance "
	mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -e "CREATE DATABASE $instance;" 2>/dev/null
	mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -e "GRANT ALL ON $instance.* TO $dbuser@$mysqlserveraddress IDENTIFIED BY '$dbpass';" 2>/dev/null

	# Create the new tomcat instance
	echo -e "\nInstalling JSS application to new instance: $instance"
	
	# Check if installing ROOT, if so just copy the file to the webapps folder
	# Otherwise make a copy of the ROOT.war, rename it to the instance name and
	# then move that to the webapps folder.
	if [[ $instance = "ROOT" ]];
	then
		cp $rootwarloc/ROOT.war $webapploc
	else
		cp $rootwarloc/ROOT.war $rootwarloc/$instance.war
		mv $rootwarloc/$instance.war $webapploc
	fi

	# Create a specific DataBase.xml file for this new instance
	echo -e "\nPreparing DataBase.xml for new instance: $instance"
	sed -i "s/\(<ServerName.*>\).*\(<\/ServerName.*\)/\1$mysqlserveraddress\2/" $DataBaseXML
	sed -i "s/\(<DataBaseName.*>\).*\(<\/DataBaseName.*\)/\1$instance\2/" $DataBaseXML
	sed -i "s/\(<DataBaseUser.*>\).*\(<\/DataBaseUser.*\)/\1$dbuser\2/" $DataBaseXML
	sed -i "s/\(<DataBasePassword.*>\).*\(<\/DataBasePassword.*\)/\1$dbpass\2/" $DataBaseXML

	# Wait 10 seconds to allow Tomcat to expand the .war file we copied over.
	echo -e "\nWaiting 10 seconds to allow Tomcat to expand the .war file"
	sleep 10

	# Copy the new file over the top of the existing file.
	echo -e "\nCopying the replacement DataBase.xml file into new instance: $instance"
	cp $DataBaseXML $webapploc/$instance/$DataBaseLoc/DataBase.xml

	# Create the instance name and empty log files with an exception for ROOT
	echo -e "\nCreating log files for new instance: $instance"
	if [[ $instance = "ROOT" ]];
	then
		touch $logfiles/JAMFChangeManagement.log
		touch $logfiles/JAMFSoftwareServer.log
		touch $logfiles/JSSAccess.log
		chown -R tomcat:tomcat $logfiles
	else
		mkdir $logfiles/$instance
		touch $logfiles/$instance/JAMFChangeManagement.log
		touch $logfiles/$instance/JAMFSoftwareServer.log
		touch $logfiles/$instance/JSSAccess.log
		chown -R tomcat:tomcat $logfiles/$instance
	fi

	# Finally modify the log4j file inside the new instance to point to the right files/folders
	echo -e "\nModifying new instance: $instance to point to new log files"
	if [[ $instance = "ROOT" ]];
	then	
		sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File=$logfiles/JAMFChangeManagement.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
		sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/JAMFSoftwareServer.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
		sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/JSSAccess.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
	else
		sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File=$logfiles/$instance/JAMFChangeManagement.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
		sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/$instance/JAMFSoftwareServer.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
		sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/$instance/JSSAccess.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
	fi

	# Restart Tomcat 7
	echo -e "\nRestarting Tomcat 7\n"
	systemctl restart tomcat
}

InstanceList()
{
	tomcat=$(yum -q list installed tomcat &>/dev/null && echo "yes" || echo "no" )

	if [[ $tomcat = "no" ]];
	then
		echo -e "\nTomcat 7 not present. Please install before trying again."
	else
		# Shows all directory names in the tomcat webapps folder, with some sed work for legibility.
		echo -e "\nJSS Instance List\n-----------------\n"
		find $webapploc/* -maxdepth 0 -type d 2>/dev/null | sed -r 's/^.+\///'
	fi
}

DeleteInstance()
{
	# Check for presence of Tomcat and MySQL before proceeding
	tomcat=$(yum -q list installed tomcat &>/dev/null && echo "yes" || echo "no" )
	mysql=$(yum -q list installed mysql-community-server &>/dev/null && echo "yes" || echo "no")

	if [[ $tomcat = "no" || $mysql = "no" ]];
	then
		echo -e "\nTomcat 7 / MySQL not present. Please install before trying again."
		return 1
	fi

	# Call function to show all directory names in the tomcat webapps folder
	InstanceList

	# Prompt for the instance name
	echo -e "\n"
	read -p "Please enter a JSS instance to delete (or enter to skip) : " instance

	# Does this name already exist?
	webapps=($(find $webapploc/* -maxdepth 0 -type d | sed -r 's/^.+\///'))
	[[ " ${webapps[@]} " =~ " $instance " ]] && found=true || found=false

	if [[ $found = false ]];
	then
		echo -e "\nInstance name does not exist."
		return 1
	fi

	# It does exist. Are they sure? Very very very VERY sure?
	echo -e "\nWARNING: This will restart the Tomcat service!\n"
	read -p "Are you completely certain? There is NO RECOVERY from this! (Y/N) : " areyousure

	case "$areyousure" in

		Y|y)
		
		# Stop the tomcat service
		echo -e "\nStopping Tomcat service.\n"
		systemctl stop tomcat

		# Delete the tomcat ROOT.war folder
		echo -e "\nDeleting Tomcat instance: $instance"
		rm $webapploc/$instance.war 2>/dev/null
		rm -rf $webapploc/$instance

		# Delete the database
		echo -e "\nDeleting database for instance: $instance"
		mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -e "DROP DATABASE $instance;" 2>/dev/null

		# Delete the logfiles
		echo -e "\nDeleting log files for instance: $instance"
		if [[ $instance = "ROOT" ]];
		then
			rm $logfiles/JAMFSoftwareServer.log	2>/dev/null
			rm $logfiles/jamfChangeManagement.log 2>/dev/null
			rm $logfiles/JSSAccess.log 2>/dev/null
		else
			rm -rf $logfiles/$instance 2>/dev/null
		fi

		# Delete the tomcat cache folder
		echo -e "\nDeleting Tomcat cache folder for instance: $instance"
		if [[ $instance = "ROOT" ]];
		then
			rm -rf $tomcatloc/work/Catalina/localhost/_ 2>/dev/null
		else
			rm -rf $tomcatloc/work/Catalina/localhost/$instance 2>/dev/null
		fi
		
		# Restart tomcat
		echo -e "\nRestarting Tomcat service\n"
		systemctl restart tomcat
		;;

		*)
			echo -e "\nSkipping deletion of instance"
		;;

	esac
}

DumpDatabase()
{
	# Is MySQL 5.6 present?
	mysql=$(yum -q list installed mysql-community-server &>/dev/null && echo "yes" || echo "no")

	if [[ $mysql = "no" ]];
	then
		echo -e "\nMySQL 5.6 not installed. Please install before trying again.\n"
		return 1
	fi

	# Shows all JSS databases in MySQL but removing the SQL server specific ones.
	echo -e "\nJSS Database List\n-----------------\n"
	mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -Bse "SHOW DATABASES;" 2>/dev/null | grep -v "mysql" | grep -E -v "(information|performance)_schema"
	
	# Choose either a single instance or all of them
	echo -e "\n"
	read -p "Please enter an instance name to dump (or ALL for entire database) : " instance

	# Has the entire database been selected?
	if [[ $instance = "ALL" ]];
	then
		echo -e "\nDumping all databases to files."
		databases=$( mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -Bse "SHOW DATABASES;" 2>/dev/null | grep -v "mysql" | grep -E -v "(information|performance)_schema" )
		
		# Stop the tomcat service
		echo -e "\nStopping Tomcat service."
		systemctl stop tomcat
				
		for db in $databases; do
			echo "Dumping database: $db"
			mysqldump -h$mysqlserveraddress -u$mysqluser -p$mysqlpw $db 2>/dev/null | gzip > $rootwarloc/$db.sql.gz
		done
		
		# Restart tomcat
		echo -e "\nRestarting Tomcat service"
		systemctl restart tomcat
				
		return
	fi
	
	# Does this name already exist?
	dbs=($(mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -Bse "SHOW DATABASES;" 2>/dev/null | grep -v "mysql" | grep -E -v "(information|performance)_schema"))
	[[ " ${dbs[@]} " =~ " $instance " ]] && found=true || found=false
	
	if [[ $found = false ]];
	then
		echo -e "\nInstance name does not exist."
		return 1
	fi

	# Dump selected database table
	echo -e "\nDumping database $instance ..."
	mysqldump -h$mysqlserveraddress -u$mysqluser -p$mysqlpw $instance 2>/dev/null | gzip > $rootwarloc/$instance.sql.gz
}

UploadDatabase()
{
	# Is MySQL 5.6 present?
	mysql=$(yum -q list installed mysql-community-server &>/dev/null && echo "yes" || echo "no")

	if [[ $mysql = "no" ]];
	then
		echo -e "\nMySQL 5.6 not installed. Please install before trying again.\n"
		return 1
	fi
	
	# Show list of backup files
	echo -e "\nDatabase Backup List\n-----------------\n"
	find $rootwarloc/*.sql.gz -maxdepth 0 | sed -r 's/^.+\///'
	
	# Ask which file to restore
	echo -e "\n"
	read -p "Please enter filename to restore (enter to skip / ALL for everything!) : " dbname

	# Has the entire database been selected?
	if [[ $dbname = "ALL" ]];
	then
		echo -e "\nWARNING: This will overwrite ALL existing MySQL database(s)!\n"
		echo -e "This will stop Tomcat from running while the process completes.\n"
		read -p "Are you completely certain? (Y/N) : " areyousure

		case "$areyousure" in

			Y|y)
				# Stop the tomcat service
				echo -e "\nStopping Tomcat service."
				systemctl stop tomcat

				echo -e "\nImporting all database files."
				databases=($(find $rootwarloc/*.sql.gz -maxdepth 0 | sed -r 's/^.+\///'))

				for (( i=0; i<${#databases[@]}; i++ ));
				do
					# Work out what the database name is without the .sql.gz on the end of it!
					db="${databases[i]%.sql.gz}"

					echo -e "\nDropping existing database for instance: ${databases[i]} "
					mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -e "drop database $db;" 2>/dev/null
					mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -e "create database $db;" 2>/dev/null

					echo -e "\nImporting database: ${databases[i]}"
					gzip -dc < $rootwarloc/${databases[i]} | mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw $db 2>/dev/null

					echo -e "\nRe-establishing grants for database: ${databases[i]}"
					mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -e "GRANT ALL ON $db.* TO $dbuser@$mysqlserveraddress IDENTIFIED BY '$dbpass';" 2>/dev/null
				done

				# Restart tomcat
				echo -e "\nRestarting Tomcat service"
				systemctl restart tomcat
				
				return
			;;
		
			*)
				echo -e "\nSkipping database restoration"
				return 1
			;;

		esac	
	fi
	
	# Does this name already exist?.
	backups=($(find $rootwarloc/*.sql.gz -maxdepth 0 | sed -r 's/^.+\///'))
	[[ " ${backups[@]} " =~ " $dbname " ]] && found=true || found=false

	if [[ $found = false ]];
	then
		echo -e "\nIncorrect or missing database filename."
		return 1
	fi

	# It does exist. Are they sure? Very very very VERY sure?

	echo -e "\nWARNING: This will overwrite any existing MySQL database(s)!\n"
	echo -e "This will stop Tomcat from running while the process completes.\n"
	read -p "Are you completely certain? (Y/N) : " areyousure

	case "$areyousure" in

		Y|y)
			# Stop the tomcat service
			echo -e "\nStopping Tomcat service."
			systemctl stop tomcat
			
			# Work out what the database name is without the .sql.gz on the end of it!
			db="${dbname%.sql.gz}"

			echo -e "\nDropping existing database for instance: $dbname "
			mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -e "drop database $db;"
			mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -e "create database $db;"

			# Upload the selected database dump
			echo -e "\nImporting database: $dbname"
			gzip -dc < $rootwarloc/$dbname | mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw $db

			echo -e "\nRe-establishing grants for database: $dbname"
			mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -e "GRANT ALL ON $db.* TO $dbuser@$mysqlserveraddress IDENTIFIED BY '$dbpass';"

			# Restart tomcat
			echo -e "\nRestarting Tomcat service"
			systemctl restart tomcat
		;;
		
		*)
			echo -e "\nSkipping database restoration"
		;;

	esac
}

UpgradeInstance()
{
	# Check for presence of Tomcat and MySQL before proceeding
	tomcat=$(yum -q list installed tomcat &>/dev/null && echo "yes" || echo "no" )
	mysql=$(yum -q list installed mysql-community-server &>/dev/null && echo "yes" || echo "no")

	if [[ $tomcat = "no" || $mysql = "no" ]];
	then
		echo -e "\nTomcat 7 / MySQL not present. Please install before trying again."
		return 1
	fi

	# Call function to show all directory names in the tomcat webapps folder
	InstanceList

	# Prompt for the instance name.
	echo -e "\n"
	read -p "Please enter a JSS instance to upgrade (or enter to skip) : " instance

	# Does this name already exist?.
	webapps=($(find $webapploc/* -maxdepth 0 -type d | sed -r 's/^.+\///'))
	[[ " ${webapps[@]} " =~ " $instance " ]] && found=true || found=false

	if [[ $found = false ]];
	then
		echo -e "\nInstance name does not exist."
		return 1
	fi

	# It does exist. Are they sure? Very very very VERY sure?
	echo -e "\nWARNING: This will restart the Tomcat service!\n"
	echo -e "\nThe upgrade will be performed with the ROOT.war file located in $rootwarloc "
	read -p "Are you completely certain? (Y/N) : " areyousure

	case "$areyousure" in

		Y|y)
			# Stop the tomcat service
			echo -e "\nStopping Tomcat service."
			systemctl stop tomcat

			# Backup the <instance>/WEB-INF/xml/DataBase.xml file
			echo -e "\nBacking up DataBase.xml of instance: $instance"
			cp $webapploc/$instance/$DataBaseLoc/DataBase.xml /tmp

			# Delete the tomcat ROOT.war folder
			echo -e "\nDeleting Tomcat instance: $instance"
			rm $webapploc/$instance.war
			rm -rf $webapploc/$instance

			# Rename, copy and expand the replacement tomcat ROOT.war file
			echo -e "\nReplacing Tomcat instance: $instance"
			cp $rootwarloc/ROOT.war $webapploc/$instance.war && unzip -oq $webapploc/$instance.war -d $webapploc/$instance

			# Modify the log4j file inside the new instance to point to the right files/folders
			echo -e "\nModifying new instance: $instance to point to new log files"
			if [[ $instance = "ROOT" ]];
			then	
				sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File=$logfiles/JAMFChangeManagement.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/JAMFSoftwareServer.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/JSSAccess.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
			else
				sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File=$logfiles/$instance/JAMFChangeManagement.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/$instance/JAMFSoftwareServer.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/$instance/JSSAccess.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
			fi
		
			# Copy back the DataBase.xml file
			echo -e "\nCopying back DataBase.xml of instance: $instance"
			mv -f /tmp/DataBase.xml $webapploc/$instance$DataBaseLoc

			# Restart tomcat
			echo -e "\nRestarting Tomcat service"
			systemctl restart tomcat
		;;
		
		*)
			echo -e "\nSkipping upgrade of instance"
		;;

	esac
}

UpgradeAllInstances() {
	# Check for presence of Tomcat and MySQL before proceeding
	tomcat=$(yum -q list installed tomcat &>/dev/null && echo "yes" || echo "no" )
	mysql=$(yum -q list installed mysql-community-server &>/dev/null && echo "yes" || echo "no")

	if [[ $tomcat = "no" || $mysql = "no" ]];
	then
		echo -e "\nTomcat 7 / MySQL not present. Please install before trying again."
		return 1
	fi

	# It does exist. Are they sure? Very very very VERY sure?
	echo -e "\nWARNING: This will restart the Tomcat service and upgrade ALL JSS instances!"
	echo -e "\nThe upgrade will be performed with the ROOT.war file located in $rootwarloc "
	read -p "Are you completely certain you wish to upgrade ALL instances? (Y/N) : " areyousure

	case "$areyousure" in

		Y|y)	
			# Grab an array containing all current JSS instances for processing.
			webapps=($(find $webapploc/* -maxdepth 0 -type d | sed -r 's/^.+\///'))
		
			# Stop the tomcat service
			echo -e "\nStopping Tomcat service.\n"
			systemctl stop tomcat

			# Start the upgrade processing loop here.
			for (( i=0; i<${#webapps[@]}; i++ ));
			do
		
			# Line feed for clarity
			echo -e "\n"
		
			# Backup the <instance>/WEB-INF/xml/DataBase.xml file
			echo -e "Backing up DataBase.xml of instance: ${webapps[i]}"
			mv $webapploc/${webapps[i]}/$DataBaseLoc/DataBase.xml /tmp

			# Delete the tomcat ROOT.war folder
			echo -e "Deleting Tomcat instance: ${webapps[i]}"
			rm $webapploc/${webapps[i]}.war
			rm -rf $webapploc/${webapps[i]}

			# Rename, copy and expand the replacement tomcat ROOT.war file
			echo -e "Replacing Tomcat instance: ${webapps[i]}"
			cp $rootwarloc/ROOT.war $webapploc/${webapps[i]}.war && unzip -oq $webapploc/${webapps[i]}.war -d $webapploc/${webapps[i]}

			# Modify the log4j file inside the new instance to point to the right files/folders
			echo -e "\nModifying new instance: $instance to point to new log files"
			if [[ $instance = "ROOT" ]];
			then	
				sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File=$logfiles/JAMFChangeManagement.log@" $webapploc/${webapps[i]}/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/JAMFSoftwareServer.log@" $webapploc/${webapps[i]}/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/JSSAccess.log@" $webapploc/${webapps[i]}/WEB-INF/classes/log4j.properties
			else
				sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File=$logfiles/${webapps[i]}/JAMFChangeManagement.log@" $webapploc/${webapps[i]}/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/${webapps[i]}/JAMFSoftwareServer.log@" $webapploc/${webapps[i]}/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/${webapps[i]}/JSSAccess.log@" $webapploc/${webapps[i]}/WEB-INF/classes/log4j.properties
			fi

			# Copy back the DataBase.xml file
			echo -e "Copying back DataBase.xml of instance: ${webapps[i]}"
			mv -f /tmp/DataBase.xml $webapploc/${webapps[i]}/$DataBaseLoc/

			# Loop finishes here
			done
		
			# Restart tomcat
			echo -e "\nRestarting Tomcat service\n"
			systemctl restart tomcat
		;;

		*)
			echo -e "\nSkipping upgrade of instance"
		;;

	esac
}

MainMenu()
{
# Set IFS to only use new lines as field separator.
IFS=$'\n'

# Clear Screen
	clear

# Start menu screen here
	echo -e "\n----------------------------------------"
	echo -e "\n              JSS in a Box"
	echo -e "\n----------------------------------------"
	echo -e "    Version $currentver - $currentverdate"
	echo -e "----------------------------------------\n"

while [[ $choice != "q" ]]
do
	echo -e "\nMain Menu\n"
	echo -e "1) Check & Install Server Software"
	echo -e "2) Show list of current JSS instances"
	echo -e "3) Create new JSS & Database Instance"
	echo -e "4) Delete existing JSS & Database Instance"
	echo -e "5) Dump MySQL Database to file"
	echo -e "6) Upload MySQL dump to database"
	echo -e "7) Upgrade a single JSS instance"
	echo -e "8) Upgrade ALL JSS instances"
	echo -e "9) Refresh SSL certificates from CA"
	echo -e "q) Exit Script\n"

	read -p "Choose an option (1-9 / q) : " choice

	case "$choice" in
		1)
			InitialiseServer ;;
		2)
			InstanceList ;;
		3)
			CreateNewInstance ;;
		4)
			DeleteInstance ;;
		5)
			DumpDatabase ;;
		6)
			UploadDatabase ;;
		7)
			UpgradeInstance ;;
		8)
			UpgradeAllInstances ;;
		9)
			UpdateLeSSLKeys	;;
		q)
			echo -e "\nThank you for using JSS in a Box!"
			;;
		*)
			echo -e "\nIncorrect input. Please try again." ;;
	esac

done
}

## Main Code Begins here!

# Check for distribution, user privilege level and required files

WhichDistAmI
AmIroot
IsROOTwarPresent
PrepDBfile

# Parameter checking code here.

case "$1" in
	-d|--dump)
		DumpDatabase
		exit 0
	;;

	-i|--instance)
		InstanceList
		exit 0
	;;
	
	-u|--upgrade)
		UpgradeAllInstances
		exit 0
	;;
	
	-s|--ssl)
		UpdateLeSSLKeys
		exit 0
	;;
	
	-h|--help)
		echo -e "\nJSS in a Box"
		echo -e "Version $currentver - $currentverdate"
		echo -e "\nUsage: sudo ./jss-in-a-box.sh <option>"
		echo -e "Run without specifying options for interactive mode."
		echo -e "\nAvailable options:"
		echo -e "-d, --dump			Dump existings JSS database(s) to compressed files"
		echo -e "-h, --help			Shows this help screen"
		echo -e "-i, --instance			Lists all running JSS instances on this server"
		echo -e "-u, --upgrade			Performs an upgrade on ALL JSS instances from the provided ROOT.war file"
		echo -e "-s, --ssl			Updates the existing SSL certificates for Tomcat"
		exit 0
	;;
esac

# Run the main menu here.

MainMenu

exit 0
