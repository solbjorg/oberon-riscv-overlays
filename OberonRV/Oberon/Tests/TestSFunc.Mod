MODULE TestSFunc;
IMPORT SYSTEM;

PROCEDURE Test*;
  VAR a: INTEGER;
BEGIN
  SYSTEM.PUT(-60, 0AA00H);
  a := -500000;
  SYSTEM.PUT(-60, a);
  a := ASR(a, 8);
  SYSTEM.PUT(-60, a);
  a := ASR(a, 8);
  SYSTEM.PUT(-60, a);
  a := ASR(a, 8);
  SYSTEM.PUT(-60, a);
END Test;

END TestSFunc.
