#!/bin/sh
sudo rm -rf /Applications/Docker.app
sudo rm -rf /usr/local/lib/docker
sudo rm -rf /Library/LaunchDaemons/com.docker.vmnetd.plist
sudo rm -rf /Library/PrivilegedHelperTools/com.docker.vmnetd
sudo rm /usr/local/bin/docker*
sudo rm /usr/local/bin/kubectl*
sudo rm /usr/local/bin/hub-tool
sudo rm /usr/local/bin/vpnkit
sudo rm /usr/local/bin/com.docker.cli
rm -rf "${HOME}/.docker"
rm -rf "${HOME}/Library/Application Support/Docker Desktop"
rm -rf "${HOME}/Library/Application Support/com.bugsnag.Bugsnag/com.docker.docker"
rm -rf "${HOME}/Library/Preferences/com.docker.docker.plist"
rm -rf "${HOME}/Library/Saved Application State/com.electron.docker-frontend.savedState"
rm -rf "${HOME}/Library/Group Containers/group.com.docker"
rm -rf "${HOME}/Library/Logs/Docker Desktop"
rm -rf "${HOME}/Library/Preferences/com.electron.docker-frontend.plist"
rm -rf "${HOME}/Library/Cookies/com.docker.docker.binarycookies"
rm -rf "${HOME}/Library/Containers/com.docker.docker"
rm -rf "${HOME}/Library/Caches/com.docker.docker"
echo "done"
