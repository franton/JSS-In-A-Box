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

# Ubuntu 14.04 LTS ONLY at present!

# Author : Richard Purves <contact@richard-purves.com>

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

# Set up variables to be used here

# These variables are user modifiable.

export useract="richardpurves"							# Server admin username. Used for home location.

export letsencrypt="FALSE"									# Set this to TRUE if you are going to use LetsEncrypt as your HTTPS Certificate Authority.
export sslTESTMODE="TRUE"									# Set this to FALSE when you're confident it's generating proper certs for you
export ssldomain="jssinabox.westeurope.cloudapp.azure.com"	# Domain name for the SSL certificates
export sslemail="contact@richard-purves.com"				# E-mail address for the SSL CA
export sslkeypass="changeit"								# Password to the keystore. Default is "changeit". Please change it!

export mysqluser="root"										# MySQL root account
export mysqlpw="changeit"									# MySQL root account password. Please change it!
export mysqlserveraddress="localhost" 						# IP/Hostname of MySQL server. Default is local server.

export dbuser="jamfsoftware"								# Database username for JSS
export dbpass="changeit"									# Database password for JSS. Default is "changeit". Please change it!

# These variables should not be tampered with or script functionality will be affected!

currentdir=$( pwd )
currentver="1.0"
currentverdate="4th January 2016"

export homefolder="/home/$useract"							# Home folder base path
export rootwarloc="$homefolder"								# Location of where you put the ROOT.war file
export logfiles="/var/log/JSS"								# Location of ROOT and instance JSS log files

export tomcatloc="/var/lib/tomcat7"							# Tomcat's installation path
export server="$tomcatloc/conf/server.xml"					# Tomcat's server.xml based on install path
export webapploc="$tomcatloc/webapps"						# Tomcat's webapps folder based on install path

export tomcatuid="`id -u tomcat7`"							# User PID for Tomcat7
export tomcatdefault="/etc/default/tomcat7"					# Default config file for Tomcat7

export DataBaseLoc="/WEB-INF/xml/"							# DataBase.xml location inside the JSS webapp
export DataBaseXML="$rootwarloc/DataBase.xml.original"		# Location of the tmp DataBase.xml file we use for reference

export sslkeystorepath="$tomcatloc/keystore"				# The path for the SSL keystore we'll use in Tomcat
export lepath="/etc/letsencrypt/live"						# LetsEncrypt's certificate storage location

# All functions to be set up here

