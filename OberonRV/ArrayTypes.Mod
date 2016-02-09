MODULE ArrayTypes;
TYPE
  A1 = ARRAY 256 OF INTEGER;
  A2 = ARRAY 256 OF CHAR;
  RT = RECORD i, j: BYTE; k: INTEGER END;
  A3 = ARRAY 256 OF RT;

VAR
  v1: A1;
  v2: A2;
  v3: A3;
  i: INTEGER;

BEGIN
  v1[0] := 0DEADBEEFH;
  v1[29] := 0FEEDFACEH;
  v1[255] := 11111111H;

  v2 := "HELLO WORLD";
  v2[11] := "!";
  v2[12] := 00X;

  FOR i := 0 TO LEN(A3)-2 DO v3[i] := v3[i+1] END
END ArrayTypes.
