MODULE RVOG;
  IMPORT SYSTEM, RVAssem, Files, ORS:=RVOS, ORB:=RVOB;


CONST
  WordSize* = 4;    (* Targeting 64-bit RISC-V runtime *)
  DWordSize* = 8;

  LNK = 1;          (* X1 = RA = LNK; holds return address *)
  SP = 2;           (* X2 = SP; stack pointer *)
  SB = 3;           (* X3 = SB = GP; holds pointer to module globals *)
  MT = 4;           (* X4 = MT = TP; holds pointer to module table. *)

  RHStart = 8;      (* X8 is first register to allocate *)
  RHLimit = 31;     (* X31 is the highest register RISC-V supports *)

  maxCode = 8000;   (* Maximum size of a module's code, in words *)
  maxTD = 128;      (* Maximum number of type descriptors in a module *)
  maxStrx = 3172;   (* Maximum number of characters for static strings *)
  VarOrg0 = 0;      (* Real address for ROM ABI global variables *)
  invalidSB = 0;    (* Sentinel indicating an invalid/unknown SB state *)


VAR
  check: BOOLEAN; (* TRUE if enforce array bounds checks *)

    tdx,          (* Words consumed by type descriptors *)
    strx,         (* Bytes consumed by string constants *)
    varsize,      (* Number of bytes needed for variables *)
    curSB,        (* a module number (I think), or invalidSB *)
    entry,        (* Offset of the module's initialization code. *)
    abi,          (* 0 for bootstrap ABI; 1 for Oberon System ABI *)
    pc*,          (* current location counter in code buffer *)
    RH            (* Top of register label stack (RHStart <= RH <= RHLimit) *)
  : INTEGER;

  code: ARRAY maxCode OF INTEGER;
  data: ARRAY maxTD OF INTEGER;
  str:  ARRAY maxStrx OF CHAR;


(*
  The following logic is sufficient to support generation of empty modules,
  like this:

    MODULE Foo;
    END Foo.
*)

PROCEDURE invalSB;
(*
  Mark the compiler's understanding of the current SB register to an invalid
  value.
*)
BEGIN
  curSB := invalidSB;
END invalSB;


PROCEDURE put(w: INTEGER);
(*
  Place a word into the code space, and increment the location counter.
*)
BEGIN code[pc] := w; INC(pc);
END put;


PROCEDURE FindPtrs(VAR R: Files.Rider; typ: ORB.Type; adr: LONGINT);
(*
  Given a record or array type, write out the indices of globally accessible
  pointers (pointers accessible off of SB).  This is required for garbage
  collection, as each of these pointers constitutes a root.
*)
VAR
  fld: ORB.Object; i, s: LONGINT;
BEGIN
  IF (typ.form = ORB.Pointer) OR (typ.form = ORB.NilTyp) THEN Files.WriteInt(R, adr)
  ELSIF typ.form = ORB.Record THEN
    fld := typ.dsc;
    WHILE fld # NIL DO FindPtrs(R, fld.type, fld.val + adr); fld := fld.next END
  ELSIF typ.form = ORB.Array THEN
    s := typ.base.size;
    FOR i := 0 TO typ.len-1 DO FindPtrs(R, typ.base, i*s + adr) END
  END
END FindPtrs;


PROCEDURE NofPtrs(typ: ORB.Type): LONGINT;
(*
  Given a record or array type, answer the number of pointers contained
  within.  This is required knowledge for proper garbage collection.
*)
VAR
  fld: ORB.Object; n: LONGINT;
BEGIN
  IF (typ.form = ORB.Pointer) OR (typ.form = ORB.NilTyp) THEN n := 1
  ELSIF typ.form = ORB.Record THEN
    fld := typ.dsc; n := 0;
    WHILE fld # NIL DO n := NofPtrs(fld.type) + n; fld := fld.next END
  ELSIF typ.form = ORB.Array THEN n := NofPtrs(typ.base) * typ.len
  ELSE n := 0
  END ;
  RETURN n
END NofPtrs;


PROCEDURE Open*(v: INTEGER);
(*
  Initialize the code generator for a fresh module.
*)
BEGIN
  pc := 0; RH := RHStart;
  check := v # 0; abi := v;
  IF abi = 0 THEN pc := 8 END;

  tdx := 0; strx := 0;
  (* fixorgP := 0; fixorgD := 0; fixorgT := 0; *)
END Open;


PROCEDURE Header*;
(*
  Begin code for the module's initialization procedure.  Sets variable
  `entry` to the byte address of this procedure.
*)
BEGIN
  entry := pc*WordSize;
  IF abi = 0 THEN
    code[0] := RVAssem.jal(0, entry);
    put(RVAssem.addi(SB, 0, VarOrg0));
  ELSE
    put(RVAssem.addi(SP, SP, -DWordSize));
    put(RVAssem.sd(LNK, SP, 0));
    invalSB;
  END
END Header;


PROCEDURE Close*(VAR modid: ORS.Ident; key, nofent: LONGINT);
(*
  Generate module initializer epilog code.  Then, write out the module file.
*)
VAR
  nofimps,    (* Number of imports *)
  nofptrs,    (* Number of pointers (to variables?) *)
  size,       (* Total size of module's data and code *)
  comsize,    (* Size, in bytes, of command table *)
  i: LONGINT;

  obj: ORB.Object;
  name: ORS.Ident;
  F: Files.File; R: Files.Rider;
BEGIN  (*exit code*)
  IF abi = 0 THEN
    put(RVAssem.addi(LNK, 0, 0));
  ELSE
    put(RVAssem.lw(LNK, SP, 0)); put(RVAssem.addi(SP, SP, 4));
  END;
  put(RVAssem.jalr(0, LNK, 0));

  (*
    Tally various objects created during compilation.  We need this to create
    the object file later on.
  *)

  obj := ORB.topScope.next; nofimps := 0; comsize := 4; nofptrs := 0;
  WHILE obj # NIL DO
    IF (obj.class = ORB.Mod) & (obj.dsc # ORB.system) THEN INC(nofimps) (*count imports*)
    ELSIF (obj.exno # 0) & (obj.class = ORB.Const) & (obj.type.form = ORB.Proc)
        & (obj.type.nofpar = 0) & (obj.type.base = ORB.noType) THEN i := 0; (*count commands*)
      WHILE obj.name[i] # 0X DO INC(i) END ;
      i := (i+4) DIV 4 * 4; INC(comsize, i+4)
    ELSIF obj.class = ORB.Var THEN INC(nofptrs, NofPtrs(obj.type))  (*count pointers*)
    END ;
    obj := obj.next
  END ;
  size := varsize + strx + comsize + (pc + nofimps + nofent + nofptrs + 1)*WordSize;  (*varsize includes type descriptors*)

  (*
    Create the object file.
  *)

  ORB.MakeFileName(name, modid, ".rv64.obj"); (* object header *)
  F := Files.New(name); Files.Set(R, F, 0);
  Files.WriteInt(R, 00AA5500H);   (* Magic to identify RV64I RISC OBJ file *)
  Files.WriteString(R, modid); Files.WriteInt(R, key); Files.WriteByte(R, abi);
  Files.WriteInt(R, size);

  obj := ORB.topScope.next;  (* Imports *)
  WHILE (obj # NIL) & (obj.class = ORB.Mod) DO
    IF obj.dsc # ORB.system THEN
      Files.WriteString(R, obj(ORB.Module).orgname);
      Files.WriteInt(R, obj.val)
    END ;
    obj := obj.next
  END ;
  Files.Write(R, 0X);

  Files.WriteInt(R, tdx*4);   (* type descriptors *)
  i := 0;
  WHILE i < tdx DO Files.WriteInt(R, data[i]); INC(i) END;

  Files.WriteInt(R, varsize - tdx*4);  (* uninitialized data *)

  Files.WriteInt(R, strx);  (* Strings *)
  FOR i := 0 TO strx-1 DO Files.Write(R, str[i]); END;

  Files.WriteInt(R, pc);  (* code *)
  FOR i := 0 TO pc-1 DO Files.WriteInt(R, code[i]) END;

  obj := ORB.topScope.next;   (* Command table *)
  WHILE obj # NIL DO
    IF (obj.exno # 0) & (obj.class = ORB.Const) & (obj.type.form = ORB.Proc) &
        (obj.type.nofpar = 0) & (obj.type.base = ORB.noType) THEN
      Files.WriteString(R, obj.name); Files.WriteInt(R, obj.val)
    END ;
    obj := obj.next
  END ;
  Files.Write(R, 0X);

  Files.WriteInt(R, nofent); (* Exported Entries *)
  Files.WriteInt(R, entry);  (* 1st entry always module init *)
  obj := ORB.topScope.next;
  WHILE obj # NIL DO
    IF obj.exno # 0 THEN
      IF (obj.class = ORB.Const) & (obj.type.form = ORB.Proc) OR (obj.class = ORB.Var) THEN  (* Write address of procedure or variable *)
        Files.WriteInt(R, obj.val)
      ELSIF obj.class = ORB.Typ THEN (* Write type descriptor index *)
        IF obj.type.form = ORB.Record THEN Files.WriteInt(R,  obj.type.len MOD 10000H)
        ELSIF (obj.type.form = ORB.Pointer) & ((obj.type.base.typobj = NIL) OR (obj.type.base.typobj.exno = 0)) THEN
          Files.WriteInt(R, obj.type.base.len MOD 10000H)
        END
      END
    END ;
    obj := obj.next
  END ;

  obj := ORB.topScope.next;  (* Global roots for GC *)
  WHILE obj # NIL DO
    IF obj.class = ORB.Var THEN FindPtrs(R, obj.type, obj.val) END ;
    obj := obj.next
  END ;
  Files.WriteInt(R, -1);

  Files.WriteInt(R, entry);
  Files.Write(R, "O"); Files.Register(F)
END Close;

END RVOG.
