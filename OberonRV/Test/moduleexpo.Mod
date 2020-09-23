MODULE TestModule;

  CONST SectorLength = 1024;

  TYPE Sector* = ARRAY SectorLength OF BYTE;

  VAR x, y: INTEGER;

  PROCEDURE Simple*(src: INTEGER; VAR a: Sector);
  BEGIN x := 5; y := 3 + x;
  END Simple;

END TestModule.
