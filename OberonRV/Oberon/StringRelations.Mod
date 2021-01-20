MODULE StringRelations;
  IMPORT SYSTEM;

  PROCEDURE TestString(s, t: ARRAY OF CHAR);
  BEGIN
    SYSTEM.PUT(-60, 0EH);
    IF (s = t) THEN SYSTEM.PUT(-60, 0FH) ELSE SYSTEM.PUT(-60, 0AH) END;
    IF (s > t) THEN SYSTEM.PUT(-60, 0FH) ELSE SYSTEM.PUT(-60, 0AH) END;
    IF (s <= t) THEN SYSTEM.PUT(-60, 0FH) ELSE SYSTEM.PUT(-60, 0AH) END;
    IF (s >= t) THEN SYSTEM.PUT(-60, 0FH) ELSE SYSTEM.PUT(-60, 0AH) END;
    IF (s # t) THEN SYSTEM.PUT(-60, 0FH) ELSE SYSTEM.PUT(-60, 0AH) END;
  END TestString;

  PROCEDURE TestIndexing(s: ARRAY OF CHAR);
    VAR t: ARRAY 32 OF CHAR;
      i,j: INTEGER;
  BEGIN
    FOR i := 0 TO 10 DO
      t[i] := s[i]
    END;
    FOR j := 0 TO 10 DO
      SYSTEM.PUT(-60, t[j]);
    END;
  END TestIndexing;


BEGIN TestIndexing("Good morning");
END StringRelations.
