MODULE TestType;
  IMPORT SYSTEM;
  TYPE R0 = RECORD x: INTEGER END ;
    R1 = RECORD (R0) y: INTEGER END ;
    R2 = RECORD (R1) z: INTEGER END ;
    P0 = POINTER TO R0;
    P1 = POINTER TO R1;
    P2 = POINTER TO R2;
  VAR k: INTEGER;
    p0: P0; p1: P1; p2: P2;

  PROCEDURE Install*(Padr, at: INTEGER);
    VAR inst: LONGINT;

     (* Returns a `jal x0, imm` instruction. *)
    PROCEDURE Jal(imm: LONGINT) : LONGINT;
      VAR result, imm20, imm19to12, imm11, imm10to1: LONGINT;
    BEGIN
      imm20 := imm DIV 100000H;
      imm19to12 := (imm - imm20 * 100000H) DIV 1000H;
      imm11 := (imm - (imm20 * 100000H + imm19to12 * 1000H)) DIV 800H;
      imm10to1 := (imm - (imm20 * 100000H + imm19to12 * 1000H + imm11 * 800H)) DIV 2H;
      result := ((((imm20 * 400H + imm10to1) * 2H + imm11) * 100H + imm19to12) * 20H + 0) * 80H + 111;
      RETURN result
    END Jal;

  BEGIN inst := Jal(Padr - at); SYSTEM.PUT(at, inst);
  END Install;

  PROCEDURE Trap(VAR a: INTEGER; b: INTEGER);
    VAR u, v, w: INTEGER;
    (* In RISC5, bits were conveniently unused in the reg jump instruction, which Oberon *)
    (* then used to encode trap numbers. We don't have that luxury, so we deposit the trap *)
    (* number _after_ the instruction instead. It can't be executed, so it will cause *)
    (* errors if jumped to (and confuse any disassembler!). *)
  BEGIN u := SYSTEM.REG(1); SYSTEM.GET(u + 4, v); w := v DIV 1000000H MOD 10H; (*trap number*)
    (* Note: 192 sets the top two LEDs. This indicates that a trap was hit. *)
    SYSTEM.PUT(-60, v); REPEAT UNTIL FALSE
    (* Ok, more explanation of some of the low-level hacks in use here. *)
    (* We had to deposit the trap number _after_ the instruction, which means if we *)
    (* return to that location, we're in trouble, as it will execute gobbledygook. *)
    (* Ideal solution: we just add 4 to RA, and we'll jump to after the trap number. *)
    (* That doesn't work, as the function epilogue overwrites RA... *)
    (* So currently there is a jump instruction to skip over the trapnum as we return... *)
    (* It is ugly. *)
    (* Note that this will never execute if trapnum > 0; but we had to do *)
    (* this for NEW() to work as it's supposed to. *)
    (* There may be a better scheme for RISC-V! TODO. *)
  END Trap;

BEGIN
  Install(SYSTEM.ADR(Trap), 20H);  (*install temporary trap; replaced later by System.Mod*)
  SYSTEM.PUT(-60, 0ABCH);
  IF p0 IS P2 THEN k := 3 END ;
  SYSTEM.PUT(-60, k);
  p0(P2).z := 50;
  k := p0(P2).z;
  SYSTEM.PUT(-60, k);
END TestType.
