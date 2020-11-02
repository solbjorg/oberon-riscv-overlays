MODULE TestBigArrays;
  IMPORT SYSTEM;
  CONST FnLength*    = 32;
        SecTabSize*   = 64;
        ExTabSize*   = 12;
        SectorSize*  = 1024;
        IndexSize*   = SectorSize DIV 4;
        HeaderSize*  = 352;
  TYPE DiskAdr  = INTEGER;
    FileName*       = ARRAY FnLength OF CHAR;
    SectorTable*    = ARRAY SecTabSize OF DiskAdr;
    ExtensionTable* = ARRAY ExTabSize OF DiskAdr;
    FileHeader* =
      RECORD (*first page of each file on disk*)
        mark*: INTEGER;
        name*: FileName;
        aleng*, bleng*, date*: INTEGER;
        ext*:  ExtensionTable;
        sec*: SectorTable;
        fill: ARRAY SectorSize - HeaderSize OF BYTE;
      END ;
    IndexSector* = ARRAY IndexSize OF DiskAdr;

  PROCEDURE Init;
    VAR k: INTEGER;
        A: ARRAY 2000 OF DiskAdr;

    PROCEDURE MarkSectors(VAR A: ARRAY OF DiskAdr);
      VAR i: INTEGER;
        bigarray: ARRAY 10000 OF INTEGER;
    BEGIN
      SYSTEM.PUT(-60, SYSTEM.ADR(A));
      FOR i := 0 TO 2000 DO
        SYSTEM.PUT(-60, 0F0000000H + A[i]);
      END;
    END MarkSectors;

    PROCEDURE TraverseDir(VAR A: ARRAY OF DiskAdr);
      VAR i, j: INTEGER;
    BEGIN i := 0; j := 5678H;
      WHILE i < 2000 DO
        A[i] := j; INC(i); DEC(j);
      END ;
    END TraverseDir;

  BEGIN
    SYSTEM.PUT(-60, SYSTEM.ADR(A));
    TraverseDir(A);
    MarkSectors(A);
  END Init;

BEGIN SYSTEM.PUT(-60, 0FAB50000H); Init;
END TestBigArrays.
