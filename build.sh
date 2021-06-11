#!/bin/bash
set -e
make

ROOT="$PWD"

if [ -e build ]; then
  echo >&2 "Build directories already exist, delete them using 'make clean' first."
  exit 1
fi
mkdir build

function rename {
  for i in *.$1; do
    mv $i ${i%.$1}.$2
  done
}

function compile_everything {
  ../norebo ORP.Compile \
	Norebo.Mod/s \
	Kernel.Mod/s \
  	FileDir.Mod/s \
  	Files.Mod/s \
  	Modules.Mod/s \
  	Fonts.Mod/s \
  	Texts.Mod/s \
  	RS232.Mod/s \
  	Oberon.Mod/s \
  	CoreLinker.Mod/s \
  	ORS.Mod/s \
  	ORB.Mod/s \
  	ORG.Mod/s \
  	ORP.Mod/s \
  	ORTool.Mod/s
  rename rsc rsx
  ../norebo CoreLinker.LinkSerial Modules InnerCore
  rename rsx rsc
}

export NOREBO_PATH="$ROOT/Norebo:$ROOT/Oberon:$ROOT/Bootstrap"
cd build
compile_everything
cd ..
