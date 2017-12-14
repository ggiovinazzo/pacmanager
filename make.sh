#!/bin/bash

if [ $(whoami) != "root" ]
then
	echo "*******************************"
	echo "You moust run $0 as user 'root'"
	echo "*******************************"
	exit 1;
fi

if [ ! -r pac.list ]
then
	echo "*******************************"
	echo "You are not in a pac source directory"
	echo "*******************************"
	exit 1
fi

#Use variables ($src_basedir) from pac.list
. <(perl -nle'print $1 if /^\$([^\s=]+?=\S+$)/;exit if /Common header/' pac.list)

fileowner=$USER
fileownergroup=`id -gn`

build_dir=${src_basedir%/*}
#parent of src_basedir from pac.list will be recursively deleted and re-created, used as a build directory
if [ -z "$build_dir" -o ${PWD#$build_dir} != ${PWD} ]
then
	echo "*******************************"
	echo "Invalid src_basedir in pac.list"
	echo "(or you're in src_basedir)"
	echo "*******************************"
	exit 1
fi

#preserve old builds
[ -d $build_dir/dist ] &&  mv $build_dir/dist $build_dir/.dist
rm -rf $build_dir/*
[ -d $build_dir/.dist ] && mv $build_dir/.dist $build_dir/dist

mkdir -p $build_dir/{pac,dist}
cp -r * $src_basedir/

cd $build_dir

find $src_basedir -name "*.svn" -o -name "*.git" -o -name "*~" -print0 | xargs -0 rm -rf

if [ -f pac.pl ] ; then    #dev environment stuff. eclipse and debugger likes .pl better. Restore it.
	[ -e pac ] && rm pac   #  debugger doesn't work with a soft link, and git doesn't preserve hard links
	mv pac.pl pac          #  so renaming is only option
	[ -L lib/pac_conn.pl ] && rm lib/pac_conn.pl
fi

# Get version from PACUtils.pm module
V=$(grep "our \$APPVERSION" pac/lib/PACUtils.pm | awk -F"'" '{print $2;}')

echo "**********************************"
echo "**********************************"
echo "Creating packages for PAC ${V}..."
echo "**********************************"
echo "**********************************"
echo ""

rm -rf meta

# First of all, change %version in pac.list
echo "----------------------------------------------"
echo " - Changing version in 'pac.list' to ${V}..."
echo "----------------------------------------------"
echo ""
sed "s/%version .*/%version $V/g" pac/pac.list > pac.list
ret=$?
if [ $ret -ne 0 ];
then
	echo " *********** ERROR ************"
	exit $ret
fi

cp pac.list pac/
chown -R $fileowner:$fileownergroup pac/

# .tar.gz
echo "----------------------------------------------"
echo " - Creating '.tar.gz' package for PAC ${V}..."
echo "----------------------------------------------"
echo ""
tar -czf pac-${V}-all.tar.gz pac
chown $fileowner:$fileownergroup pac-${V}-all.tar.gz
mv pac-${V}-all.tar.gz dist/

# DEB
echo "----------------------------------------------"
echo " - Creating '.deb' package for PAC ${V}..."
echo "----------------------------------------------"
echo ""
epm -vv --keep-files -f deb pac -m meta
ret=$?
if [ $ret -ne 0 ]; then
	echo " *********** ERROR ************"
	exit $ret
fi

sed 's/Architecture:.*/Architecture: all/g' meta/pac-${V}-meta/DEBIAN/control > meta/pac-${V}-meta/DEBIAN/control.new
mv meta/pac-${V}-meta/DEBIAN/control.new meta/pac-${V}-meta/DEBIAN/control
echo "Recommends: libgtk2-sourceview2-perl, rdesktop, xtightvncviewer, remote-tty, cu" >> meta/pac-${V}-meta/DEBIAN/control
echo "Section: networking" >> meta/pac-${V}-meta/DEBIAN/control
echo "Installed-Size: 3000" >> meta/pac-${V}-meta/DEBIAN/control
echo "Homepage: http://sourceforge.net/projects/pacmanager/" >> meta/pac-${V}-meta/DEBIAN/control
echo "Provides: pac-manager" >> meta/pac-${V}-meta/DEBIAN/control
echo "Priority: optional" >> meta/pac-${V}-meta/DEBIAN/control

dpkg -D1 -b meta/pac-${V}-meta pac-${V}-all.deb
chown $fileowner:$fileownergroup pac-${V}-all.deb
mv pac-${V}-all.deb dist/

# -orig.tar.gz
echo "----------------------------------------------"
echo " - Creating '-orig.tar.gz' package for PAC ${V}..."
echo "----------------------------------------------"
echo ""
cd meta/pac-${V}-meta
tar -czf ../../dist/pac-${V}-orig.tar.gz *
cd -
#rm -rf meta

# RPM
if [ -x "`which alien`" ]; then
	echo "----------------------------------------------"
	echo " - Creating 32/64 bit '.rpm' package for PAC ${V}..."
	echo "----------------------------------------------"
	echo ""
	alien -g -r --scripts dist/pac-${V}-all.deb
	ret=$?
	if [ $ret -ne 0 ]; then
		echo " *********** ERROR ************"
		exit $ret
	fi
	#sed "s/^Group:.*/Group: Converted\/networking\nRequires: perl perl-Crypt-Blowfish rdesktop tightvnc cunit remtty/g" pac-${V}/pac-${V}-2.spec > pac-${V}/pac-${V}-2.spec.new
	sed "s/^Group:.*/Group: Converted\/networking\nRequires: perl vte ftp telnet perl-IO-Stty perl-Crypt-Blowfish rdesktop tigervnc/g" pac-${V}/pac-${V}-2.spec > pac-${V}/pac-${V}-2.spec.new
	mv pac-${V}/pac-${V}-2.spec.new pac-${V}/pac-${V}-2.spec
	cp -r pac-${V} pac-${V}.64
	echo ""
	echo " ------ Creating 32 bit '.rpm' package for PAC ${V}..."
	rpmbuild --quiet -bb --buildroot $(pwd)/pac-${V} --target i386 pac-${V}/pac-${V}-2.spec
	mv pac-${V}.64 pac-${V}
	echo " ------ Creating 64 bit '.rpm' package for PAC ${V}..."
	rpmbuild --quiet -bb --clean --buildroot $(pwd)/pac-${V} --target x86_64 pac-${V}/pac-${V}-2.spec

	mv ../pac-${V}-2.*.rpm dist/
else
	echo "----------------------------------------------"
	echo "- Alien not installed. rpm package not created."
	echo "----------------------------------------------"
	echo ""
fi

echo ""
echo "--------------------------"
echo "- List of generated files:"
echo "--------------------------"
find $build_dir/dist -newer $src_basedir -type f -print0 | xargs -0 ls -lF

# Empty temp dir
rm -rf meta
rm -rf /home/$fileowner/rpmbuild
rm -rf $src_basedir
