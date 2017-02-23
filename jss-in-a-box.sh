#!/bin/bash

##########################################################################################
#
# JSS in a Box
# (aka a script to initialise, create, configure and delete JSS instances on a Ubuntu/RedHat server.)
# (with apologies to Tom Bridge and https://github.com/tbridge/munki-in-a-box)
#
# The MIT License (MIT)
# Copyright (c) 2015 <richard at richard-purves.com>
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
# Version 1.1 - 12th April 2016    - Update of SSL cipher list to bring into line with https://jamfnation.jamfsoftware.com/article.html?id=384
# Version 2.0 - 14th April 2016    - Merged both scripts together. Now one big universal version with better OS checking.
# Version 2.1 - 16th April 2016    - Now manages Tomcat, MySQL and Java memory settings. Calculated per current formulas on JAMF's CJA course.
# Version 2.2 - 18th April 2016    - Optional redirection of HTTPS traffic to port 443 from 8443 via firewall rules.
# Version 2.3 - 21st April 2016    - Tomcat really doesn't like running with less than 1Gb ram, so we check for 1.5Gb available. Quit if not available.
# Version 2.4 - 22nd April 2016	   - Choice of which supported Java version to install. In variable below.
# Version 2.5 - 15th June 2016	   - Fixed missing rule in UFW configuration. Also fixed bug where connector keystore file isn't set properly.
# Version 2.6 - 23rd June 2016	   - Recoded large chunks of the LetsEncrypt code due to them suddenly getting distribution via repo AND changing the name of the binary that does the work.
# Version 2.7 - 14th July 2016 	   - Added code to make sure that tomcat webapp folders have correct ownership of the appropriate tomcat user.
# Version 3.0 - 4th August 2016	   - Removed Java 7, upgraded Tomcat to version 8. Refactored all the relevant code and paths to compensate for manual install. Down 300+ lines for same functionality!
# Version 3.1 - 6th August 2016	   - Cleaned up some embarrassing typos and code swapping to do with LetsEncrypt. Also some interesting Tomcat 8 server.xml changes.
#									 Big thanks to Cody Butcher for his help on this!
# Version 3.2 - 17th February 2017 - Fixed some pesky mysql error redirection stuff. Won't be prompted for insecure command line anymore!
#									 Fixed some very annoying tomcat webapp folder ownership stuff that never worked properly. Apparently.
# Version 3.3 - 23rd February 2017 - Brought the Tomcat HTTPS connector settings into line with Jamf's current documentation.
# Version 3.5 - 23rd February 2017 - Major update to use Ubuntu 16.04 LTS in place of 14.04 LTS. Java now uses OpenJDK 8 on both OS. Tomcat has a unified systemd launcher. Code simplified.
#									 Big thanks to Rich Trouton for quickly helping me with the systemd testing today!

# Set up variables to be used here

# These variables are user modifiable. Don't forget to configure firewall settings from Line 737!

export useract="richardpurves"								# Server admin username. Used for home location.

export letsencrypt="FALSE"									# Set this to TRUE if you are going to use LetsEncrypt as your HTTPS Certificate Authority.
export sslTESTMODE="TRUE"									# Set this to FALSE when you're confident it's generating proper certs for you
export httpsredirect="FALSE"								# Set this to TRUE if you want your JSS to appear to be on port 443 using HTTPS
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
currentver="3.5"
currentverdate="23rd February 2017"

export homefolder="/home/$useract"							# Home folder base path
export rootwarloc="$homefolder"								# Location of where you put the ROOT.war file
export logfiles="/var/log/JSS"								# Location of ROOT and instance JSS log files

export tomcatloc="/opt/tomcat8"								# Tomcat's installation path
export webapploc="$tomcatloc/webapps"						# Tomcat web application install path
export user="tomcat"										# User and Group used for tomcat
export sslkeystorepath="$tomcatloc/keystore"				# Keystore path
export server="$tomcatloc/conf/server.xml"					# Tomcat server.xml path

export ubmycnfloc="/etc/mysql/my.cnf"						# MySQL's configuration file path(s)
export rhmycnfloc="/etc/my.cnf"

export DataBaseLoc="WEB-INF/xml"							# DataBase.xml location inside the JSS webapp
export DataBaseXML="$rootwarloc/DataBase.xml.original"		# Location of the tmp DataBase.xml file we use for reference

export lepath="/etc/letsencrypt/live"						# LetsEncrypt's certificate storage location

# All functions to be set up here

WhichDistAmI()
{
	# First check is for Ubuntu 14.04 LTS	
	if [ -f "/usr/bin/lsb_release" ];
	then
		ubuntuVersion=`lsb_release -s -d`

		case $ubuntuVersion in
			*"Ubuntu 16.04"*)
				OS="Ubuntu"
				export OS
			;;

			*)
				echo -e "Script requires Ubuntu 16.04 LTS. Exiting."
				exit 1
			;;
		esac
	fi

	# Second check is for RedHat 7.x
	if [ -f "/etc/redhat-release" ];
	then
		version=$( cat /etc/redhat-release | awk '{ print $7 }' | cut -c 1 )

		# Is this RedHat 7 server?
		if [[ $version != "7" ]];
		then
			echo -e "Script requires RedHat 7.x. Exiting."
			exit 1
		else
			echo -e "Redhat 7 detected. Proceeding."
			OS="RedHat"
			export OS
		fi
	fi
	
	# Last check is to see if we got a bite or not
	if [[ $OS != "Ubuntu" && $OS != "RedHat" ]];
	then
		echo -e "Script requires either Ubuntu 14.04 LTS or RHEL 7.x. Exiting."
		exit 1
	fi
}

