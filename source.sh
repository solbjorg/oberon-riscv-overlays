DIR="$(dirname "$(readlink -f "$0")")"

export NOREBO_BIN="${DIR}/norebo"
export NOREBO_PATH="${DIR}/build:${DIR}/OberonRV:${DIR}/OberonRV/rvbuild:${DIR}/Oberon-building-tools/Sources/FPGAOberon2013:${DIR}/OberonRV/Oberon:${DIR}/OberonRV/Oberon/build"

