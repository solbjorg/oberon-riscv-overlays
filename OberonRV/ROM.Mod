MODULE* ROM;

IMPORT SYSTEM;

VAR
  uartOut: INTEGER;
  i, j: INTEGER;

(*
  Initialize ROM module's global variables and type descriptors from the
  corresponding ROM contents.
*)

PROCEDURE get(VAR out: INTEGER);
BEGIN
  SYSTEM.GET(i, out);
  INC(i, SYSTEM.SIZE(INTEGER))
END get;

PROCEDURE getChar(VAR out: CHAR);
BEGIN
  SYSTEM.GET(i, out);
  INC(i, SYSTEM.SIZE(CHAR))
END getChar;

PROCEDURE put(in: INTEGER);
BEGIN
  SYSTEM.PUT(j, in);
  INC(j, SYSTEM.SIZE(INTEGER))
END put;

PROCEDURE putChar(in: CHAR);
BEGIN
  SYSTEM.PUT(j, in);
  INC(j, SYSTEM.SIZE(CHAR))
END putChar;

PROCEDURE copyTypeDescriptors;
VAR
  n, w: INTEGER;
BEGIN
  i := 0FFF00000H; j := 0;
  get(n);
  WHILE n # 0 DO
    get(w); put(w);
    DEC(n)
  END  
END copyTypeDescriptors;

PROCEDURE zeroVariables;
VAR
  size: INTEGER;
BEGIN
  get(size);
  WHILE size # 0 DO
    putChar(00X)
  END
END zeroVariables;

PROCEDURE copyStrings;
VAR
  size: INTEGER;
  ch: CHAR;
BEGIN
  get(size);
  WHILE size # 0 DO
    getChar(ch); putChar(ch);
    DEC(size)
  END;
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

