#!/bin/bash
set -e
make

DIR="$(dirname "$(readlink -f "$0")")"

export NOREBO_BIN="${DIR}/norebo"
export NOREBO_PATH="${DIR}/Norebo:${DIR}/Oberon:${DIR}/Bootstrap"

mkdir -p build
cd build

$NOREBO_BIN ORP.Compile \
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

for i in *.rsc; do
  mv $i ${i%.rsc}.rsx
done

$NOREBO_BIN CoreLinker.LinkSerial Modules InnerCore

for i in *.rsx; do
  mv $i ${i%.rsx}.rsc
done
