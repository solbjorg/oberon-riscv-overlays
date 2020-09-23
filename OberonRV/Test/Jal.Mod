MODULE* JalTest;
  IMPORT SYSTEM;

  (* Deposits a relative offset jump to `Padr` in location `at` *)
  (* Used to install functions at places required for the operating system. *)
  PROCEDURE Install(Padr, at: INTEGER);
    VAR inst: LONGINT;

     (* Returns a `jal x0, imm` instruction. *)
    PROCEDURE Jal(imm: LONGINT) : LONGINT;
      VAR imm20, imm19to12, imm11, imm10to1: INTEGER;
    BEGIN
      imm20 := imm DIV 100000H;
      imm19to12 := (imm - imm20 * 100000H) DIV 1000H;
      imm11 := (imm - (imm20 * 100000H + imm19to12 * 1000H)) DIV 800H;
      imm10to1 := (imm - (imm20 * 100000H + imm19to12 * 1000H + imm11 * 800H)) DIV 2H;
      RETURN ((((imm20 * 400H + imm10to1) * 2H + imm11) * 100H + imm19to12) * 20H + 0) * 80H + 111
    END Jal;

  BEGIN inst := Jal((Padr - at) MOD 200000H); SYSTEM.PUT(at, inst); SYSTEM.PUT(-60, inst);
  END Install;

BEGIN Install(3028H, 20H);
END JalTest.
