(*
  This module provides services to assemble RISC-V RV64I software into a
  buffer.  Supported instructions cover everything the Kestrel-3 emulator
  can run.
*)

MODULE RVAssem;


(*
  These two procedures are the lowest level assemblers in the module.
  The I- and U- format instructions are *the* fundamental instruction forms
  that RISC-V supports.  All other instruction formats can, for the purposes
  of this assembler module, be expressed in terms of I- or U-formats.

  Note that loc refers to a word-aligned location (measured in 32-bit words)
  in the code array.
*)


PROCEDURE fmtI*(VAR code: ARRAY OF INTEGER; VAR loc: INTEGER;
    opcode, fn3, rd, rs1, imm: INTEGER);
BEGIN
  code[loc] := (opcode MOD 128) + LSL(rd MOD 32, 7) + LSL(fn3 MOD 8, 12) +
            LSL(rs1 MOD 32, 15) + LSL(imm MOD 1000H, 20);
  INC(loc);
END fmtI;


PROCEDURE fmtU*(VAR code: ARRAY OF INTEGER; VAR loc: INTEGER;
    opcode, rd, imm);
BEGIN
  code[loc] := (opcode MOD 128) + LSL(rd MOD 32, 7) + LSL(imm MOD 100000H, 12);
  INC(loc);
END fmtU;


(*
  The following procedures assemble the remaining RISC-V instruction forms.
*)


PROCEDURE fmtR*(VAR code: ARRAY OF INTEGER; VAR loc: INTEGER;
    opcode, fn3, fn7, rd, rs1, rs2: INTEGER);
(*
  Place an R-format instruction into the code buffer at location loc.  Note
  that loc is in units of words, not bytes.
*)
BEGIN
  fmtI(code, loc, opcode, fn3, rd, rs1, (rs MOD 32) + LSL(fn7, 5));
END fmtR;


PROCEDURE fmtS*(VAR code: ARRAY OF INTEGER; VAR loc: INTEGER;
    opcode, fn3, rs1, rs2, imm: INTEGER);
BEGIN
  fmtI(code, loc, opcode, fn3, imm MOD 32, rs1,
      (rs2 MOD 32) + LSL(imm DIV 32 MOD 128, 5));
END fmtS;


PROCEDURE fmtSB*(VAR code: ARRAY OF INTEGER; VAR loc: INTEGER;
    opcode, fn3, rs1, rs2, imm: INTEGER);
BEGIN
  fmtI(code, loc, opcode, fn3, ASR(imm, 11) MOD 2 + LSL(ASR(imm, 1) MOD 16, 1),
      rs1, rs2, (imm DIV 32 MOD 64) + LSL(ASR(imm, 12), 7));
END fmtSB;


PROCEDURE fmtUJ*(VAR code: ARRAY OF INTEGER; VAR loc: INTEGER;
    opcode, rd, imm);
BEGIN
  fmtU(code, loc, opcode, rd,
      LSL(ASR(imm, 20) MOD 2, 19) + LSL(ASR(imm, 1) MOD 1024, 9) +
      LSL(ASR(imm, 11) MOD 2, 8) + (ASR(imm, 12) MOD 256));
END fmtUJ;


(*
  The following procedures provide a more natural interface to the lower-level
  constructors above.
*)


PROCEDURE LUI*(VAR c: ARRAY OF INTEGER: VAR l: INTEGER; rd, imm: INTEGER);
BEGIN fmtU(c, l, 37H, rd, ASR(imm, 12));
END LUI;

PROCEDURE AUIPC*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, imm: INTEGER);
BEGIN fmtU(c, l, 17H, rd, ASR(imm, 12));
END AUIPC;

PROCEDURE JAL*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, imm: INTEGER);
BEGIN fmtUJ(c, l, 6FH, rd, imm MOD 200000H);
END JAL;

PROCEDURE JALR*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 67H, 0, rd, rs1, imm);
END JALR;

PROCEDURE BEQ*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rs1, rs2, imm: INTEGER);
BEGIN fmtSB(c, l, 63H, 0, rs1, rs2, imm);
END BEQ;

PROCEDURE BNE*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rs1, rs2, imm: INTEGER);
BEGIN fmtSB(c, l, 63H, 1, rs1, rs2, imm);
END BNE;

PROCEDURE BLT*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rs1, rs2, imm: INTEGER);
BEGIN fmtSB(c, l, 63H, 4, rs1, rs2, imm);
END BLT;

