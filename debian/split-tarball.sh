#!/bin/bash
# Split an upstream tarball into +dfsg, and libclamunrar.
if test $# -ne 2; then
    echo -e "Usage: $0 <PATH> <VERSION>\n\t<PATH> - directory that contains clamav-<VERSION>.tar.gz";
    exit 1;
fi

DIR=$1
VERS=$2

test -d $DIR || { echo "Directory $DIR doesn't exist"; exit 2; }
TARBALL="$PWD/$DIR/clamav-$VERS.tar.gz"
test -f $TARBALL || { echo "Tarball $TARBALL doesn't exist"; exit 3; }

TEMP=`mktemp -d __splitXXXXXX` || { echo "Cannot create temporary directory"; exit 2; }
echo "Temporary directory is $TEMP"
cd $TEMP || exit 3;
echo "Extracting $TARBALL";
tar -xzf $TARBALL || { echo "Failed to extract $TARBALL"; exit 4; }

UNRARPKG=libclamunrar_$VERS.orig.tar.xz
DFSGPKG=clamav_$VERS+dfsg.orig.tar.xz
UNRARDIR="libclamunrar-$VERS"
MAKEFLAGS=-j4

set -e

mv clamav-* clamav-$VERS+dfsg

mkdir $UNRARDIR
UNRARDIR="$PWD/$UNRARDIR"
echo "Preparing dfsg package"
cd clamav-$VERS+dfsg
# remove win32 stuff, doesn't make sense to ship it
rm -rf win32
sed -i 's/ win32//' Makefile.am Makefile.in
find shared -name '*.la' -o -name '*.lo' -o -name Makefile  -exec rm {} \;
# cleanup llvm
set -- libclamav/c++/llvm/utils/lit/lit/*.pyc
if [ -f "$1" ] ; then
  echo "Pre-compiled python files found!"
  exit 1
fi
rm -rf libclamav/c++/llvm/tools libclamav/c++/llvm/unittests \
 libclamav/c++/llvm/bindings libclamav/c++/llvm/bindings/ocaml \
 libclamav/c++/llvm/examples libclamav/c++/llvm/runtime \
 libclamav/c++/llvm/projects libclamav/c++/llvm/test
# remove llvm, we build with the system version
#rm -rf libclamav/c++/llvm
cp -R libclamunrar_iface $UNRARDIR
mv libclamunrar $UNRARDIR
cp -R m4/ $UNRARDIR
cp -R config/ $UNRARDIR
cp configure.ac $UNRARDIR
cp platform.h.in $UNRARDIR
cp COPYING{,.unrar,.LGPL} $UNRARDIR
cd ../
tar -cJf $DFSGPKG --numeric-owner clamav-$VERS+dfsg/
cd $UNRARDIR
echo "Preparing unrar package"
# The sed sorcery below makes sure that the AC_CONFIG_FILES in the unrar package looks
# like:
# AC_CONFIG_FILES([
# libclamunrar_iface/Makefile
# Makefile
# platform.h
# ])
# It also removes ltdl, and renames the AC_CONFIG_SRCDIR parameter to an
# existing file.
sed -i '/AC_CONFIG_FILES/,/])/ {
/^AC_CONFIG_FILES(\[$/p
s/^clamscan\/Makefile/libclamunrar_iface\/Makefile/p
/^Makefile/p
/^platform.h/p
/^])/p
d
}
/LTDL/d
/ltdl/d
/AC_OUTPUT(\[.*Makefile/d
s/clamscan\/clamscan.c/libclamunrar_iface\/unrar_iface.c/
' configure.ac
cat <<EOF >Makefile.am &&
ACLOCAL_AMFLAGS=-I m4
DISTCLEANFILES = target.h
SUBDIRS = libclamunrar_iface
EOF
autoreconf
rm -r autom4te.cache
cd ..
tar -cJf $UNRARPKG --numeric-owner libclamunrar-$VERS/

printf "Test archives?"
read yes
if [ x$yes != xy ] ; then
    echo "Copying tarballs to current directory"
    mv $UNRARPKG ../ &&
    mv $DFSGPKG ../ &&
    echo "Ready (untested): $UNRARPKG $DFSGPKG" &&
    cd .. && rm -r $TEMP &&
    echo "Removed temporary directory $TEMP" &&
    exit 0
    exit 30
fi

mkdir testpfx || { echo "Failed to create testpfx"; exit 5; }
TESTPFX="$PWD/testpfx"
mkdir buildtest && cd buildtest
echo "Running build-test for $DFSGPKG"
tar -xJf ../$DFSGPKG && cd clamav-$VERS+dfsg
echo "Configuring"
./configure --disable-clamav --disable-unrar --enable-milter --prefix=$TESTPFX | tee -a makelog
echo "Building"
make $MAKEFLAGS | tee -a makelog
echo "Checking"
make $MAKEFLAGS check VERBOSE=1 2>&1 | tee -a makelog
make $MAKEFLAGS install 2>&1 | tee -a makelog
make $MAKFELAGS installcheck 2>&1 | tee -a makelog
echo "OK"
cd ..
echo "Running build-test for $UNRARPKG"
tar -xJf ../$UNRARPKG && cd libclamunrar-$VERS
echo "Configuring"
./configure --disable-clamav --prefix=$TESTPFX | tee -a makelog
echo "Building"
make $MAKEFLAGS 2>&1 | tee -a makelog
make $MAKEFLAGS install 2>&1 | tee -a makelog
make $MAKEFLAGS installcheck 2>&1 | tee -a makelog
echo "OK"
cd ../..
echo "Testing whether unrar functionality works"
cat <<EOF >test.hdb
aa15bcf478d165efd2065190eb473bcb:544:ClamAV-Test-File
EOF

if test $? -ne 0; then
    tail makelog
    echo
    echo "Failed"
    exit 50;
fi
# clamscan will exit with exitcode 1 on success (virus found)
set +e
$TESTPFX/bin/clamscan buildtest/clamav-$VERS+dfsg/test/clam-v*.rar -dtest.hdb >clamscanlog
if test $? -ne 1; then
    echo "Test failed";
    cat clamscanlog
    exit 10;
fi
NDET=`grep FOUND clamscanlog | wc -l`
if test "0$NDET" -eq "2"; then
    echo "All testfiles detected"
    echo "Copying tarballs to current directory"
    mv $UNRARPKG ../ &&
    mv $DFSGPKG ../ &&
    echo "Ready: $UNRARPKG $DFSGPKG" &&
    cd .. && rm -r $TEMP &&
    echo "Removed temporary directory $TEMP" &&
    exit 0
    exit 30
fi
echo "Test failed"
cat clamscanlog
exit 100
