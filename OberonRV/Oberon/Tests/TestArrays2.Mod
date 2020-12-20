MODULE TestArrays2;
  IMPORT SYSTEM;

  CONST NKW = 34;  (*nof keywords*)
    IdLen* = 32;
    maxExp = 38; stringBufSize = 2560;
    (*lexical symbols*)
    null = 0; times* = 1; rdiv* = 2; div* = 3; mod* = 4;
    and* = 5; plus* = 6; minus* = 7; or* = 8; eql* = 9;
    neq* = 10; lss* = 11; leq* = 12; gtr* = 13; geq* = 14;
    in* = 15; is* = 16; arrow* = 17; period* = 18;
    char* = 20; int* = 21; real* = 22; false* = 23; true* = 24;
    nil* = 25; string* = 26; not* = 27; lparen* = 28; lbrak* = 29;
    lbrace* = 30; ident* = 31;
    if* = 32; while* = 34; repeat* = 35; case* = 36; for* = 37;
    comma* = 40; colon* = 41; becomes* = 42; upto* = 43; rparen* = 44;
    rbrak* = 45; rbrace* = 46; then* = 47; of* = 48; do* = 49;
    to* = 50; by* = 51; semicolon* = 52; end* = 53; bar* = 54;
    else* = 55; elsif* = 56; until* = 57; return* = 58;
    array* = 60; record* = 61; pointer* = 62; const* = 63; type* = 64;
    var* = 65; procedure* = 66; begin* = 67; import* = 68; module* = 69; eot = 70;

  TYPE Ident* = ARRAY IdLen OF CHAR;

  VAR ival*, slen*: LONGINT;  (*results of Get*)
    id*: Ident;  (*for identifiers*)
    str*: ARRAY stringBufSize OF CHAR;
    KWX*: ARRAY 10 OF INTEGER;
    errcnt*: INTEGER;

    ch: CHAR;  (*last character read*)
    errpos: LONGINT;
    k: INTEGER;
    keyTab: ARRAY NKW OF
        RECORD sym: INTEGER; id: ARRAY 12 OF CHAR END;

  PROCEDURE GlobalArray*;
    VAR i, sym: INTEGER;
  BEGIN
    i := 0;
    SYSTEM.PUT(-60, 0DAFBAH);
    SYSTEM.PUT(-60, SYSTEM.ADR(KWX[5]));
    SYSTEM.PUT(-60, KWX[5]);
    SYSTEM.PUT(-60, KWX[i+5]);
    k := KWX[i+5];
    SYSTEM.PUT(-60, KWX[5]);
    SYSTEM.PUT(-60, KWX[i+5]);
  END GlobalArray;

BEGIN
  errcnt := 2;
  KWX[0] := 0;
  KWX[1] := 1;
  KWX[2] := 2;
  KWX[3] := 3;
  KWX[4] := 4;
  KWX[5] := 5;
  KWX[6] := 6;
  KWX[7] := 7;
  KWX[8] := 8;
  KWX[9] := 9;
  GlobalArray;
END TestArrays2.
