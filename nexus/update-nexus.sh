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
	set +u
	set +e

	echo -e "ERROR: installation failed, rolling back to original installation"

	echo -e "change to installation dir"
	cd $INSTALL_DIR

	echo -e "remove symlink to failed update version"
	rm nexus

	echo -e "restore symlink to old nexus"
	ln -s $OLD_NEXUS_FOLDER nexus

	echo -e "remove possibly existing new plugin update files"
	rm -rf $PLUGIN_PATH/nexus-p2-repository-plugin-$NEW_NEXUS_VERSION
	rm -rf $PLUGIN_PATH/nexus-p2-bridge-plugin-$NEW_NEXUS_VERSION

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
declare -r OLD_NEXUS_VERSION="`echo $OLD_NEXUS_FOLDER | awk -F- '{print $2"-"$3}'`"
declare -r P2_REPO_PLUGIN_OLD="$PLUGIN_PATH/nexus-p2-repository-plugin-$OLD_NEXUS_VERSION"
declare -r P2_BRIDGE_PLUGIN_OLD="$PLUGIN_PATH/nexus-p2-bridge-plugin-$OLD_NEXUS_VERSION"

echo -e "remove possibly existing old download file"
rm -f nexus-latest-bundle.tar.gz

echo -e "download new nexus"
wget http://www.sonatype.org/downloads/nexus-latest-bundle.tar.gz

echo -e "get the folder name of the new nexus version"
declare -r NEW_NEXUS_FOLDER="$(tar -tzf nexus-latest-bundle.tar.gz | head -1 | cut -f1 -d"/")"
declare -r NEW_NEXUS_VERSION="`echo $NEW_NEXUS_FOLDER | awk -F- '{print $2"-"$3}'`"



if [[ "${OLD_NEXUS_VERSION}" == "$NEW_NEXUS_VERSION" ]]; then
	echo -e "no update needed, newest version $NEW_NEXUS_FOLDER already installed"
	exit 0
fi


#--------- install update
echo -e "installing new nexus $NEW_NEXUS_VERSION, shutting down nexus ${OLD_NEXUS_VERSION}"
systemctl stop nexus.service

echo -e "unpack new nexus"
rm -rf $NEW_NEXUS_FOLDER                 # remove possibly preexisting folder, maybe from prev failed installation
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

for i in "bridge" "repository"; do
	echo -e "install plugins/nexus-p2-$i-plugin"
	P2_PLUGIN_ZIP_NEW=nexus-p2-$i-plugin-$NEW_NEXUS_VERSION-bundle.zip
	rm -rf $P2_PLUGIN_ZIP_NEW
	wget http://search.maven.org/remotecontent?filepath=org/sonatype/nexus/plugins/nexus-p2-$i-plugin/$NEW_NEXUS_VERSION/nexus-p2-$i-plugin-$NEW_NEXUS_VERSION-bundle.zip --output-document=$P2_PLUGIN_ZIP_NEW
	rm -rf "$PLUGIN_PATH/nexus-p2-$i-plugin-$NEW_NEXUS_VERSION"
	unzip -o $P2_PLUGIN_ZIP_NEW
	rm $P2_PLUGIN_ZIP_NEW
done

echo -e "move old plugins out of the way"
mv $P2_REPO_PLUGIN_OLD $PLUGIN_REVERT_PATH
mv $P2_BRIDGE_PLUGIN_OLD $PLUGIN_REVERT_PATH


#--------- finish
echo -e "restart nexus service"
systemctl restart nexus.service

echo -e "Successfully updated to $NEW_NEXUS_FOLDER"

