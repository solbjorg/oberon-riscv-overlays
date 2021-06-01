MODULE Overlay3;
  IMPORT SYSTEM, Overlay4;

  PROCEDURE Test*;
  BEGIN SYSTEM.PUT(-60, 0BB4H);
    Overlay4.Test;
  END Test;

BEGIN SYSTEM.PUT(-60, 0DD1H);
  Test;
END Overlay3.
