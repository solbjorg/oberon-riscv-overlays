MODULE Overlay2;
  IMPORT SYSTEM, Overlay3;

  CONST N = 32; M = 11;  (*M ~ N*log2*)

  TYPE SectorMap* = POINTER TO SectorMapDesc;

    SectorMapDesc = RECORD
      a, b: INTEGER;
    END;

    Handler* = PROCEDURE;
    Task* = POINTER TO TaskDesc;

    TaskDesc* = RECORD
      state, nextTime, period*: INTEGER;
      next: Task;
      handle: Handler
    END;

  VAR unused: ARRAY 32 OF INTEGER;
    d: Task;

  PROCEDURE Generate*;
    VAR i, k, n, exp: INTEGER;
      c, r, t: INTEGER;
      d: ARRAY M OF INTEGER;
      f: ARRAY N OF INTEGER;
      u: SectorMap; v: Task;
  BEGIN
    n := 10; d[0] := 1; k := 1; exp := 1;
    WHILE exp < n DO
      (*compute d = 2^exp*)
      c := 0;  (*carry*) i := 0;
      WHILE i < k DO
        t := 2*d[i] + c;
        IF t < 10 THEN d[i] := t; c := 0 ELSE d[i] := t - 10; c := 1 END ;
        i := i+1
      END ;
      IF c = 1 THEN d[k] := 1; k := k+1 END ;
      (*write d*) i := M;
      WHILE i > k DO i := i-1; END ;
      WHILE i > 0 DO i := i-1; END ;
      (*compute  f = 2^-exp*)
      r := 0; i := 1;
      WHILE i < exp DO
        r := 10*r + f[i]; f[i] := r DIV 2; r := r MOD 2;
        i := i+1
      END ;
      f[exp] := 5; exp := exp + 1;
      (*SYSTEM.PUT(-60, exp);*)
    END ;
    NEW(u); ASSERT(u # NIL); u.a := 1234H; SYSTEM.PUT(-60, u.a);
    NEW(v); ASSERT(v # NIL);
  END Generate;


  PROCEDURE Test2;
  BEGIN SYSTEM.PUT(-60, 0BB3H);
    Overlay3.Test;
    Generate;
    SYSTEM.PUT(-60, 0BB5H);
  END Test2;

  PROCEDURE Test*;
  BEGIN SYSTEM.PUT(-60, 0BB2H);
    Test2;
  END Test;

  PROCEDURE Test3*;
  BEGIN SYSTEM.PUT(-60, 0BB21H);
    SYSTEM.PUT(-60, 0BB22H);
  END Test3;

  PROCEDURE TestArguments*(a, b: INTEGER);
    VAR c: INTEGER;
  BEGIN SYSTEM.PUT(-60, a); SYSTEM.PUT(-60, b);
    c := 0BB56H; SYSTEM.PUT(-60, c);
    SYSTEM.PUT(-60, a); SYSTEM.PUT(-60, b);
  END TestArguments;

  PROCEDURE NewTask*(h: Handler; period: INTEGER): Task;
    VAR t: Task;
  BEGIN SYSTEM.PUT(-60, 0AB01234H);
    NEW(t); ASSERT(t # NIL); t.state := 0; t.next := t; t.handle := h; t.period := period; RETURN t
  END NewTask;

BEGIN SYSTEM.PUT(-60, 0CC1H);
  d := NewTask(Test, 1000);
END Overlay2.
