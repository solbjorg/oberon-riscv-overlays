MODULE TestSets;
  IMPORT SYSTEM;

  VAR r, s, t, u: SET;

  PROCEDURE Test*;
    VAR i: INTEGER;
  BEGIN
    SYSTEM.PUT(-60, 0AAABCH);
    s := {2, 8 .. 15}; t := {4, 8 .. 15}; r := {1};
    SYSTEM.PUT(-60, SYSTEM.VAL(INTEGER, s));
    s := s * t + r;
    SYSTEM.PUT(-60, SYSTEM.VAL(INTEGER, s));
    s := s / t;
    SYSTEM.PUT(-60, SYSTEM.VAL(INTEGER, s));
    INCL(t, 2);
    SYSTEM.PUT(-60, SYSTEM.VAL(INTEGER, r));
    EXCL(t, 4);
    SYSTEM.PUT(-60, SYSTEM.VAL(INTEGER, r));
    u := {0..31};
    SYSTEM.PUT(-60, 0ABABCH);
    SYSTEM.PUT(-60, SYSTEM.VAL(INTEGER, u));
    i := 1;
    i := i MOD 32;
    SYSTEM.PUT(-60, i);
    IF ~(i MOD 32 IN u) THEN
      SYSTEM.PUT(-60, 0EEEEEEH);
    ELSE
      SYSTEM.PUT(-60, 0EFEEEEH);
    END;
  END Test;

END TestSets.