AmIroot()
{
	# Check for root, quit if not present with a warning.
	if [[ "$(id -u)" != "0" ]];
	then
		echo -e "Script needs to be run as root."
		exit 1
	else
		echo -e "Script running as root. Proceeding."
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

TomcatService()
{
	systemctl $1 tomcat
}

MySQLService()
{
	systemctl $1 mysql
}

CheckMySQL()
{
	if [[ $OS = "Ubuntu" ]];
	then
		export mysql=$(dpkg -l | grep "mysql-server-5.6" >/dev/null && echo "yes" || echo "no")
	fi
	
	if [[ $OS = "RedHat" ]];
	then
		export mysql=$(yum -q list installed mysql-community-server &>/dev/null && echo "yes" || echo "no")
	fi
}

InstanceList()
{
	# Is Tomcat present?
	[ -d "$tomcatloc" ] && tomcat="yes" || tomcat="no"	

	if [[ $tomcat = "no" ]];
	then
		echo -e "\nTomcat 8 not present. Please install before trying again."
	else
		echo -e "\nJSS Instance List\n-----------------\n"
		find $tomcatloc/webapps/* -maxdepth 0 -type d 2>/dev/null | sed -r 's/^.+\///'
	fi
}

SetupTomcatUser()
{
	export user="tomcat"
}

SetupLogs()
{	
	# Check and create the JSS log file folder if missing with appropriate permissions.
	if [ ! -d $logfiles ];
	then
		mkdir $logfiles
		SetupTomcatUser
		chown -R $user:$user $logfiles
	fi
}

UpdatePkgMgr()
{
	if [[ $OS = "Ubuntu" ]];
	then
		echo -e "\nUpdating apt-get repository ...\n"
		apt-get update -q

		echo -e "\nUpgrading installed packages ...\n"
		apt-get upgrade -q -y
	fi
	
	if [[ $OS = "RedHat" ]];
	then
	
	# Is the delta RPM module installed?
	deltarpm=$(yum -q list installed deltarpm &>/dev/null && echo "yes" || echo "no")

		if [[ $git = "no" ]];
		then
			echo -e "\nInstalling Delta RPM functionality\n"
			yum install -y deltarpm
		else
			echo -e "\nDelta RPM already present. Proceeding."
		fi
	
		echo -e "\nUpdating yum repository ...\n"
		yum -q -y update
	fi
}

InstallGit()
{
	if [[ $OS = "Ubuntu" ]];
	then
		# Is git present?
		git=$(dpkg -l | grep -w "git" >/dev/null && echo "yes" || echo "no")

		if [[ $git = "no" ]];
		then
			echo -e "\ngit not present. Installing\n"
			apt-get install -q -y git
		else
			echo -e "\ngit already present. Proceeding."
		fi
	fi

	if [[ $OS = "RedHat" ]];
	then
		# Is git present?
		git=$(yum -q list installed git &>/dev/null && echo "yes" || echo "no" )

		if [[ $git = "no" ]];
		then
			echo -e "\ngit not present. Installing."
			yum -q -y install git
		else
			echo -e "\ngit already present. Proceeding."
		fi
	fi
}

InstallCurl()
{
	if [[ $OS = "Ubuntu" ]];
	then
		# Is curl present?
		git=$(dpkg -l | grep -w "curl" >/dev/null && echo "yes" || echo "no")

		if [[ $git = "no" ]];
		then
			echo -e "\ncurl not present. Installing\n"
			apt-get install -q -y curl
		else
			echo -e "\ncurl already present. Proceeding."
		fi
	fi

	if [[ $OS = "RedHat" ]];
	then
		# Is wget present?
		wget=$(yum -q list installed curl &>/dev/null && echo "yes" || echo "no" )

		if [[ $wget = "no" ]];
		then
			echo -e "\nwcurl not present. Installing."
			yum -q -y install curl
		else
			echo -e "\ncurl already present. Proceeding."
		fi
	fi
}

InstallWget()
{
	if [[ $OS = "Ubuntu" ]];
	then
		# Is wget present?
		git=$(dpkg -l | grep -w "wget" >/dev/null && echo "yes" || echo "no")

		if [[ $git = "no" ]];
		then
			echo -e "\nwget not present. Installing\n"
			apt-get install -q -y wget
		else
			echo -e "\nwget already present. Proceeding."
		fi
	fi

	if [[ $OS = "RedHat" ]];
	then
		# Is wget present?
		wget=$(yum -q list installed wget &>/dev/null && echo "yes" || echo "no" )

		if [[ $wget = "no" ]];
		then
			echo -e "\nwget not present. Installing."
			yum -q -y install wget
		else
			echo -e "\nwget already present. Proceeding."
		fi
	fi
}

InstallUnzip()
{
	if [[ $OS = "Ubuntu" ]];
	then
		# Is unzip installed?
		unzip=$(dpkg -l | grep -w "unzip" >/dev/null && echo "yes" || echo "no")
	
		if [[ $unzip = "no" ]];
		then
			echo -e "\nunzip not present. Installing\n"
			apt-get install -q -y unzip
		else
			echo -e "\nunzip already present. Proceeding."
		fi
	fi

	if [[ $OS = "RedHat" ]];
	then
		# Is unzip installed?
		unzip=$(yum -q list installed unzip &>/dev/null && echo "yes" || echo "no" )
	
		if [[ $unzip = "no" ]];
		then
			echo -e "\nunzip not present. Installing\n"
			yum -q -y install unzip
		else
			echo -e "\nunzip already present. Proceeding."
		fi
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
	if [[ $OS = "Ubuntu" ]];
	then
		# Is UFW present?
		ufw=$(dpkg -l | grep "ufw" >/dev/null && echo "yes" || echo "no")

		if [[ $ufw = "no" ]];
		then
			echo -e "\nufw not present. Installing.\n"
			apt-get install -q -y ufw
		else
			echo -e "\nufw already installed. Proceeding."
		fi
	fi
		
	if [[ $OS = "RedHat" ]];
	then
		# Is firewalld installed?
		fwd=$(yum -q list installed firewalld &>/dev/null && echo "yes" || echo "no" )

		if [[ $fwd = "no" ]];
		then
			echo -e "\nFirewallD not present. Installing."
			yum -q -y install firewalld
		else
			echo -e "\nFirewallD already installed. Proceeding."
		fi
	fi
}

InstallOpenSSH()
{
	if [[ $OS = "Ubuntu" ]];
	then
		# Is OpenSSH present?
		openssh=$(dpkg -l | grep "openssh" >/dev/null && echo "yes" || echo "no")

		if [[ $openssh = "no" ]];
		then
			echo -e "\nopenssh not present. Installing.\n"
			apt-get install -q -y openssh
		else
			echo -e "\nopenssh already installed. Proceeding."
		fi
	fi
	
	if [[ $OS = "RedHat" ]];
	then	
		# Is OpenSSH present?
		openssh=$(yum -q list installed openssh &>/dev/null && echo "yes" || echo "no" )

		if [[ $openssh = "no" ]];
		then
			echo -e "\nopenssh not present. Installing.\n"
			yum -q -y install openssh
		else
			echo -e "\nopenssh already installed. Proceeding."
		fi
	fi
}

InstallOpenVMTools()
{
	if [[ $OS = "Ubuntu" ]];
	then
		# Are the open-vm-tools present?
		openvmtools=$(dpkg -l | grep "open-vm-tools" >/dev/null && echo "yes" || echo "no")

		if [[ $openvmtools = "no" ]];
		then
			echo -e "\nopen vm tools not present. Installing."

			echo -e "\nGetting VMware packaging keys from server."
			wget http://packages.vmware.com/tools/keys/VMWARE-PACKAGING-GPG-DSA-KEY.pub
			wget http://packages.vmware.com/tools/keys/VMWARE-PACKAGING-GPG-RSA-KEY.pub

			echo -e "\nInstalling VMware packaging keys into apt."
			apt-key add ./VMWARE-PACKAGING-GPG-DSA-KEY.pub
			apt-key add ./VMWARE-PACKAGING-GPG-RSA-KEY.pub

			echo -e "\nCleaning up key files."
			rm ./VMWARE-PACKAGING-GPG-DSA-KEY.pub
			rm ./VMWARE-PACKAGING-GPG-RSA-KEY.pub

			echo -e "\nInstalling open vm tools."
			apt-get install -q -y open-vm-tools
		else
			echo -e "\nopen vm tools already installed. Proceeding."
		fi
	fi
	
	if [[ $OS = "RedHat" ]];
	then
		# Are the open-vm-tools present?
		openvmtools=$(yum -q list installed open-vm-tools &>/dev/null && echo "yes" || echo "no" )

		if [[ $openvmtools = "no" ]];
		then
			echo -e "\nopen vm tools not present. Installing."
			yum -q -y install open-vm-tools
		else
			echo -e "\nopen vm tools already installed. Proceeding."
		fi
	fi
}

InstallJava()
{
	if [[ $OS = "Ubuntu" ]];
	then
		# Is Oracle Java 1.8 present?
		java8=$(dpkg -l | grep "openjdk-8-jre" >/dev/null && echo "yes" || echo "no")

		if [[ $java8 = "no" ]];
		then
			echo -e "\nOpenJDK 8 not present. Installing."
			apt-get install -q -y openjdk-8-jre
	
			echo -e "\nInstalling Java Cryptography Extension 8\n"
			curl -v -j -k -L -H "Cookie:oraclelicense=accept-securebackup-cookie" http://download.oracle.com/otn-pub/java/jce/8/jce_policy-8.zip  > $rootwarloc/jce_policy-8.zip
			unzip $rootwarloc/jce_policy-8.zip
			cp $rootwarloc/UnlimitedJCEPolicyJDK8/* /usr/lib/jvm/java-8-openjdk-amd64/jre/lib/security
			rm $rootwarloc/jce_policy-8.zip
			rm -rf $rootwarloc/UnlimitedJCEPolicyJDK8
		else
			echo -e "\nOpenJDK 8 already installed. Proceeding."
		fi
	fi

	if [[ $OS = "RedHat" ]];
	then
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
	fi
}

InstallTomcat()
{
	# Is Tomcat present?
	[ -d "$tomcatloc" ] && tomcat="yes" || tomcat="no"

	if [[ $tomcat = "no" ]];
	then
		echo -e "\nTomcat 8 not installed. Installing."

		# Create tomcat group
		echo -e "\nCreating user group: $user"
		groupadd $user

		if [[ $OS = "Ubuntu" ]];
		then
			echo -e "\nUbuntu detected."
		
			# Create tomcat user - Ubuntu 14.04 LTS
			echo -e "\nCreating tomcat user: $user"
			useradd -s /bin/false -g "$user" -d /opt/tomcat "$user"
		fi
		
		if [[ $OS = "RedHat" ]];
		then
			echo -e "\nRedHat detected."

			# Create tomcat user - RHEL 7.x
			echo -e "\nCreating tomcat user: $user"
			useradd -M -s /sbin/nologin -g "$user" -d /opt/tomcat "$user"
		fi

		# Create systemd script so tomcat can run as a service
		echo -e "\nCreating systemd script for Tomcat 8"
		
systemd='# Systemd unit file for tomcat
# Created by JSS in a Box
[Unit]
Description=Apache Tomcat Web Application Container
After=syslog.target network.target

[Service]
Type=forking

ExecStart=/opt/tomcat8/bin/startup.sh
ExecStop=/bin/kill -15 $MAINPID

User=tomcat
Group=tomcat

[Install]
WantedBy=multi-user.target
Alias=tomcat.service'

		echo "$systemd" > /lib/systemd/system/tomcat.service
		systemctl daemon-reload

		# Find latest tomcat version
		echo -e "\nFinding latest Tomcat 8 version"
		version=$( curl -s http://tomcat.apache.org/download-80.cgi | grep "<h3 id=\"8.0" | head -n1 | awk '{gsub("<[^>]*>", "")}1' )
		echo -e "\nVersion: $version"

		# Work out proper download path
		path="http://www.apache.org/dist/tomcat/tomcat-8/v${version}/bin/apache-tomcat-${version}.tar.gz"

		# Grab the latest .tar.gz distribution and install to /opt
		echo -e "\nDownloading and installing latest Tomcat 8"
		cd /opt
		wget $path
		tar -xzf /opt/apache-tomcat-${version}.tar.gz
		mv /opt/apache-tomcat-${version} "$tomcatloc"
		rm /opt/apache-tomcat-${version}.tar.gz

		# Configure permissions on tomcat installation
		echo -e "\nConfiguring Tomcat folder permissions"
		chown -R $user:$user $tomcatloc
		chmod g+rwx $tomcatloc/conf
		chmod g+r $tomcatloc/conf/*

		chmod g+rwx $tomcatloc/webapps
		chmod g+r $tomcatloc/webapps/*
		
		# Configure Tomcat environment variable
		echo -e "\nSetting Tomcat environment variable"
		echo "export CATALINA_HOME="${tomcatloc}"" >> ~/.bashrc
		source ~/.bashrc

		# Create Tomcat setenv.sh configuration file
setenv='#!/bin/bash

# Tomcat configuration file. Generated by JSS-in-a-Box.

CATALINA_BASE='"'$tomcatloc'"'
CATALINA_HOME="$CATALINA_BASE"
CATALINA_OPTS="-Xms1024m -Xmx3072m"
CATALINA_OPTS="$CATALINA_OPTS -XX:MaxPermSize=512m"
CATALINA_OPTS="$CATALINA_OPTS -Xss256k"
CATALINA_OPTS="$CATALINA_OPTS -XX:MaxGCPauseMillis=1500"
CATALINA_OPTS="$CATALINA_OPTS -XX:GCTimeRatio=9"
CATALINA_OPTS="$CATALINA_OPTS -Djava.awt.headless=true"
CATALINA_OPTS="$CATALINA_OPTS -server"
CATALINA_OPTS="$CATALINA_OPTS -XX:+DisableExplicitGC"
CATALINA_OPTS="$CATALINA_OPTS -Djava.security.egd=file:/dev/./urandom"'

echo "$setenv" > $tomcatloc/bin/setenv.sh
chown tomcat:tomcat $tomcatloc/bin/setenv.sh
chmod 750 $tomcatloc/bin/setenv.sh

		# Clean default tomcat webapps out. We don't require them and could be a security hazard.	
		echo -e "\nClearing out Tomcat default installations"
		rm -rf $tomcatloc/webapps/* 2>/dev/null
		
		echo -e "\nEnabling Tomcat to start on system restart"
		systemctl enable tomcat
	else
		echo -e "\nTomcat already present. Proceeding."
	fi
}

InstallMySQL()
{
	if [[ $OS = "Ubuntu" ]];
	then
		# Is MySQL 5.6 present?
		mysql=$(dpkg -l | grep "mysql-server-5.6" >/dev/null && echo "yes" || echo "no")

		if [[ $mysql = "no" ]];
		then
			echo -e "\nMySQL 5.6 not present. Installing\n"

			# MySQL 5.6 isn't part of the standard Ubuntu 16.04 repo, so we'll have to add that first.
			echo -e "\nAdding Ubuntu Trusty repo and updating\n"
			apt install -q -y software-properties-common
			add-apt-repository 'deb http://archive.ubuntu.com/ubuntu trusty universe'
			apt-get update

			echo -e "\nSetting MySQL password defaults\n"
			debconf-set-selections <<< "mysql-server-5.6 mysql-server/root_password password $mysqlpw"
			debconf-set-selections <<< "mysql-server-5.6 mysql-server/root_password_again password $mysqlpw"

			echo -e "\nInstalling MySQL 5.6\n"
			apt-get install -q -y mysql-server-5.6
			
			echo -e "\nEnabling MySQL to start on system restart"
			systemctl enable mysql

			echo -e "\nStarting MySQL 5.6"
			MySQLService start
		else
			echo -e "\nMySQL 5.6 already present. Proceeding."
		fi
	fi

	if [[ $OS = "RedHat" ]];
	then	
		# Is MySQL 5.6 present?
		mysql=$(yum -q list installed mysql-community-server &>/dev/null && echo "yes" || echo "no")

		if [[ $mysql = "no" ]];
		then
			echo -e "\nMySQL 5.6 not present. Installing."

			echo -e "\nAdding MySQL 5.6 to yum repo list\n"
			wget http://repo.mysql.com/mysql-community-release-el7.rpm -P $homefolder
			rpm -ivh $homefolder/mysql-community-release-el7.rpm
			rm $homefolder/mysql-community-release-el7.rpm
		
			echo -e "\nInstalling MySQL 5.6\n"
			yum -q -y install mysql-server

			echo -e "\nEnabling MySQL to start on system restart"
			systemctl enable mysql

			echo -e "\nStarting MySQL 5.6"
			MySQLService start
		
			echo -e "\nSecuring MySQL 5.6\n"
			mysqladmin -u root password $mysqlpw
		else
			echo -e "\nMySQL 5.6 already present. Proceeding."
		fi
	fi
}

SetupFirewall()
{	
	# It's time to harden the server firewall.
	if [[ $OS = "Ubuntu" ]];
	then
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
		ufw allow 8443			# Port 8443 (delete if you enable 443 redirection or are using 8080 above)
		ufw allow 2195			# Apple Push Notification Service
		ufw allow 2196			# Apple Push Notification Service
		ufw allow 5223			# Apple Push Notification Service
		ufw allow 5228			# Google Cloud Messaging
		ufw --force enable		# Turns on the firewall. May cause ssh disruption in the process.
		
		# Is https redirect enabled? If so, we have to set up some firewall rules to direct 8443 to 443.
		# We're going to use firewall port redirection as the alternative using authbind has proven unreliable.
		# And we have to add the rules manually before totally restarting the service too. Fun.
		if [[ $httpsredirect = "TRUE" ]];
		then
			# Append the following lines into the before firewall rules file.
			echo "# Port 443 to 8443 redirect rules - added by JSS in a Box" >> /etc/ufw/before.rules
			echo "*nat" >> /etc/ufw/before.rules
			echo ":PREROUTING ACCEPT [0:0]" >> /etc/ufw/before.rules
			echo "-A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443" >> /etc/ufw/before.rules
			echo "COMMIT" >> /etc/ufw/before.rules
			
			# Restart the entire UFW service or this won't work until reboot.
			service ufw restart
		fi
	fi

	if [[ $OS = "RedHat" ]];
	then	
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
		
		# Is https redirect enabled? If so, we have to set up some firewall rules to direct 443 to 8443.
		# A little nicer than UFW, as there are commands to do this instead of directly manipulating firewall rules.
		if [[ $httpsredirect = "TRUE" ]];
		then
			firewall-cmd --permanent --add-masquerade
			firewall-cmd --permanent --add-forward-port=port=443:proto=tcp:toport=8443
			firewall-cmd --reload
		fi	
	fi
}

InstallLetsEncrypt()
{
	# Is LetsEncrypt present?
	# This one is a git clone, rather than an installation for cross distro reasons. We'll be putting this in /usr/local/letsencrypt
	if [ ! -d "/opt/letsencrypt" ];
	then
		echo -e "\nLetsEncrypt not present. Downloading installation script from dl.eff.org.\n"
		mkdir /opt/letsencrypt
		cd /opt/letsencrypt
		wget https://dl.eff.org/certbot-auto
		chmod +x /opt/letsencrypt/certbot-auto
		sudo -H /opt/letsencrypt/certbot-auto -n
		cd $currentdir
	else
		echo -e "\nLetsEncrypt is already installed. Proceeding."
		return
	fi

	# We'll be doing some work with Tomcat so let's stop the service to make sure we don't hurt anything.
	echo "\nStopping Tomcat service\n"
	TomcatService stop

	# Get LetsEncrypt to generate the appropriate certificate files for later processing.
	# We're using sudo -H even as root because there's some weird errors that happen if you don't.
	echo -e "\nObtaining Certificate from LetsEncrypt Certificate Authority\n"
	if [[ $sslTESTMODE = "TRUE" ]];
	then
		sudo -H /opt/letsencrypt/certbot-auto certonly --standalone -m $sslemail -d $ssldomain --agree-tos --test-cert
	else
		sudo -H /opt/letsencrypt/certbot-auto certonly --standalone -m $sslemail -d $ssldomain --agree-tos
	fi

	# Code to generate a Java KeyStore for Tomcat from what's provided by LetsEncrypt
	# Based on work by Carmelo Scollo (https://melo.myds.me)
	# https://community.letsencrypt.org/t/how-to-use-the-certificate-for-tomcat/3677/9

	# Create a keystore folder for Tomcat with the correct permissions
	mkdir $sslkeystorepath
	chown $user:$user $sslkeystorepath
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

	# Tomcat server.xml was previous prepared in the ConfigureMemoryUseage function.
	# Now we disable HTTP and enable the HTTPS connectors

	echo -e "\nDisabling Tomcat HTTP connector\n"
	sed -i '75i<!--' $server
	sed -i '80i-->' $server

	echo -e "\nEnabling Tomcat HTTPS Connector with executor\n"
	sed -i '94d' $server
	sed -i '86d' $server
	
	# We're done here. Start 'er up.
	TomcatService start
	
	# Oh wait, we have to set up a periodic renewal since LetsEncrypt doesn't do that for Tomcat
 	# (at time of coding - 23rd June 2016)
 	# This should run every night at midnight. LE certs last 90 days but quicker is fine as it won't renew.
 	crontab -l | { echo "0 0 * * *	$homefolder/jss-in-a-box.sh -s"; } | crontab -
	
	# The following commented out code is the forthcoming systemd replacement for the crontab job above.

lerenew='[Unit]
Description=Perform LetsEncrypt tomcat certificate renewal

[Timer]
OnCalendar=daily

[Install]
WantedBy=timers.target'

# echo "$lerenew" > /etc/systemd/system/le-renew.timer

leservice='[Unit]
Description=Perform LetsEncrypt tomcat certificate renewal

[Service]
Type=simple
Nice=19
IOSchedulingClass=2
IOSchedulingPriority=7
ExecStart="$homefolder"/jss-in-a-box.sh -s'

# echo "$leservice" > /etc/systemd/system/le-renew.timer

# sudo systemctl start le-renew.service
}

UpdateLeSSLKeys()
{
	# update SSL keys from LetsEncrypt

	# Is LetsEncrypt present?
	if [[ $letsencrypt = "FALSE" ]];
	then
		echo -e "\nLetsEncrypt option disabled in script. Cannot proceed.\n"
		return 1
	else
		# Derive the correct file locations from the current tomcat install location
		export sslkeystorepath="$tomcatloc/keystore"
		export server="$tomcatloc/conf/server.xml"

		# We'll be doing some work with Tomcat so let's stop the service to make sure we don't hurt anything.
		echo -e "\nStopping Tomcat service\n"
		TomcatService stop

		# Get LetsEncrypt to generate the appropriate certificate files for later processing.
		# We're using sudo -H even as root because there's some weird errors that happen if you don't.
		echo -e "\nObtaining Certificate from LetsEncrypt Certificate Authority\n"
		if [[ $sslTESTMODE = "TRUE" ]];
		then
			sudo -H /opt/letsencrypt/certbot-auto renew --dry-run
		else
			sudo -H /opt/letsencrypt/certbot-auto renew --quiet --no-self-upgrade
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
		TomcatService start
	fi
}

ConfigureMemoryUsage()
{
	# Derive the correct file locations from the current OS
	webapps="$tomcatloc/webapps"
	server="$tomcatloc/conf/server.xml"
	sslkeystorepath="$tomcatloc/keystore"
	server="$tomcatloc/conf/server.xml"
	tomcatconf="$tomcatloc/bin"
		
	# Now we work out the correct memory and connection settings
	# What's the default MaxPoolSize?
	MaxPoolSize=$( cat $DataBaseXML | grep MaxPoolSize | sed 's/[^0-9]*//g' )
	echo -e "\nMax Pool Size : $MaxPoolSize"

	# How many JSS instances do we currently have? We need at least one, so check for that too.
	NoOfJSSinstances=$( find $webapps/* -maxdepth 0 -type d 2>/dev/null | sed -r 's/^.+\///' | wc -l )
	if [ $NoOfJSSinstances -lt 1 ];
	then
		NoOfJSSinstances=1
	fi
	echo -e "\nNo of current JSS instances: $NoOfJSSinstances"

	# MaxThreads = ( MaxPoolSize x 2.5 ) x no of webapps
	MaxThreads=$( awk "BEGIN {print ($MaxPoolSize*2.5)*$NoOfJSSinstances}" )
	echo -e "\nOptimal Max Threads calculated to be: $MaxThreads"

	# Derive the maximum number of SQL connections based on the above information
	# Formula is: Maximum Pool Size x No of JSS instances plus one ;)
	MySQLMaxConnections=$( awk "BEGIN {print ($MaxPoolSize*$NoOfJSSinstances)+1}" )

	# Work out the amount of system memory, convert to Mb and then subtract 256Mb
	# That'll be what we'll allocate to Java as a maximum memory size. OS needs room too!
	mem=$( grep MemTotal /proc/meminfo | awk '{ print $2 }' )
	memtotal=$( expr $mem / 1024 )
	memtotal=$( expr $memtotal - 256 )

	# Well unless we get less than 1024Mb quit as we're in trouble.
	# JSS will not like running that low so you will HAVE to boost your RAM allocation.
	# I've been informed by JAMF support that 8Gb is ideal but I've run it on 4Gb without issue.
	if [ $memtotal -lt 1536 ];
	then
		echo -e "\nERROR: Not enough memory to allocate to Tomcat"
		echo -e "\nNeeded minimum memory: 2048"
		echo -e "\nAvailable memory: $memtotal"
		echo -e "\nPlease increase available RAM on this server."
	fi

	echo -e "\nMaximum memory to allocate to Tomcat is: $memtotal Mb"

	# Ok has Tomcat previously had it's server.xml altered by this script? Check for the backup.
	if [ ! -f "$server.backup" ];
	then
		# Configure the Tomcat server.xml. None of this stuff is pretty and could be better. Improvements welcome.
		# Let's start by backing up the server.xml file in case things go wrong.

		echo -e "\nBacking up $server file"
		cp $server $server.backup

		# Delete HTTPS connector settings
		sed -i '84,88d' $server

		# Replace HTTPS connector settings
		sed -i '84i<!--' $server
		sed -i '85i\    \<Connector' $server
		sed -i '86i\    \t\tport="8443" SSLEnabled="true" maxHttpHeaderSize="8192"' $server
		sed -i '87i\    \t\tmaxPostSize="-1" maxThreads="150" minSpareThreads="25"' $server
		sed -i '88i\    \t\tmaxSpareThreads="75" enableLookups="false" disableUploadTimeout="true"' $server
		sed -i '89i\    \t\tacceptCount="100" scheme="https" secure="true" clientAuth="false"' $server
		sed -i '90i\    \t\tsslProtocol="TLS" sslEnabledProtocols="TLSv1.2, TLSv1.1, TLSv1"' $server
		sed -i '91i\    \t\tkeystoreFile="'"$sslkeystorepath/keystore.jks"'" keystorePass="'"$sslkeypass"'" keyAlias="tomcat"' $server
		sed -i '92i\    \t\tciphers="TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDH_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDH_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDH_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDH_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA,TLS_ECDH_RSA_WITH_AES_256_CBC_SHA384,TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA384,TLS_ECDH_RSA_WITH_AES_256_CBC_SHA,TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA,TLS_ECDH_RSA_WITH_AES_128_CBC_SHA256,TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA256,TLS_ECDH_RSA_WITH_AES_128_CBC_SHA,TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA"' $server
		sed -i '93i-->' $server
		
		echo -e "\nEnabling Tomcat shared executor"
		sed -i '59d' $server
		sed -i '56d' $server
	
		echo -e "\nDisabling Tomcat default HTTP Connector"
		sed -i '67i<!--' $server
		sed -i '71i-->' $server

		echo -e "\nEnabling Tomcat HTTP Connector with executor"
		sed -i '78d' $server
		sed -i '73d' $server
		
		echo -e "\nAdding Max Threads to HTTP connector"
		sed -i 's/<Connector executor="tomcatThreadPool"/<Connector executor="tomcatThreadPool" maxThreads="'"$MaxThreads"'"/' $server
		
		echo -e "\nDisabling Tomcat Listener settings"
		sed -i '28i<!--' $server
		sed -i '30i-->' $server
	fi
	
	# Now for the settings we'll be periodically adjusting
	echo -e "\nConfiguring the TomcatThreadPool executor with current maximum threads"
	sed -i 's/maxThreads="150" /maxThreads="'"$MaxThreads"'" /' $server

	# Configure max ram available to Java from what we worked out earlier.
	echo -e "\nConfiguring Java to use $memtotal as max memory."
	sed -i 's/-Xmx.*/-Xmx'"$memtotal"'m"/' $tomcatloc/bin/setenv.sh

	if [[ $OS = "Ubuntu" ]];
	then
		# MySQL
		echo -e "\nConfiguring MySQL max connections to $MySQLMaxConnections"
		sed -i 's/max_connections.*/max_connections = '$MySQLMaxConnections'/' $ubmycnfloc		
	fi

	if [[ $OS = "RedHat" ]];
	then	
		# MySQL	
		echo -e "\nConfiguring MySQL max connections to: $MySQLMaxConnections"
		sed -i 's/max_connections.*/max_connections = '$MySQLMaxConnections'/' $rhmycnfloc
	fi
	
	# Time to restart MySQL and Tomcat
	TomcatService stop
	MySQLService restart
	TomcatService start
}

InitialiseServer()
{
	# This is to make sure the appropriate services and software are installed and configured.
	InstallGit
	InstallCurl
	InstallWget
	InstallUnzip
	InstallFirewall
	InstallOpenSSH
	InstallOpenVMTools
	InstallJava			# This includes the Cryptography Extensions
	InstallTomcat
	InstallMySQL
	ConfigureMemoryUsage
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
	[ -d "$tomcatloc" ] && tomcat="yes" || tomcat="no"
	CheckMySQL
	
	if [[ $tomcat = "no" || $mysql = "no" ]];
	then
		echo -e "\nTomcat 8 / MySQL not present. Please install before trying again.\n"
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
	
	# Stop tomcat service
	TomcatService stop
	
	# Prep variables for future use based on current OS
	SetupTomcatUser

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
		cp $rootwarloc/ROOT.war $tomcatloc/$webapps && unzip -oq $tomcatloc/$webapps/ROOT.war -d $webapploc/ROOT
	else
		cp $rootwarloc/ROOT.war $tomcatloc/$webapps/$instance.war && unzip -oq $tomcatloc/$webapps/$instance.war -d $tomcatloc/$webapps/$instance
	fi

	# Create a specific DataBase.xml file for this new instance
	echo -e "\nPreparing DataBase.xml for new instance: $instance"
	sed -i "s/\(<ServerName.*>\).*\(<\/ServerName.*\)/\1$mysqlserveraddress\2/" $DataBaseXML
	sed -i "s/\(<DataBaseName.*>\).*\(<\/DataBaseName.*\)/\1$instance\2/" $DataBaseXML
	sed -i "s/\(<DataBaseUser.*>\).*\(<\/DataBaseUser.*\)/\1$dbuser\2/" $DataBaseXML
	sed -i "s/\(<DataBasePassword.*>\).*\(<\/DataBasePassword.*\)/\1$dbpass\2/" $DataBaseXML

	# Wait for allow Tomcat to expand the .war file we copied over.
	echo -e "\nWaiting for .war file to be expanded"
	while [ ! -d "$webapploc/$instance" ]
	do
	   echo -e "Awaiting Tomcat to expand instance: $instance"
	   sleep 3
	done
	sleep 5

	# Copy the new file over the top of the existing file.
	echo -e "\nCopying the replacement DataBase.xml file into new instance: $instance"
	cp "$DataBaseXML" "$webapploc"$webapps/$instance/$DataBaseLoc/DataBase.xml

	# Create the instance name and empty log files with an exception for ROOT
	echo -e "\nCreating log files for new instance: $instance"
	if [[ $instance = "ROOT" ]];
	then
		touch $logfiles/JAMFChangeManagement.log
		touch $logfiles/JAMFSoftwareServer.log
		touch $logfiles/JSSAccess.log
		chown -R $user:$user $logfiles
	else
		mkdir $logfiles/$instance
		touch $logfiles/$instance/JAMFChangeManagement.log
		touch $logfiles/$instance/JAMFSoftwareServer.log
		touch $logfiles/$instance/JSSAccess.log
		chown -R $user:$user $logfiles/$instance
	fi

	# Finally modify the log4j file inside the new instance to point to the right files/folders
	echo -e "\nModifying new instance: $instance to point to new log files"
	if [[ $instance = "ROOT" ]];
	then	
		sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File=$logfiles/JAMFChangeManagement.log@" "$webapploc"$webapps/$instance/WEB-INF/classes/log4j.properties
		sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/JAMFSoftwareServer.log@" "$webapploc"$webapps/$instance/WEB-INF/classes/log4j.properties
		sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/JSSAccess.log@" "$webapploc"$webapps/$instance/WEB-INF/classes/log4j.properties
	else
		sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File=$logfiles/$instance/JAMFChangeManagement.log@" "$webapploc"$webapps/$instance/WEB-INF/classes/log4j.properties
		sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/$instance/JAMFSoftwareServer.log@" "$webapploc"$webapps/$instance/WEB-INF/classes/log4j.properties
		sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/$instance/JSSAccess.log@" "$webapploc"$webapps/$instance/WEB-INF/classes/log4j.properties
	fi

	# Make sure folder ownership is correctly set to Tomcat user or bad things happen!
	chown -R $user:$user $tomcatloc/webapps/

	# Recalculate memory usage since we've made changes
	ConfigureMemoryUsage
}

DeleteInstance()
{
	# Check for presence of Tomcat and MySQL before proceeding
	[ -d "$tomcatloc" ] && tomcat="yes" || tomcat="no"
	CheckMySQL

	if [[ $tomcat = "no" || $mysql = "no" ]];
	then
		echo -e "\nTomcat 8 / MySQL not present. Please install before trying again."
		return 1
	fi

	# Call function to show all directory names in the tomcat webapps folder
	InstanceList

	# Prompt for the instance name
	echo -e "\n"
	read -p "Please enter a JSS instance to delete (or enter to skip) : " instance

	# Does this name already exist?
	webapps=($(find $tomcatloc/webapps/* -maxdepth 0 -type d | sed -r 's/^.+\///'))
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
		TomcatService stop

		# Delete the tomcat ROOT.war folder
		echo -e "\nDeleting Tomcat instance: $instance"
		rm $tomcatloc/webapps/$instance.war 2>/dev/null
		rm -rf $tomcatloc/webapps/$instance

		# Delete the database
		echo -e "\nDeleting database for instance: $instance"
		mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -e "DROP DATABASE $instance;" 2>/dev/null

		# Delete the logfiles
		echo -e "\nDeleting log files for instance: $instance"
		if [[ $instance = "ROOT" ]];
		then
			rm $logfiles/JAMFSoftwareServer.log	2>/dev/null
			rm $logfiles/JAMFChangeManagement.log 2>/dev/null
			rm $logfiles/JSSAccess.log 2>/dev/null
		else
			rm -rf $logfiles/$instance 2>/dev/null
		fi

		# Delete the tomcat cache folder
		echo -e "\nDeleting Tomcat cache folder for instance: $instance"
		if [[ $instance = "ROOT" ]];
		then
			rm -rf $cacheloc/_ 2>/dev/null
		else
			rm -rf $cacheloc/$instance 2>/dev/null
		fi
		
		# Recalculate memory usage since we've made changes
		ConfigureMemoryUsage
		;;

		*)
			echo -e "\nSkipping deletion of instance"
		;;

	esac
}

DumpDatabase()
{
	# Is MySQL 5.6 present?
	CheckMySQL

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
		TomcatService stop
				
		for db in $databases; do
			echo "Dumping database: $db"
			mysqldump -h$mysqlserveraddress -u$mysqluser -p$mysqlpw $db 2>/dev/null | gzip > $rootwarloc/$db.sql.gz
		done
		
		# Restart tomcat
		echo -e "\nRestarting Tomcat service"
		TomcatService restart
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
	CheckMySQL

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
				TomcatService stop

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

				# Recalculate memory usage since we've made changes
				ConfigureMemoryUsage
				
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
			TomcatService stop
			
			# Work out what the database name is without the .sql.gz on the end of it!
			db="${dbname%.sql.gz}"

			echo -e "\nDropping existing database for instance: $dbname "
			mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -e "drop database $db;" 2>/dev/null
			mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -e "create database $db;" 2>/dev/null

			# Upload the selected database dump
			echo -e "\nImporting database: $dbname"
			gzip -dc < $rootwarloc/$dbname | mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw $db

			echo -e "\nRe-establishing grants for database: $dbname"
			mysql -h$mysqlserveraddress -u$mysqluser -p$mysqlpw -e "GRANT ALL ON $db.* TO $dbuser@$mysqlserveraddress IDENTIFIED BY '$dbpass';" 2>/dev/null

			# Recalculate memory usage since we've made changes
			ConfigureMemoryUsage
		;;
		
		*)
			echo -e "\nSkipping database restoration"
		;;

	esac
}

UpgradeInstance()
{
	# Check for presence of Tomcat and MySQL before proceeding
	[ -d "$tomcatloc" ] && tomcat="yes" || tomcat="no"
	CheckMySQL

	if [[ $tomcat = "no" || $mysql = "no" ]];
	then
		echo -e "\nTomcat 8 / MySQL not present. Please install before trying again."
		return 1
	fi

	# Call function to show all directory names in the tomcat webapps folder
	InstanceList

	# Prompt for the instance name.
	echo -e "\n"
	read -p "Please enter a JSS instance to upgrade (or enter to skip) : " instance

	# Does this name already exist?.
	webapps=($(find $tomcatloc/webapps/* -maxdepth 0 -type d | sed -r 's/^.+\///'))
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
			TomcatService stop

			# Backup the <instance>/WEB-INF/xml/DataBase.xml file
			echo -e "\nBacking up DataBase.xml of instance: $instance"
			cp $tomcatloc/webapps/$instance/$DataBaseLoc/DataBase.xml /tmp

			# Delete the tomcat ROOT.war folder
			echo -e "\nDeleting Tomcat instance: $instance"
			rm $tomcatloc/webapps/$instance.war
			rm -rf $webapploc/$instance

			# Rename, copy and expand the replacement tomcat ROOT.war file
			echo -e "\nReplacing Tomcat instance: $instance"
			cp $rootwarloc/ROOT.war $tomcatloc/webapps/$instance.war && unzip -oq $tomcatloc/webapps/$instance.war -d $tomcatloc/webapps/$instance
			
			# Wait for allow Tomcat to expand the .war file we copied over.
			echo -e "\nWaiting for .war file to be expanded"
			while [ ! -d "$tomcatloc/webapps/$instance" ]
			do
			   echo -e "Awaiting Tomcat to expand instance: $instance"
			   sleep 3
			done
			sleep 5

			# Modify the log4j file inside the new instance to point to the right files/folders
			echo -e "\nModifying new instance: $instance to point to new log files"
			if [[ $instance = "ROOT" ]];
			then	
				sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File=$logfiles/JAMFChangeManagement.log@" $tomcatloc/webapps/$instance/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/JAMFSoftwareServer.log@" $tomcatloc/webapps/$instance/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/JSSAccess.log@" $tomcatloc/webapps/$instance/WEB-INF/classes/log4j.properties
			else
				sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File=$logfiles/$instance/JAMFChangeManagement.log@" $tomcatloc/webapps/$instance/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/$instance/JAMFSoftwareServer.log@" $tomcatloc/webapps/$instance/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/$instance/JSSAccess.log@" $tomcatloc/webapps/$instance/WEB-INF/classes/log4j.properties
			fi
		
			# Copy back the DataBase.xml file
			echo -e "\nCopying back DataBase.xml of instance: $instance"
			mv -f /tmp/DataBase.xml $tomcatloc/webapps/$instance/$DataBaseLoc

			# Make sure folder ownership is correctly set to Tomcat user or bad things happen!
			chown -R $user:$user $tomcatloc/webapps/

			# Restart tomcat
			echo -e "\nRestarting Tomcat service"
			TomcatService restart
		;;
		
		*)
			echo -e "\nSkipping upgrade of instance"
		;;

	esac
}

UpgradeAllInstances() {
	# Check for presence of Tomcat and MySQL before proceeding
	[ -d "$tomcatloc" ] && tomcat="yes" || tomcat="no"
	CheckMySQL

	if [[ $tomcat = "no" || $mysql = "no" ]];
	then
		echo -e "\nTomcat 8 / MySQL not present. Please install before trying again."
		return 1
	fi

	# It does exist. Are they sure? Very very very VERY sure?
	echo -e "\nWARNING: This will restart the Tomcat service and upgrade ALL JSS instances!"
	echo -e "\nThe upgrade will be performed with the ROOT.war file located in $rootwarloc "
	read -p "Are you completely certain you wish to upgrade ALL instances? (Y/N) : " areyousure

	case "$areyousure" in

		Y|y)	
			# Grab an array containing all current JSS instances for processing.
			webapps=($(find $tomcatloc/webapps/* -maxdepth 0 -type d | sed -r 's/^.+\///'))
		
			# Stop the tomcat service
			echo -e "\nStopping Tomcat service.\n"
			TomcatService stop

			# Start the upgrade processing loop here.
			for (( i=0; i<${#webapps[@]}; i++ ));
			do
		
			# Line feed for clarity
			echo -e "\n"
		
			# Backup the <instance>/WEB-INF/xml/DataBase.xml file
			echo -e "Backing up DataBase.xml of instance: ${webapps[i]}"
			mv $tomcatloc/webapps/${webapps[i]}/$DataBaseLoc/DataBase.xml /tmp

			# Delete the tomcat ROOT.war folder
			echo -e "Deleting Tomcat instance: ${webapps[i]}"
			rm $tomcatloc/webapps/${webapps[i]}.war
			rm -rf $tomcatloc/webapps/${webapps[i]}

			# Rename, copy and expand the replacement tomcat ROOT.war file
			echo -e "Replacing Tomcat instance: ${webapps[i]}"
			cp $rootwarloc/ROOT.war $tomcatloc/webapps/${webapps[i]}.war && unzip -oq $tomcatloc/webapps/${webapps[i]}.war -d $tomcatloc/webapps/${webapps[i]}
			
			# Wait for allow Tomcat to expand the .war file we copied over.
			echo -e "\nWaiting for the .war file to be expanded"
			while [ ! -d '$rootwarloc/$instance' ]
			do
			   sleep 1
			done
			sleep 5

			# Modify the log4j file inside the new instance to point to the right files/folders
			echo -e "\nModifying new instance: $instance to point to new log files"
			if [[ $instance = "ROOT" ]];
			then	
				sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File=$logfiles/JAMFChangeManagement.log@" $tomcatloc/webapps/${webapps[i]}/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/JAMFSoftwareServer.log@" $tomcatloc/webapps/${webapps[i]}/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/JSSAccess.log@" $tomcatloc/webapps/${webapps[i]}/WEB-INF/classes/log4j.properties
			else
				sed -i "s@log4j.appender.JAMFCMFILE.File=.*@log4j.appender.JAMFCMFILE.File=$logfiles/${webapps[i]}/JAMFChangeManagement.log@" $tomcatloc/webapps/${webapps[i]}/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JAMF.File=.*@log4j.appender.JAMF.File=$logfiles/${webapps[i]}/JAMFSoftwareServer.log@" $tomcatloc/webapps/${webapps[i]}/WEB-INF/classes/log4j.properties
				sed -i "s@log4j.appender.JSSACCESSLOG.File=.*@log4j.appender.JSSACCESSLOG.File=$logfiles/${webapps[i]}/JSSAccess.log@" $tomcatloc/webapps/${webapps[i]}/WEB-INF/classes/log4j.properties
			fi

			# Copy back the DataBase.xml file
			echo -e "Copying back DataBase.xml of instance: ${webapps[i]}"
			mv -f /tmp/DataBase.xml $tomcatloc/webapps/${webapps[i]}/$DataBaseLoc/

			# Make sure folder ownership is correctly set to Tomcat user or bad things happen!
			chown -R $user:$user $tomcatloc/webapps/

			# Loop finishes here
			done
		
			# Restart tomcat
			echo -e "\nRestarting Tomcat service\n"
			TomcatService restart
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
UpdatePkgMgr
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