#!/bin/bash
set -e
#set -x
set -u

######################################
# bare metal nexus update management
# Author: Patrick Wolfart
# Date:   23.02.2018
######################################

recover_from_error()
{
	echo -e "ERROR: reverting to existing installation"

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

	echo -e "SUCCESS: revert done"

	error
}


error()
{
	echo -e "ERROR: installation failed of new nexus version failed"
	exit 1
}

trap error ERR TERM QUIT



echo -e "change to installation dir"
cd /usr/local

echo -e "get current nexus folder name / version"
OLD_NEXUS_FOLDER="`readlink nexus`"

echo -e "remove possibly existing old download file"
rm -f nexus-latest-bundle.tar.gz

echo -e "download new nexus"
wget http://www.sonatype.org/downloads/nexus-latest-bundle.tar.gz

echo -e "get the folder name of the new nexus version"
NEW_NEXUS_FOLDER="$(tar -tzf nexus-latest-bundle.tar.gz | head -1 | cut -f1 -d"/")"

if [[ "${OLD_NEXUS_FOLDER}" == "$NEW_NEXUS_FOLDER" ]]; then
	echo -e "no update needed, newest version $NEW_NEXUS_FOLDER already installed"
	exit 0
fi

echo -e "shutdown nexus"
systemctl stop nexus.service

echo -e "unpack nexus"
tar -xf nexus-latest-bundle.tar.gz

echo -e "copy config to new nexus"
cp /usr/local/nexus/conf/nexus.properties /usr/local/$NEW_NEXUS_FOLDER/conf/
cp /usr/local/nexus/bin/nexus /usr/local/$NEW_NEXUS_FOLDER/bin/nexus

echo -e "remove the old symlink pointing to current version"
rm nexus

echo -e "register recover handler to rewind on error"
trap recover_from_error ERR TERM QUIT

echo -e "create symlink to new nexus"
ln -s $NEW_NEXUS_FOLDER nexus

echo -e "ensure nexus user is allowed to access the installation"
chown nexus:nexus /usr/local/nexus -R

echo -e "ensure pid file dir exists"
mkdir -p /var/run/nexus
chown nexus:nexus /var/run/nexus

echo -e "install new plugins"

PLUGIN_PATH="/home/nexus/nexus-main-repo/plugin-repository"
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


PLUGIN_REVERT_PATH="/tmp"
P2_REPO_PLUGIN_OLD=nexus-p2-repository-plugin-$OLD_NEXUS_FOLDER
P2_BRIDGE_PLUGIN_OLD=nexus-p2-bridge-plugin-$OLD_NEXUS_FOLDER

echo -e "move old plugins out of the way"
mv $P2_REPO_PLUGIN_OLD $PLUGIN_REVERT_PATH
mv $P2_BRIDGE_PLUGIN_OLD $PLUGIN_REVERT_PATH

echo -e "restart nexus service"
systemctl restart nexus.service

echo -e "Successfully updated to $NEW_NEXUS_FOLDER"

