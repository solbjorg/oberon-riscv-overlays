MODULE RVOP; (* Oberon compiler for RISC-V in Oberon-07 *)
IMPORT SYSTEM, Texts, Oberon, ORS:=RVOS, RVAssem, RVDis;


CONST
  DWordSize = 8;        (* RISC-V DWords are 64-bits wide *)
  WordSize = 4;         (* RISC-V Words are 32-bits wide *)

  maxCode = 8000;

  firstReg = 8;
  maxReg = 32;

  RA = 1;               (* CPU registers used by the Oberon ABI *)
  SP = 2;
  SB = 3;
  MT = 4;


  (* "Kinds" of symbols allowed in an Oberon text *)
  noKind = 0;
  module = 1; (* typically an import *)
  type = 2;   (* e.g., INTEGER, SET; but not aggregate types *)
  gvar = 3;   (* dword offset relative to SB register *)
  lvar = 4;   (* dword offset relative to SP register *)
  proc = 5;   (* procedure *)
  const = 6;  (* Symbol is a constant value; offset has value *)

  (*
    Items can sit in memory, in a CPU register, or be specified as a literal.
  *)
  nowhere = 0;
  mem = 1;
  reg = 2;
  lit = 3;

TYPE
  Symbol = POINTER TO SymbolRec;
  Item = POINTER TO ItemRec;

  (*
    Symbols describe static entities in a program.  These include things like:
    procedures, global or local variables, etc.
  *)
  SymbolRec = RECORD
    name: ORS.Ident;    (* What the programmer named this symbol *)
    type: Symbol;       (* Determines the set of assign-compatible types *)
    kind: INTEGER;      (* Kind of symbol; determine base address *)
    offset: INTEGER;    (* offset from some base (dep. on kind) *)
                        (* gvars have dword offset; procs have word offset *)
    size: INTEGER;      (* How many bytes this kind of object takes. *)
    level: INTEGER;     (* Scoping level for removing out-of-scope symbols *)
    next: Symbol;
  END;

  (*
    Items describe dynamic entities in a program.  These include numeric or
    string literals, procedure addresses, global or local variable references,
    etc.  Keep in mind that these do not actually describe actual values
    (except for constants!), but rather, where these values can be found at
    RUN-TIME.

    Where possible, fields in Item are the same as corresponding fields in a
    Symbol record.
  *)
  ItemRec = RECORD
    type: Symbol;       (* Type of the item (useful for calculating size) *)
    kind: INTEGER;      (* module, type, gvar, lvar, etc. *)
    offset: LONGINT;    (* offset from some base, or literal value *)
    loc: INTEGER;       (* where is this item?  Memory, register, literal? *)
  END;


VAR
  W: Texts.Writer;      (* Output for logging/errors. *)
  newSF: BOOLEAN;       (* TRUE to replace/FALSE to validate against smb file *)
  sym: INTEGER;         (* Last fetched symbol classification *)
  level: INTEGER;       (* 0 for global scope; >0 for local scopes. *)
  symtab: Symbol;       (* List of symbols known to the module *)
  dp: INTEGER;          (* Data Pointer; dword offset into data space *)
  cp: INTEGER;          (* Code Pointer; word offset into code space *)
  RH: INTEGER;          (* The next register to allocate for computation *)
  lotp: INTEGER;        (* Index into the Large Operand Table *)
  loftp: INTEGER;       (* Index into the Large Operand Fixup Table *)

  dummyS: Symbol;       (* Used to initialize global types, procedures, etc. *)
  dummyId: ORS.Ident;
  longint, integer, set, bool: Symbol;

  code: ARRAY maxCode OF INTEGER;
  lot: ARRAY maxCode OF INTEGER;  (* Tune me *)
  loft: ARRAY maxCode OF INTEGER;  (* Tune me *)


(* Code and data construction *)


PROCEDURE incR;
BEGIN IF RH < maxReg THEN INC(RH)
  ELSE ORS.Mark("Register stack overflow")
  END
END incR;


