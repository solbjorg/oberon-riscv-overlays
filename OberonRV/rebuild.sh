#!/bin/bash
export NOREBO_PATH="${PWD}/../build:${PWD}"
NOREBO_BIN="${PWD}/../norebo"
mkdir -p rvbuild; cd rvbuild
${NOREBO_BIN} ORP.Compile RVAssem.Mod/s RVDis.Mod/s RVOB.Mod/s RVOG.Mod/s RVOP.Mod/s RVOTool.Mod/s
