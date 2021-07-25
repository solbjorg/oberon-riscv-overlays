# Code overlays for Project Oberon 2013 on RISC-V
This repository is a fork of my project last year, which ported the Oberon system to RISC-V. It adds code overlays to the Oberon system, meaning unused code is written to disk, and read into memory when it is needed. In doing so, the memory requirements of the Oberon system are reduced, though with a performance cost. (The performance is still usually acceptable in the emulator, though it may vary from program to program.) It is able to link and load the entire Oberon system, as well as run programs on top of it, including tasks such as Stars. Additionally, improvements have been made to heap allocation and garbage collection. Garbage collection can now run at any moment during program execution, and not only as a Task when no other program is executing.

Note that this is intended as a prototype, and not as a system for daily use. For instance, as generation of overlays has to occur in runtime, booting is considerably slower than in an unmodified RISC-V Oberon system.

## How to run Oberon with code overlays
Run `make imagerv` to create a disk image `imagebuild/Oberon.dsk`. This can be run by the RISC-V emulator that can be found [here](https://github.com/solbjorg/oberon-riscv-emu). More details on the build process can be found in the [original RISC-V port repository](https://github.com/solbjorg/oberon-riscv).

## Overview
Overlays.Mod contains the core of the overlay system. The version of this project in the master branch is one using the system heap to store code segments. These code segments are organised as an overlay tree, such that, when garbage collection is run, procedures not currently in the call tree are freed from the heap.

It is possible to change the strategy determining which overlays should be evicted. This can be done by tinkering with Overlays.OverlayManager, which governs what occurs in a procedure call to an overlaid procedure.

## TODO
- Improve documentation, as currently it is rather bare-bones.
- Freeing modules is currently not integrated into the overlay system. This means that modules can be freed, but they are not removed from the overlay table. This can be improved most easily by only allowing modules on the top of the overlay table to be removed, and decrementing `numGeneratedOverlays` in the Overlays module by however many procedures that module contained (essentially creating a stack).
- Outer core support is enough to make the system functional, but helper functions beyond what is necessary have not been written. It may be useful to have commands in System that e.g. report the current state of the overlay table, the number of remaining available entries, etc.

### Known Bugs
- The overlay system is currently unable to run the compiler.

Of course, feel free to report any additional bugs!
