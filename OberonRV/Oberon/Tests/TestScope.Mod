MODULE TestScope;
  IMPORT SYSTEM;

  VAR a, b, c: INTEGER;

  PROCEDURE Test;
    VAR b, c: INTEGER;
  BEGIN
    SYSTEM.PUT(-60, a);
    a := 1;
    SYSTEM.PUT(-60, a);
    SYSTEM.PUT(-60, b);
    b := 3;
    SYSTEM.PUT(-60, b);
  END Test;

BEGIN a := 5; b := 7; c := 100; Test;
END TestScope.
