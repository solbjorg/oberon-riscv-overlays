MODULE* ROM;

IMPORT SYSTEM;

VAR uartOut: INTEGER;

PROCEDURE emit(ch: CHAR);
BEGIN
  SYSTEM.PUT(uartOut, ch);
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
  uartOut := LSL(0E000000H, 32);
  REPEAT
    type("Hello world, this is Kestrel running Oberon code!"); cr
  UNTIL FALSE
END ROM.

