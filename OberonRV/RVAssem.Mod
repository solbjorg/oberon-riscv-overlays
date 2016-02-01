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


PROCEDURE fmtI*(opcode, fn3, rd, rs1, imm: INTEGER): INTEGER;
BEGIN
  RETURN (opcode MOD 128) + LSL(rd MOD 32, 7) + LSL(fn3 MOD 8, 12) +
      LSL(rs1 MOD 32, 15) + LSL(imm MOD 1000H, 20)
END fmtI;


PROCEDURE fmtU*(opcode, rd, imm: INTEGER): INTEGER;
BEGIN
  RETURN (opcode MOD 128) + LSL(rd MOD 32, 7) + LSL(imm MOD 100000H, 12)
END fmtU;


(*
  The following procedures assemble the remaining RISC-V instruction forms.
*)


PROCEDURE fmtR*(opcode, fn3, fn7, rd, rs1, rs2: INTEGER): INTEGER;
(*
  Place an R-format instruction into the code buffer at location loc.  Note
  that loc is in units of words, not bytes.
*)
BEGIN
  RETURN fmtI(opcode, fn3, rd, rs1, (rs1 MOD 32) + LSL(fn7, 5))
END fmtR;


PROCEDURE fmtS*(opcode, fn3, rs1, rs2, imm: INTEGER): INTEGER;
BEGIN
  RETURN fmtI(opcode, fn3, imm MOD 32, rs1, (rs2 MOD 32) +
      LSL(imm DIV 32 MOD 128, 5))
END fmtS;


PROCEDURE fmtSB*(opcode, fn3, rs1, rs2, imm: INTEGER): INTEGER;
BEGIN
  RETURN fmtI(opcode, fn3, ASR(imm, 11) MOD 2 + LSL(ASR(imm, 1) MOD 16, 1),
      rs1, (rs2 MOD 32) + LSL(ASR(imm, 5) MOD 64, 5) + LSL(ASR(imm, 12), 11))
END fmtSB;


PROCEDURE fmtUJ*(opcode, rd, imm: INTEGER): INTEGER;
BEGIN
  RETURN fmtU(opcode, rd, LSL(ASR(imm, 20) MOD 2, 19) +
      LSL(ASR(imm, 1) MOD 1024, 9) + LSL(ASR(imm, 11) MOD 2, 8) +
      (ASR(imm, 12) MOD 256))
END fmtUJ;


(*
  The following procedures provide a more natural interface to the lower-level
  constructors above.
*)


PROCEDURE lui*(rd, imm: INTEGER): INTEGER;
BEGIN RETURN fmtU(37H, rd, ASR(imm, 12))
END lui;

PROCEDURE auipc*(rd, imm: INTEGER): INTEGER;
BEGIN RETURN fmtU(17H, rd, ASR(imm, 12))
END auipc;

PROCEDURE jal*(rd, imm: INTEGER): INTEGER;
BEGIN RETURN fmtUJ(6FH, rd, imm MOD 200000H)
END jal;

PROCEDURE jalr*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(67H, 0, rd, rs1, imm)
END jalr;

PROCEDURE beq*(rs1, rs2, imm: INTEGER): INTEGER;
BEGIN RETURN fmtSB(63H, 0, rs1, rs2, imm)
END beq;

PROCEDURE bne*(rs1, rs2, imm: INTEGER): INTEGER;
BEGIN RETURN fmtSB(63H, 1, rs1, rs2, imm)
END bne;

PROCEDURE blt*(rs1, rs2, imm: INTEGER): INTEGER;
BEGIN RETURN fmtSB(63H, 4, rs1, rs2, imm)
END blt;

PROCEDURE bge*(rs1, rs2, imm: INTEGER): INTEGER;
BEGIN RETURN fmtSB(63H, 5, rs1, rs2, imm)
END bge;

PROCEDURE bltu*(    rs1, rs2, imm: INTEGER): INTEGER;
BEGIN RETURN fmtSB(63H, 6, rs1, rs2, imm)
END bltu;

PROCEDURE bgeu*(    rs1, rs2, imm: INTEGER): INTEGER;
BEGIN RETURN fmtSB(63H, 7, rs1, rs2, imm)
END bgeu;

