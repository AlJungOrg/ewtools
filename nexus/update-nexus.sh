#!/bin/bash
set -e
#set -x
set -u

######################################
# bare metal nexus update management
# Author: Patrick Wolfart
# Date:   23.02.2018
######################################



#>>==========================================================================>>
# DESCRIPTION:  rollback to last version, installation of new nexus failed
# PARAMETER 1:  -
# RETURN:       -
# USAGE:        rollback
#
# AUTHOR:       PW
# REVIEWER(S):  -
#<<==========================================================================<<
rollback()
{
	echo -e "ERROR: installation failed, rolling back to original installation"

	echo -e "change to installation dir"
	cd $INSTALL_DIR

	echo -e "remove symlink to failed update version"
	rm nexus

	echo -e "restore symlink to old nexus"
	ln -s $OLD_NEXUS_FOLDER nexus

	echo -e "remove possibly existing new plugin update files"
	rm -f $P2_BRIDGE_PLUGIN_ZIP_NEW
	rm -f $P2_REPO_PLUGIN_ZIP_NEW
	rm -rf nexus-p2-repository-plugin-$NEW_NEXUS_FOLDER
	rm -rf nexus-p2-bridge-plugin-$NEW_NEXUS_FOLDER

	echo -e "restore old plugins"
	if [ -e "$PLUGIN_REVERT_PATH/$P2_REPO_PLUGIN_OLD" ]; then
		mv $PLUGIN_REVERT_PATH/$P2_REPO_PLUGIN_OLD $PLUGIN_PATH
	fi
	if [ -e "$PLUGIN_REVERT_PATH/$P2_BRIDGE_PLUGIN_OLD" ]; then
		mv $PLUGIN_REVERT_PATH/$P2_BRIDGE_PLUGIN_OLD $PLUGIN_PATH
	fi

	echo -e "restart nexus service"
	systemctl restart nexus.service

	echo -e "SUCCESS: rollback done"

	error
}


#>>==========================================================================>>
# DESCRIPTION:  stop intallation script
# PARAMETER 1:  -
# RETURN:       -
# USAGE:        error
#
# AUTHOR:       PW
# REVIEWER(S):  -
#<<==========================================================================<<
error()
{
	echo -e "ERROR: installation failed of new nexus version failed"
	exit 1
}

trap error ERR TERM QUIT



declare -r INSTALL_DIR="/usr/local"
declare -r PLUGIN_PATH="/home/nexus/nexus-main-repo/plugin-repository"
declare -r PLUGIN_REVERT_PATH="/tmp"


#--------- check
echo -e "change to installation dir"
cd $INSTALL_DIR

echo -e "get current nexus folder name / version"
declare -r OLD_NEXUS_FOLDER="`readlink nexus`"
declare -r P2_REPO_PLUGIN_OLD=nexus-p2-repository-plugin-$OLD_NEXUS_FOLDER
declare -r P2_BRIDGE_PLUGIN_OLD=nexus-p2-bridge-plugin-$OLD_NEXUS_FOLDER

echo -e "remove possibly existing old download file"
rm -f nexus-latest-bundle.tar.gz

echo -e "download new nexus"
wget http://www.sonatype.org/downloads/nexus-latest-bundle.tar.gz

echo -e "get the folder name of the new nexus version"
declare -r NEW_NEXUS_FOLDER="$(tar -tzf nexus-latest-bundle.tar.gz | head -1 | cut -f1 -d"/")"

if [[ "${OLD_NEXUS_FOLDER}" == "$NEW_NEXUS_FOLDER" ]]; then
	echo -e "no update needed, newest version $NEW_NEXUS_FOLDER already installed"
	exit 0
fi


#--------- install update
echo -e "installing new nexus $NEW_NEXUS_FOLDER, shutting down nexus $OLD_NEXUS_FOLDER..."
systemctl stop nexus.service

echo -e "unpack new nexus"
tar -xf nexus-latest-bundle.tar.gz

echo -e "copy config to new nexus"
cp /usr/local/nexus/conf/nexus.properties /usr/local/$NEW_NEXUS_FOLDER/conf/
cp /usr/local/nexus/bin/nexus /usr/local/$NEW_NEXUS_FOLDER/bin/nexus

echo -e "remove the old symlink pointing to current version"
rm nexus

echo -e "register recover handler to rewind on error"
trap rollback ERR TERM QUIT

echo -e "create symlink to new nexus"
ln -s $NEW_NEXUS_FOLDER nexus

echo -e "ensure nexus user is allowed to access the new installation"
chown nexus:nexus /usr/local/nexus -R

echo -e "ensure pid file dir exists"
mkdir -p /var/run/nexus
chown nexus:nexus /var/run/nexus


#--------- update plugins
echo -e "update plugins matching nexus version $NEW_NEXUS_FOLDER"
cd $PLUGIN_PATH

echo -e "install plugins/nexus-p2-bridge-plugin"
P2_BRIDGE_PLUGIN_ZIP_NEW=nexus-p2-bridge-plugin-$NEW_NEXUS_FOLDER-bundle.zip
wget http://search.maven.org/remotecontent?filepath=org/sonatype/nexus/plugins/nexus-p2-bridge-plugin/$NEW_NEXUS_FOLDER/nexus-p2-bridge-plugin-$NEW_NEXUS_FOLDER-bundle.zip --output-document=$P2_BRIDGE_PLUGIN_ZIP_NEW
unzip $P2_BRIDGE_PLUGIN_ZIP_NEW
rm $P2_BRIDGE_PLUGIN_ZIP_NEW

echo -e "install nexus-p2-repository-plugin"
P2_REPO_PLUGIN_ZIP_NEW=nexus-p2-bridge-plugin-$NEW_NEXUS_FOLDER-bundle.zip
wget http://search.maven.org/remotecontent?filepath=org/sonatype/nexus/plugins/nexus-p2-repository-plugin/$NEW_NEXUS_FOLDER/nexus-p2-repository-plugin-$NEW_NEXUS_FOLDER-bundle.zip --output-document=$P2_REPO_PLUGIN_ZIP_NEW
unzip $P2_REPO_PLUGIN_ZIP_NEW
rm $P2_REPO_PLUGIN_ZIP_NEW

echo -e "move old plugins out of the way"
mv $P2_REPO_PLUGIN_OLD $PLUGIN_REVERT_PATH
mv $P2_BRIDGE_PLUGIN_OLD $PLUGIN_REVERT_PATH


#--------- finish
echo -e "restart nexus service"
systemctl restart nexus.service

echo -e "Successfully updated to $NEW_NEXUS_FOLDER"

