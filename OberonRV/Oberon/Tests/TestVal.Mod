MODULE TestVal;
IMPORT SYSTEM, FileDir;

CONST HS        = FileDir.HeaderSize;

TYPE  DiskAdr = INTEGER;
      Buffer  = POINTER TO BufferDesc;

      BufferDesc =
        RECORD apos, lim: INTEGER;
          mod: BOOLEAN;
          next: Buffer;
          data: FileDir.DataSector
        END ;

PROCEDURE Test*;
  VAR a: INTEGER;
    buf, buf2: Buffer;
    F1, F2: FileDir.FileHd;
BEGIN
  SYSTEM.PUT(-60, 0AA00H);
  NEW(buf); buf.apos := 15; buf.next := buf; buf.mod := FALSE;
  F1 := SYSTEM.VAL(FileDir.FileHd, SYSTEM.ADR(buf.data));
  F1.mark := FileDir.HeaderMark;
  F1.aleng := 0; F1.bleng := HS;
  a := SYSTEM.VAL(INTEGER, buf);
  SYSTEM.PUT(-60, SYSTEM.ADR(buf^));
  SYSTEM.PUT(-60, a);
  SYSTEM.PUT(-60, buf.apos);
  buf2 := SYSTEM.VAL(Buffer, a);
  SYSTEM.PUT(-60, buf2.apos);
  a := -1;
  SYSTEM.PUT(-60, -1);
  SYSTEM.PUT(-60, a);
  SYSTEM.PUT(-60, 0AA00H);
END Test;

END TestVal.
