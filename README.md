# Project Norebo

This version of Norebo is a fork of @pdewacht's Project Norebo.

His version is a hack to run some _Project Oberon 2013_ software on the
Unix command line. Programs that use the GUI obviously won't work, but
e.g. the compiler runs.

His work enables me to work on porting the Oberon System 2013 to the
[Kestrel-3](http://github.com/kestrelcomputer/kestrel) computer environment.
However, porting isn't as simple as changing a few files and recompiling.
Lots of things need to change.
Here's an inexhaustive list that readily comes to mind:

* Target CPU needs to change from [RISC-5](http://www.inf.ethz.ch/personal/wirth/FPGA-relatedWork/RISC-Arch.pdf) to [RISC-V](http://riscv.org).
* Support for boot ROMs located $FFFFFFFFFFF00000 - $FFFFFFFFFFFFFFFF needs to be supported.
* SD card utilization needs to start at block 0, not 80000H.
* Software multiply and divide routines need to be implemented to make up for lack of M-instruction set extensions.  I already have assembly language versions of such things; I just need to reformulate them into a form suitable for Oberon.
* Support for 64-bit LONGINTs needs to be restored, in order for `SYSTEM.GET` and `SYSTEM.PUT` to access I/O registers.
* PS/2 keyboard driver needs to be retrofit to use the KIA instead of OberonStation's PS/2 interface.
* Mouse needs to be emulated using the keyboard with numeric keypad, since my current Kestrel hardware lacks a PS/2 port for a mouse.  A mouse is coming; it's just not there right now.
* SD card interface needs to use the GPIA instead of a dedicated controller.
* Support for *removable* SD card volumes.  (Put another way, make Oberon System run off of floppy-like devices.)
* Required for automated testing: add support for terminating an emulator and returning an arbitrary return code.

Norebo, by virtue of running in a Unix environment,
provides several benefits to me:

* Sources are normal Unix files, which makes revision control with `git` easier.
* Scriptable builds are reproducable builds.

I'm hoping to let Norebo *replace* my current Kestrel software development toolchain.
If Norebo's compiler and linker replaces my assembler,
6 minute build times will be replaced with 6 *second* build times.

## Contents

* `Runtime/` RISC5 emulator and operating system interface.
* `Oberon/` Unmodified source code from Project Oberon 2013.
* `Norebo/` Customized Norebo modules.
* `Bootstrap/` Pre-compiled modules to bootstrap Norebo.
* `build.sh` The build script. See Norebo in action.

## File handling

New files are always created in the current directory. Old files are
first looked up in the current directory and if they are not found,
they are searched for in the path defined by the `OBERON_PATH`
environment variable. Files found via `OBERON_PATH` are always opened
read-only.

## Bugs

Probably many.

Files are not integrated with the garbage collector. If you don't
close a file, it will remain open until Norebo exits.

Most runtime errors do not print a diagnostic message. Here's a table
of exit codes:

 Exit code | Meaning
----------:|:------------------------------
      1..7 | possibly a Modules error
         5 | (also) unknown command
       101 | array index out of range
       102 | type guard failure
       103 | array or string copy overflow
       104 | access via NIL pointer
       105 | illegal procedure call
       106 | integer division by zero
       107 | assertion violated
