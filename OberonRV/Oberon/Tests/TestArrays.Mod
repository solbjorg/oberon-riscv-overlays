MODULE TestArrays;
  IMPORT SYSTEM, Kernel, TestArrays2;

  PROCEDURE Test*;
    VAR i: INTEGER;
  BEGIN
    i := 5;

    SYSTEM.PUT(-60, 0DAAAAFBAH);
    SYSTEM.PUT(-60, Kernel.stackSize);
    SYSTEM.PUT(-60, TestArrays2.errcnt);
    SYSTEM.PUT(-60, TestArrays2.KWX[5]);
    SYSTEM.PUT(-60, TestArrays2.KWX[i]);
  END Test;

END TestArrays.
