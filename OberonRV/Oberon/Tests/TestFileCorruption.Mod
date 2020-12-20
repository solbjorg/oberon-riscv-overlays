MODULE TestFileCorruption;
IMPORT SYSTEM, Kernel, Texts, Oberon;

VAR W: Texts.Writer;

PROCEDURE Test*;
  VAR i: INTEGER;
BEGIN
  SYSTEM.PUT(-60, 0EFFEFFH);
  Texts.OpenWriter(W);
  Texts.WriteString(W, "Kernel NofSectors: "); Texts.WriteHex(W, Kernel.NofSectors);
  Texts.Append(Oberon.Log, W.buf);
  FOR i := 0 TO 100 DO
    Texts.WriteString(W, "Hello world");
  END;
END Test;

BEGIN
END TestFileCorruption.
