# Project Norebo

This version of Norebo is a fork of [pdewacht's Project Norebo](https://github.com/pdewacht/project-norebo).

His version is a hack to run some _Project Oberon 2013_ software on the
Unix command line. Programs that use the GUI obviously won't work, but
e.g. the compiler runs.

His work enables me to work on porting the Oberon System 2013 to the
[Kestrel-3](http://github.com/kestrelcomputer/kestrel) computer environment.
However, porting isn't as simple as changing a few files and recompiling.
Lots of things need to change.
Here's an *inexhaustive* list that readily comes to mind:

* Target CPU needs to change from [RISC-5](http://www.inf.ethz.ch/personal/wirth/FPGA-relatedWork/RISC-Arch.pdf) to [RISC-V](http://riscv.org). **DONE**
* Support for boot ROMs located $FFFFFFFFFFF00000 - $FFFFFFFFFFFFFFFF needs to be supported. **DONE**
* SD card utilization needs to start at block 0, not 80000H.
* A mechanism for writing ROM-resident trap handlers is needed.
* Software multiply and divide routines need to be implemented to make up for lack of M-instruction set extensions.  I already have assembly language versions of such things; I just need to reformulate them into a form suitable for Oberon.
* INTEGERs and LONGINTs widened to 64-bits. **DONE**
* PS/2 keyboard driver needs to be retrofit to use the KIA instead of OberonStation's PS/2 interface.
* Mouse needs to be emulated using the keyboard with numeric keypad, since my current Kestrel hardware lacks a PS/2 port for a mouse.  A mouse is coming; it's just not there right now.
* SD card interface needs to use the GPIA or Kestrel-3's specific controller.
* Support for *removable* SD card volumes.  (Put another way, make Oberon System capable of running off of a computer with a single floppy-like device.)

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
* `OberonRV/` RISC-V modified source code.
* `Custom/` Customized Norebo modules.
* `Bootstrap/` Pre-compiled modules to bootstrap Norebo.
* `build.sh` The build script. See Norebo in action.

## File handling

New files are always created in the current directory. Old files are
first looked up in the current directory and if they are not found,
they are searched for in the path defined by the `OBERON_PATH`
environment variable. Files found via `OBERON_PATH` are always opened
read-only.

## Building RISC-V ROM Images for Kestrel-3

Follow this recipe:

```sh
git clone git@github.com:kestrelcomputer/project-norebo
cd project-norebo
./build.sh
cd OberonRV
./rebuild.sh
```

Once these steps are done, you should have a working RVO compiler
(as distinct from the Niklaus Wirth compiler, OR).

Next, try typing in the following module source file.
For sake of illustration, put it in `ROM.Mod`:

```modula2
MODULE* ROM;
IMPORT SYSTEM;

CONST
  RomStart = -1048576;
  RamStart = 0;

(*
  This bit of boilerplate code is required to let our ROM
  image properly address string constants and/or structured
  types.  If this is not important to you, and you can make
  everything work with plain-vanilla integers or sets, then
  you can avoid having to write this boilerplate.
*)

PROCEDURE typeDescriptors(VAR f, t: INTEGER);
VAR
  int, integersLeft: INTEGER;
BEGIN
  SYSTEM.GET(f, integersLeft);  INC(f, SYSTEM.SIZE(INTEGER));
  WHILE integersLeft # 0 DO
    SYSTEM.GET(f, int);  INC(f, SYSTEM.SIZE(INTEGER));
    SYSTEM.PUT(t, int);  INC(t, SYSTEM.SIZE(INTEGER));
    DEC(integersLeft)
  END
END typeDescriptors;

PROCEDURE variables(VAR f, t: INTEGER);
VAR
  bytesLeft: INTEGER;
BEGIN
  SYSTEM.GET(f, bytesLeft);  INC(f, SYSTEM.SIZE(INTEGER));
  WHILE bytesLeft # 0 DO
    SYSTEM.PUT(t, 00X);  INC(t);
    DEC(bytesLeft)
  END
END variables;

PROCEDURE strings(VAR f, t: INTEGER);
VAR
  bytesLeft: INTEGER;
  byte: BYTE;
BEGIN
  SYSTEM.GET(f, bytesLeft);  INC(f, SYSTEM.SIZE(INTEGER));
  WHILE bytesLeft # 0 DO
    SYSTEM.GET(f, byte);  INC(f);
    SYSTEM.PUT(t, byte);  INC(t);
    DEC(bytesLeft)
  END
END strings;

PROCEDURE initRam;
VAR
  from, to: INTEGER;
BEGIN
  from := RomStart;   to := RamStart;

  typeDescriptors(from, to); variables(from, to);
  strings(from, to)
END initRam;

(*
  I/O procedures used to communicate with the outside world.

  Note that in the Kestrel-3 emulation environment, a "debug UART"
  exists at address 0E00000000000000H.  Since we cannot yet make
  64-bit constants when running RVOG in a 32-bit RISC5 emulator,
  we fake it by constructing the 64-bit address using LSL().
*)

PROCEDURE emit(ch: CHAR);
BEGIN
  SYSTEM.PUT(LSL(0E000000H, 32), ch);
END emit;

PROCEDURE type(s: ARRAY OF CHAR);
VAR
  i: INTEGER;
BEGIN
  FOR i := 0 TO LEN(s)-1 DO
    emit(s[i])
  END
END type;

PROCEDURE cr;
BEGIN emit(0DX); emit(0AX)
END cr;

PROCEDURE bye;
BEGIN
  (* todo: when compiler supports access to CSRs, quit emulator here. *)
  REPEAT UNTIL FALSE;
END bye;

(*
  When the Kestrel-3 cold-starts, it'll begin execution
  here.
*)

BEGIN
  SYSTEM.LDREG(2, 10000H); (* Sets initial stack pointer *)
  initRam;

  type("Hello world!  I am a Kestrel-3!");
  cr; bye
END ROM.
```

Once you have this file in place,
you should be able to compile it and run it with the following recipe:

    . ./functions.sh
    roc ROM.Mod
    e romfile ROM.rv64.Rom

**NOTE**: this assumes, of course,
that you have your path set up for running the `e` emulator.

**NOTE**: `roc` is a Bash function, not a program.
Its definition resides in the file `functions.sh` which you ran earlier.

If everything goes well,
you should see a Kestrel-3 window pop up with nothing (potentially garbage) in it,
and the string "Hello World!" written out
to the console from which you launched `e` from.
Press **CTRL-C** to exit the emulator.

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
