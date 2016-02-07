MODULE* ROM;

IMPORT S := SYSTEM;

VAR
  ramTop, I: INTEGER;

PROCEDURE ramCheck;
VAR
  a: LONGINT;
  immutable: BOOLEAN;
  probe1, probe2: INTEGER;
  metric1, metric2: INTEGER;
BEGIN
  a := -512;
  immutable := FALSE;
  probe1 := 55555555H;
  probe2 := 0AAAAAAAAH;
  REPEAT
    INC(a, 1024);
    S.PUT(a, probe1);
    S.GET(a, metric1);
    immutable := probe1 # metric1;
(*    S.PUT(a, probe2);
    S.GET(a, metric2);
    immutable := immutable OR (probe2 # metric2); *)
  UNTIL immutable;
  ramTop := a - 512;
END ramCheck;

PROCEDURE place(s: ARRAY OF CHAR);
VAR i, p: INTEGER;
BEGIN
  p := 0;
  FOR i := 0 TO LEN(s) DO S.PUT(p, s[i]) END;
  S.PUT(p+LEN(s), 00X)
END place;

BEGIN
  I := 0DEADBEEFH;
  I := I*I DIV 5;
  S.LDREG(2, 8000H);
  ramCheck;
  FOR I := 8000H TO ramTop DO S.PUT(I, 00X) END;
  place("Hello world!")
END ROM.