WhichDistAmI()
{
	# This script is currently designed for Ubuntu only, so let's fail gracefully if we're running on anything else.

	# Check for version
	version=$( lsb_release -d | cut -d " " -f2 | cut -c1-5 )

	# Is this Ubuntu 14.04 server?
	if [[ $version != "14.04" ]];
	then
		echo -e "\nScript requires Ubuntu Server 14.04. Exiting."
		exit 1
	else
		echo -e "\nUbuntu 14.04 detected. Proceeding."
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

UpdateAPT()
{
	# Now let's start by making sure the apt-get package list is up to date. Then an upgrade!
	echo -e "\nUpdating apt-get repository ...\n"
	apt-get update -q

	echo -e "\nUpgrading installed packages ...\n"
	apt-get upgrade -q -y
}

InstallGit()
{
	# Is git present?
	git=$(dpkg -l | grep -w "git" >/dev/null && echo "yes" || echo "no")

	if [[ $git = "no" ]];
	then
		echo -e "\ngit not present. Installing\n"
		apt-get install -q -y git
	else
		echo -e "\ngit already present. Proceeding."
	fi
}

InstallUnzip()
{
	# Is unzip installed?
	unzip=$(dpkg -l | grep -w "unzip" >/dev/null && echo "yes" || echo "no")
	
	if [[ $unzip = "no" ]];
	then
		echo -e "\nunzip not present. Installing\n"
		apt-get install -q -y unzip
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

InstallHTOP()
{
	# Is htop installed?
	unzip=$(dpkg -l | grep -w "htop" >/dev/null && echo "yes" || echo "no")
	
	if [[ $unzip = "no" ]];
	then
		echo -e "\nhtop not present. Installing\n"
		apt-get install -q -y htop
	else
		echo -e "\nhtop already present. Proceeding."
	fi
}

InstallUFW()
{
	# Is UFW present?
	ufw=$(dpkg -l | grep "ufw" >/dev/null && echo "yes" || echo "no")

	if [[ $ufw = "no" ]];
	then
		echo -e "\nufw not present. Installing.\n"
		apt-get install -q -y ufw
	else
		echo -e "\nufw already installed. Proceeding."
	fi
}

InstallOpenSSH()
{
	# Is OpenSSH present?
	openssh=$(dpkg -l | grep "openssh" >/dev/null && echo "yes" || echo "no")

	if [[ $openssh = "no" ]];
	then
		echo -e "\nopenssh not present. Installing.\n"
		apt-get install -q -y openssh
	else
		echo -e "\nopenssh already installed. Proceeding."
	fi
}

InstallOpenVMTools()
{
	# Are the open-vm-tools present?
	openvmtools=$(dpkg -l | grep "open-vm-tools" >/dev/null && echo "yes" || echo "no")

	if [[ $openvmtools = "no" ]];
	then
		echo -e "\nopen vm tools not present. Installing."

		echo -e "\nGetting VMware packaging keys from server.\n"
		wget http://packages.vmware.com/tools/keys/VMWARE-PACKAGING-GPG-DSA-KEY.pub
		wget http://packages.vmware.com/tools/keys/VMWARE-PACKAGING-GPG-RSA-KEY.pub

		echo -e "\nInstalling VMware packaging keys into apt.\n"
		apt-key add ./VMWARE-PACKAGING-GPG-DSA-KEY.pub
		apt-key add ./VMWARE-PACKAGING-GPG-RSA-KEY.pub

		echo -e "\nCleaning up key files.\n"
		rm ./VMWARE-PACKAGING-GPG-DSA-KEY.pub
		rm ./VMWARE-PACKAGING-GPG-RSA-KEY.pub

		echo -e "\nInstalling open vm tools.\n"
		apt-get install -q -y open-vm-tools
	else
		echo -e "\nopen vm tools already installed. Proceeding."
	fi
}

InstallJava8()
{
	# Is Oracle Java 1.8 present?
	java8=$(dpkg -l | grep "oracle-java8-installer" >/dev/null && echo "yes" || echo "no")

	if [[ $java8 = "no" ]];
	then
		echo -e "\nOracle Java 8 not present. Installing."

		echo -e "\nAdding webupd8team repository to list.\n"
		add-apt-repository -y ppa:webupd8team/java
		apt-get update

		echo -e "\nInstalling Oracle Java 8.\n"
		echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections
		apt-get install -q -y oracle-java8-installer

		echo -e "\nSetting Oracle Java 8 to the system default.\n"
		apt-get install -q -y oracle-java8-set-default
		
		echo -e "\nInstalling Java Cryptography Extension 8\n"
		curl -v -j -k -L -H "Cookie:oraclelicense=accept-securebackup-cookie" http://download.oracle.com/otn-pub/java/jce/8/jce_policy-8.zip  > $rootwarloc/jce_policy-8.zip
		unzip $rootwarloc/jce_policy-8.zip
		cp $rootwarloc/UnlimitedJCEPolicyJDK8/* /usr/lib/jvm/java-8-oracle/jre/lib/security
		rm $rootwarloc/jce_policy-8.zip
		rm -rf $rootwarloc/UnlimitedJCEPolicyJDK8

	else
		echo -e "\nOracle Java 8 already installed. Proceeding."
	fi
}

InstallTomcat()
{
	# Is Tomcat 7 present?
	tomcat=$(dpkg -l | grep "tomcat7" >/dev/null && echo "yes" || echo "no")

	if [[ $tomcat = "no" ]];
	then
		echo -e "\nTomcat 7 not present. Installing\n"
		apt-get install -q -y tomcat7
		
		echo -e "\nClearing out Tomcat 7 default ROOT.war installation\n"
		rm $webapploc/ROOT.war 2>/dev/null
		rm -rf $webapploc/ROOT	

		echo -e "\nSetting Tomcat to use Oracle Java 8 in /etc/default/tomcat7 \n"
		sed -i "s|#JAVA_HOME=/usr/lib/jvm/openjdk-6-jdk|JAVA_HOME=/usr/lib/jvm/java-8-oracle|" /etc/default/tomcat7	

		echo -e "\nSetting Tomcat to use more system ram\n"
		sed -i 's/$CATALINA_OPTS $JPDA_OPTS/$CATALINA_OPTS $JPDA_OPTS -server -Xms1024m -Xmx3052m -XX:MaxPermSize=128m/' /usr/share/tomcat7/bin/catalina.sh

		echo -e "\nStarting Tomcat service\n"
		service tomcat7 start
	else
		echo -e "\nTomcat already present. Proceeding."
	fi
}

InstallMySQL()
{
	# Is MySQL 5.6 present?
	mysql=$(dpkg -l | grep "mysql-server-5.6" >/dev/null && echo "yes" || echo "no")

	if [[ $mysql = "no" ]];
	then
		echo -e "\nMySQL 5.6 not present. Installing\n"
		debconf-set-selections <<< "mysql-server-5.6 mysql-server/root_password password $mysqlpw"
		debconf-set-selections <<< "mysql-server-5.6 mysql-server/root_password_again password $mysqlpw"
		apt-get install -q -y mysql-server-5.6
		
		echo -e "\nConfiguring MySQL 5.6 ...\n"
		sed -i "s/.*max_allowed_packet.*/max_allowed_packet	   = 256M/" /etc/mysql/my.cnf
		sed -i '/#max_connections        = 100/c\max_connections         = 400' /etc/mysql/my.cnf
		
	else
		echo -e "\nMySQL 5.6 already present. Proceeding."
	fi
}

SetupFirewall()
{	
	# It's time to harden the server firewall.
	# For Ubuntu, we're using UFW to do this.
	ufw --force disable		# Disables the firewall before we make our changes
	ufw --force reset		# Resets any firewall rules
	ufw allow ssh			# Port 22
#	ufw allow http			# Port 80  (JSS used to use this for xml lookups. Unsure if still needed.)
	ufw allow smtp			# Port 25
	ufw allow ntp			# Port 123
#	ufw allow ldap			# Port 389 (unsecure port. use for internal servers only)
#	ufw allow ldaps			# Port 636 (ssl ldap. hopefully to be used in preference to above)
	ufw allow https			# Port 443
	ufw allow mysql			# Port 3306
	ufw allow http-alt		# Port 8080 (delete once you got SSL working)
	ufw allow 2195			# Apple Push Notification Service
	ufw allow 2196			# Apple Push Notification Service
	ufw allow 5223			# Apple Push Notification Service
	ufw allow 5228			# Google Cloud Messaging
	ufw --force enable		# Turns on the firewall. May cause ssh disruption in the process.
}

SetupLogs()
{	
	# Check and create the JSS log file folder if missing with appropriate permissions.
	if [ ! -d $logfiles ];
	then
		mkdir $logfiles
		chown -R tomcat7:tomcat7 $logfiles
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
	service tomcat7 stop

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
	chown tomcat7:tomcat7 $sslkeystorepath
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

		echo -e "\nConfiguring HTTPS connector to use port 443\n"
		sed -i 's/port="8443"/port="443"/' $server

		echo -e "\nConfiguring HTTPS connector to use keystore and more advanced TLS\n"
		sed -i '/clientAuth="false" sslProtocol="TLS"/i sslEnabledProtocols="TLSv1.2,TLSv1.1,TLSv1" keystoreFile="'"$sslkeystorepath/keystore.jks"'" keystorePass="'"$sslkeypass"'" keyAlias="tomcat" ' $server

		echo -e "\nConfiguring HTTPS to use more secure ciphers\n"
		sed -i '/clientAuth="false" sslProtocol="TLS"/i ciphers="TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDH_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDH_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDH_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDH_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA,TLS_ECDH_RSA_WITH_AES_256_CBC_SHA384,TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA384,TLS_ECDH_RSA_WITH_AES_256_CBC_SHA,TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA,TLS_ECDH_RSA_WITH_AES_128_CBC_SHA256,TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA256,TLS_ECDH_RSA_WITH_AES_128_CBC_SHA,TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA,TLS_RSA_WITH_AES_128_CBC_SHA/" ' $server

		echo -e "\nConfiguring Tomcat to use AUTHBIND\n"
		sed -i 's/#AUTHBIND=no/AUTHBIND=yes/' $tomcatdefault
				
		echo -e "\nConfiguring Tomcat ByUID AUTHBIND file\n"
		echo '::/0,443' >>/etc/authbind/byuid/$tomcatuid
		echo '0.0.0.0/0,443' >>/etc/authbind/byuid/$tomcatuid
		chown tomcat7:tomcat7 /etc/authbind/byuid/$tomcatuid
		chmod 700 /etc/authbind/byuid/$tomcatuid
	else
		echo -e "\n$server appears to be already configured for HTTPS. Skipping\n"
	fi

	# We're done here. Start 'er up.
	service tomcat7 start
	
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
		service tomcat7 stop

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
		service tomcat7 start
	fi
}

InitialiseServer()
{
	# This is to make sure the appropriate services and software are installed and configured.
	UpdateAPT
	InstallGit
	InstallUnzip
	InstallHTOP
	InstallUFW
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
	tomcat=$(dpkg -l | grep "tomcat7" >/dev/null && echo "yes" || echo "no")
	mysql=$(dpkg -l | grep "mysql-server-5.6" >/dev/null && echo "yes" || echo "no")
	
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
		chown -R tomcat7:tomcat7 $logfiles
	else
		mkdir $logfiles/$instance
		touch $logfiles/$instance/JAMFChangeManagement.log
		touch $logfiles/$instance/JAMFSoftwareServer.log
		touch $logfiles/$instance/JSSAccess.log
		chown -R tomcat7:tomcat7 $logfiles/$instance
	fi

	# Finally modify the log4j file inside the new instance to point to the right files/folders
	echo -e "\nModifying new instance: $instance to point to new log files"
	if [[ $instance = "ROOT" ]];
	then	
		sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File=$logfiles/JAMFChangeManagement.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
		sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/JAMFSoftwareServer.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
		sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/JSSAccess.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
	else
		sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File==$logfiles/$instance/JAMFChangeManagement.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
		sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/$instance/JAMFSoftwareServer.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
		sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/$instance/JSSAccess.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
	fi

	# Restart Tomcat 7
	echo -e "\nRestarting Tomcat 7\n"
	service tomcat7 restart
}

InstanceList()
{
	tomcat=$(dpkg -l | grep "tomcat7" >/dev/null && echo "yes" || echo "no")

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
	tomcat=$(dpkg -l | grep "tomcat7" >/dev/null && echo "yes" || echo "no")
	mysql=$(dpkg -l | grep "mysql-server-5.6" >/dev/null && echo "yes" || echo "no")

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
		service tomcat7 stop

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
			rm -rf /var/lib/tomcat7/work/Catalina/localhost/_ 2>/dev/null
		else
			rm -rf /var/lib/tomcat7/work/Catalina/localhost/$instance 2>/dev/null
		fi
		
		# Restart tomcat
		echo -e "\nRestarting Tomcat service\n"
		service tomcat7 restart
		;;

		*)
			echo -e "\nSkipping deletion of instance"
		;;

	esac
}

DumpDatabase()
{
	# Is MySQL 5.6 present?
	mysql=$(dpkg -l | grep "mysql-server-5.6" >/dev/null && echo "yes" || echo "no")

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
		service tomcat7 stop
				
		for db in $databases; do
			echo "Dumping database: $db"
			mysqldump -h$mysqlserveraddress -u$mysqluser -p$mysqlpw $db 2>/dev/null | gzip > $rootwarloc/$db.sql.gz
		done
		
		# Restart tomcat
		echo -e "\nRestarting Tomcat service"
		service tomcat7 restart
				
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
	mysql=$(dpkg -l | grep "mysql-server-5.6" >/dev/null && echo "yes" || echo "no")

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
				service tomcat7 stop

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
				service tomcat7 restart
				
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
			service tomcat7 stop
			
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
			service tomcat7 restart
		;;
		
		*)
			echo -e "\nSkipping database restoration"
		;;

	esac
}