PROCEDURE decR;
BEGIN IF RH > firstReg THEN DEC(RH)
  ELSE ORS.Mark("Register stack underflow")
  END
END decR;


PROCEDURE put(w: INTEGER);
BEGIN code[cp] := w; INC(cp);
RVDis.WriteOpcode(W, w); Texts.WriteLn(W);
END put;


(* Built-in Self Test *)


PROCEDURE appendLog;
BEGIN
  Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
END appendLog;


PROCEDURE comment(msg: ARRAY OF CHAR);
BEGIN
  Texts.WriteString(W, msg); appendLog
END comment;


PROCEDURE assertTrue(fact: BOOLEAN; msg: ARRAY OF CHAR);
BEGIN
  IF ~fact THEN
    Texts.WriteString(W, "  FAIL  "); Texts.WriteString(W, msg); appendLog;
    ASSERT(FALSE);
  END
END assertTrue;


(*
  Symbol table management
*)


PROCEDURE NewSymbol(VAR s: Symbol);
BEGIN
  NEW(s); s.next := symtab; s.level := level; symtab := s;
END NewSymbol;


PROCEDURE NewModuleSymbol(VAR s: Symbol; name: ORS.Ident);
BEGIN
  NewSymbol(s);
  s.name := name;
  s.kind := module;
END NewModuleSymbol;


PROCEDURE NewTypeSymbol(VAR s: Symbol; name: ORS.Ident; size: INTEGER);
BEGIN
  NewSymbol(s);
  s.name := name;
  s.kind := type;
  s.size := size;
END NewTypeSymbol;


PROCEDURE NewProcedureSymbol(VAR s: Symbol; name: ORS.Ident; offset: INTEGER);
BEGIN
  NewSymbol(s);
  s.name := name;
  s.kind := proc;
  s.offset := offset;
END NewProcedureSymbol;


