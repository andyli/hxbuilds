#!/bin/sh

LNX=$PWD

if [ $# -eq 0 ]; then
	echo "No arguments supplied: $1"
	exit 1
fi

cd ../../repo/neko
rm -rf bin
make clean && make all os=osx && cp -rf bin $LNX/build/ && exit 0
exit 1
