MODULE* ROM;

IMPORT SYSTEM;

VAR
  uartOut: INTEGER;
  i, j: INTEGER;

(*
  Initialize ROM module's global variables and type descriptors from the
  corresponding ROM contents.
*)

PROCEDURE copyTypeDescriptors;
VAR
  n, w: INTEGER;
BEGIN
  i := 0FFF00000H; j := 0;
  SYSTEM.GET(i, n);  INC(i, SIZE(INTEGER));
  WHILE n # 0 DO
    SYSTEM.GET(i, w);  SYSTEM.PUT(j, w);
    INC(i, SIZE(INTEGER));
    INC(j, SIZE(INTEGER));
    DEC(n)
  END  
END copyTypeDescriptors;

PROCEDURE zeroVariables;
VAR
  size: INTEGER;
BEGIN
  SYSTEM.GET(i, size);
  INC(i, SIZE(INTEGER));
  WHILE size # 0 DO
    SYSTEM.PUT(j, 00X);
    INC(j)
  END
END zeroVariables;

PROCEDURE copyStrings;
VAR
  size: INTEGER;
  ch: CHAR;
BEGIN
  SYSTEM.GET(i, size);
  INC(i, SIZE(INTEGER));
  WHILE size # 0 DO
    SYSTEM.GET(i, ch); SYSTEM.PUT(j, ch);
    INC(i); INC(j); DEC(size)
  END
  i := (i+3) DIV 4 * 4;
END copyStrings;

PROCEDURE initializeRam;
BEGIN  copyTypeDescriptors; zeroVariables; copyStrings
END initializeRam;

(*
  The actual ROM-resident "application" dumps a string to the UART.
*)

PROCEDURE emit(ch: CHAR);
BEGIN SYSTEM.PUT(uartOut, ch);
END emit;

PROCEDURE type(s: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  FOR i := 0 TO LEN(s) DO emit(s[i]) END
END type;

PROCEDURE cr;
BEGIN emit(0DX); emit(0AX)
END cr;

BEGIN
  initializeRam;
  uartOut := LSL(0E000000H, 32);
  REPEAT
    type("Hello world, this is Kestrel running Oberon code!"); cr
  UNTIL FALSE
END ROM.