UpgradeInstance()
{
	# Check for presence of Tomcat and MySQL before proceeding
	tomcat=$(dpkg -l | grep "tomcat7" >/dev/null && echo "yes" || echo "no")
	mysql=$(dpkg -l | grep "mysql-server-5.6" >/dev/null && echo "yes" || echo "no")

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
			service tomcat7 stop

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
				sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File==$logfiles/$instance/JAMFChangeManagement.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/$instance/JAMFSoftwareServer.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/$instance/JSSAccess.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
			fi
		
			# Copy back the DataBase.xml file
			echo -e "\nCopying back DataBase.xml of instance: $instance"
			mv -f /tmp/DataBase.xml $webapploc/$instance$DataBaseLoc

			# Restart tomcat
			echo -e "\nRestarting Tomcat service"
			service tomcat7 restart
		;;
		
		*)
			echo -e "\nSkipping upgrade of instance"
		;;

	esac
}

UpgradeAllInstances() {
	# Check for presence of Tomcat and MySQL before proceeding
	tomcat=$(dpkg -l | grep "tomcat7" >/dev/null && echo "yes" || echo "no")
	mysql=$(dpkg -l | grep "mysql-server-5.6" >/dev/null && echo "yes" || echo "no")

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
			service tomcat7 stop

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
				sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File=$logfiles/JAMFChangeManagement.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/JAMFSoftwareServer.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/JSSAccess.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
			else
				sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File==$logfiles/$instance/JAMFChangeManagement.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/$instance/JAMFSoftwareServer.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/$instance/JSSAccess.log@" $webapploc/$instance/WEB-INF/classes/log4j.properties
			fi

			# Copy back the DataBase.xml file
			echo -e "Copying back DataBase.xml of instance: ${webapps[i]}"
			mv -f /tmp/DataBase.xml $webapploc/${webapps[i]}/$DataBaseLoc/

			# Loop finishes here
			done
		
			# Restart tomcat
			echo -e "\nRestarting Tomcat service\n"
			service tomcat7 restart
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