PROCEDURE BGE*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rs1, rs2, imm: INTEGER);
BEGIN fmtSB(c, l, 63H, 5, rs1, rs2, imm);
END BGE;

PROCEDURE BLTU*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER;
    rs1, rs2, imm: INTEGER);
BEGIN fmtSB(c, l, 63H, 6, rs1, rs2, imm);
END BLTU;

PROCEDURE BGEU*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER;
    rs1, rs2, imm: INTEGER);
BEGIN fmtSB(c, l, 63H, 7, rs1, rs2, imm);
END BGEU;

PROCEDURE LB*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 03H, 0, rd, rs1, imm);
END LB;

PROCEDURE LH*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 03H, 1, rd, rs1, imm);
END LH;

PROCEDURE LW*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 03H, 2, rd, rs1, imm);
END LW;

PROCEDURE LD*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 03H, 3, rd, rs1, imm);
END LD;

PROCEDURE LBU*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 03H, 4, rd, rs1, imm);
END LBU;

PROCEDURE LHU*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 03H, 5, rd, rs1, imm);
END LHU;

PROCEDURE LWU*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 03H, 6, rd, rs1, imm);
END LWU;

PROCEDURE LDU*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 03H, 7, rd, rs1, imm);
END LDU;

(*
  NOTE: We reverse register arguments for memory stores to make the use
  of the instruction consistent with the corresponding load instructions.
  E.g., if we write LB(c, l, 1, 2, 300); to load X1 with the byte at 300(X2),
  then SB(c, l, 1, 2, 300); will store the byte in X1 back into 300(X2).
*)

PROCEDURE SB*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rs2, rs1, imm: INTEGER);
BEGIN fmtS(c, l, 23H, 0, rs1, rs2, imm);
END SB;

PROCEDURE SH*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rs2, rs1, imm: INTEGER);
BEGIN fmtS(c, l, 23H, 1, rs1, rs2, imm);
END SH;

PROCEDURE SW*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rs2, rs1, imm: INTEGER);
BEGIN fmtS(c, l, 23H, 2, rs1, rs2, imm);
END SW;

PROCEDURE SD*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rs2, rs1, imm: INTEGER);
BEGIN fmtS(c, l, 23H, 3, rs1, rs2, imm);
END SD;

PROCEDURE ADDI*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 13H, 0, rd, rs1, imm);
END ADDI;

PROCEDURE SLLI*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 13H, 1, rd, rs1, imm MOD 64);
END SLLI;

PROCEDURE SLTI*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 13H, 2, rd, rs1, imm);
END SLTI;

PROCEDURE SLTIU*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER;
    rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 13H, 3, rd, rs1, imm);
END SLTIU;

PROCEDURE XORI*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 13H, 4, rd, rs1, imm);
END XORI;

PROCEDURE SRLI*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 13H, 5, rd, rs1, imm MOD 64);
END SRLI;

PROCEDURE SRAI*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 13H, 5, rd, rs1, imm MOD 64 + 40000000H);
END SRAI;

PROCEDURE ORI*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 13H, 6, rd, rs1, imm);
END ORI;

PROCEDURE ANDI*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm: INTEGER);
BEGIN fmtI(c, l, 13H, 7, rd, rs1, imm);
END ANDI;

PROCEDURE ADD*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, rs2: INTEGER);
BEGIN fmtR(c, l, 33H, 0, 0, rd, rs1, rs2);
END ADD;

PROCEDURE SLL*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, rs2: INTEGER);
BEGIN fmtR(c, l, 33H, 1, 0, rd, rs1, rs2);
END SLL;

PROCEDURE SLT*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, rs2: INTEGER);
BEGIN fmtR(c, l, 33H, 2, 0, rd, rs1, rs2);
END SLT;

PROCEDURE SLTU*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER;
    rd, rs1, rs2: INTEGER);
BEGIN fmtR(c, l, 33H, 3, 0, rd, rs1, rs2);
END SLTU;

PROCEDURE XOR*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, rs2: INTEGER);
BEGIN fmtR(c, l, 33H, 4, 0, rd, rs1, rs2);
END XOR;

PROCEDURE SRL*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, rs2: INTEGER);
BEGIN fmtR(c, l, 33H, 5, 0, rd, rs1, rs2);
END SRL;

PROCEDURE SRA*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, rs2: INTEGER);
BEGIN fmtR(c, l, 33H, 5, 0, rd, rs1, rs2 + 40000000H);
END SRA;

