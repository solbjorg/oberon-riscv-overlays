MODULE Overlay2;
  IMPORT SYSTEM, Overlay3, Overlay4;

  CONST N = 32; M = 11;  (*M ~ N*log2*)
  VAR unused: ARRAY 32 OF INTEGER;

  PROCEDURE Test*;
  BEGIN SYSTEM.PUT(-60, 0BB2H);
  END Test;

  (*
  PROCEDURE NewTask*(h: Handler; period: INTEGER): Task;
    VAR t: Task;
  BEGIN SYSTEM.PUT(-60, 0AB01234H);
    NEW(t); ASSERT(t # NIL); t.state := 0; t.next := t; t.handle := h; t.period := period; RETURN t
  END NewTask; *)

BEGIN SYSTEM.PUT(-60, 0CC1H);
  Test;
  (*d := NewTask(Test, 1000);*)
END Overlay2.
