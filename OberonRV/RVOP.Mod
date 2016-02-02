MODULE RVOP; (* Oberon compiler for RISC-V in Oberon-07 *)
IMPORT Texts, Oberon, ORS:=RVOS;


TYPE
  Symbol = POINTER TO SymDesc;
  Constant = POINTER TO ConDesc;

  (* All symbols are of type SymDesc *)

  SymDesc = RECORD
    next: Symbol
  END;

  (* Constants are of ConDesc type. *)

  ConDesc = RECORD(SymDesc)
    name: ORS.Ident;	(* Name of the const identifier *)
    type: INTEGER;	(* Type of the value *)
    value: LONGINT;	(* integer value, string address *)
    exported: BOOLEAN;	(* TRUE if public *)
  END;


VAR
  W: Texts.Writer;    (* Output for logging/errors. *)
  newSF: BOOLEAN;     (* TRUE to replace/FALSE to validate against smb file *)
  sym: INTEGER;       (* Last fetched symbol classification *)
  symbols: Symbol;    (* Symbols in current scope *)


(*
  These procedures are utilities to check aspects of the syntax.
*)


PROCEDURE Check(s: INTEGER; msg: ARRAY OF CHAR);
BEGIN
  IF sym = s THEN ORS.Get(sym) ELSE ORS.Mark(msg) END
END Check;


PROCEDURE expression(VAR v: LONGINT);
BEGIN
  IF sym = ORS.int THEN v := ORS.ival; ORS.Get(sym)
  ELSE ORS.Mark("Integer value expected")
  END
END expression;


PROCEDURE Constants;
VAR
  constName: ORS.Ident;
  value: LONGINT;
  c: Constant;
  exported: BOOLEAN;
BEGIN
  WHILE sym = ORS.ident DO
    ORS.CopyId(constName);  ORS.Get(sym);
    exported := sym = ORS.times; IF exported THEN ORS.Get(sym) END;
    Check(ORS.eql, "Equation expected");
    expression(value);
    Check(ORS.semicolon, "; expected");
    NEW(c);  c.name := constName;  c.value := value;  c.exported := exported;
    c.next := symbols;  symbols := c;
  END
END Constants;


PROCEDURE Module;
VAR
  modid: ORS.Ident;
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
    
    (* Imports *)

    IF sym = ORS.const THEN ORS.Get(sym); Constants END;

    (* Procedures *)

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
    END;
    Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
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


BEGIN
  Texts.OpenWriter(W); Texts.WriteString(W, "RVO Compiler  2016 Feb");
  Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
END RVOP.
