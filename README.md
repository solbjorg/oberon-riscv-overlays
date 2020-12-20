# Project Oberon 2013 on RISC-V
This respository contains everything necessary to create a working RISC-V image of Project Oberon 2013, including a working RV32IM compiler as well as a port of Oberon itself.

## Contents

* `Runtime/` RISC5 emulator and operating system interface.
* `Oberon/` Unmodified source code from Project Oberon 2013.
* `OberonRV/` RISC-V modified source code.
* `Norebo/` Norebo-specific and new modules.
* `Bootstrap/` Pre-compiled modules to bootstrap Norebo.
* `build.sh` Script to rebuild Norebo. See Norebo in action.

## How to run Oberon on RISC-V
If you don't want to figure out how to build an image, and you just want to try this out, go pull [the repository for the RISC-V Oberon emulator](https://github.com/solbjorg/oberon-riscv-emu) instead, as it includes an example RISC-V image.

## How to build an image
To build a RISC-V image, simply run:
``` shell
make imagerv
```

This will deposit a disk image: `imagebuild/Oberon.dsk`. This can be used for the emulator.

If you wish more control over the process, here is how to generate one with a different manifest, from whichever folder you prefer:
``` shell
rm -rf imagebuild
./build-image.py -r OberonRV/Oberon -m manifests/manifest.csv
```

The `-r` flag specifies the creation of a RISC-V image. By default, build-image will select the `manifests/manifest.csv` manifest; but there are a few other manifests in that folder, and you can use a `-m` flag to specify using them instead. Editing the manifest to include whichever files you wish to include should be fairly straight-forward; just remember to add the corresponding `.Mod` files in the `OberonRV/Oberon` folder. You can specify a different folder than OberonRV/Oberon, but an unedited PO2013 repository will not work without some significant changes.

## How to change the bootloader 
The bootloader is embedded in the emulator. Thus, changing it is a separate process from building the image. You *probably* don't need to change the bootloader, but if you desire to:
- Compile your bootloader using the RISC-V compiler. To make this easier for yourself, running `cd OberonRV; source functions.sh` will source the `roc` and `nor` commands. You can then run `roc BootLoad.mod`, and the compiled program can be found in `BootLoad.rsc`.
- Use `ORX.Mod` in andreaspirklbauer's `Oberon-building-tools`, included as a submodule, to write a file that can be used as bootloader: `nor ORX.WriteFile BootLoad.rsc BootLoad.code`. BootLoad.code now contains a list of RISC-V instructions.
- Currently, the emulator won't understand this format. You need to add `0x` to the start of every line, and a comma to the end. You can look at `src/emu/bootloader.inc` in the emulator for an example of the formatting. (I use vim to do this, and that's quick enough that I never bothered to write a script for it. Thus, this part is left as an exercise to the reader.)

## TODO
- Test it on an FPGA; should be doable
- Support REALs and interrupts
- 64-bit support. This is rather easy, as to my knowledge it only requires minor changes.
- Bootstrap Norebo using a RISC-V emulator rather than RISC-5

## Credits
Several open-source projects were used to finish this port.
- Of course, [Project Oberon](https://people.inf.ethz.ch/wirth/ProjectOberon/) itself.
- sam-folvo's [Oberon-RV compiler](https://github.com/sam-falvo/project-norebo), of which this repository is a fork.
- pdewacht's [Project Norebo](https://github.com/pdewacht/project-norebo), used to create the RISC-V image, of which this repository is also a fork.
- pdewacht's [Oberon emulator](https://github.com/pdewacht/oberon-risc-emu), used to emulate the created images. My port of the emulator to RISC-V can be found [here](https://github.com/solbjorg/oberon-riscv-emu).
- andreaspirklbauer's [Oberon-building-tools](https://github.com/andreaspirklbauer/Oberon-building-tools), which is included as a submodule of this repository. The documentation on Oberon's boot process is useful, along with some of the tooling to create the bootloader.
