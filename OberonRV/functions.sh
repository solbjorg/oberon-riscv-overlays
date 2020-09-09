#!/bin/bash

nor() {
  NOREBO_PATH="${PWD}/../build:${PWD}:${PWD}/rvbuild" ../norebo $*
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

