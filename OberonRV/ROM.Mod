MODULE* ROM;
IMPORT S := SYSTEM;

VAR
  ramTop: INTEGER;

PROCEDURE ramCheck;
VAR
  a: LONGINT;
  fixed: BOOLEAN;
  probe1, probe2: LONGINT;
BEGIN
  probe1 := 55555555H;
  probe2 := 0AAAAAAAAH;
  a := -512
END ramCheck;

END ROM.

  REPEAT
    INC(a, 1024);
    S.PUT(a, probe1);
    S.GET(a, metric1);
    immutable := probe1 # metric1;
    S.PUT(a, probe2);
    S.GET(a, metric2);
    immutable := immutable OR (probe2 # metric2);
  UNTIL immutable;
  ramTop := a - 512;

