#!/bin/bash

nor() {
  NOREBO_PATH=../build ../norebo $*
}

roc() {
  nor RVOP.Compile $*
}

rot() {
  nor RVOTool.DecObj $*
}

