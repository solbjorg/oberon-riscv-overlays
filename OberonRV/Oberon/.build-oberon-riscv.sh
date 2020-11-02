#!/bin/bash
# TODO replace this with something like a make system
DIR="$(dirname "$(readlink -f "$0")")"
COMPILER=roc

while getopts "or" opt; do
    case "$opt" in
    r)  COMPILER=roc
        ;;
    o)  COMPILER=oc
        ;;
    esac
done

cd ..; source ./functions.sh; ./rebuild.sh; cd Oberon;
#export NOREBO_PATH="${NOREBO_PATH}:${DIR}:${DIR}/build"
#export NOREBO_BIN="${DIR}/../../norebo"
./clean.sh
mkdir -p build; cd build

# Stage 0
$COMPILER RVBootLoad.Mod/s

# Stage 1
$COMPILER RVKernel.Mod/s \
          RVFileDir.Mod/s \
          RVFiles.Mod/s \
          RVModules.Mod/s 

# Stage 2
$COMPILER RVInput.Mod/s \
          RVDisplay.Mod/s \
          RVViewers.Mod/s \
          RVFonts.Mod/s \
          RVTexts.Mod/s \
          RVOberon.Mod/s 

#Stage 3
$COMPILER RVMenuViewers.Mod/s \
          RVTextFrames.Mod/s \
          RVSystem.Mod/s \
#Blink.Mod/s \
#BootLoad.Mod/s \
#Checkers.Mod/s \
#Curves.Mod/s \
#Draw.Mod/s \
#EBNF.Mod/s \
#Edit.Mod/s \
#GraphTool.Mod/s \
#GraphicFrames.Mod/s \
#Graphics.Mod/s \
#Hilbert.Mod/s \
#MacroTool.Mod/s \
#Math.Mod/s \
#Net.Mod/s \
#ORB.Mod/s \
#ORC.Mod/s \
#ORG.Mod/s \
#ORP.Mod/s \
#ORS.Mod/s \
#ORTool.Mod/s \
#PCLink1.Mod/s \
#PIO.Mod/s \
#RISC.Mod/s \
#RS232.Mod/s \
#Rectangles.Mod/s \
#SCC.Mod/s \
#Sierpinski.Mod/s \
#SmallPrograms.Mod/s \
#Stars.Mod/s \
#System.Mod/s \
#TextFrames.Mod/s \
#Tools.Mod/s \
#RVAssem.Mod/s RVDis.Mod/s RVOB.Mod/s RVOG.Mod/s RVOP.Mod/s RVOTool.Mod/s
