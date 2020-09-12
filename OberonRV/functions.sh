#!/bin/bash

export NOREBO_BIN="${PWD}/../norebo"
export NOREBO_PATH="${PWD}/../build:${PWD}:${PWD}/rvbuild"

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

