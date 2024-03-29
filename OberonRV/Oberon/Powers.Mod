MODULE Powers;  (*NW  10.10.07; Tabulate positive and negative powers of 2*)
  IMPORT Texts, Oberon;

  CONST N = 32; M = 11;  (*M ~ N*log2*)
  VAR W: Texts.Writer;

  PROCEDURE Generate*;
    VAR i, k, n, exp: INTEGER;
      c, r, t: INTEGER;
      d: ARRAY M OF INTEGER;
      f: ARRAY N OF INTEGER;
      S: Texts.Scanner;
  BEGIN
  Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF (S.class = Texts.Int) & (S.i <= N) THEN
      n := S.i; d[0] := 1; k := 1; exp := 1;
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
        WHILE i > k DO i := i-1; Texts.Write(W, " ") END ;
        WHILE i > 0 DO i := i-1; Texts.Write(W, CHR(d[i] + 30H)) END ;
        Texts.WriteInt(W, exp, M);
        (*compute  f = 2^-exp*)
        Texts.WriteString(W, "  0."); r := 0; i := 1;
        WHILE i < exp DO
          r := 10*r + f[i];

          f[i] := r DIV 2; r := r MOD 2;
          Texts.Write(W, CHR(f[i] + 30H)); i := i+1
        END ;
        f[exp] := 5; Texts.Write(W, "5"); Texts.WriteLn(W); exp := exp + 1
      END ;
      Texts.Append(Oberon.Log, W.buf)
    END;
  END Generate;

BEGIN Texts.OpenWriter(W)
END Powers.