PROCEDURE OR*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, rs2: INTEGER);
BEGIN fmtR(c, l, 33H, 6, 0, rd, rs1, rs2);
END OR;

PROCEDURE AND*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, rs2: INTEGER);
BEGIN fmtR(c, l, 33H, 7, 0, rd, rs1, rs2);
END AND;

PROCEDURE FENCE*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER;
    pred, succ: INTEGER);
BEGIN fmtI(c, l, 0FH, 0, 0, 0, (succ MOD 16) + LSL(pred MOD 16, 4));
END FENCE;

PROCEDURE FENCEI*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER);
BEGIN fmtI(c, l, 0FH, 1, 0, 0, 0);
END FENCEI;

PROCEDURE ECALL*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER);
BEGIN fmtI(c, l, 73H, 0, 0, 0, 0);
END ECALL;

PROCEDURE EBREAK*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER);
BEGIN fmtI(c, l, 73H, 0, 0, 0, 1);
END EBREAK;

PROCEDURE ERET*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER);
BEGIN fmtI(c, l, 73H, 0, 0, 0, 100H);
END ERET;

PROCEDURE ADDIW*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm);
BEGIN fmtI(c, l, 1BH, 0, rd, rs1, imm);
END ADDIW;

PROCEDURE SLLIW*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm);
BEGIN fmtI(c, l, 1BH, 1, rd, rs1, imm MOD 64);
END SLLIW;

PROCEDURE SRLIW*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm);
BEGIN fmtI(c, l, 1BH, 5, rd, rs1, imm MOD 64);
END SRLIW;

PROCEDURE SRAIW*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, imm);
BEGIN fmtI(c, l, 1BH, 5, rd, rs1, imm MOD 64 + 40000000H);
END SRAIW;

PROCEDURE ADDW*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, rs2);
BEGIN fmtR(c, l, 3BH, 0, 0, rd, rs1, rs2);
END ADDW;

PROCEDURE SUBW*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, rs2);
BEGIN fmtR(c, l, 3BH, 0, 20H, rd, rs1, rs2);
END SUBW;

PROCEDURE SLLW*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, rs2);
BEGIN fmtR(c, l, 3BH, 1, 0, rd, rs1, rs2);
END SLLW;

PROCEDURE SRLW*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, rs2);
BEGIN fmtR(c, l, 3BH, 5, 0, rd, rs1, rs2);
END SRLW;

PROCEDURE SRAW*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, rs2);
BEGIN fmtR(c, l, 3BH, 5, 20H, rd, rs1, rs2);
END SRAW;

PROCEDURE CSRRW*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, csr);
BEGIN fmtI(c, l, 73H, 1, rd, rs1, csr);
END CSRRW;

PROCEDURE CSRRS*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, csr);
BEGIN fmtI(c, l, 73H, 2, rd, rs1, csr);
END CSRRS;

PROCEDURE CSRRC*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, rs1, csr);
BEGIN fmtI(c, l, 73H, 3, rd, rs1, csr);
END CSRRC;

PROCEDURE CSRRWI*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, imm, csr);
BEGIN fmtI(c, l, 73H, 5, rd, imm, csr);
END CSRRWI;

PROCEDURE CSRRSI*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, imm, csr);
BEGIN fmtI(c, l, 73H, 6, rd, imm, csr);
END CSRRSI;

PROCEDURE CSRRCI*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rd, imm, csr);
BEGIN fmtI(c, l, 73H, 7, rd, imm, csr);
END CSRRCI;

PROCEDURE MRTS*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER);
BEGIN fmtI(c, l, 73H, 0, 0, 0, 305H);
END MRTS;

PROCEDURE MRTH*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER);
BEGIN fmtI(c, l, 73H, 0, 0, 0, 306H);
END MRTS;

PROCEDURE HRTS*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER);
BEGIN fmtI(c, l, 73H, 0, 0, 0, 205H);
END MRTS;

PROCEDURE WFI*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER);
BEGIN fmtI(c, l, 73H, 0, 0, 0, 102H);
END WFI;

PROCEDURE FENCEVM*(VAR c: ARRAY OF INTEGER; VAR l: INTEGER; rs1: INTEGER);
BEGIN fmtI(c, l, 73H, 0, 0, rs1, 101H);
END FENCEVM;

END RVAssem.

