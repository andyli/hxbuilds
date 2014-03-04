#!/bin/bash

WIN=$PWD

rm -rf tmp
mkdir -p tmp/resources/haxe

if [ ! -e neko-stable.tar.gz ]; then
  echo "In order to have a working installer, you need to provide a neko directory with the desired version"
  exit 1
fi

cd ../../repo/haxe
BRANCH=$(git rev-parse --abbrev-ref HEAD)
ADDREV=1
if [ $BRANCH == "master" ]; then
  ADDREV=0
fi

rm -f haxe*
make clean && make "ADD_REVISION=$ADDREV" "OCAMLOPT=i686-w64-mingw32-ocamlopt" "OCAMLC=i686-w64-mingw32-ocamlc" && cp haxe $WIN/tmp/resources/haxe/haxe.exe && cp -rf std $WIN/tmp/resources/haxe/ && echo "haxe --run tools.haxelib.Main %*" > $WIN/tmp/resources/haxe/haxelib.bat
if [ $? -neq 0 ]; then
  exit 1
fi

cp extra/*.nsi $WIN/tmp
cp extra/*.nsh $WIN/tmp
cp -rf extra/images $WIN/tmp
tar -zxvf $WIN/neko-stable.tar.gz -C $WIN/tmp/resources
mv $WIN/tmp/resources/neko* $WIN/tmp/resources/neko

# docs
cd $WIN/repo/dox
git checkout -- .
git fetch
git pull
haxelib dev dox .
haxe gen.hxml
haxe std.hxml
cp -Rf bin/pages $WIN/tmp/haxe/doc

# ready to execute!
cd $WIN/tmp
makensis installer.nsi || exit 1
cp *.exe ../build

exit 0
