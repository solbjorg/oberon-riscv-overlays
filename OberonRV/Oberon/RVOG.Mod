MODULE RVOG; (* NW  31.5.2015  code generator in Oberon-07 for RISC*)
IMPORT SYSTEM, Files, Texts, Oberon, RVAssem, RVOS, RVOB; (*RVDis;*)

(*
  Code generator for Oberon compiler for RISC-V processor.
  Procedural interface to Parser OSAP; result in array "code".
  Procedure Close writes code-files
*)

CONST
  BitsPerInteger = RVOB.BitsPerInteger;
  IntegerSize = BitsPerInteger DIV 8;

  BitsPerInsn = RVOB.BitsPerInsn;
  InsnSize = BitsPerInsn DIV 8;

  StkOrg0 = 65536;    (* For ROM modules only *)
  VarOrg0 = 0;

  firstReg* = 8;    (* First usable data register *)
  maxReg* = 32;     (* Last usable data register, plus one *)

  RA = 1;           (* Return address register *)
  SP = 2;           (* Stack pointer *)
  GP = 3;           (* Globals Pointer *)
  TP = 4;           (* Thread Pointer *)

  SB = GP;          (* We assign the role of SB to GP *)
  MT = TP;          (* We assign the role of MT to TP *)

  (* Note: all of these can be safely made larger, so long as you have the heap space! *)
  maxCode = 16384;  (* Total # of instructions in a module *)
  maxStrx = 3000;  (* statically allocated strings *)
  maxTD = 512;      (* 512 words of space for type descriptors *)

  Reg = 10; RegI = 11; Cond = 12;  (*internal item modes*)

  (*
    Conditional branch codes.  Note that EQ..GEU map to the RISC-V
    hardware encodings for the same operations.  NEV and ALW are
    logical operations which get translated to non-conditional
    instructions.
  *)

  EQ = 0;  NE = 1;
  LT = 4;  GE = 5;
  LTU = 6; GEU = 7; (* Used mainly with strings *)
  NEV = 8; ALW = 9; (* never and always *)

  (* Trap numbers *)

  TrapNew = 0;          (* NEW *)
  TrapIndexBounds = 1;  (* Array index bounds check failed *)
  TrapTypeMismatch = 2; (* Type check failed at runtime *)
  TrapSourceTooBig = 3; (* Source record, array, or string is too big for := *)
  TrapNilProcedure = 4; (* Attempt to call NIL procedure *)
  TrapDivByZero = 6;    (* Attempt to divide by zero *)
  TrapAssertFailure = 7;
  TrapNegativeSize = 8;

  (* Useful constants for bit manip *)
  C24 = 1000000H;
  C20 = 100000H;
  C16 = 10000H;
  C12 = 1000H;
  C8  = 100H;

TYPE
  Item* = RECORD
    mode*: INTEGER;
    type*: RVOB.Type;
    a*, b*, r, cl, cr: INTEGER;
    rdo*: BOOLEAN  (*read only*)
  END;

  Program* = POINTER TO ProgramDesc;
  Code* = POINTER TO CodeDesc;
  Strings* = POINTER TO StringsDesc;
  TypeDescriptors* = POINTER TO TypeDescriptorsDesc;

  ProgramDesc* = RECORD
    code: Code;
    strings: Strings;
    data: TypeDescriptors;
  END;

  CodeDesc* = RECORD
    c: ARRAY maxCode OF INTEGER;
  END;

  StringsDesc* = RECORD
    s: ARRAY maxStrx OF CHAR;
  END;

  TypeDescriptorsDesc* = RECORD
    t: ARRAY maxTD OF INTEGER;  (*type descriptors*)
  END;

  (*
    Item forms and meaning of fields:

    mode    r      a       b          cl        cr
    ----------------------------------------------------
    Const   -      value   procedure
    Var     base   off     -
    Par     -      off0    off1
    Reg     regno
    RegI    regno  off     -
    Cond    cond   Fchain  Tchain     LHS reg   RHS reg
    ----------------------------------------------------

    Const items typically manifest when you use an immediate value
    inside the program being compiled.  Const items can also refer
    to procedures as well.
    
    Var items typically refer to "direct" addresses, such as the
    location of a global or local variable (hence it's name).
    
    Par items typically refer to "indirect" addresses, such as those
    you'd find in parameter lists.
  *)

VAR
  W: Texts.Writer;
  pc*, varsize: INTEGER;  (* program counter, data indices *)
  tdx, strx: INTEGER;     (* Type descriptor and string array indices *)
  entry: INTEGER;         (* module body entrypoint *)
  RH: INTEGER;            (* available registers R[firstReg] ... R[H-1]*)
  curSB: INTEGER;         (* current static base in SB (module table index) *)
  frame: INTEGER;         (* frame offset changed in SaveRegs, RestoreRegs *)
  check: BOOLEAN;          (* emit run-time checks *)
  stacktrace: BOOLEAN;    (* add a stack trace *)
  version: INTEGER;       (* ABI Version: 0 = boot ROM, 1 = Oberon System *)
  modid: RVOS.Ident;

  sym2rel: ARRAY 6 OF INTEGER;
  sym2uRel: ARRAY 6 OF INTEGER;
    
  program: Program;
  code: Program;
  data: TypeDescriptors;
  str: Strings;

  (* Origins of lists of relocations to be fixed up by the loader *)
  fixorgP, fixorgD, fixorgT: INTEGER;

PROCEDURE put*(w: INTEGER);
BEGIN
   (*
  Texts.WriteHex(W, pc*InsnSize);  Texts.WriteString(W, "   ");
  Texts.WriteHex(W, w); Texts.WriteString(W, " : ");
  RVDis.WriteOpcode(W, w);  Texts.WriteLn(W);
  Texts.Append(Oberon.Log, W.buf); *)
  program.code.c[pc] := w;  INC(pc)
END put;

(* Register Stack Maintenance *)

(* Allocate register RH, adjusting RH accordingly. *)
PROCEDURE incR;
BEGIN
  IF RH < maxReg THEN INC(RH) ELSE RVOS.Mark("register stack overflow") END
END incR;

(* Free register RH-1, adjusting RH accordingly. *)
PROCEDURE decR;
BEGIN
  IF RH > firstReg THEN DEC(RH) ELSE RVOS.Mark("register stack underflow") END
END decR;

(* Compiler error if register stack is corrupt or if program is too big *)
PROCEDURE CheckRegs*;
BEGIN
  IF RH # firstReg THEN RVOS.Mark("Reg Stack"); RH := firstReg END ;
  IF pc >= maxCode - 40 THEN RVOS.Mark("Program too long") END
END CheckRegs;

(* Used for immediate bitfield checks for ANDI/ORI/XORI insns *)
PROCEDURE FitsIn11Bits(n: INTEGER): BOOLEAN;
BEGIN
  RETURN (0 <= n) & (n < 2048)
END FitsIn11Bits;

PROCEDURE FitsIn12Bits(n: INTEGER): BOOLEAN;
BEGIN
  RETURN (-2048 <= n) & (n < 2048)
END FitsIn12Bits;

PROCEDURE FitsIn32Bits(n: INTEGER): BOOLEAN;
BEGIN
  RETURN TRUE  (* hack for 32-bit Oberon bootstrap (-80000000H <= n) & (n < 80000000H) *)
END FitsIn32Bits;

(*
  Initialize an item that represents a conditional jump later on.
  The true and false fixup chains are zeroed.  Additionally, the left and
  right comparison registers are set to RH-2 and RH-1, respectively.
  Use SetCC0 if you wish to compare an expression against zero instead.
*)

PROCEDURE SetCC(VAR x: Item; n: INTEGER);
BEGIN
  ASSERT(n IN {EQ, NE, LT, GE, LTU, GEU});
  x.mode := Cond;
  x.a := 0; x.b := 0; x.r := n;
  x.cl := RH-2; x.cr := RH-1
END SetCC;

PROCEDURE SetCC0(VAR x: Item; n: INTEGER);
BEGIN
  SetCC(x, n);
  x.cl := RH-1; x.cr := 0;
END SetCC0;

(*
  Compile a conditional branch to a trap handler of some kind.  The way NW
  encoded this instruction for RISC0 or RISC5 is:

  | BLR | cond | byte offset in .Mod file | trap# |  14  |

  The idea was that the trap handler would produce an Oberon log diagnostic
  that informed the user of the trap number, and the byte offset of the file.
  Presumably, based on the PC, the the trap handler could deduce the actual
  file *name*.  My version of Oberon System doesn't provide all of this, but
  does yield what it can.

  Alas, RISC-V doesn't offer the convenient unused opcode bits that RISC5 does.
  So, we need to make do with a much less elegant sequence of instructions:

    Bxx     xL, xR, *+
    JALR    RA, 0(MT)
    JAL     x0, 8
    WORD    LSL(trap, 24) + (RVOS.Pos() MOD 16777216)
    (normal execution resumes here)

  In order for this to work, of course, the branch must test the inverse of
  the desired condition.  Set xR to 0 to test against zero.

  NOTE: This requires that MT[0] *not* be a pointer to a module's data section.
  Rather, it must contain a JAL instruction to the trap handler.
*)

PROCEDURE opposite(cond: INTEGER): INTEGER;
BEGIN
  ASSERT(cond IN {EQ, NE, LT, GE, LTU, GEU, NEV, ALW});
  (*
    Depends on the fact that condition codes are binary encoded like so:
    2 1 0
    \_/ |
     |  +-- 0 = branch on true; 1 = branch on false
     +----- 00 = L=R, 10 = L<R signed; 11 = L<R unsigned
  *)
  RETURN SYSTEM.VAL(INTEGER, SYSTEM.VAL(SET, cond) / {0})
END opposite;

PROCEDURE Trap(cond, num, regL, regR: INTEGER);
BEGIN
  (* Emits a branch that skips past the trap if requirement is met. *)
  IF num > 0 THEN put(RVAssem.fmtSB(63H, opposite(cond), regL, regR, 16)) END;
  put(RVAssem.jalr(RA, MT, 0));
  put(RVAssem.jal(0, 8));
  (* Deposit the trap number as well as where it happened. *)
  put(LSL(num, 24) + (RVOS.Pos() MOD 16777216))
END Trap;

(*
  SB register management.
*)

(* Module numbers start at 1, as MT[0] always points to the Trap procedure *)
   (* in the Oberon system. See Ch. 12.7.10 of the PO book (PO.Applications). *)
PROCEDURE invalSB;
BEGIN curSB := 1
END invalSB;

(*
  Handling of forward reference, fixups of forward branch addresses.

  The forward branches themselves are stored as simple 32-bit data words.
  They have the binary representation as follows:

    LSL(cond MOD 16, 0) +       (4 bits)
    LSL(rightReg MOD 32, 4) +   (5 bits)
    LSL(leftReg MOD 32, 9) +    (5 bits)
                                (2 bits unused)
    LSL(link MOD 10000H, 16)    (16 bits)

  The act of patching the fixup will replace the entire word with a conditional
  branch instruction as appropriate.  A zero link field terminates the list.
*)

PROCEDURE MakeFwdBranch(cond, l, r, link: INTEGER): INTEGER;
BEGIN
  ASSERT(cond IN {EQ, NE, LT, GE, LTU, GEU, NEV, ALW});
  IF ~(((firstReg <= l) & (l < maxReg)) OR (l = 0)) THEN
    RVOS.Mark("Invalid comparison register")
  END;
  (*ASSERT((firstReg <= l) & (l < maxReg));*)
  IF ~(((firstReg <= r) & (r < maxReg)) OR (r = 0)) THEN
    RVOS.Mark("Invalid comparison register");
  END;
  ASSERT((0 <= link) & (link < maxCode));
  RETURN
    LSL(cond MOD 16, 0) +
    LSL(l MOD 32, 9) + LSL(r MOD 32, 4) +
    LSL(link MOD 10000H, 16)
END MakeFwdBranch;

PROCEDURE fix(at, with: INTEGER);
VAR
  displacement, cond, lr, rr: INTEGER;
BEGIN
  cond := program.code.c[at] MOD 16;
  lr := ASR(program.code.c[at], 9) MOD 32;
  rr := ASR(program.code.c[at], 4) MOD 32;
  displacement := (with-at)*InsnSize;
  IF cond = ALW THEN program.code.c[at] := RVAssem.jal(0, displacement)
  ELSIF cond = NEV THEN program.code.c[at] := RVAssem.ori(0, 0, 0)
  ELSE
    IF ~FitsIn12Bits(displacement DIV 2) THEN
      (* Can't do this fixup if we aren't at the head of code *)
      IF with # pc THEN
        RVOS.Mark("Conditional body too large");
      ELSE
        (* Quick explainer: we replace the branch with a jump to /the end of the if body/, *)
        (* and then construct the branch there. This allows us to create branches covering more *)
        (* instructions than the offset of a B-type instruction allows, by leveraging JAL instead.*)
        program.code.c[at] := RVAssem.jal(0, displacement+4); (* jumps to the SB instruction below *)
        put(RVAssem.jal(0, 12)); (* jump over branch; only executed in execution of if body... *)
        put(RVAssem.fmtSB(63H, cond, lr, rr, 8)); (* jump over below JAL into start of if body *)
        put(RVAssem.jal(0, -displacement-4)) (* jump into start of if body *)
      END;
    ELSE
      program.code.c[at] := RVAssem.fmtSB(63H, cond, lr, rr, displacement)
    END
  END
END fix;

PROCEDURE FixLinkWith(L, dst: INTEGER);
  VAR next: INTEGER;
BEGIN
  WHILE L # 0 DO
    next := ASR(program.code.c[L], 16) MOD 10000H; fix(L, dst);
    L := next
  END
END FixLinkWith;

PROCEDURE FixLink*(L: INTEGER);
  VAR next: INTEGER;
BEGIN invalSB; FixLinkWith(L, pc);
END FixLink;

(*
  If L0 is non-zero, it must refer to a list of fixups.  Then,
  concatenate a list of fixups L1 onto list of fixups L0.
  Since L0 is the head of the list, it returns L0.

  Otherwise, if L0 is zero, we assume that L1 represents the
  fixup list; in this case, we return L1.
  
  In either case, answers the head of the (potentially) longer list.
*)

PROCEDURE merged(L0, L1: INTEGER): INTEGER;
  VAR L2, L3: INTEGER;
BEGIN 
  IF L0 # 0 THEN
    L3 := L0;   (* Find the end of L0 and place in L2 *)
    REPEAT L2 := L3; L3 := ASR(program.code.c[L2], 16) MOD 10000H UNTIL L3 = 0;
    program.code.c[L2] := program.code.c[L2] + LSL(L1 MOD 10000H, 16); L1 := L0
  END ;
  RETURN L1
END merged;

(*
  Loading of operands and addresses into registers.

  Loading the SB register absolutely requires fixing up at load-time;
  it cannot be done at compile time, because there is no way to predict
  module table offsets corresponding to specific modules.  (Boy, wouldn't
  THAT be nice?!)

  The SB register will always be loaded with an instruction of the form:

      LD    SB, offset(MT)

  for some computed offset.  It would be *really* nice if we could encode
  this instruction in the code space.  However, we cannot accomodate all
  the necessary fields in 12-bits of immediate opcode space to handle the
  local module ID and the linkage to the next such instruction.  Therefore,
  we rely yet again on a place-holder data word of the following form:

      5H + LSL(moduleID MOD 128, 4) + LSL(link MOD 10000H, 16)

  The low nybble will technically be ignored by the loader, since by virtue
  of the slot being in a list of fixups, we already know that it's a SB
  load instruction.  Rather, the 5H is handy to cause the RV64 disassembler
  to answer with a "DWORD" directive instead of trying to figure out the
  corresponding actual RISC-V instruction it would happen to decode to.
  This helps mainly when debugging and looking at output from RVOTool.DecObj.

  Following up on the above note, we also need to calculate the offset from SB
  to get the correct address to the exported variable/procedure.  This is _only_
  required if it is an exported variable, rather than the same module's global
  variable, as we can already retrieve that at compile-time. These addresses
  are stored as a series of offsets from the entry of a module. In other words,
  regrettably, the compiler also cannot know the value of the offset, and thus
  this also needs fixups. There are three different "scenarios" to my knowledge
  that require reloading SB that need consideration:
    - loading another module's exported var/proc
    - storing a value to another module's exported var/proc
    - loading the address of another module's exported var/proc
  These are LOAD, STORE, and ADDI instructions respectively. Only their immediates
  need fixing up after the fact, and since we're only dealing with I-type and S-type
  formatting, it isn't *too* hairy to do it directly in codespace rather than using a
  placeholder word. Thus it becomes the linker's job to fix this too.
*)

PROCEDURE MakeLoadSB(base: INTEGER): INTEGER;
BEGIN
  (*
    Test explicitly for fixorgD < 10000H due to hardwired 16-bit shift.
    If someone expands maxCode to a value large enough and forgets to alter
    this fixup format, hopefully this assert will trigger before hard to
    diagnose bugs will occur.
  *)
  ASSERT((0 <= fixorgD) & (fixorgD < maxCode) & (fixorgD < 10000H));
  ASSERT((-128 <= base) & (base <= 0));  (* Allows up to 128 imported modules *)
  RETURN 5 + LSL(-base, 4) + LSL(fixorgD MOD 10000H, 16)
END MakeLoadSB;

PROCEDURE GetSB(base: INTEGER);
BEGIN
  IF (version # 0) & ((base # curSB) OR (base # 0)) THEN
    put(MakeLoadSB(base));  fixorgD := pc-1;  curSB := base
  END
END GetSB;

PROCEDURE NilCheck;
BEGIN IF check THEN Trap(EQ, 4, RH, 0); END
END NilCheck;

PROCEDURE LuiForXorIn(dest, n: INTEGER);
BEGIN
  IF ~SYSTEM.BIT(SYSTEM.ADR(n), 11) THEN   (* Account for sign-extension of next insn *)
    put(RVAssem.lui(dest, n));
  ELSE
    put(RVAssem.lui(dest, SYSTEM.VAL(INTEGER, SYSTEM.VAL(SET, n) / {12..31})));
  END;
END LuiForXorIn;

PROCEDURE LuiForXor(n: INTEGER);
BEGIN LuiForXorIn(RH, n)
END LuiForXor;

PROCEDURE LuiForAddIn(dest, n: INTEGER);  (* assuming ADDI, Lx, Sx follows *)
BEGIN
  IF ~SYSTEM.BIT(SYSTEM.ADR(n), 11) THEN   (* Account for sign-extension of next insn *)
    put(RVAssem.lui(dest, n));
  ELSE
    put(RVAssem.lui(dest, n + 1000H))
  END;
END LuiForAddIn;

PROCEDURE LuiForAdd(n: INTEGER);
BEGIN LuiForAddIn(RH, n)
END LuiForAdd;

PROCEDURE Load32BitImmIn(dest, n: INTEGER);
BEGIN
  ASSERT(FitsIn32Bits(n));
  LuiForXorIn(dest, n);
  IF n MOD 1000H # 0 THEN put(RVAssem.xori(dest, dest, n)) END
END Load32BitImmIn;

PROCEDURE Load32BitImm(n: INTEGER);
BEGIN Load32BitImmIn(RH, n)
END Load32BitImm;

PROCEDURE Load64BitImmIn(dest, n: INTEGER);
BEGIN
  (*
    To load a 64-bit immediate value into a register, we cannot use ADDI or
    the LUI/XORI approach.  We must store the 64-bit constant in memory
    following the current procedure, and refer to it via a PC-relative memory
    fetch.

    Since we haven't a clue what our PC-relative offset will actually be yet,
    we maintain a linked list of fixups just for this purpose, with the head
    referred to by fixupL64.  This variable points to the AUIPC instruction
    of the following sequence:

        AUIPC   RH, 0
        LD      RH, 0(RH)

    The AUIPC gives us 20 bits of linkage space to play with.  The LD
    instruction gives us 12 bits of offset space to play with.  A link of 0
    terminates the list.

    We know that each 64-bit entity will be 8 bytes in size, so 12 bits minus
    3 bits = 9 bits.  Thus, each procedure is allowed up to 512 large
    immediates.  If you need more, refactor your code, or LSL to synthesize
    the desired constant.

  put(RVAssem.auipc(dest, LSL(fixupL64, 12)));  fixupL64 := pc - 1;
  put(RVAssem.ld(dest, dest, lotx));
  lot[lotx] := n; incLotx;
  *)

  (*
    64-bit integers are not easily encoded in a 32-bit compiler, so we're going
    to fake it with a call to Load32BitImm for now.  This should allow boot-
    strapping the 64-bit compiler.
  *)
  RVOS.Mark("Attempted load of 64-bit integer in 32-bit compiler.");
  Load32BitImm(n)
END Load64BitImmIn;

PROCEDURE Load64BitImm(n: INTEGER);
BEGIN Load64BitImmIn(RH, n)
END Load64BitImm;

PROCEDURE LoadImmTo(dest, n: INTEGER);
BEGIN
  IF FitsIn12Bits(n) THEN put(RVAssem.addi(dest, 0, n))
  ELSIF FitsIn32Bits(n) THEN Load32BitImmIn(dest, n)
  ELSE Load64BitImmIn(dest, n)
  END
END LoadImmTo;

PROCEDURE LoadImm(n: INTEGER);
BEGIN  LoadImmTo(RH, n)
END LoadImm;

PROCEDURE Fetch32BitDisplacement(base, n: INTEGER);
BEGIN
  LuiForAdd(n);
  put(RVAssem.add(RH, RH, base));
  put(RVAssem.lw(RH, RH, n MOD 1000H));
END Fetch32BitDisplacement;

PROCEDURE Fetch64BitDisplacement(base, n: INTEGER);
BEGIN
  RVOS.Mark("Attempted fetch of 64-bit displacement in RV32 compiler. FIXME");
  LoadImm(n);
  put(RVAssem.add(RH, RH, base));
  put(RVAssem.ld(RH, RH, 0));
END Fetch64BitDisplacement;

PROCEDURE Fetch(base, n: INTEGER);
BEGIN
  IF FitsIn12Bits(n) THEN put(RVAssem.lw(RH, base, n))
  ELSIF FitsIn32Bits(n) THEN Fetch32BitDisplacement(base, n)
  ELSE Fetch64BitDisplacement(base, n)
  END
END Fetch;

PROCEDURE AddImmTo(dest, base, n: INTEGER);
BEGIN
  IF FitsIn12Bits(n) THEN
    put(RVAssem.addi(dest, base, n));
  ELSE
    LoadImmTo(dest, n);
    put(RVAssem.add(dest, dest, base))
  END
END AddImmTo;

PROCEDURE AddImm(base, n: INTEGER);
BEGIN AddImmTo(RH, base, n)
END AddImm;

PROCEDURE load(VAR x: Item);
  VAR op: INTEGER;
BEGIN
  (* op = 3 if 64-bit *)
  IF x.type.size = 1 THEN op := 4 ELSE op := 2 END;
  IF x.mode # Reg THEN
    IF x.mode = RVOB.Const THEN
      IF x.type.form = RVOB.Proc THEN
        IF x.r > 0 THEN RVOS.Mark("not allowed")
        ELSIF x.r = 0 THEN  (* Answer address of procedure in current module *)
          put(RVAssem.auipc(RH, 0));
          LoadImmTo(RH+1, (pc-1)*InsnSize - x.a);
          put(RVAssem.sub(RH, RH, RH+1));
        ELSE  (* Answer address of procedure in a different module *)
          GetSB(x.r); AddImm(SB, x.a+100H);
        END
      ELSE LoadImm(x.a)
      END;
      x.r := RH; incR
    ELSIF x.mode = RVOB.Var THEN
      IF x.r > 0 THEN (*local*)
        IF FitsIn12Bits(x.a+frame) THEN
          put(RVAssem.fmtI(03H, op, RH, SP, x.a + frame));
        ELSE
          LoadImm(x.a + frame); put(RVAssem.add(RH, RH, SP));
          put(RVAssem.fmtI(03H, op, RH, RH, 0));
        END
      ELSE (* relative to another module, or global variable *)
        GetSB(x.r);
        (* x.a must be less than 256 *)

        IF FitsIn12Bits(x.a) THEN
          put(RVAssem.fmtI(03H, op, RH, SB, x.a))
        ELSE
          LoadImm(x.a); put(RVAssem.add(RH, RH, SB));
          put(RVAssem.fmtI(03H, op, RH, RH, 0))
        END
      END ;
      x.r := RH; incR
    ELSIF x.mode = RVOB.Par THEN
      ASSERT(FitsIn12Bits(x.a + frame));
      ASSERT(FitsIn12Bits(x.b));
      put(RVAssem.lw(RH, SP, x.a + frame));
      put(RVAssem.fmtI(03H, op, RH, RH, x.b));
      x.r := RH; incR;
    ELSIF x.mode = RegI THEN
      IF FitsIn12Bits(x.a) THEN
        put(RVAssem.fmtI(03H, op, x.r, x.r, x.a));
      ELSE
        AddImm(x.r, x.a);
        put(RVAssem.fmtI(03H, op, RH, x.r, 0));
      END
    ELSIF x.mode = Cond THEN
      put(RVAssem.fmtSB(63H, opposite(x.r), x.cl, x.cr, 12));
      FixLink(x.b);
      put(RVAssem.addi(RH, 0, 1));
      put(RVAssem.jal(0, 8));
      FixLink(x.a);
      put(RVAssem.addi(RH, 0, 0));
      x.r := RH; incR
    END ;
    x.mode := Reg
  END
END load;

PROCEDURE loadAdr(VAR x: Item);
BEGIN
  IF x.mode = RVOB.Var THEN
    IF x.r > 0 THEN (*local*)
      AddImm(SP, x.a + frame)
    ELSE
      GetSB(x.r); AddImm(SB, x.a);
    END ;
    x.r := RH; incR
  ELSIF x.mode = RVOB.Par THEN
    IF FitsIn12Bits(x.a + frame) THEN
      put(RVAssem.lw(RH, SP, x.a + frame));
      IF x.b # 0 THEN
        IF FitsIn12Bits(x.b) THEN
          put(RVAssem.addi(RH, RH, x.b))
        ELSE
          incR; LoadImm(x.b); decR;
          put(RVAssem.add(RH, RH, RH+1))
        END
      END
    ELSE
      AddImm(SP, x.a + frame);
      IF FitsIn12Bits(x.b) THEN
        put(RVAssem.addi(RH, RH, x.b))
      ELSE
        incR; Load32BitImm(x.b); decR;
        put(RVAssem.add(RH, RH, RH+1))
      END
    END;
    x.r := RH; incR
  ELSIF x.mode = RegI THEN
    IF x.a # 0 THEN
      IF FitsIn12Bits(x.a) THEN
        put(RVAssem.addi(x.r, x.r, x.a))
      ELSE
        incR; Load32BitImm(x.a); decR;
        put(RVAssem.add(x.r, x.r, RH+1))
      END
    END
  ELSE RVOS.Mark("address error")
  END ;
  x.mode := Reg
END loadAdr;

PROCEDURE loadCond(VAR x: Item);
BEGIN
  IF x.type.form = RVOB.Bool THEN
    IF x.mode = RVOB.Const THEN
      IF x.a # 0 THEN x.r := ALW ELSE x.r := NEV END;
      x.cr := 0; x.cl := 0;
    ELSE
      load(x);
      x.r := NE; x.cl := RH-1; x.cr := 0; DEC(RH)
    END ;
    x.mode := Cond; x.a := 0; x.b := 0
  ELSE RVOS.Mark("not Boolean?")
  END
END loadCond;

PROCEDURE loadTypTagAdr(T: RVOB.Type);
  VAR x: Item;
BEGIN x.mode := RVOB.Var; x.a := T.len; x.r := -T.mno; loadAdr(x)
END loadTypTagAdr;

PROCEDURE loadStringAdr(VAR x: Item);
VAR offset: INTEGER;
BEGIN
  offset := varsize + x.a;
  GetSB(0); AddImm(SB, offset);
  x.mode := Reg; x.r := RH; incR
END loadStringAdr;

(* Items: Conversion from constants or from Objects on the Heap to Items on the Stack*)

PROCEDURE MakeConstItem*(VAR x: Item; typ: RVOB.Type; val: INTEGER);
BEGIN
  x.mode := RVOB.Const; x.type := typ; x.a := val;
  IF x.type = RVOB.boolType THEN x.cl := firstReg END
END MakeConstItem;

PROCEDURE MakeRealItem*(VAR x: Item; val: REAL);
BEGIN
  x.mode := RVOB.Const; x.type := RVOB.realType; x.a := SYSTEM.VAL(INTEGER, val)
END MakeRealItem;

PROCEDURE MakeStringItem*(VAR x: Item; len: INTEGER); (*copies string from RVOS-buffer to RVOG-string array*)
VAR i: INTEGER;
BEGIN
  x.mode := RVOB.Const; x.type := RVOB.strType; x.a := strx; x.b := len; i := 0;
  IF strx + len + IntegerSize < maxStrx THEN
    WHILE len > 0 DO program.strings.s[strx] := RVOS.str[i]; INC(strx); INC(i); DEC(len) END;
    WHILE strx MOD IntegerSize # 0 DO program.strings.s[strx] := 0X; INC(strx) END
  ELSE RVOS.Mark("too many strings")
  END
END MakeStringItem;

PROCEDURE MakeItem*(VAR x: Item; y: RVOB.Object; curlev: INTEGER);
BEGIN
  x.mode := y.class; x.type := y.type; x.a := y.val; x.rdo := y.rdo;
  IF y.class = RVOB.Par THEN x.b := 0
  ELSIF y.class = RVOB.Typ THEN x.a := y.type.len; x.r := -y.lev
  ELSIF (y.class = RVOB.Const) & (y.type.form = RVOB.String) THEN x.b := y.lev  (*len*)
  ELSE x.r := y.lev
  END;
  IF (y.lev > 0) & (y.lev # curlev) & (y.class # RVOB.Const) THEN
    RVOS.Mark("level error, not accessible")
  END
END MakeItem;

(* Code generation for Selectors, Variables, Constants *)

PROCEDURE Field*(VAR x: Item; y: RVOB.Object);   (* x := x.y *)
BEGIN;
  IF x.mode = RVOB.Var THEN
    IF x.r >= 0 THEN x.a := x.a + y.val
    ELSE loadAdr(x); x.mode := RegI; x.a := y.val
    END
  ELSIF x.mode = RegI THEN x.a := x.a + y.val
  ELSIF x.mode = RVOB.Par THEN x.b := x.b + y.val
  END
END Field;

PROCEDURE log2(m: INTEGER; VAR e: INTEGER): INTEGER;
BEGIN e := 0;
  WHILE ~ODD(m) DO m := m DIV 2; INC(e) END ;
  RETURN m
END log2;

PROCEDURE Index*(VAR x, y: Item);   (* x := x[y] *)
  VAR e, s1, s, lim: INTEGER;
BEGIN
  s := x.type.base.size;    (* Type size, in bytes *)
  lim := x.type.len;        (* Limit of the array dimension, in elements *)

  IF (y.mode = RVOB.Const) & (lim >= 0) THEN
    IF (y.a < 0) OR (y.a >= lim) THEN RVOS.Mark("bad index") END ;
    IF x.mode IN {RVOB.Var, RegI} THEN x.a := y.a * s + x.a
    ELSIF x.mode = RVOB.Par THEN x.b := y.a * s + x.b
    END
  ELSE
    load(y);
    IF check THEN  (*check array bounds*)
      IF lim >= 0 THEN (* closed array *)
        LoadImm(lim)
      ELSE (* open array *)
        IF x.mode IN {RVOB.Var, RVOB.Par} THEN
          Fetch(SP, x.a + frame + IntegerSize)
        ELSE RVOS.Mark("error in Index")
        END
      END ;
      Trap(GE, TrapIndexBounds, y.r, RH);
    END;
    (* y < lim *)
    s1 := log2(s, e);
    IF s1 = 1 THEN
      IF e > 0 THEN put(RVAssem.slli(y.r, y.r, e)) END;
    ELSIF s > 1 THEN
      LoadImm(s);
      put(RVAssem.mul(y.r, y.r, RH))
    END;

    IF x.mode = RVOB.Var THEN
      IF x.r > 0 THEN
        put(RVAssem.add(y.r, SP, y.r));
        INC(x.a, frame)
      ELSE
        GetSB(x.r);
        (*
        Texts.WriteLn(W); Texts.WriteString(W, "pos");
        Texts.WriteInt(W, RVOS.Pos(), 1); Texts.Append(Oberon.Log, W.buf);
        Texts.WriteLn(W); Texts.WriteString(W, "sb x.r"); Texts.WriteInt(W, x.r, 1); Texts.Append(Oberon.Log, W.buf); *)
        AddImm(SB, x.a);  put(RVAssem.add(y.r, RH, y.r));
        x.a := 0
          (*
        IF x.r = 0 THEN put(RVAssem.add(y.r, SB, y.r));
          Texts.WriteLn(W); Texts.WriteString(W, "x.a loading index: "); Texts.WriteHex(W, x.a); Texts.Append(Oberon.Log, W.buf);
        ELSE
          AddImm(SB, x.a);  put(RVAssem.add(y.r, RH, y.r));
          x.a := 0
        END *)
      END ;
      x.r := y.r; x.mode := RegI
    ELSIF x.mode = RVOB.Par THEN
      Fetch(SP, x.a + frame);
      put(RVAssem.add(y.r, y.r, RH));
      x.mode := RegI;  x.r := y.r;  x.a := x.b
    ELSIF x.mode = RegI THEN
      put(RVAssem.add(x.r, x.r, y.r)); decR
    END
  END;
END Index;

PROCEDURE DeRef*(VAR x: Item);
BEGIN
  (*Texts.WriteLn(W); Texts.WriteString(W, "Deref"); Texts.Append(Oberon.Log, W.buf);*)
  IF x.mode = RVOB.Var THEN
    IF x.r > 0 THEN (*local*)
      Fetch(SP, x.a + frame)
    ELSE
      GetSB(x.r);  Fetch(SB, x.a)
    END;
    NilCheck;
    x.r := RH; incR;
  ELSIF x.mode = RVOB.Par THEN
    IF FitsIn12Bits(x.b) THEN
      Fetch(SP, x.a + frame);  put(RVAssem.lw(RH, RH, x.b));
    ELSE
      Fetch(SP, x.a + frame);
      incR; LoadImm(x.b); decR; put(RVAssem.add(RH, RH, RH+1));
      put(RVAssem.lw(RH, RH, 0))
    END;
    NilCheck;
    x.r := RH;  incR;
  ELSIF x.mode = RegI THEN
    IF FitsIn12Bits(x.a) THEN
      put(RVAssem.lw(x.r, x.r, x.a))
    ELSIF FitsIn32Bits(x.a) THEN
      LuiForAdd(x.a);
      put(RVAssem.lw(x.r, x.r, x.a))
    ELSE (* Fits in 64 bits *)
      RVOS.Mark("64-bit DeRef. FIXME");
      LoadImm(x.a);
      put(RVAssem.add(x.r, x.r, RH));
      put(RVAssem.ld(x.r, x.r, 0))
    END;
    IF check THEN Trap(EQ, 4, x.r, 0); END
  ELSIF x.mode # Reg THEN RVOS.Mark("bad mode in DeRef")
  END ;
  x.mode := RegI; x.a := 0; x.b := 0
END DeRef;

PROCEDURE Q(T: RVOB.Type; VAR dcw: INTEGER);
BEGIN (*one entry of type descriptor extension table*)
  IF T.base # NIL THEN
    Q(T.base, dcw); program.data.t[dcw] := (T.mno*1000H + T.len) * 1000H + dcw - fixorgT;
    fixorgT := dcw; INC(dcw)
  END
END Q;

PROCEDURE FindPtrFlds(typ: RVOB.Type; off: INTEGER; VAR dcw: INTEGER);
  VAR fld: RVOB.Object; i, s: INTEGER;
BEGIN
  IF (typ.form = RVOB.Pointer) OR (typ.form = RVOB.NilTyp) THEN program.data.t[dcw] := off; INC(dcw)
  ELSIF typ.form = RVOB.Record THEN
    fld := typ.dsc;
    WHILE fld # NIL DO FindPtrFlds(fld.type, fld.val + off, dcw); fld := fld.next END
  ELSIF typ.form = RVOB.Array THEN
    s := typ.base.size;
    FOR i := 0 TO typ.len-1 DO FindPtrFlds(typ.base, i*s + off, dcw) END
  END
END FindPtrFlds;

PROCEDURE BuildTD*(T: RVOB.Type; VAR dc: INTEGER);
  VAR dcw, k, s: INTEGER;  (*dcw = word address*)
BEGIN
  dcw := dc DIV IntegerSize;

  (* Convert size for heap allocation; KERNEL DEPENDENT. *)
  s := T.size;
  IF s <= 24 THEN s := 32
  ELSIF s <= 56 THEN s := 64
  ELSIF s <= 120 THEN s := 128
  ELSE s := (s+263) DIV 256 * 256
  END ;

  T.len := dc;  program.data.t[dcw] := s;  INC(dcw);
  k := T.nofpar;   (*extension level!*)
  IF k > 3 THEN RVOS.Mark("ext level too large")
  ELSE Q(T, dcw);
    WHILE k < 3 DO program.data.t[dcw] := -1; INC(dcw); INC(k) END
  END ;
  FindPtrFlds(T, 0, dcw); program.data.t[dcw] := -1; INC(dcw);
  tdx := dcw;  dc := dcw * IntegerSize;
  IF tdx >= maxTD THEN RVOS.Mark("too many record types"); tdx := 0 END
END BuildTD;

PROCEDURE TypeTest*(VAR x: Item; T: RVOB.Type; varpar, isguard: BOOLEAN);
  VAR pc0: INTEGER;
BEGIN (*fetch tag into RH*)
  IF varpar THEN Fetch(SP, x.a + frame + IntegerSize)
  ELSE
    load(x);  pc0 := pc;
    put(MakeFwdBranch(EQ, x.r, 0, 0));  (*NIL belongs to every pointer type*)
    put(RVAssem.lw(RH, x.r, -8))
  END;
  Fetch(RH, T.nofpar * IntegerSize); incR;
  loadTypTagAdr(T);  (*tag of T is in RH-1 *)
  put(RVAssem.sub(RH-1, RH-1, RH-2));
  IF isguard THEN
    IF check THEN Trap(NE, TrapTypeMismatch, RH-1, 0) END
  END;

  IF ~varpar THEN fix(pc0, pc) END ;
  IF ~isguard THEN
    SetCC0(x, EQ);
    IF ~varpar THEN decR END
  END;
  decR; decR;
END TypeTest;

(* Code generation for Boolean operators *)

PROCEDURE Swap(VAR x, y: INTEGER);
VAR
  t: INTEGER;
BEGIN
  t := x;  x := y;  y := t;
END Swap;

PROCEDURE Not*(VAR x: Item);   (* x := ~x *)
  VAR t: INTEGER;
BEGIN
  IF x.mode # Cond THEN loadCond(x) END ;
  x.r := opposite(x.r);  Swap(x.a, x.b)
END Not;

PROCEDURE And1*(VAR x: Item);   (* x := x & *)
BEGIN
  IF x.mode # Cond THEN loadCond(x) END ;
  put(MakeFwdBranch(opposite(x.r), x.cl, x.cr, x.a));
  x.a := pc-1; FixLink(x.b); x.b := 0
END And1;

PROCEDURE And2*(VAR x, y: Item);
BEGIN
  IF y.mode # Cond THEN loadCond(y) END ;
  x.a := merged(y.a, x.a); x.b := y.b; x.r := y.r;
  x.cl := y.cl; x.cr := y.cr
END And2;

PROCEDURE Or1*(VAR x: Item);   (* x := x OR *)
BEGIN
  IF x.mode # Cond THEN loadCond(x) END ;
  put(MakeFwdBranch(x.r, x.cl, x.cr, x.b));
  x.b := pc-1; FixLink(x.a); x.a := 0
END Or1;

PROCEDURE Or2*(VAR x, y: Item);
BEGIN
  IF y.mode # Cond THEN loadCond(y) END ;
  x.a := y.a; x.b := merged(y.b, x.b); x.r := y.r;
  x.cl := y.cl; x.cr := y.cr
END Or2;

(* Code generation for arithmetic operators *)

PROCEDURE Neg*(VAR x: Item);   (* x := -x *)
BEGIN
  IF x.type.form = RVOB.Int THEN
    IF x.mode = RVOB.Const THEN x.a := -x.a
    ELSE load(x); put(RVAssem.sub(x.r, 0, x.r))
    END
  ELSIF x.type.form = RVOB.Real THEN
  (*
    IF x.mode = RVOB.Const THEN x.a := x.a + 7FFFFFFFH + 1
    ELSE load(x); Put1(Mov, RH, 0, 0); Put0(Fsb, x.r, RH, x.r)
    END
  *) RVOS.Mark("Not supported yet");
  ELSE (*form = Set*)
    IF x.mode = RVOB.Const THEN x.a := -x.a-1
    ELSE load(x); put(RVAssem.xori(x.r, x.r, -1))
    END
  END
END Neg;

PROCEDURE AddOp*(op: INTEGER; VAR x, y: Item);   (* x := x +- y *)
BEGIN
  IF op = RVOS.plus THEN
    IF (x.mode = RVOB.Const) & (y.mode = RVOB.Const) THEN x.a := x.a + y.a
    ELSIF y.mode = RVOB.Const THEN
      load(x);
      IF y.a # 0 THEN
        IF FitsIn12Bits(y.a) THEN put(RVAssem.addi(x.r, x.r, y.a))
        ELSE LoadImm(y.a); put(RVAssem.add(x.r, x.r, RH))
        END
      END
    ELSE
      load(x); load(y);
      put(RVAssem.add(RH-2, x.r, y.r));
      decR;  x.r := RH-1
    END
  ELSE (*op = RVOS.minus*)
    IF (x.mode = RVOB.Const) & (y.mode = RVOB.Const) THEN x.a := x.a - y.a
    ELSIF y.mode = RVOB.Const THEN
      load(x);
      IF y.a # 0 THEN
        IF FitsIn12Bits(y.a) THEN put(RVAssem.addi(x.r, x.r, -y.a))
        ELSE LoadImm(y.a); put(RVAssem.sub(x.r, x.r, RH))
        END
      END
    ELSE
      load(x);  load(y);
      put(RVAssem.sub(RH-2, x.r, y.r)); decR;
      x.r := RH-1
    END
  END
END AddOp;

PROCEDURE MulOp*(VAR x, y: Item);   (* x := x * y *)
  VAR e: INTEGER;
BEGIN
  IF (x.mode = RVOB.Const) & (y.mode = RVOB.Const) THEN x.a := x.a * y.a
  ELSIF (y.mode = RVOB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN
    load(x); put(RVAssem.slli(x.r, x.r, e))
  ELSIF y.mode = RVOB.Const THEN
    load(x); LoadImm(y.a);
    put(RVAssem.mul(x.r, x.r, RH))
  ELSIF (x.mode = RVOB.Const) & (x.a >= 2) & (log2(x.a, e) = 1) THEN
    load(y); put(RVAssem.slli(y.r, y.r, e));
    x.mode := Reg; x.r := y.r
  ELSIF x.mode = RVOB.Const THEN
    load(y); LoadImm(x.a);
    put(RVAssem.mul(y.r, y.r, RH));
    x.mode := Reg; x.r := y.r
  ELSE
    load(x); load(y);
    put(RVAssem.mul(RH-2, x.r, y.r)); decR;
    x.r := RH-1
  END
END MulOp;

PROCEDURE DivOp*(op: INTEGER; VAR x, y: Item);   (* x := x op y *)
  VAR e: INTEGER;
BEGIN
  IF op = RVOS.div THEN
    IF (x.mode = RVOB.Const) & (y.mode = RVOB.Const) THEN
      IF y.a > 0 THEN x.a := x.a DIV y.a ELSE RVOS.Mark("bad divisor") END
    ELSIF (y.mode = RVOB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN
      load(x); put(RVAssem.srai(x.r, x.r, e));
    ELSIF y.mode = RVOB.Const THEN
      IF y.a > 0 THEN
        load(x); LoadImm(y.a); put(RVAssem.div(x.r, x.r, RH))
      ELSE RVOS.Mark("bad divisor")
      END
    ELSE
      load(y);
      IF check THEN Trap(EQ, TrapDivByZero, y.r, 0) END ;
      load(x);  put(RVAssem.div(RH-2, x.r, y.r)); decR;
      x.r := RH-1
    END
  ELSE (*op = RVOS.mod*)
    IF (x.mode = RVOB.Const) & (y.mode = RVOB.Const) THEN
      IF y.a > 0 THEN x.a := x.a MOD y.a ELSE RVOS.Mark("bad modulus") END
    ELSIF (y.mode = RVOB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN
      load(x);
      IF e <= 11 THEN put(RVAssem.andi(x.r, x.r, y.a-1))
      ELSE
        put(RVAssem.slli(x.r, x.r, BitsPerInteger-e));
        put(RVAssem.srli(x.r, x.r, BitsPerInteger-e));
      END
    ELSIF y.mode = RVOB.Const THEN
      IF y.a > 0 THEN
        load(x); LoadImm(y.a);
        put(RVAssem.rem(x.r, x.r, RH))
      ELSE
        RVOS.Mark("bad modulus")
      END
    ELSE
      load(y);
      IF check THEN Trap(EQ, TrapDivByZero, y.r, 0) END ;
      load(x);
      put(RVAssem.rem(RH-2, x.r, y.r)); decR;
      x.r := RH-1
    END
  END
END DivOp;

(* Code generation for REAL operators *)

PROCEDURE RealOp*(op: INTEGER; VAR x, y: Item);   (* x := x op y *)
BEGIN 
(*
  load(x); load(y);
  IF op = RVOS.plus THEN Put0(Fad, RH-2, x.r, y.r)
  ELSIF op = RVOS.minus THEN Put0(Fsb, RH-2, x.r, y.r)
  ELSIF op = RVOS.times THEN Put0(Fml, RH-2, x.r, y.r)
  ELSIF op = RVOS.rdiv THEN Put0(Fdv, RH-2, x.r, y.r)
  END ;
  DEC(RH); x.r := RH-1
*)  RVOS.Mark("REALs not implemented")
END RealOp;

(* Code generation for set operators *)

PROCEDURE Singleton*(VAR x: Item);  (* x := {x} *)
BEGIN
  IF x.mode = RVOB.Const THEN x.a := LSL(1, x.a)
  ELSE
    load(x);
    put(RVAssem.addi(RH, 0, 1));  put(RVAssem.sll(x.r, RH, x.r))
  END
END Singleton;

PROCEDURE Set*(VAR x, y: Item);   (* x := {x .. y} *)
BEGIN
  IF (x.mode = RVOB.Const) & (y.mode = RVOB.Const) THEN
    IF x.a <= y.a THEN
      x.a := LSL(2, y.a) - LSL(1, x.a)
    ELSE
      RVOS.Mark("Set range x..y, check that x <= y");
      x.a := 0
    END
  ELSE
    IF (x.mode = RVOB.Const) & (x.a < 12) THEN
      x.a := LSL(-1, x.a)
    ELSE
      load(x);
      put(RVAssem.ori(RH, 0, -1)); put(RVAssem.sll(x.r, RH, x.r))
    END ;
    IF (y.mode = RVOB.Const) & (y.a < 12) THEN
      put(RVAssem.ori(RH, 0, LSL(-2, y.a)));
      y.mode := Reg;  y.r := RH;  incR
    ELSE
      load(y);
      put(RVAssem.ori(RH, 0, -2)); put(RVAssem.sll(y.r, RH, y.r))
    END ;
    IF x.mode = RVOB.Const THEN
      IF x.a # 0 THEN
        put(RVAssem.xori(y.r, y.r, -1)); put(RVAssem.andi(RH-1, y.r, x.a))
      END;
      x.mode := Reg; x.r := RH-1
    ELSE
      decR;
      put(RVAssem.xori(y.r, y.r, -1)); put(RVAssem.and(RH-1, y.r, x.r))
    END
  END
END Set;

PROCEDURE In*(VAR x, y: Item);  (* x := x IN y *)
BEGIN
  load(y);
  IF x.mode = RVOB.Const THEN
    put(RVAssem.slli(y.r, y.r, (BitsPerInteger-1)-x.a));
  ELSE
    load(x);
    put(RVAssem.addi(RH, 0, BitsPerInteger-1));
    put(RVAssem.sub(x.r, RH, x.r));
    put(RVAssem.sll(y.r, y.r, x.r));
    decR;
  END ;
  SetCC0(x, LT); x.cl := y.r; decR;
END In;

PROCEDURE SetOp*(op: INTEGER; VAR x, y: Item);   (* x := x op y *)
  VAR xset, yset: SET; (*x.type.form = Set*)
BEGIN
  IF (x.mode = RVOB.Const) & (y.mode = RVOB.Const) THEN
    xset := SYSTEM.VAL(SET, x.a); yset := SYSTEM.VAL(SET, y.a);
    IF op = RVOS.plus THEN xset := xset + yset
    ELSIF op = RVOS.minus THEN xset := xset - yset
    ELSIF op = RVOS.times THEN xset := xset * yset
    ELSIF op = RVOS.rdiv THEN xset := xset / yset
    END ;
    x.a := SYSTEM.VAL(INTEGER, xset)
  ELSIF (y.mode = RVOB.Const) & FitsIn11Bits(y.a) THEN
    load(x);
    IF op = RVOS.plus THEN put(RVAssem.ori(x.r, x.r, y.a))
    ELSIF op = RVOS.minus THEN put(RVAssem.andi(x.r, x.r, -y.a-1))
    ELSIF op = RVOS.times THEN put(RVAssem.andi(x.r, x.r, y.a))
    ELSIF op = RVOS.rdiv THEN put(RVAssem.xori(x.r, x.r, y.a))
    END ;
  ELSE load(x); load(y);
    IF op = RVOS.plus THEN put(RVAssem.or(RH-2, x.r, y.r))
    ELSIF op = RVOS.minus THEN
      put(RVAssem.xori(y.r, y.r, -1)); put(RVAssem.and(RH-2, x.r, y.r))
    ELSIF op = RVOS.times THEN put(RVAssem.and(RH-2, x.r, y.r))
    ELSIF op = RVOS.rdiv THEN put(RVAssem.xor(RH-2, x.r, y.r))
    END ;
    decR;  x.r := RH-1
  END 
END SetOp;

(* Code generation for relations *)

PROCEDURE relFromSym(s: INTEGER): INTEGER;
BEGIN RETURN sym2rel[s-RVOS.eql]
END relFromSym;

PROCEDURE uRelFromSym(s: INTEGER): INTEGER;
BEGIN RETURN sym2uRel[s-RVOS.eql]
END uRelFromSym;

PROCEDURE IntRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
BEGIN
  load(x);  load(y);      (* Thanks to pdewacht for his help with this! *)
  x.mode := Cond;  x.a := 0;  x.b := 0;
  IF op IN {RVOS.eql, RVOS.neq, RVOS.lss, RVOS.geq} THEN
    x.cl := x.r;  x.cr := y.r;
    x.r := relFromSym(op)
  ELSIF op = RVOS.leq THEN
    x.cl := y.r;  x.cr := x.r;  x.r := GE
  ELSE
    ASSERT(op = RVOS.gtr);
    x.cl := y.r;  x.cr := x.r;  x.r := LT
  END;
  decR; decR
END IntRelation;

PROCEDURE SetRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
BEGIN
  load(x);
  IF (op = RVOS.eql) OR (op = RVOS.neq) THEN
    IF (y.mode = RVOB.Const) & FitsIn11Bits(y.a) THEN
      put(RVAssem.xori(x.r, x.r, y.a)); 
    ELSE
      load(y);
      put(RVAssem.xor(x.r, x.r, y.r));
      decR
    END;
    IF op = RVOS.eql THEN SetCC0(x, EQ) ELSE SetCC0(x, NE) END;
    decR;
  ELSE RVOS.Mark("illegal relation")
  END
END SetRelation;

PROCEDURE RealRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
BEGIN
(*
  load(x);
  IF (y.mode = RVOB.Const) & (y.a = 0) THEN DEC(RH)
  ELSE load(y); Put0(Fsb, x.r, x.r, y.r); DEC(RH, 2)
  END ;
  SetCC(x, relmap[op - RVOS.eql])
*)  RVOS.Mark("REALs not implemented")
END RealRelation;

PROCEDURE StringRelation*(op: INTEGER; VAR x, y: Item);   (* x := x < y *)
  (*x, y are char arrays or strings*)
BEGIN
  IF x.type.form = RVOB.String THEN loadStringAdr(x) ELSE loadAdr(x) END ;
  IF y.type.form = RVOB.String THEN loadStringAdr(y) ELSE loadAdr(y) END ;
  put(RVAssem.lbu(RH, x.r, 0));
  put(RVAssem.addi(x.r, x.r, 1));
  put(RVAssem.lbu(RH+1, y.r, 0));
  put(RVAssem.addi(y.r, y.r, 1));
  put(RVAssem.bne(RH, RH+1, 8));
  put(RVAssem.bne(RH, 0, -20));
  SetCC(x, uRelFromSym(op));
  x.cl := RH;  x.cr := RH+1;
  IF (op = RVOS.gtr) OR (op = RVOS.leq) THEN Swap(x.cl, x.cr) END;
  decR; decR
END StringRelation;

(* Code generation of Assignments *)

PROCEDURE StrToChar*(VAR x: Item);
BEGIN x.type := RVOB.charType; DEC(strx, 4); x.a := ORD(program.strings.s[x.a])
END StrToChar;

PROCEDURE Store*(VAR x, y: Item); (* x := y *)
VAR op: INTEGER;
BEGIN  load(y);
   (* op := 3 if 64-bit *)
  IF x.type.size = 1 THEN op := 0 ELSE op := 2 END ;
  IF x.mode = RVOB.Var THEN
    IF x.r > 0 THEN (*local*) 
      (*ASSERT(FitsIn12Bits(x.a + frame));*)
      IF FitsIn12Bits(x.a + frame) THEN
        put(RVAssem.fmtS(23H, op, SP, y.r, x.a + frame))
      ELSE
        LoadImm(x.a + frame); put(RVAssem.add(RH, RH, SP));
        put(RVAssem.fmtS(23H, op, RH, y.r, 0))
      END;
    ELSE
      GetSB(x.r);
      IF FitsIn12Bits(x.a) THEN
        put(RVAssem.fmtS(23H, op, SB, y.r, x.a))
      ELSE
        LoadImm(x.a); put(RVAssem.add(RH, RH, SB));
        put(RVAssem.fmtS(23H, op, RH, y.r, 0))
      END
    END
  ELSIF x.mode = RVOB.Par THEN
    ASSERT(FitsIn12Bits(x.a + frame));
    ASSERT(FitsIn12Bits(x.b));
    put(RVAssem.lw(RH, SP, x.a + frame));
    put(RVAssem.fmtS(23H, op, RH, y.r, x.b));
  ELSIF x.mode = RegI THEN
    IF FitsIn12Bits(x.a) THEN
      put(RVAssem.fmtS(23H, op, x.r, y.r, x.a)); decR
    ELSE
      AddImm(x.r, x.a);
      put(RVAssem.fmtS(23H, op, RH, y.r, 0)); decR
    END
  ELSE RVOS.Mark("bad mode in Store")
  END ;
  decR
END Store;

PROCEDURE StoreStruct*(VAR x, y: Item); (* x := y, frame = 0 *)
  VAR s, pc0: INTEGER;
BEGIN loadAdr(x); loadAdr(y);
  IF (x.type.form = RVOB.Array) & (x.type.len > 0) THEN
    IF y.type.len >= 0 THEN 
      IF x.type.len >= y.type.len THEN
        put(RVAssem.addi(RH, 0, (y.type.size+(IntegerSize-1)) DIV IntegerSize))
      ELSE RVOS.Mark("source array too long")
      END
    ELSE (*y is open array*)
      ASSERT(FitsIn12Bits(y.a+IntegerSize));
      put(RVAssem.lw(RH, SP, y.a + IntegerSize));
      s := y.type.base.size;  (* element size *)
      pc0 := pc; put(MakeFwdBranch(EQ, RH, 0, 0));
      IF s = 1 THEN put(RVAssem.addi(RH, RH, 3)); put(RVAssem.srai(RH, RH, 2))
      ELSIF s # 4 THEN 
        incR; LoadImm(s DIV 4); decR; put(RVAssem.mul(RH, RH, RH+1))
      END ;
      IF check THEN
        incR; LoadImm(x.type.size+(IntegerSize-1) DIV IntegerSize); decR;
        Trap(LT, TrapSourceTooBig, RH+1, RH)
      END ;
      (* Sets forward branch to jump to the store struct loading loop below *)
      fix(pc0, pc + 5)
    END
  ELSIF x.type.form = RVOB.Record THEN LoadImm(x.type.size DIV IntegerSize)
  ELSE RVOS.Mark("inadmissible assignment")
  END ;
  put(RVAssem.lw(RH+1, y.r, 0));
  put(RVAssem.addi(y.r, y.r, IntegerSize));
  put(RVAssem.sw(RH+1, x.r, 0));
  put(RVAssem.addi(x.r, x.r, IntegerSize));
  put(RVAssem.addi(RH, RH, -1));
  put(RVAssem.bne(RH, 0, -20));
  decR; decR;
END StoreStruct;

PROCEDURE CopyString*(VAR x, y: Item);  (*from x to y*)
  VAR len: INTEGER;
BEGIN loadAdr(y); len := y.type.len;
  IF len >= 0 THEN
    IF x.b > len THEN RVOS.Mark("string too long") END
  ELSIF check THEN (*array length check*)
    put(RVAssem.lw(RH, y.r, IntegerSize));
    incR; LoadImm(x.b+1); decR;
    Trap(GE, TrapSourceTooBig, RH, RH+1)
  END ;
  loadStringAdr(x);
  put(RVAssem.lw(RH, x.r, 0));  put(RVAssem.addi(x.r, x.r, IntegerSize));
  put(RVAssem.sw(RH, y.r, 0));  put(RVAssem.addi(y.r, y.r, IntegerSize));
  put(RVAssem.srli(RH, RH, BitsPerInteger-8));
  put(RVAssem.bne(RH, 0, -20));
  decR; decR;
END CopyString;

(* Code generation for parameters *)

PROCEDURE VarParam*(VAR x: Item; ftype: RVOB.Type);
  VAR xmd: INTEGER;
BEGIN
  xmd := x.mode; loadAdr(x);
  IF (ftype.form = RVOB.Array) & (ftype.len < 0) THEN (*open array*)
    IF x.type.len >= 0 THEN
      LoadImm(x.type.len)
    ELSE
      ASSERT(FitsIn12Bits(x.a + frame + IntegerSize));
      put(RVAssem.lw(RH, SP, x.a + frame + IntegerSize))
    END;
    incR
  ELSIF ftype.form = RVOB.Record THEN
    IF xmd = RVOB.Par THEN
      put(RVAssem.lw(RH, SP, x.a + frame + IntegerSize)); incR
    ELSE
      loadTypTagAdr(x.type)
    END
  END
END VarParam;

PROCEDURE ValueParam*(VAR x: Item);
BEGIN load(x)
END ValueParam;

PROCEDURE OpenArrayParam*(VAR x: Item);
BEGIN
  loadAdr(x);
  IF x.type.len >= 0 THEN
    LoadImm(x.type.len)
  ELSE
    ASSERT(FitsIn12Bits(x.a + frame + IntegerSize));
    put(RVAssem.lw(RH, SP, x.a + frame + IntegerSize))
  END;
  incR
END OpenArrayParam;

PROCEDURE StringParam*(VAR x: Item);
BEGIN loadStringAdr(x); LoadImm(x.b); incR  (*len*)
END StringParam;

(*For Statements*)

PROCEDURE For0*(VAR x, y: Item);
BEGIN load(y)
END For0;

PROCEDURE For1*(VAR x, y, z, w: Item; VAR L: INTEGER);
BEGIN 
  load(z);
  IF w.a > 0 THEN
    put(MakeFwdBranch(LT, RH-1, RH-2, 0))  (* z < x ==> x > z *)
  ELSIF w.a < 0 THEN
    put(MakeFwdBranch(LT, RH-2, RH-1, 0))
  ELSE
    RVOS.Mark("zero increment");
    put(MakeFwdBranch(LTU, RH-1, 0, 0))
  END;
  L := pc-1; decR;
  Store(x, y);
END For1;

PROCEDURE For2*(VAR x, y, w: Item);
BEGIN load(x); decR; AddImmTo(x.r, x.r, w.a)
END For2;

(* Branches, procedure calls, procedure prolog and epilog *)

PROCEDURE Here*(): INTEGER;
BEGIN invalSB; RETURN pc
END Here;

PROCEDURE FJump*(VAR L: INTEGER);
BEGIN put(MakeFwdBranch(ALW, RH, 0, L));  L := pc-1
END FJump;

PROCEDURE CFJump*(VAR x: Item);
BEGIN
  IF x.mode # Cond THEN loadCond(x) END ;
  put(MakeFwdBranch(opposite(x.r), x.cl, x.cr, x.a));
  FixLink(x.b); x.a := pc-1
END CFJump;

PROCEDURE BJump*(L: INTEGER);
BEGIN put(RVAssem.jal(0, (L-pc)*InsnSize))
END BJump;

PROCEDURE CBJump*(VAR x: Item; L: INTEGER);
VAR
  c, opcode: INTEGER;
BEGIN
  IF x.mode # Cond THEN loadCond(x) END ;
  c := opposite(x.r);
  IF (EQ <= c) & (c < GEU) THEN
    put(RVAssem.fmtSB(63H, c, x.cl, x.cr, (L-pc)*InsnSize))
  ELSIF c = ALW THEN
    put(RVAssem.jal(0, (L-pc)*InsnSize))
  END;
  FixLink(x.b); FixLinkWith(x.a, L)
END CBJump;

PROCEDURE Fixup*(VAR x: Item);
BEGIN FixLink(x.a)
END Fixup;

PROCEDURE SaveRegs(r: INTEGER);  (* R[firstReg .. r-1]*)
  VAR r0: INTEGER;
BEGIN
  ASSERT(r >= firstReg);
  r0 := firstReg;
  put(RVAssem.addi(SP, SP, (firstReg-r)*IntegerSize));
  INC(frame, (r-firstReg)*IntegerSize);
  REPEAT put(RVAssem.sw(r0, SP, (r-r0-1)*IntegerSize)); INC(r0) UNTIL r0 = r
END SaveRegs;

PROCEDURE RestoreRegs(r: INTEGER); (*R[firstReg .. r-1]*)
  VAR r0: INTEGER;
BEGIN
  ASSERT(r >= firstReg);
  r0 := r;
  REPEAT DEC(r0); put(RVAssem.lw(r0, SP, (r-r0-1)*IntegerSize))
  UNTIL r0 = firstReg;
  put(RVAssem.addi(SP, SP, (r-firstReg)*IntegerSize));
  DEC(frame, (r-firstReg)*IntegerSize)
END RestoreRegs;

PROCEDURE PrepCall*(VAR x: Item; VAR r: INTEGER);
BEGIN (*x.type.form = RVOB.Proc*)
  IF x.mode > RVOB.Par THEN load(x) END ;
  r := RH;
  IF RH > firstReg THEN SaveRegs(RH); RH := firstReg END
END PrepCall;

(*
  Place a subroutine call.

  For inter-module calls, we cannot predict the PC-relative offset, and the
  RISC-V doesn't give us enough bits to store the fixup information we need to
  reconstruct the JAL instruction operand.  So we must use a pseudo-
  instruction instead.

  Similar to loading the static base, we use the following instruction slot:

    procedureID + LSL(moduleID MOD 128, 8) + LSL(fixupLink MOD 10000H, 16)

  It is up to the module loader or linker to replace these pseudo-instructions
  with the appropriate JAL instruction.
*)
PROCEDURE Call*(VAR x: Item; r: INTEGER);
  VAR i: INTEGER;
BEGIN (*x.type.form = RVOB.Proc*)
  (* Store where we call the function from to a magic IO port - for debugging purposes *)
  IF (stacktrace) THEN
    incR;
    i := 0;
    WHILE (modid[i] # 0X) & (i < 5) DO
        LoadImm(LSL(0AAH, 24) + ORD(modid[i]) MOD C24);
        put(RVAssem.sw(RH, 0, -32));
        INC(i);
    END;
    LoadImm(LSL(0CCH, 24) + RVOS.Pos() MOD C24);
    put(RVAssem.sw(RH, 0, -32));
    decR;
  END;

  IF x.mode = RVOB.Const THEN
    IF x.r >= 0 THEN
      put(RVAssem.jal(RA, x.a - (pc*InsnSize)))
    ELSE (*imported*)
      IF (fixorgP < 10000H) & (x.a < 100H) & (-x.r < 80H) THEN
        (* -x.r = moduleID?? *)
        put(x.a MOD 100H + LSL(-x.r, 8) + LSL(fixorgP MOD 10000H, 16)); fixorgP := pc-1
      ELSE RVOS.Mark("fixup impossible")
      END
    END
  ELSE
    IF x.mode <= RVOB.Par THEN
      load(x); decR
    ELSE
      put(RVAssem.lw(RH, SP, 0)); put(RVAssem.addi(SP, SP, IntegerSize));
      DEC(r);
      DEC(frame, IntegerSize)
    END ;
    IF check THEN Trap(EQ, TrapNilProcedure, RH, 0) END ;
    put(RVAssem.jalr(RA, RH, 0))
  END ;
  (* Store that we return from that call context - debug *)
  IF (stacktrace) THEN
    put(RVAssem.sw(0, 0, -32));
  END;
  IF x.type.base.form = RVOB.NoTyp THEN (*procedure*) RH := firstReg
  ELSE (*function*)
    IF r > firstReg THEN put(RVAssem.addi(r, firstReg, 0)); RestoreRegs(r) END;
    x.mode := Reg; x.r := r; RH := r+1
  END ;
  invalSB
END Call;

PROCEDURE Enter*(parblksize, locblksize: INTEGER; int: BOOLEAN);
  VAR a, r, freereg: INTEGER;
BEGIN invalSB; frame := 0;
  IF ~int THEN (*procedure prolog*)
    a := IntegerSize; r := firstReg;
    IF locblksize >= 10000H THEN RVOS.Mark("too many locals") END ;
    IF ~FitsIn12Bits(-locblksize) THEN
       (* RH does not point at an empty register here, because they're currently used for parameters. *)
       (* So we pick the one big enough to be unaffected by parameters. *)
       (* A runtime check to see if we have too many parameters for an empty register to exist may be wise ... *)
       (* TODO. *)
      freereg := parblksize DIV 4 + firstReg + 1;
      LoadImmTo(freereg, locblksize);
      put(RVAssem.sub(SP, SP, freereg));
    ELSE put(RVAssem.addi(SP, SP, -locblksize));
    END;
    put(RVAssem.sw(RA, SP, 0));
    WHILE a < parblksize DO
      put(RVAssem.sw(r, SP, a)); INC(r); INC(a, IntegerSize)
    END
  ELSE (*interrupt procedure*)
  (*
    Put1(Sub, SP, SP, 12); Put2(Str, 0, SP, 0); Put2(Str, 1, SP, 4); Put2(Str, SB, SP, 8)
    (*R0, R1, SB saved on stack*)
  *)  RVOS.Mark("Interrupt procedures not yet supported")
  END
END Enter;

PROCEDURE Return*(form: INTEGER; VAR x: Item; size: INTEGER; int: BOOLEAN);
BEGIN
  IF form # RVOB.NoTyp THEN load(x) END ;
  IF ~int THEN (*procedure epilog*)
    put(RVAssem.lw(RA, SP, 0));
    IF ~FitsIn12Bits(size) THEN
       LoadImm(size);
       put(RVAssem.add(SP, SP, RH));
    ELSE put(RVAssem.addi(SP, SP, size));
    END;
    put(RVAssem.jalr(0, RA, 0));
  ELSE (*interrupt return, restore SB, R1, R0*)
  (*
    Put2(Ldr, SB, SP, 8); Put2(Ldr, 1, SP, 4); Put2(Ldr, 0, SP, 0); Put1(Add, SP, SP, 12); Put3(BR, 7, 10H)
  *)  RVOS.Mark("Interrupt procedures not yet supported")
  END ;
  RH := firstReg
END Return;

(* In-line code procedures*)

PROCEDURE Increment*(upordown: INTEGER; VAR x, y: Item);
  VAR sign, op, zr, v: INTEGER;
BEGIN (*frame = 0*)
  (* v := 3 if 64-bit *)
  IF x.type = RVOB.byteType THEN v := 0 ELSE v := 2 END ;
  IF y.type.form = RVOB.NoTyp THEN y.mode := RVOB.Const; y.a := 1 END ;
  IF upordown = 0 THEN sign := 1 ELSE sign := -1 END;

  IF (x.mode = RVOB.Var) & (x.r > 0) THEN
    zr := RH; put(RVAssem.fmtI(03H, v, zr, SP, x.a)); incR;
    IF (y.mode = RVOB.Const) & FitsIn12Bits(y.a) THEN
      put(RVAssem.addi(zr, zr, y.a * sign))
    ELSE
      load(y);
      IF upordown = 0 THEN put(RVAssem.add(zr, zr, y.r))
      ELSE put(RVAssem.sub(zr, zr, y.r))
      END;
      decR
    END;
    put(RVAssem.fmtS(23H, v, SP, zr, x.a)); decR
  ELSE
    loadAdr(x); zr := RH; put(RVAssem.fmtI(03H, v, RH, x.r, 0)); incR;
    IF (y.mode = RVOB.Const) & FitsIn12Bits(y.a) THEN
      put(RVAssem.addi(zr, zr, y.a * sign))
    ELSE
      load(y);
      IF upordown = 0 THEN put(RVAssem.add(zr, zr, y.r))
      ELSE put(RVAssem.sub(zr, zr, y.r))
      END;
      decR
    END;
    put(RVAssem.fmtS(23H, v, x.r, zr, 0));
    decR; decR
  END
END Increment;

(* inorex = Include or Exclude... 0 = include, 1 = exclude. *)
PROCEDURE Include*(inorex: INTEGER; VAR x, y: Item);
  VAR zr: INTEGER;
BEGIN
  loadAdr(x); zr := RH; put(RVAssem.lw(RH, x.r, 0)); incR;
  IF y.mode = RVOB.Const THEN
    IF inorex = 0 THEN
      ASSERT(FitsIn12Bits(LSL(1, y.a)));
      put(RVAssem.ori(zr, zr, LSL(1, y.a)))
    ELSE
      ASSERT(FitsIn12Bits(-LSL(1, y.a)-1));
      put(RVAssem.andi(zr, zr, (-LSL(1, y.a))-1))
    END
  ELSE
    load(y);
    IF inorex = 0 THEN
      put(RVAssem.addi(RH, 0, 1));
      put(RVAssem.sll(y.r, RH, y.r));
      put(RVAssem.or(zr, zr, y.r));
    ELSE
      put(RVAssem.addi(RH, 0, -2));
      put(RVAssem.sll(y.r, RH, y.r));
      put(RVAssem.and(zr, zr, y.r));
    END;
    decR
  END ;
  put(RVAssem.sw(zr, x.r, 0)); decR; decR
END Include;

PROCEDURE Assert*(VAR x: Item);
  VAR cond, l, r: INTEGER;
BEGIN
  IF x.mode # Cond THEN loadCond(x) END ;
  IF x.a = 0 THEN
    cond := opposite(x.r);
  ELSE
    put(MakeFwdBranch(x.r, x.cl, x.cr, x.b)); FixLink(x.a);
    x.b := pc-1; cond := ALW;
  END ;
  Trap(cond, TrapAssertFailure, x.cl, x.cr); FixLink(x.b)
END Assert; 

PROCEDURE New*(VAR x: Item);
BEGIN
  loadAdr(x); loadTypTagAdr(x.type.base);
  Trap(0, 0, 0, 0);
  RH := firstReg; invalSB
END New;

PROCEDURE Pack*(VAR x, y: Item);
  VAR z: Item;
BEGIN
(*
  z := x; load(x); load(y);
  Put1(Lsl, y.r, y.r, 23); Put0(Add, x.r, x.r, y.r); DEC(RH); Store(z, x)
*)  RVOS.Mark("REALs not supported")
END Pack;

PROCEDURE Unpk*(VAR x, y: Item);
  VAR z, e0: Item;
BEGIN  z := x; load(x); e0.mode := Reg; e0.r := RH; e0.type := RVOB.intType;
(*
  Put1(Asr, RH, x.r, 23); Put1(Sub, RH, RH, 127); Store(y, e0); incR;
  Put1(Lsl, RH, RH, 23); Put0(Sub, x.r, x.r, RH); Store(z, x)
*)  RVOS.Mark("REALs not supported")
END Unpk;

PROCEDURE Led*(VAR x: Item);
BEGIN (* We don't support LED as an intrinsic I/O primitive. *)
END Led;

PROCEDURE Get*(VAR x, y: Item);
BEGIN load(x); x.type := y.type; x.mode := RegI; x.a := 0; Store(y, x)
END Get;

PROCEDURE Put*(VAR x, y: Item);
BEGIN load(x); x.type := y.type; x.mode := RegI; x.a := 0; Store(x, y)
END Put;

PROCEDURE Copy*(VAR x, y, z: Item);
BEGIN load(x); load(y);
  IF z.mode = RVOB.Const THEN
    IF z.a > 0 THEN load(z) ELSE RVOS.Mark("bad count") END
  ELSE load(z);
    IF check THEN Trap(LT, TrapNegativeSize, z.r, 0) END ;
    put(RVAssem.beq(z.r, 0, 24))
  END ;
  put(RVAssem.lw(RH, x.r, 0));  put(RVAssem.addi(x.r, x.r, IntegerSize));
  put(RVAssem.sw(RH, x.r, 0));  put(RVAssem.addi(x.r, y.r, IntegerSize));
  put(RVAssem.addi(z.r, z.r, -1));
  put(RVAssem.bne(z.r, 0, -20));
  decR; decR; decR
END Copy;

PROCEDURE LDPSR*(VAR x: Item);
BEGIN RVOS.Mark("PSR not supported")
END LDPSR;

PROCEDURE LDREG*(VAR x, y: Item);
BEGIN
  IF (y.mode = RVOB.Const) & FitsIn12Bits(y.a) THEN
    put(RVAssem.addi(x.a, 0, y.a))
  ELSE
    load(y); put(RVAssem.addi(x.a, y.r, 0)); decR
  END
END LDREG;

(*In-line code functions*)

PROCEDURE Abs*(VAR x: Item);
BEGIN
  IF x.mode = RVOB.Const THEN x.a := ABS(x.a)
  ELSE
    load(x);
    IF x.type.form = RVOB.Real THEN
    (*
      Put1(Lsl, x.r, x.r, 1); Put1(Ror, x.r, x.r, 1)
    *)  RVOS.Mark("REALs not supported")
    ELSE
      put(RVAssem.bge(x.r, 0, 8));
      put(RVAssem.sub(x.r, 0, x.r));
    END
  END
END Abs;

PROCEDURE Odd*(VAR x: Item);
BEGIN load(x); put(RVAssem.andi(x.r, x.r, 1)); SetCC0(x, NE); decR
END Odd;

PROCEDURE Floor*(VAR x: Item);
BEGIN
(*
  load(x); Put1(Mov+U, RH, 0, 4B00H); Put0(Fad+V, x.r, x.r, RH)
*)  RVOS.Mark("REALs not supported")
END Floor;

PROCEDURE Float*(VAR x: Item);
BEGIN
(*
  load(x); Put1(Mov+U, RH, 0, 4B00H);  Put0(Fad+U, x.r, x.r, RH)
*)  RVOS.Mark("REALs not supported")
END Float;

PROCEDURE Ord*(VAR x: Item);
BEGIN
  IF x.mode IN {RVOB.Var, RVOB.Par, RegI, Cond} THEN load(x) END
END Ord;

PROCEDURE Len*(VAR x: Item);
BEGIN
  IF x.type.len >= 0 THEN x.mode := RVOB.Const; x.a := x.type.len
  ELSE (*open array*)
    put(RVAssem.lw(RH, SP, x.a + frame + IntegerSize));
    x.mode := Reg; x.r := RH; incR
  END 
END Len;

PROCEDURE Shift*(fct: INTEGER; VAR x, y: Item);
  VAR op: INTEGER;
BEGIN load(x);
  IF fct = 0 THEN (* LSL *)
    IF y.mode = RVOB.Const THEN
      put(RVAssem.slli(x.r, x.r, y.a MOD BitsPerInteger))
    ELSE
      load(y); put(RVAssem.sll(RH-2, x.r, y.r));
      decR; x.r := RH-1
    END
  ELSIF fct = 1 THEN (* ASR *)
    IF y.mode = RVOB.Const THEN
      put(RVAssem.srai(x.r, x.r, y.a MOD BitsPerInteger))
    ELSE
      load(y); put(RVAssem.sra(RH-2, x.r, y.r));
      decR; x.r := RH-1
    END
  ELSE (* ROR *)
    IF y.mode = RVOB.Const THEN
      put(RVAssem.srli(RH, x.r, y.a MOD BitsPerInteger));
      put(RVAssem.slli(x.r, x.r, BitsPerInteger - (y.a MOD BitsPerInteger)));
      put(RVAssem.or(x.r, x.r, RH))
    ELSE
      load(y);
      put(RVAssem.addi(RH+1, 0, BitsPerInteger));
      put(RVAssem.sub(RH+1, RH+1, y.r));
      put(RVAssem.srl(RH, x.r, y.r));
      put(RVAssem.sll(x.r, x.r, RH+1));
      put(RVAssem.or(x.r, x.r, RH));
      decR; x.r := RH-1
    END
  END
END Shift;

PROCEDURE Bit*(VAR x, y: Item);
BEGIN
  load(x); put(RVAssem.lw(x.r, x.r, 0));
  IF y.mode = RVOB.Const THEN
    put(RVAssem.slli(x.r, x.r, (BitsPerInteger-1)-(y.a MOD BitsPerInteger)))
  ELSE
    load(y);
    put(RVAssem.addi(RH, 0, BitsPerInteger-1));
    put(RVAssem.sub(y.r, RH, y.r));
    put(RVAssem.sll(x.r, x.r, y.r));
    decR
  END ;
  SetCC0(x, LT); decR
END Bit;

(* Loads register x.a into x.r *)
PROCEDURE Register*(VAR x: Item);
BEGIN (*x.mode = Const*)
  put(RVAssem.addi(RH, x.a MOD maxReg, 0));
  x.mode := Reg; x.r := RH; incR
END Register;

PROCEDURE Adr*(VAR x: Item);
BEGIN 
  IF x.mode IN {RVOB.Var, RVOB.Par, RegI} THEN loadAdr(x)
  ELSIF (x.mode = RVOB.Const) & (x.type.form = RVOB.Proc) THEN load(x)
  ELSIF (x.mode = RVOB.Const) & (x.type.form = RVOB.String) THEN loadStringAdr(x)
  ELSE RVOS.Mark("not addressable")
  END
END Adr;

PROCEDURE CSRop*(op: INTEGER; VAR x, y: Item);
BEGIN
  ASSERT(x.mode = RVOB.Const);
  IF (x.a < 0) OR  (4096 <= x.a) THEN
    RVOS.Mark("CSR must lie between 0000H and 0FFFH inclusive.");
  ELSE
    IF (y.mode = RVOB.Const) & (0 <= y.a) & (y.a < 32) THEN
      put(RVAssem.fmtI(73H, op+5, RH, y.a, x.a));
      x.mode := Reg;
      x.r := RH; incR
    ELSE
      load(y);
      ASSERT(y.mode = Reg);
      put(RVAssem.fmtI(73H, op+1, y.r, y.r, x.a));
      x := y
    END
  END
END CSRop;

PROCEDURE Init*(VAR success: BOOLEAN);
  VAR p : Program; c : Code; s : Strings; d : TypeDescriptors;
BEGIN
  NEW(p); NEW(c); NEW(s); NEW(d);
  IF (p = NIL) OR (c = NIL) OR (s = NIL) OR (d = NIL) THEN
    Texts.WriteLn(W); Texts.WriteString(W, "Warning! Not enough heap space to allocate space for program; compilation will fail!"); Texts.Append(Oberon.Log, W.buf);
    success := FALSE;
  ELSE
    program := p; program.code := c; program.strings := s; program.data := d;
    success := TRUE;
  END;
END Init;

PROCEDURE Open*(v: INTEGER; id: RVOS.Ident);
  VAR success: BOOLEAN;
BEGIN pc := 0; tdx := 0; strx := 0; RH := firstReg; fixorgP := 0; fixorgD := 0; fixorgT := 0; check := v # 0; version := v;
  stacktrace := FALSE;
  IF v = 0 THEN pc := 8 END;
  modid := id;
END Open;

PROCEDURE SetDataSize*(dc: INTEGER);
BEGIN varsize := dc
END SetDataSize;

PROCEDURE Header*;
BEGIN entry := pc*InsnSize;
  IF version = 0 THEN  (* ROM-resident ABI *)
    program.code.c[0] := RVAssem.jal(0, pc*InsnSize);
    LoadImmTo(SB, VarOrg0);
    LoadImmTo(SP, StkOrg0);
  ELSE
    put(RVAssem.addi(SP, SP, -IntegerSize));
    (* must be changed if 64-bit is desired *)
    put(RVAssem.sw(RA, SP, 0));
    invalSB
  END
END Header;

PROCEDURE NofPtrs(typ: RVOB.Type): INTEGER;
  VAR fld: RVOB.Object; n: INTEGER;
BEGIN
  IF (typ.form = RVOB.Pointer) OR (typ.form = RVOB.NilTyp) THEN n := 1
  ELSIF typ.form = RVOB.Record THEN
    fld := typ.dsc; n := 0;
    WHILE fld # NIL DO n := NofPtrs(fld.type) + n; fld := fld.next END
  ELSIF typ.form = RVOB.Array THEN n := NofPtrs(typ.base) * typ.len
  ELSE n := 0
  END ;
  RETURN n
END NofPtrs;

PROCEDURE FindPtrs(VAR R: Files.Rider; typ: RVOB.Type; adr: INTEGER);
  VAR fld: RVOB.Object; i, s: INTEGER;
BEGIN
  IF (typ.form = RVOB.Pointer) OR (typ.form = RVOB.NilTyp) THEN Files.WriteInt(R, adr)
  ELSIF typ.form = RVOB.Record THEN
    fld := typ.dsc;
    WHILE fld # NIL DO FindPtrs(R, fld.type, fld.val + adr); fld := fld.next END
  ELSIF typ.form = RVOB.Array THEN
    s := typ.base.size;
    FOR i := 0 TO typ.len-1 DO FindPtrs(R, typ.base, i*s + adr) END
  END
END FindPtrs;

PROCEDURE CloseModule(VAR modid: RVOS.Ident; key, nofent: INTEGER);
  VAR obj: RVOB.Object;
    i, comsize, nofimps, nofptrs, size: INTEGER;
    name, namecode: RVOS.Ident;
    F: Files.File; R: Files.Rider;
BEGIN
  obj := RVOB.topScope.next; nofimps := 0;
  comsize := 4; nofptrs := 0;
  WHILE obj # NIL DO
    IF (obj.class = RVOB.Mod) & (obj.dsc # RVOB.system) THEN INC(nofimps) (*count imports*)
    ELSIF (obj.exno # 0) & (obj.class = RVOB.Const) & (obj.type.form = RVOB.Proc)
        & (obj.type.nofpar = 0) & (obj.type.base = RVOB.noType) THEN i := 0; (*count commands*)
      WHILE obj.name[i] # 0X DO INC(i) END ;
      i := (i+4) DIV 4 * 4;
      INC(comsize, i+4)
    ELSIF obj.class = RVOB.Var THEN INC(nofptrs, NofPtrs(obj.type))  (*count pointers*)
    END ;
    obj := obj.next
  END ;
  size := varsize + strx + comsize +    (* varsize includes type descriptors *)
      (pc + nofimps + nofent + nofptrs + 1)*4;

  IF (varsize > 2048) THEN
    Texts.WriteLn(W); Texts.WriteString(W, "Warning! Global variable size too large at "); Texts.WriteInt(W, varsize, 1);
    Texts.WriteString(W, " bytes. Maximum is 2048 bytes. Other modules will be unable to access exported variables; such access will cause undefined behaviour."); Texts.WriteInt(W, varsize, 1); Texts.Append(Oberon.Log, W.buf);
  END;

  RVOB.MakeFileName(name, modid, ".rsc"); (*write code file*)
  F := Files.New(name); Files.Set(R, F, 0);
  Files.WriteString(R, modid); Files.WriteInt(R, key); Files.WriteByte(R, version);
  Files.WriteInt(R, size);
  obj := RVOB.topScope.next;
  WHILE (obj # NIL) & (obj.class = RVOB.Mod) DO  (*imports*)
    IF obj.dsc # RVOB.system THEN Files.WriteString(R, obj(RVOB.Module).orgname); Files.WriteInt(R, obj.val) END ;
    obj := obj.next
  END ;
  Files.Write(R, 0X);
  Files.WriteInt(R, tdx*4);
  i := 0;
  WHILE i < tdx DO Files.WriteInt(R, program.data.t[i]); INC(i) END ; (*type descriptors*)
  Files.WriteInt(R, varsize - tdx*4);  (*data*)
  Files.WriteInt(R, strx);
  FOR i := 0 TO strx-1 DO Files.Write(R, program.strings.s[i]) END ;  (*strings*)
  Files.WriteInt(R, pc);  (*code len*)
  FOR i := 0 TO pc-1 DO Files.WriteInt(R, program.code.c[i]); END ;  (*program*)
  obj := RVOB.topScope.next;
  WHILE obj # NIL DO  (*commands*)
    IF (obj.exno # 0) & (obj.class = RVOB.Const) & (obj.type.form = RVOB.Proc) &
        (obj.type.nofpar = 0) & (obj.type.base = RVOB.noType) THEN
      Files.WriteString(R, obj.name); Files.WriteInt(R, obj.val)
    END ;
    obj := obj.next
  END ;
  Files.Write(R, 0X);
  Files.WriteInt(R, nofent); Files.WriteInt(R, entry);
  obj := RVOB.topScope.next;
  WHILE obj # NIL DO  (*entries*)
    IF obj.exno # 0 THEN
      IF (obj.class = RVOB.Const) & (obj.type.form = RVOB.Proc) OR (obj.class = RVOB.Var) THEN
        Files.WriteInt(R, obj.val)
      ELSIF obj.class = RVOB.Typ THEN
        IF obj.type.form = RVOB.Record THEN Files.WriteInt(R,  obj.type.len MOD 10000H);
        ELSIF (obj.type.form = RVOB.Pointer) & ((obj.type.base.typobj = NIL) OR (obj.type.base.typobj.exno = 0)) THEN
          Files.WriteInt(R, obj.type.base.len MOD 10000H);
        END
      END
    END ;
    obj := obj.next
  END ;
  obj := RVOB.topScope.next;
  WHILE obj # NIL DO  (*pointer variables*)
    IF obj.class = RVOB.Var THEN FindPtrs(R, obj.type, obj.val) END ;
    obj := obj.next
  END ;
  Files.WriteInt(R, -1);
  Files.WriteInt(R, fixorgP); Files.WriteInt(R, fixorgD); Files.WriteInt(R, fixorgT); Files.WriteInt(R, entry);
  Files.Write(R, "O"); Files.Register(F);
  program.code := NIL; program.strings := NIL; program.data := NIL;
  program := NIL;
END CloseModule;

PROCEDURE writeDword(VAR R: Files.Rider; i: INTEGER);
BEGIN
  Files.WriteInt(R, i);
  IF i < 0 THEN Files.WriteInt(R, -1) ELSE Files.WriteInt(R, 0) END
END writeDword;

PROCEDURE Close*(VAR modid: RVOS.Ident; key, nofent: INTEGER);
  VAR obj: RVOB.Object;
    i, comsize, nofimps, nofptrs, size: INTEGER;
    name: RVOS.Ident;
    F: Files.File; R: Files.Rider;
BEGIN  (* module body epilog *)
  IF version = 0 THEN  (* ROM ABI *)
    put(RVAssem.addi(RA, 0, 0));
    put(RVAssem.jalr(0, RA, 0));
    (*CloseRom(modid, key, nofent);*)
    CloseModule(modid, key, nofent);
  ELSE
    put(RVAssem.lw(RA, SP, 0));
    put(RVAssem.addi(SP, SP, 4));
    put(RVAssem.jalr(0, RA, 0));
    CloseModule(modid, key, nofent);
  END ;
END Close;

BEGIN
  sym2rel[RVOS.eql-RVOS.eql] := EQ;
  sym2rel[RVOS.neq-RVOS.eql] := NE;
  sym2rel[RVOS.lss-RVOS.eql] := LT;
  sym2rel[RVOS.leq-RVOS.eql] := GE;   (* not a typo; swap args first! *)
  sym2rel[RVOS.gtr-RVOS.eql] := LT;   (* not a typo; swap args first! *)
  sym2rel[RVOS.geq-RVOS.eql] := GE;

  sym2uRel[RVOS.eql-RVOS.eql] := EQ;
  sym2uRel[RVOS.neq-RVOS.eql] := NE;
  sym2uRel[RVOS.lss-RVOS.eql] := LTU;
  sym2uRel[RVOS.leq-RVOS.eql] := GEU; (* not a typo; swap args first! *)
  sym2uRel[RVOS.gtr-RVOS.eql] := LTU; (* not a typo; swap args first! *)
  sym2uRel[RVOS.geq-RVOS.eql] := GEU;

  Texts.OpenWriter(W);
END RVOG.
