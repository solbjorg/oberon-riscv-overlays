MODULE Overlay1;
  IMPORT SYSTEM;

  PROCEDURE TestFunctionCall;
  BEGIN SYSTEM.PUT(-60, 0AA3H);
  END TestFunctionCall;

  PROCEDURE TestLoad*;
  BEGIN SYSTEM.PUT(-60, 0AA2H);
    TestFunctionCall;
  END TestLoad;

  (*
  PROCEDURE CallOverlay*;
  BEGIN SYSTEM.PUT(-60, 0FF1H); Overlay2.Test; SYSTEM.PUT(-60, 0FF3H);
  END CallOverlay;
  *)

BEGIN SYSTEM.PUT(-60, 0AA1H); TestLoad;
END Overlay1.
