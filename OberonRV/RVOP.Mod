MODULE RVOP; (*N. Wirth 1.7.97 / 7.6.2014  Oberon compiler for RISC in Oberon-07*)
  IMPORT Texts, Oberon, ORS:=RVOS, ORB:=RVOB, ORG:=RVOG;

TYPE
  PtrBase = POINTER TO PtrBaseDesc;
  PtrBaseDesc = RECORD  (*list of names of pointer base types*)
    name: ORS.Ident; type: ORB.Type; next: PtrBase
  END ;
  
VAR
  W: Texts.Writer;      (* Output for logging/errors. *)

  newSF: BOOLEAN;       (* TRUE to generate a new symbol file; FALSE to validate *)
  modid: ORS.Ident;     (* Module name *)
  pbsList: PtrBase;     (* Track of forward type references for POINTER TO *)
  dummy: ORB.Object;    (* Used for constructing qualified identifiers *)

    sym,                (* Next symbol in source text *)
    version,            (* 0 for ROM image; 1 for system image *)
    dc,                 (* # of bytes taken by module-scope variables *)
    exno,               (* ID of next export; aka # of exports so far *)
    level               (* 0 for global scope; >0 for inner scopes *)
  : INTEGER;


(*
  These procedures are utilities to check aspects of the syntax.
*)


PROCEDURE Check(s: INTEGER; msg: ARRAY OF CHAR);
BEGIN
  IF sym = s THEN ORS.Get(sym) ELSE ORS.Mark(msg) END
END Check;


PROCEDURE Declarations(VAR varsize: LONGINT);
VAR obj, first: ORB.Object;
    x: ORG.Item; tp: ORB.Type; ptbase: PtrBase;
    expo: BOOLEAN; id: ORS.Ident;
BEGIN
  pbsList := NIL;
  IF (sym < ORS.const) & (sym # ORS.end) THEN (* try to sync w/ next decl *)
    ORS.Mark("Missing declaration?");
    REPEAT ORS.Get(sym) UNTIL (sym >= ORS.const) OR (sym = ORS.end)
  END ;

  (*
    CONST declarations
  *)

  IF sym = ORS.const THEN
    ORS.Get(sym);
    WHILE sym = ORS.ident DO
      ORS.CopyId(id); ORS.Get(sym); CheckExport(expo); Check(ORS.eql, "= ?");
      expression(x);
      IF (x.type.form = ORB.String) & (x.b = 2) THEN ORG.StrToChar(x) END;
      ORB.NewObj(obj, id, ORB.Const); obj.expo := expo;
      IF x.mode = ORB.Const THEN
        obj.val := x.a; obj.lev := x.b; obj.type := x.type
      ELSE
        ORS.Mark("expression not constant"); obj.type := ORB.intType
      END;
      Check(ORS.semicolon, "; missing")
    END
  END ;

(*
  (*
    TYPE declarations
    
    These MUST appear ahead of VAR declarations because these will actually
    allocate type descriptors in data space.
  *)

  IF sym = ORS.type THEN
    ORS.Get(sym);
    WHILE sym = ORS.ident DO
      ORS.CopyId(id); ORS.Get(sym); CheckExport(expo);
      IF sym = ORS.eql THEN ORS.Get(sym) ELSE ORS.Mark("=?") END ;
      Type(tp);
      ORB.NewObj(obj, id, ORB.Typ); obj.type := tp; obj.expo := expo; obj.lev := level; tp.typobj := obj;
      IF expo & (obj.type.form = ORB.Record) THEN obj.exno := exno; INC(exno) ELSE obj.exno := 0 END ;
      IF tp.form = ORB.Record THEN
        ptbase := pbsList;  (*check whether this is base of a pointer type; search and fixup*)
        WHILE ptbase # NIL DO
          IF obj.name = ptbase.name THEN ptbase.type.base := obj.type END ;
          ptbase := ptbase.next
        END ;
        IF level = 0 THEN ORG.BuildTD(tp, dc) END    (*type descriptor; len used as its address*)
      END ;
      Check(ORS.semicolon, "; missing")
    END
  END ;

  (* VAR declarations *)

  IF sym = ORS.var THEN
    ORS.Get(sym);
    WHILE sym = ORS.ident DO
      IdentList(ORB.Var, first); Type(tp);
      obj := first;
      WHILE obj # NIL DO
        obj.type := tp; obj.lev := level;
        IF tp.size > 1 THEN varsize := (varsize + 3) DIV 4 * 4 (*align*) END ;
        obj.val := varsize; varsize := varsize + obj.type.size;
        IF obj.expo THEN obj.exno := exno; INC(exno) END ;
        obj := obj.next
      END ;
      Check(ORS.semicolon, "; missing")
    END
  END ;
  varsize := (varsize + 3) DIV 4 * 4;
  ptbase := pbsList;
  WHILE ptbase # NIL DO
    IF ptbase.type.base.form = ORB.Int THEN ORS.Mark("undefined pointer base of") END ;
    ptbase := ptbase.next
  END ;
  IF (sym >= ORS.const) & (sym <= ORS.var) THEN ORS.Mark("declaration in bad order") END
*)
END Declarations;


PROCEDURE Module;
  VAR key: LONGINT;
    obj: ORB.Object;
    impid, impid1: ORS.Ident;
BEGIN
  Texts.WriteString(W, "  compiling "); ORS.Get(sym);
  IF sym = ORS.module THEN
    ORS.Get(sym);
    IF sym = ORS.times THEN version := 0; Texts.Write(W, "*"); ORS.Get(sym) ELSE version := 1 END ;
    ORB.Init; ORB.OpenScope;
    IF sym = ORS.ident THEN
      ORS.CopyId(modid); ORS.Get(sym);
      Texts.WriteString(W, modid); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
    ELSE ORS.Mark("identifier expected")
    END ;
    Check(ORS.semicolon, "no ;"); level := 0; dc := 0; exno := 1; key := 0;
    IF sym = ORS.import THEN
      ORS.Get(sym);
      WHILE sym = ORS.ident DO
        ORS.CopyId(impid); ORS.Get(sym);
        IF sym = ORS.becomes THEN
          ORS.Get(sym);
          IF sym = ORS.ident THEN ORS.CopyId(impid1); ORS.Get(sym)
          ELSE ORS.Mark("id expected")
          END
        ELSE impid1 := impid
        END ;
        ORB.Import(impid, impid1);
        IF sym = ORS.comma THEN ORS.Get(sym)
        ELSIF sym = ORS.ident THEN ORS.Mark("comma missing")
        END
      END ;
      Check(ORS.semicolon, "no ;")
    END ;
    obj := ORB.topScope.next;
    ORG.Open(version); Declarations(dc); (* ORG.SetDataSize((dc + 3) DIV 4 * 4); *)
    (*TODO WHILE sym = ORS.procedure DO ProcedureDecl; Check(ORS.semicolon, "no ;") END ; *)
    ORG.Header;
    (*TODO IF sym = ORS.begin THEN ORS.Get(sym); StatSequence END ; *)
    Check(ORS.end, "no END");
    IF sym = ORS.ident THEN
      IF ORS.id # modid THEN ORS.Mark("no match") END ;
      ORS.Get(sym)
    ELSE ORS.Mark("identifier missing")
    END ;
    IF sym # ORS.period THEN ORS.Mark("period missing") END ;
    IF (ORS.errcnt = 0) & (version # 0) THEN
      ORB.Export(modid, newSF, key);
      IF newSF THEN Texts.WriteString(W, " new symbol file") END
    END ;
    IF ORS.errcnt = 0 THEN
      ORG.Close(modid, key, exno);
      Texts.WriteString(W, "PC: "); Texts.WriteInt(W, ORG.pc, 6);
      Texts.WriteString(W, "  DC: "); Texts.WriteInt(W, dc, 6);
      Texts.WriteString(W, "  Key: "); Texts.WriteHex(W, key)
    ELSE Texts.WriteLn(W); Texts.WriteString(W, "compilation FAILED")
    END ;
    Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
    ORB.CloseScope; pbsList := NIL
  ELSE ORS.Mark("must start with MODULE")
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

BEGIN Texts.OpenWriter(W); Texts.WriteString(W, "OR Compiler  7.6.2014");
  Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
  NEW(dummy); dummy.class := ORB.Var; dummy.type := ORB.intType;
  (*TODO expression := expression0; Type := Type0; FormalType := FormalType0 *)
END RVOP.
