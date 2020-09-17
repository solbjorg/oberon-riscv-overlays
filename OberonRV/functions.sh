#!/bin/bash

DIR="$(dirname "$(readlink -f "$0")")"
echo $DIR

export NOREBO_BIN="${DIR}/../norebo"
export NOREBO_PATH="${DIR}/../build:${DIR}:${DIR}/rvbuild:${DIR}/../Oberon-building-tools/Sources/FPGAOberon2013:${DIR}/Oberon:${DIR}/Oberon/build"

nor() {
  ${NOREBO_BIN} $*
}

roc() {
  nor RVOP.Compile $*
}

rot() {
  nor RVOTool.DecObj $*
}

oc() {
  nor ORP.Compile $*
}

ot() {
  nor ORTool.DecObj $*
}