PROCEDURE LookupSymbol(VAR s: Symbol; name: ORS.Ident);
VAR current: Symbol;
BEGIN
  current := symtab; s := NIL;
  WHILE (current # NIL) & (s = NIL) DO
    IF current.name = name THEN s := current; END;
    current := current.next;
  END;
END LookupSymbol;


PROCEDURE closeScope;
VAR
  s: Symbol;
BEGIN
  s := symtab; WHILE (s # NIL) & (s.level = level) DO s := s.next END;
  symtab := s
END closeScope;


PROCEDURE openScope;
BEGIN INC(level);
END openScope;


PROCEDURE BistSymTab;
VAR
  s, t, u, v: Symbol;
  systemName, oberonName, filesName, dummyName: ORS.Ident;
BEGIN
  systemName := "SYSTEM";
  oberonName := "Oberon";
  filesName := "Files";
  dummyName := "dummy";
  symtab := NIL;

  comment("Create a SYSTEM module symbol");
  assertTrue(level = 0, "Expecting global scope");
  NewModuleSymbol(s, systemName);
  assertTrue(s.next = NIL, "linkage unexpected");
  assertTrue(s.name = "SYSTEM", "name should be SYSTEM");
  assertTrue(s.kind = module, "Module symbol expected");
  assertTrue(s.type = NIL, "I expect NEW to zero uninitialized fields");

  comment("Create a second symbol");
  NewModuleSymbol(t, oberonName);
  assertTrue(t.next # NIL, "Should point to 1st symbol");
  assertTrue(t.name = "Oberon", "name should be Oberon");
  assertTrue(t.kind = module, "Module symbol expected");
  assertTrue(t.next.name = "SYSTEM", "1st symbol should be SYSTEM");
  assertTrue(t.next = s, "1st symbol should be what we just added");

  comment("Symbol lookup");
  LookupSymbol(u, systemName);
  assertTrue(u # NIL, "SYSTEM exists");
  assertTrue(u.name = "SYSTEM", "result should be system module");
  assertTrue(u = s, "should answer the SYSTEM module");

  LookupSymbol(u, oberonName);
  assertTrue(u # NIL, "Oberon exists");
  assertTrue(u.name = "Oberon", "result should be Oberon module");
  assertTrue(u = t, "should answer the Oberon module");

  symtab := NIL; Oberon.Collect(0);

  comment("Introducing a scope");
  NewModuleSymbol(s, systemName);
  NewModuleSymbol(t, oberonName);
  openScope;
  assertTrue(level = 1, "Should be local now.");
  NewModuleSymbol(u, filesName);
  assertTrue(u.next = t, "Files module should link with Oberon");
  NewModuleSymbol(v, dummyName);
  assertTrue(symtab = v, "just making sure linkage is OK");
  assertTrue(u.level = 1, "Files should be at level 1");
  assertTrue(v.level = 1, "Dummy should be at level 1");
  closeScope;
  assertTrue(symtab = t, "Should discard all symbols at level 1");

  symtab := NIL; Oberon.Collect(0);
END BistSymTab;


(*
  These procedures are utilities to check aspects of the syntax.
*)


PROCEDURE Check(s: INTEGER; msg: ARRAY OF CHAR);
BEGIN
  IF sym = s THEN ORS.Get(sym) ELSE ORS.Mark(msg) END
END Check;


PROCEDURE DoImport(shortId, importId: ORS.Ident);
VAR
  smb: Symbol;
BEGIN
  IF importId # "SYSTEM" THEN
    ORS.Mark("Imports other than SYSTEM not yet supported.");
  ELSE
    NewModuleSymbol(smb, shortId);
  END;
END DoImport;


PROCEDURE admitVars(vl, type: Symbol; kind: INTEGER);
VAR vn: Symbol;
BEGIN
  WHILE vl # NIL DO
    vn := vl.next;
    vl.kind := kind; vl.type := type;
    vl.offset := dp; INC(dp, ASR(type.size + 7, 3));
    vl.next := symtab; symtab := vl;
    vl := vn;
  END
END admitVars;


PROCEDURE varDecl(kind: INTEGER);
VAR
  idList, idNode: Symbol;
  s: Symbol;
BEGIN
  idList := NIL;
  WHILE sym = ORS.ident DO
    NEW(idNode); ORS.CopyId(idNode.name); idNode.kind := noKind;
    idNode.next := idList;  idList := idNode;
    ORS.Get(sym);
    IF sym = ORS.comma THEN ORS.Get(sym) END
  END;
  IF sym # ORS.colon THEN
    ORS.Mark(": expected, then type specifier")
  ELSE
    ORS.Get(sym);
    IF sym = ORS.ident THEN
      LookupSymbol(s, ORS.id);
      IF (s = NIL) OR (s.kind # type) THEN ORS.Mark("Unknown type")
      ELSE admitVars(idList, s, kind);
      END
    ELSE ORS.Mark("Type expected")
    END;
    ORS.Get(sym);
    Check(ORS.semicolon, "; expected");
  END
END varDecl;


PROCEDURE declarations(kind: INTEGER);
BEGIN
  IF sym = ORS.var THEN
    ORS.Get(sym);
    WHILE sym = ORS.ident DO varDecl(kind) END;
  END;
END declarations;


PROCEDURE NewItemFromSymbol(VAR i: Item; s: Symbol);
BEGIN
  IF s.kind IN {gvar, lvar} THEN
    NEW(i);  IF i # NIL THEN
      i.loc := mem;
      i.type := s.type; i.kind := s.kind; i.offset := s.offset
    END
  ELSE i := NIL;
  END
END NewItemFromSymbol;


PROCEDURE NewItemFromInteger(VAR i: Item; v: LONGINT);
BEGIN
  NEW(i);  IF i # NIL THEN
    i.loc := lit;
    i.type := longint; i.kind := const; i.offset := v
  END
END NewItemFromInteger;


PROCEDURE emitLoad(x: Item);
BEGIN
  IF x.loc = reg THEN (* do nothing; we're already loaded *)
  ELSIF x.loc = mem THEN
    IF x.kind = lvar THEN
      put(RVAssem.ld(RH, SP, x.offset*DWordSize));
      x.offset := RH; incR
    ELSIF x.kind = gvar THEN
      put(RVAssem.ld(RH, SB, x.offset*DWordSize));
      x.offset := RH; incR
    ELSE ORS.Mark("Don't know how to load this in a register")
    END
  ELSIF x.loc = lit THEN
    IF (-2048 <= x.offset) & (x.offset < 2048) THEN
      put(RVAssem.addi(RH, 0, x.offset));
      x.offset := RH; incR
    ELSE
      lot[lotp] := x.offset;
      put(RVAssem.auipc(RH, 0));
      loft[loftp] := cp; INC(loftp);
      put(RVAssem.ld(RH, RH, lotp));
      INC(lotp);
      x.offset := RH; incR
    END
  ELSE ORS.Mark("Don't know how to load this in a register")
  END;
  x.loc := reg
END emitLoad;


PROCEDURE emitNegate(x: Item);
BEGIN
  put(RVAssem.xori(x.offset, x.offset, -1));
  put(RVAssem.addi(x.offset, x.offset, 1))
END emitNegate;


PROCEDURE negate(x: Item);
BEGIN
  IF x.loc = lit THEN x.offset := -x.offset
  ELSIF x.loc = reg THEN emitNegate(x)
  ELSIF x.loc = mem THEN emitLoad(x); emitNegate(x)
  ELSE ORS.Mark("Don't know how to negate this")
  END
END negate;


PROCEDURE factor(VAR x: Item);
VAR
  s: Symbol;
BEGIN
  x := NIL;
  IF sym = ORS.int THEN NewItemFromInteger(x, ORS.ival); ORS.Get(sym)
  ELSIF sym = ORS.ident THEN
    LookupSymbol(s, ORS.id); ORS.Get(sym);
    IF s = NIL THEN ORS.Mark("Unknown identifier")
    ELSE NewItemFromSymbol(x, s)
    END
  ELSE ORS.Mark("Factor expected")
  END
END factor;


PROCEDURE expression(VAR x: Item);
BEGIN
  IF sym = ORS.minus THEN
    ORS.Get(sym); factor(x); negate(x)
  ELSIF sym = ORS.plus THEN
    ORS.Get(sym); factor(x)
  ELSE
    factor(x)
  END
END expression;


PROCEDURE emitStore(x, y: Item);
BEGIN
  IF x = NIL THEN ORS.Mark("Compiler bug: NIL LHS for emitStore")
  ELSIF y = NIL THEN ORS.Mark("Compiler bug: NIL RHS for emitStore")
  ELSE
    IF x.kind = gvar THEN ORS.Mark("Not supported yet");
    ELSIF x.kind = lvar THEN
      IF x.loc = mem THEN
        IF y.loc = reg THEN
          put(RVAssem.sd(y.offset, SP, x.offset*DWordSize)); decR
        ELSIF y.loc IN {mem, lit} THEN
          emitLoad(y); emitStore(x, y);
        ELSE
          ORS.Mark("Unknown emitStore combination")
        END
      ELSIF x.loc = reg THEN
        IF y.loc = reg THEN put(RVAssem.add(x.offset, 0, y.offset)); decR; decR
        ELSIF y.loc IN {mem, lit} THEN emitLoad(y); emitStore(x, y)
        ELSE ORS.Mark("Unknown emitStore combination")
        END
      ELSE
        ORS.Mark("Cannot store into a literal")
      END
    ELSE ORS.Mark("Not supported yet")
    END
  END
END emitStore;


PROCEDURE emitBranchFalse(label: INTEGER; x: Item);
BEGIN
  IF x.loc = reg THEN put(RVAssem.beq(x.offset, 0, label)); decR
  ELSIF x.loc = mem THEN emitLoad(x); emitBranchFalse(label, x)
  ELSIF (x.loc = lit) & (x.offset = 0) THEN put(RVAssem.jal(0, label))
  ELSIF (x.loc = lit) THEN (* do nothing; it's true *)
  ELSE ORS.Mark("Don't know how to interpret branch for UNTIL")
  END
END emitBranchFalse;


PROCEDURE statements;
VAR
  s: Symbol;
  l, r: Item;
  done: BOOLEAN;
  L0: INTEGER; (* Label address *)
BEGIN
  done := FALSE;
  REPEAT
    IF sym = ORS.ident THEN (* procedure call or variable assignment *)
      LookupSymbol(s, ORS.id); ORS.Get(sym);
      IF s = NIL THEN ORS.Mark("Undefined symbol")
      ELSIF s.kind IN {gvar, lvar} THEN
        NewItemFromSymbol(l, s);
        Check(ORS.becomes, ":= expected"); expression(r);
        IF r = NIL THEN ORS.Mark("Compiler bug: nil expression on RHS") END;
        IF l.type = s.type THEN emitStore(l, r)
        ELSE ORS.Mark("Type mismatch")
        END
      ELSIF s.kind = proc THEN
        ORS.Mark("Procedure calls not yet implemented")
      ELSE
        ORS.Mark("Unknown construct")
      END
    ELSIF sym = ORS.repeat THEN (* REPEAT ... UNTIL cond *)
      L0 := cp; ORS.Get(sym); statements;
      IF sym # ORS.until THEN ORS.Mark("UNTIL expected");
      ELSE
        ORS.Get(sym); expression(l);
        IF l.type # bool THEN ORS.Mark("BOOLEAN expression needed")
        ELSE emitBranchFalse(L0, l);
        END
      END
    END;
    IF sym = ORS.semicolon THEN ORS.Get(sym)
    ELSE done := TRUE
    END
  UNTIL done;
END statements;


PROCEDURE emitProlog;
BEGIN
  put(RVAssem.addi(SP, SP, -dp*DWordSize));
  put(RVAssem.sd(RA, SP, 0));
END emitProlog;


PROCEDURE emitEpilog;
BEGIN
  put(RVAssem.ld(RA, SP, 0));
  put(RVAssem.addi(SP, SP, dp*DWordSize));
END emitEpilog;


PROCEDURE emitBareReturn;
BEGIN put(RVAssem.jalr(0, RA, 0));
END emitBareReturn;


PROCEDURE globalProcedure;
VAR
  procName: ORS.Ident;
  procSym: Symbol;
  dpBackup: INTEGER;
BEGIN
  IF sym # ORS.ident THEN ORS.Mark("Procedure name expected");
  ELSE
    ORS.CopyId(procName); ORS.Get(sym);
    Check(ORS.semicolon, "; expected");
    NewProcedureSymbol(procSym, procName, cp);
    dpBackup := dp;  dp := 1;	(* offset 0 reserved for return address *)
    INC(level);
    declarations(lvar);
    IF sym = ORS.begin THEN
      ORS.Get(sym);
      emitProlog; statements; emitEpilog
    END;
    Check(ORS.end, "END expected");
    IF sym # ORS.ident THEN ORS.Mark("Name of procedure expected")
    ELSIF ORS.id # procName THEN ORS.Mark("Name of procedure must match")
    ELSE ORS.Get(sym);
    END;
    Check(ORS.semicolon, "; expected");
    emitBareReturn;
    closeScope;
    dp := dpBackup;
  END
END globalProcedure;


PROCEDURE Module;
VAR
  modid: ORS.Ident;
  shortId, importId: ORS.Ident;
  smb: Symbol;
BEGIN
  Texts.WriteString(W, "  compiling ");
  ORS.Get(sym); IF sym # ORS.module THEN
    ORS.Mark("MODULE expected");
  ELSE
    ORS.Get(sym); IF sym = ORS.times THEN
      Texts.Write(W, "*"); ORS.Get(sym)
    ELSE ORS.Mark("Only ROM ABI modules supported right now.");
    END;

    IF sym = ORS.ident THEN
      ORS.CopyId(modid); ORS.Get(sym);
      Texts.WriteString(W, modid); Texts.WriteLn(W);
      Texts.Append(Oberon.Log, W.buf)
    ELSE ORS.Mark("identifier expected")
    END;
    Check(ORS.semicolon, "; expected");
    
    dp := 0; cp := 0; level := 0; RH := firstReg;

    (* Imports *)
    IF sym = ORS.import THEN
      ORS.Get(sym);
      WHILE sym = ORS.ident DO
        ORS.CopyId(shortId);
        ORS.CopyId(importId);
        ORS.Get(sym);
        IF sym = ORS.becomes THEN
          ORS.Get(sym);
          IF sym = ORS.ident THEN
            ORS.CopyId(importId);
            ORS.Get(sym);
          ELSE
            ORS.Mark("module name expected");
          END
        END;
        DoImport(shortId, importId);
        IF sym = ORS.comma THEN
          ORS.Get(sym);
        END
      END;
      Check(ORS.semicolon, "; expected");
    END;

    declarations(gvar);
    WHILE sym = ORS.procedure DO ORS.Get(sym); globalProcedure END;

    (* Module initialization *)

    Check(ORS.end, "END expected");
    IF sym = ORS.ident THEN
      IF ORS.id # modid THEN ORS.Mark("END name must match MODULE name.") END;
      ORS.Get(sym)
    ELSE ORS.Mark("identifier missing")
    END;
    Check(ORS.period, "MODULE..END terminates with a period.");

    IF ORS.errcnt # 0 THEN
      Texts.WriteLn(W); Texts.WriteString(W, "compilation FAILED");
    ELSE
      Texts.WriteString(W, "Compilation Statistics"); Texts.WriteLn(W);
      Texts.WriteString(W, "  Code:"); Texts.WriteInt(W, cp*WordSize, 0); Texts.WriteLn(W);
      Texts.WriteString(W, "  Data:"); Texts.WriteInt(W, dp*DWordSize, 0); Texts.WriteLn(W);
    END;
    appendLog
  END
END Module;


PROCEDURE Option(VAR S: Texts.Scanner);
BEGIN newSF := FALSE;
  IF S.nextCh = "/" THEN
    Texts.Scan(S); Texts.Scan(S);
    IF (S.class = Texts.Name) & (S.s[0] = "s") THEN newSF := TRUE END
  END
END Option;


PROCEDURE Compile*;
  VAR beg, end, time: LONGINT;
    T: Texts.Text;
    S: Texts.Scanner;
BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
  IF S.class = Texts.Char THEN
    IF S.c = "@" THEN
      Option(S); Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN ORS.Init(T, beg); Module END
    ELSIF S.c = "^" THEN
      Option(S); Oberon.GetSelection(T, beg, end, time);
      IF time >= 0 THEN
        Texts.OpenScanner(S, T, beg); Texts.Scan(S);
        IF S.class = Texts.Name THEN
          Texts.WriteString(W, S.s); NEW(T); Texts.Open(T, S.s);
          IF T.len > 0 THEN ORS.Init(T, 0); Module END
        END
      END
    END
  ELSE 
    WHILE S.class = Texts.Name DO
      NEW(T); Texts.Open(T, S.s);
      IF T.len > 0 THEN Option(S); ORS.Init(T, 0); Module
      ELSE Texts.WriteString(W, S.s); Texts.WriteString(W, " not found");
        Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
      END ;
      IF (T.len # 0) & (ORS.errcnt = 0) THEN Texts.Scan(S) ELSE S.class := 0 END
    END
  END ;
  Oberon.Collect(0)
END Compile;


PROCEDURE Bist*;
BEGIN
  BistSymTab;
END Bist;


BEGIN
  Texts.OpenWriter(W); Texts.WriteString(W, "RVO Compiler  2016 Feb");
  Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);

  dummyId := "INTEGER"; NewTypeSymbol(integer, dummyId, 8);
  dummyId := "LONGINT"; NewTypeSymbol(longint, dummyId, 8);
  dummyId := "SET"; NewTypeSymbol(set, dummyId, 8);
  dummyId := "BOOLEAN"; NewTypeSymbol(bool, dummyId, 1);
END RVOP.
