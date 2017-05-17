# JSS-In-A-Box

## The (almost) complete Jamf Pro JSS setup script
## http://www.richard-purves.com/?p=136

## Before we start, i'm planning to refactor the code and modularise a lot more functions as it's getting untidy in here. That'll be next big release, just not sure when.

### Introduction

This is the (almost) complete setup script for JAMF Software's JSS server. It will perform the following tasks :-

1. Install and configure all the software packages required to run the JSS
2. Harden the server via software firewall and optional HTTPS certificates
3. Show all currently running JSS on the server
4. Create a new JSS and Database
5. Delete an existing JSS and Database
6. Dump a selected (or ALL) JSS database to a file
7. Upload a database file back into MySQL
8. Upgrade a single JSS install on the server
9. Upgrade ALL JSS installs on the server
10. (optional) Refresh Tomcat SSL certificate from [LetsEncrypt](http://letsencrypt.org)
(The LetsEncrypt certificates are automatically renewed via a cron job. The same code can be invoked manually with this option)
11. Will now optimally configure Tomcat and MySQL (locally only) for number of instances, available ram etc etc.
(this one was HARD to do)

The only things it doesn't do are:
1) Set up anything to do with load balancing. That can be done inside the JSS itself.
2) Any remote server configuration with the sole exception of modifying remote databases.
3) Clustered server setup.

###### Oh, and NO SNEAKY using this on your CJA course! I've tipped off the JAMF instructors I know of!

### Getting started

This assumes you have an either an Ubuntu 16.04 LTS or a RedHat 7.x server installed with openssh.
This also assumes the server is properly configured to see the internet and has a properly set up DNS hostname.

Please do NOT use Ubuntu's minimal iso install. This will miss out lots of key software and this script will fail. Use the "server" download instead.

1. Download the proper script depending on which Linux distribution you are using.
2. Edit the jss-in-a-box.sh script variables in line with your own security policies
  - Server admin username
  - Use LetsEncrypt		(if this is set to FALSE, then the JSS will be set up without HTTPS)
  - SSL Domain name for the server
  - SSL E-mail address to register with the LetsEncrypt CA
  - SSL Keypass password
  - MySQL root password
  - MySQL server address
  - JSS database username
  - JSS database password
3. Edit the jss-in-a-box.sh script firewall settings.
4. scp the ROOT.war file supplied by JAMF to the server
5. scp the jss-in-a-box.sh script over to the server
6. Run the script with sudo. e.g. sudo ./jss-in-a-box.sh
7. Follow the options! (They are all disabled until no.1 is run successfully).

You should, depending on server and internet speed have a fully functioning JSS running inside of an hour. Probably less.

(Optional) Run the script with sudo ./jss-in-a-box.sh -h to get a help prompt.

The instructional video below provides more details of operation. NOTE: This is of an earlier version but the info is still valid.

### Instructional Video

<a href="http://www.youtube.com/watch?feature=player_embedded&v=ZMx-Xb2a9dM" target="_blank"><img src="http://img.youtube.com/vi/ZMx-Xb2a9dM/0.jpg" alt="JSS in a Box" border="10" /></a>

### Software Installed

* JSS
* Curl (missing from Ubuntu)
* Git (used purely for installing LetsEncrypt)
* Unzip
* Uncomplicated Firewall (Ubuntu) / FirewallD (Redhat)
* OpenSSL
* OpenVMTools
* Oracle Java 8
* Java Cryptography Extensions
* Apache Tomcat 8.0x
* MySQL Server 5.7
* (optional) LetsEncrypt
