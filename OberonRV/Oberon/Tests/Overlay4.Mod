MODULE Overlay4;
  IMPORT SYSTEM;

  TYPE A = RECORD
      a, b, c, d, e, f: LONGINT;
      g, h, i, j, k, l: LONGINT;
    END;

    Ptr = POINTER TO A;

  VAR a, b: INTEGER;

  PROCEDURE Test5*;
  BEGIN
    SYSTEM.PUT(-60, 0BB56H);
    SYSTEM.PUT(-60, 0BB57H);
    SYSTEM.PUT(-60, 0BB58H);
    SYSTEM.PUT(-60, 0BB59H);
    SYSTEM.PUT(-60, 0BB5AH);
    SYSTEM.PUT(-60, 0BB5BH);
  END Test5;

  PROCEDURE Test4*;
  BEGIN
    SYSTEM.PUT(-60, 0BB53H);
    SYSTEM.PUT(-60, 0BB54H);
    SYSTEM.PUT(-60, 0BB55H);
  END Test4;

  PROCEDURE Test*;
    VAR c, d: Ptr; f, e: INTEGER;

    PROCEDURE Test3;
      VAR g: Ptr;

      PROCEDURE Test4;
      BEGIN
      SYSTEM.PUT(-60, 0BB51H); SYSTEM.PUT(-60, 0BB52H); SYSTEM.PUT(-60, 0BB51H); SYSTEM.PUT(-60, 0BB52H);
      END Test4;
    BEGIN
      SYSTEM.PUT(-60, 0BB50H);
      Test4;
      SYSTEM.PUT(-60, 0BB53H);
      SYSTEM.PUT(-60, 0BB54H);
    END Test3;
  BEGIN
    NEW(c); ASSERT(c # NIL); c.a := 5;
    (*f := 0E4000H;*)
    SYSTEM.PUT(-60, 0BB10H);
    SYSTEM.PUT(-60, SYSTEM.VAL(INTEGER, c));
    e := SYSTEM.VAL(INTEGER, c)-4;
    SYSTEM.GET(e, e);
    SYSTEM.PUT(-60, e);
    Test3; Test4; Test5;
    SYSTEM.PUT(-60, c.a);
    NEW(d); ASSERT(d # NIL); d.a := 4;
    SYSTEM.PUT(-60, 0BB56H);
    SYSTEM.PUT(-60, c.a);
    e := SYSTEM.VAL(INTEGER, c)-4;
    SYSTEM.GET(e, e);
    SYSTEM.PUT(-60, e);
    SYSTEM.PUT(-60, d.a);
    e := SYSTEM.VAL(INTEGER, d)-4;
    SYSTEM.GET(e, e);
    SYSTEM.PUT(-60, e);
    SYSTEM.PUT(-60, f);
  END Test;

  PROCEDURE Test2*;
  BEGIN SYSTEM.PUT(-60, 0BB11H);
  END Test2;

BEGIN SYSTEM.PUT(-60, 0EE1H);
  Test;
END Overlay4.
