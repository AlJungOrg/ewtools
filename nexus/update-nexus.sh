#!/bin/bash
set -e
#set -x
set -u

######################################
# bare metal nexus update management
# Author: Patrick Wolfart
# Date:   23.02.2018
######################################

error()
{
	echo -e "ERROR: installation failed"
	exit 1
}

trap error ERR



# change to installation dir
cd /usr/local

# get current nexus folder name / version
OLD_NEXUS_FOLDER="`readlink nexus`"

# remove possibly existing old download file
rm -f nexus-latest-bundle.tar.gz

# download new nexus
wget http://www.sonatype.org/downloads/nexus-latest-bundle.tar.gz

# get the folder name of the new nexus version
NEW_NEXUS_FOLDER="$(tar -tzf nexus-latest-bundle.tar.gz | head -1 | cut -f1 -d"/")"

if [[ "${OLD_NEXUS_FOLDER}" == "$NEW_NEXUS_FOLDER" ]]; then
	echo -e "no update needed, newest version $NEW_NEXUS_FOLDER already installed"
	exit 0
fi 

# shutdown nexus
systemctl stop nexus.service

# unpack nexus
tar -xf nexus-latest-bundle.tar.gz

# copy config to new nexus
cp /usr/local/nexus/conf/nexus.properties /usr/local/$NEW_NEXUS_FOLDER/conf/
cp /usr/local/nexus/bin/nexus /usr/local/$NEW_NEXUS_FOLDER/bin/nexus

# remove the old symlink pointing to current version
rm nexus

# create symlink to new nexus
ln -s $NEW_NEXUS_FOLDER nexus

# ensure nexus user is allowed to access the installation
chown nexus:nexus /usr/local/nexus -R

# ensure pid file dir exists
mkdir -p /var/run/nexus
chown nexus:nexus /var/run/nexus

# restart nexus service
systemctl start nexus.service

echo -e "Successfully updated to $NEW_NEXUS_FOLDER"

