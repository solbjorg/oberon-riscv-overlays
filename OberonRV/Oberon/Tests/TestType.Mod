MODULE TestType;
  IMPORT SYSTEM;
  TYPE R0 = RECORD x: INTEGER END ;
    R1 = RECORD (R0) y: INTEGER END ;
    R2 = RECORD (R1) z: INTEGER END ;
    P0 = POINTER TO R0;
    P1 = POINTER TO R1;
    P2 = POINTER TO R2;
  VAR k: INTEGER;

  PROCEDURE Test*;
    VAR p0: P0; p1: P1; p2: P2;
  BEGIN
    SYSTEM.PUT(-60, 0ABCH);
    NEW(p2); p2.x := 1; p2.y := 3; p2.z := 5;
    IF p2 IS P2 THEN k := 6; SYSTEM.PUT(-60, k) END ;
    p0 := p2;
    IF p0 IS P2 THEN k := 4; SYSTEM.PUT(-60, k) END ;
    SYSTEM.PUT(-60, p0.x);
    SYSTEM.PUT(-60, p0(P2).z);
  END Test;

END TestType.
