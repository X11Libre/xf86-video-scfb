#!/bin/sh

set -e

OPSYS=$(uname -s)

Linux_git()
{

	seperator "Install git for Linux"
apt-get -y install \
git

}

FreeBSD_git()
{

	seperator "Install git for FreeBSD"
pkg-static install -y \
git-tiny

}

FreeBSD_pkgs()
{

	seperator "Install packages for FreeBSD"
pkg-static install -y \
muon \
ccache \
libXau \
libdrm \
pixman \
xtrans \
libxcvt \
pkgconf \
xkbcomp \
git-tiny \
libXdmcp \
libepoxy \
libglvnd \
mesa-dri \
libXfont2 \
libunwind \
mesa-libs \
autotools \
xorgproto \
libxkbfile \
xorg-macros \
libpciaccess \
libudev-devd \
libxshmfence \
libepoll-shim \
xkeyboard-config

}

seperator()
{
	printf "\033[0;33m _____________________________\n"
	if [ -n "$1" ]
	then
		printf "\033[0;33m/\n"
		printf "\033[0;33m\`> \033[0;36m %s\n" "$1"
	fi
	echo
	printf '\033[0m'

}

if [ "$1" = "init" ]
then
	seperator "Init"
	${OPSYS}_git

	git ls-remote https://github.com/X11Libre/xserver master > MASTER_HASH
	git ls-remote https://github.com/X11Libre/xserver 'release/*' | sort -V -k 2 | tail -n 1 > LATEST_REL_HASH
	ls
	cat *_HASH
	true
	exit
fi

export CC="ccache cc"
export CCACHE_DIR="$(pwd)/xserver-ccache-cache"
mkdir -p "$CCACHE_DIR"
export PKG_CACHEDIR="$(pwd)/pkg-cache"
mkdir -p "$PKG_CACHEDIR"

meson_args=" -Dprefix=/usr -Dnamespace=false -Dxselinux=false -Dxephyr=false -Dwerror=false -Dxcsecurity=false -Dxorg=true -Dxvfb=false -Dxnest=false -Ddocs=false "

${OPSYS}_git

# Asynchronously install packages.
${OPSYS}_pkgs &

# Asynchronously clone xserver's latest stable branch.
if [ ! -e xserver-stable-install ]
then
	seperator "Clone latest xserver stable branch"
	{
		latest_release="$(git ls-remote https://github.com/X11Libre/xserver 'release/*' | awk '{n=split($2,a,"/");print(a[n-1] "/" a[n])}' | sort -V | tail -n 1)"
		git clone --single-branch --depth 1 --branch "$latest_release" https://github.com/X11Libre/xserver xserver-stable
		git -C ./xserver-stable reset --hard $(git -C ./xserver-stable describe --abbrev=0)
	} &
fi

# Asynchronously clone xserver's master branch.
if [ ! -e xserver-master-install ]
then
	seperator "Clone xserver master branch"
	git clone --single-branch --depth 1 --branch "master" https://github.com/X11Libre/xserver xserver-master &
fi

# Wait for the packages to install and the xservers branches to clone.
wait

if [ ! -e xserver-master-install ]
then
	seperator "Build xserver master branch"
	cd xserver-master
	mkdir _build
	muon setup ${meson_args} _build
	cd _build
	muon samu
	muon install -d ../../xserver-master-install
	cd ../..
fi

if [ ! -e xserver-stable-install ]
then
	seperator "Build xserver stable branch"
	cd xserver-stable
	mkdir _build
	muon setup ${meson_args} _build
	cd _build
	muon samu
	muon install -d ../../xserver-stable-install
	cd ../..
fi

export CCACHE_DIR="$(pwd)/driver-ccache-cache"
mkdir -p "$CCACHE_DIR"

seperator "Build the driver against xserver master"
export PKG_CONFIG_PATH="$(pwd)/xserver-master-install/usr/lib/pkgconfig"
export CPPFLAGS="-I$(pwd)/xserver-master-install/usr/include/xorg"
autoreconf -v --install
./configure -C --cache-file=./cfg-cache-master
make install
make clean

seperator "Build the driver against xserver stable"
export PKG_CONFIG_PATH="$(pwd)/xserver-stable-install/usr/lib/pkgconfig"
export CPPFLAGS="-I$(pwd)/xserver-stable-install/usr/include/xorg"
autoreconf -v --install
./configure -C --cache-file=./cfg-cache-stable
make install
make clean

rm -r xserver-master xserver-stable || true
