#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root."
  exit
fi

echo "
OpenBroadcaster Player Reference Installer

This script is designed to be run on a fresh Ubuntu Server 24.04 installation.
Running on an existing installation or different operating system / release may
provide unexpected results.

This script is in an alpha state and does not validate user inputs or
command exit codes for success/failure. Things might break.
"

while true; do
  read -p "Everything look right? Type install: " confirmation

  if [ "$confirmation" = "install" ]; then
    echo "Installation proceeding..."
    echo
    break
  else
    echo "Please type 'install' to proceed."
  fi
done

cd /root

apt update
apt -y upgrade

# TODO is there a way to pre/auto-accept font EULA?
apt -y install ntp python3 python3-pycurl python3-openssl python3-apsw python3-magic python3-dateutil python3-requests python3-gi python3-gi-cairo gir1.2-gtk-3.0 gir1.2-gdkpixbuf-2.0 gir1.2-pango-1.0 python3-gst-1.0 gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0 gir1.2-gst-rtsp-server-1.0 gstreamer1.0-tools gstreamer1.0-libav gstreamer1.0-alsa gstreamer1.0-pulseaudio gstreamer1.0-pipewire gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly ffmpeg ubuntu-restricted-addons ubuntu-restricted-extras gstreamer1.0-vaapi mesa-vdpau-drivers espeak mbrola mbrola-en1 mbrola-us1 mbrola-us2 mbrola-us3 mbrola-fr1 mbrola-fr4 python3-serial python3-pip git python3-boto3 python3-pulsectl python3-inotify libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gtk-doc-tools meson

# TODO install icecast with a default configuration (is there a way to auto-configure instead of interactive?)

# pyrtlsdr not available as python3-pyrtlsdr, but its use is commented out in code so no longer needed?

git clone https://github.com/RidgeRun/gst-interpipe.git /root/gst-interpipe
cd /root/gst-interpipe
mkdir build
meson build --prefix=/usr
ninja -C build
sudo ninja -C build install # this fails due to gtkdoc issue, but otherwise works fine.

git clone https://github.com/openbroadcaster/obplayer/ /usr/local/lib/obplayer
cd /usr/local/lib/obplayer
git checkout 5.3-staging

echo "
Install complete. Run obplayer from /usr/local/lib/obplayer/.
"

# TODO download some fallback media, set default streaming configuration (need to add something to player to init settings / set setting from command line?