PROCEDURE lb*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(03H, 0, rd, rs1, imm)
END lb;

PROCEDURE lh*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(03H, 1, rd, rs1, imm)
END lh;

PROCEDURE lw*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(03H, 2, rd, rs1, imm)
END lw;

PROCEDURE ld*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(03H, 3, rd, rs1, imm)
END ld;

PROCEDURE lbu*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(03H, 4, rd, rs1, imm)
END lbu;

PROCEDURE lhu*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(03H, 5, rd, rs1, imm)
END lhu;

PROCEDURE lwu*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(03H, 6, rd, rs1, imm)
END lwu;

PROCEDURE ldu*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(03H, 7, rd, rs1, imm)
END ldu;

(*
  NOTE: We reverse register arguments for memory stores to make the use
  of the instruction consistent with the corresponding load instructions.
  E.g., if we write LB(1, 2, 300); to load X1 with the byte at 300(X2),
  then SB(1, 2, 300); will store the byte in X1 back into 300(X2).
*)

PROCEDURE sb*(rs2, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtS(23H, 0, rs1, rs2, imm)
END sb;

PROCEDURE sh*(rs2, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtS(23H, 1, rs1, rs2, imm)
END sh;

PROCEDURE sw*(rs2, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtS(23H, 2, rs1, rs2, imm)
END sw;

PROCEDURE sd*(rs2, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtS(23H, 3, rs1, rs2, imm)
END sd;

PROCEDURE addi*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(13H, 0, rd, rs1, imm)
END addi;

PROCEDURE slli*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(13H, 1, rd, rs1, imm MOD 64)
END slli;

PROCEDURE slti*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(13H, 2, rd, rs1, imm)
END slti;

PROCEDURE sltiu*(    rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(13H, 3, rd, rs1, imm)
END sltiu;

PROCEDURE xori*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(13H, 4, rd, rs1, imm)
END xori;

PROCEDURE srli*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(13H, 5, rd, rs1, imm MOD 64)
END srli;

PROCEDURE srai*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(13H, 5, rd, rs1, imm MOD 64 + 40000000H)
END srai;

PROCEDURE ori*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(13H, 6, rd, rs1, imm)
END ori;

PROCEDURE andi*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(13H, 7, rd, rs1, imm)
END andi;

PROCEDURE add*(rd, rs1, rs2: INTEGER): INTEGER;
BEGIN RETURN fmtR(33H, 0, 0, rd, rs1, rs2)
END add;

PROCEDURE sll*(rd, rs1, rs2: INTEGER): INTEGER;
BEGIN RETURN fmtR(33H, 1, 0, rd, rs1, rs2)
END sll;

PROCEDURE slt*(rd, rs1, rs2: INTEGER): INTEGER;
BEGIN RETURN fmtR(33H, 2, 0, rd, rs1, rs2)
END slt;

PROCEDURE sltu*(    rd, rs1, rs2: INTEGER): INTEGER;
BEGIN RETURN fmtR(33H, 3, 0, rd, rs1, rs2)
END sltu;

PROCEDURE xor*(rd, rs1, rs2: INTEGER): INTEGER;
BEGIN RETURN fmtR(33H, 4, 0, rd, rs1, rs2)
END xor;

PROCEDURE srl*(rd, rs1, rs2: INTEGER): INTEGER;
BEGIN RETURN fmtR(33H, 5, 0, rd, rs1, rs2)
END srl;

PROCEDURE sra*(rd, rs1, rs2: INTEGER): INTEGER;
BEGIN RETURN fmtR(33H, 5, 0, rd, rs1, rs2 + 40000000H)
END sra;

PROCEDURE or*(rd, rs1, rs2: INTEGER): INTEGER;
BEGIN RETURN fmtR(33H, 6, 0, rd, rs1, rs2)
END or;

PROCEDURE and*(rd, rs1, rs2: INTEGER): INTEGER;
BEGIN RETURN fmtR(33H, 7, 0, rd, rs1, rs2)
END and;

PROCEDURE fence*(    pred, succ: INTEGER): INTEGER;
BEGIN RETURN fmtI(0FH, 0, 0, 0, (succ MOD 16) + LSL(pred MOD 16, 4))
END fence;

PROCEDURE fencei*(): INTEGER;
BEGIN RETURN fmtI(0FH, 1, 0, 0, 0)
END fencei;

PROCEDURE ecall*(): INTEGER;
BEGIN RETURN fmtI(73H, 0, 0, 0, 0)
END ecall;

PROCEDURE ebreak*(): INTEGER;
BEGIN RETURN fmtI(73H, 0, 0, 0, 1)
END ebreak;

PROCEDURE eret*(): INTEGER;
BEGIN RETURN fmtI(73H, 0, 0, 0, 100H)
END eret;

PROCEDURE addiw*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(1BH, 0, rd, rs1, imm)
END addiw;

PROCEDURE slliw*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(1BH, 1, rd, rs1, imm MOD 64)
END slliw;

PROCEDURE srliw*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(1BH, 5, rd, rs1, imm MOD 64)
END srliw;

PROCEDURE sraiw*(rd, rs1, imm: INTEGER): INTEGER;
BEGIN RETURN fmtI(1BH, 5, rd, rs1, imm MOD 64 + 40000000H)
END sraiw;

PROCEDURE addw*(rd, rs1, rs2: INTEGER): INTEGER;
BEGIN RETURN fmtR(3BH, 0, 0, rd, rs1, rs2)
END addw;

PROCEDURE subw*(rd, rs1, rs2: INTEGER): INTEGER;
BEGIN RETURN fmtR(3BH, 0, 20H, rd, rs1, rs2)
END subw;

PROCEDURE sllw*(rd, rs1, rs2: INTEGER): INTEGER;
BEGIN RETURN fmtR(3BH, 1, 0, rd, rs1, rs2)
END sllw;

PROCEDURE srlw*(rd, rs1, rs2: INTEGER): INTEGER;
BEGIN RETURN fmtR(3BH, 5, 0, rd, rs1, rs2)
END srlw;

PROCEDURE sraw*(rd, rs1, rs2: INTEGER): INTEGER;
BEGIN RETURN fmtR(3BH, 5, 20H, rd, rs1, rs2)
END sraw;

PROCEDURE csrrw*(rd, rs1, csr: INTEGER): INTEGER;
BEGIN RETURN fmtI(73H, 1, rd, rs1, csr)
END csrrw;

PROCEDURE csrrs*(rd, rs1, csr: INTEGER): INTEGER;
BEGIN RETURN fmtI(73H, 2, rd, rs1, csr)
END csrrs;

PROCEDURE csrrc*(rd, rs1, csr: INTEGER): INTEGER;
BEGIN RETURN fmtI(73H, 3, rd, rs1, csr)
END csrrc;

PROCEDURE csrrwi*(rd, imm, csr: INTEGER): INTEGER;
BEGIN RETURN fmtI(73H, 5, rd, imm, csr)
END csrrwi;

PROCEDURE csrrsi*(rd, imm, csr: INTEGER): INTEGER;
BEGIN RETURN fmtI(73H, 6, rd, imm, csr)
END csrrsi;

PROCEDURE csrrci*(rd, imm, csr: INTEGER): INTEGER;
BEGIN RETURN fmtI(73H, 7, rd, imm, csr)
END csrrci;

PROCEDURE mrts*(): INTEGER;
BEGIN RETURN fmtI(73H, 0, 0, 0, 305H)
END mrts;

PROCEDURE mrth*(): INTEGER;
BEGIN RETURN fmtI(73H, 0, 0, 0, 306H)
END mrth;

PROCEDURE hrts*(): INTEGER;
BEGIN RETURN fmtI(73H, 0, 0, 0, 205H)
END hrts;

PROCEDURE wfi*(): INTEGER;
BEGIN RETURN fmtI(73H, 0, 0, 0, 102H)
END wfi;

PROCEDURE fencevm*(rs1: INTEGER): INTEGER;
BEGIN RETURN fmtI(73H, 0, 0, rs1, 101H)
END fencevm;

END RVAssem.

