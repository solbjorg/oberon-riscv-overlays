#!/bin/bash

DIR="$(dirname "$(readlink -f "$0")")"

export NOREBO_BIN="${DIR}/../norebo"
export NOREBO_PATH="${DIR}/../build:${DIR}:${DIR}/rvbuild:${DIR}/../Oberon-building-tools/Sources/FPGAOberon2013"

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

