MODULE PrimeNumbers;  (*NW 6.9.07; Tabulate prime numbers; for Oberon-07  NW 25.1.2013*)
  IMPORT SYSTEM, Overlays, Texts, Oberon, System;

  VAR n: INTEGER;
    W: Texts.Writer;
    p: ARRAY 400 OF INTEGER;
    v: ARRAY 20 OF INTEGER;

  PROCEDURE Primes(n: INTEGER);
    VAR i, k, m, x, inc, lim, sqr: INTEGER; prim: BOOLEAN;
  BEGIN
    x := 1; inc := 4; lim := 1; sqr := 4; m := 0;
    FOR i := 3 TO n DO
      REPEAT x := x + inc; inc := 6 - inc;
        IF sqr <= x THEN  (*sqr = p[lim]^2*)
          v[lim] := sqr; INC(lim); sqr := p[lim]*p[lim]
        END ;
        k := 2; prim := TRUE;
        WHILE prim & (k < lim) DO
          INC(k);
          IF v[k] < x THEN v[k] := v[k] + p[k] END ;
          prim := x # v[k]
        END
      UNTIL prim;
      p[i] := x; Texts.WriteInt(W, x, 5);
      IF m = 10 THEN Texts.WriteLn(W); m := 0 ELSE INC(m) END
    END ;
    IF m > 0 THEN Texts.WriteLn(W) END;
  END Primes;

  PROCEDURE Generate*;
    VAR S: Texts.Scanner;
  BEGIN
    Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF S.i < 400 THEN
      Primes(S.i); Texts.Append(System.dummytext, W.buf);
    END;
    SYSTEM.PUT(-60, Overlays.loadedOverlays);
    SYSTEM.EBREAK();
    Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF S.i < 400 THEN
      Primes(S.i); Texts.Append(Oberon.Log, W.buf)
    END;
    SYSTEM.PUT(-60, Overlays.loadedOverlays);
    SYSTEM.EBREAK();
  END Generate;

BEGIN Texts.OpenWriter(W);
END PrimeNumbers.
