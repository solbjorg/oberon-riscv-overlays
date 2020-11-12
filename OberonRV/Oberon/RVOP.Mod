MODULE RVOP; (*N. Wirth 1.7.97 / 7.6.2014  Oberon compiler for RISC in Oberon-07*)
  IMPORT Texts, Oberon, RVOS, RVOB, RVOG;
  (*Author: Niklaus Wirth, 2014.
    Parser of Oberon-RISC compiler. Uses Scanner RVOS to obtain symbols (tokens),
    RVOB for definition of data structures and for handling import and export, and
    RVOG to produce binary code. RVOP performs type checking and data allocation.
    Parser is target-independent, except for part of the handling of allocations.*)

  CONST
    IntegerSize = RVOB.IntegerSize;
    InsnSize = RVOB.InsnSize;
    BitsPerSet = RVOB.BitsPerSet;

    BytesForParameters = (RVOG.maxReg - RVOG.firstReg) * IntegerSize;

  TYPE PtrBase = POINTER TO PtrBaseDesc;
    PtrBaseDesc = RECORD  (*list of names of pointer base types*)
      name: RVOS.Ident; type: RVOB.Type; next: PtrBase
    END ;
  
  VAR sym: INTEGER;   (*last symbol read*)
    dc: LONGINT;    (*data counter*)
    level, exno, version: INTEGER;
    newSF: BOOLEAN;  (*option flag*)
    expression: PROCEDURE (VAR x: RVOG.Item);  (*to avoid forward reference*)
    Type: PROCEDURE (VAR type: RVOB.Type);
    FormalType: PROCEDURE (VAR typ: RVOB.Type; dim: INTEGER);
    modid: RVOS.Ident;
    pbsList: PtrBase;   (*list of names of pointer base types*)
    dummy: RVOB.Object;
    W: Texts.Writer;

PROCEDURE RoundUp(x: INTEGER): INTEGER;
BEGIN RETURN (x + (IntegerSize-1)) DIV IntegerSize * IntegerSize
END RoundUp;

  PROCEDURE Check(s: INTEGER; msg: ARRAY OF CHAR);
  BEGIN
    IF sym = s THEN RVOS.Get(sym) ELSE RVOS.Mark(msg) END
  END Check;

  PROCEDURE qualident(VAR obj: RVOB.Object);
  BEGIN obj := RVOB.thisObj(); RVOS.Get(sym);
    IF obj = NIL THEN RVOS.Mark("undef"); obj := dummy END ;
    IF (sym = RVOS.period) & (obj.class = RVOB.Mod) THEN
      RVOS.Get(sym);
      IF sym = RVOS.ident THEN obj := RVOB.thisimport(obj); RVOS.Get(sym);
        IF obj = NIL THEN RVOS.Mark("undef"); obj := dummy END
      ELSE RVOS.Mark("identifier expected"); obj := dummy
      END
    END
  END qualident;

  PROCEDURE CheckBool(VAR x: RVOG.Item);
  BEGIN
    IF x.type.form # RVOB.Bool THEN RVOS.Mark("not Boolean"); x.type := RVOB.boolType END
  END CheckBool;

  PROCEDURE CheckInt(VAR x: RVOG.Item);
  BEGIN
    IF x.type.form # RVOB.Int THEN RVOS.Mark("not Integer"); x.type := RVOB.intType END
  END CheckInt;

  PROCEDURE CheckIntOrSet(VAR x: RVOG.Item);
  BEGIN
    IF (x.type.form # RVOB.Int) & (x.type.form # RVOB.Set) THEN
      RVOS.Mark("neither integer nor set"); x.type := RVOB.intType
    END
  END CheckIntOrSet;

  PROCEDURE CheckReal(VAR x: RVOG.Item);
  BEGIN
    IF x.type.form # RVOB.Real THEN RVOS.Mark("not Real"); x.type := RVOB.realType END
  END CheckReal;

  PROCEDURE CheckSet(VAR x: RVOG.Item);
  BEGIN
    IF x.type.form # RVOB.Set THEN RVOS.Mark("not Set"); x.type := RVOB.setType END
  END CheckSet;

  PROCEDURE CheckSetVal(VAR x: RVOG.Item);
  BEGIN
    IF x.type.form # RVOB.Int THEN RVOS.Mark("not Int"); x.type := RVOB.setType
    ELSIF x.mode = RVOB.Const THEN
      IF (x.a < 0) OR (x.a >= BitsPerSet) THEN RVOS.Mark("invalid set") END
    END 
  END CheckSetVal;

  PROCEDURE CheckConst(VAR x: RVOG.Item);
  BEGIN
    IF x.mode # RVOB.Const THEN RVOS.Mark("not a constant"); x.mode := RVOB.Const END
  END CheckConst;

  PROCEDURE CheckReadOnly(VAR x: RVOG.Item);
  BEGIN
    IF x.rdo THEN RVOS.Mark("read-only") END
  END CheckReadOnly;

  PROCEDURE CheckExport(VAR expo: BOOLEAN);
  BEGIN
    IF sym = RVOS.times THEN
      expo := TRUE; RVOS.Get(sym);
      IF level # 0 THEN RVOS.Mark("remove asterisk") END
    ELSE expo := FALSE
    END
  END CheckExport;

  PROCEDURE IsExtension(t0, t1: RVOB.Type): BOOLEAN;
  BEGIN (*t1 is an extension of t0*)
    RETURN (t0 = t1) OR (t1 # NIL) & IsExtension(t0, t1.base)
  END IsExtension;

  (* expressions *)

  PROCEDURE TypeTest(VAR x: RVOG.Item; T: RVOB.Type; guard: BOOLEAN);
    VAR xt: RVOB.Type;
  BEGIN xt := x.type;
    WHILE (xt # T) & (xt # NIL) DO xt := xt.base END ;
    IF xt # T THEN xt := x.type;
      IF (xt.form = RVOB.Pointer) & (T.form = RVOB.Pointer) THEN
        IF IsExtension(xt.base, T.base) THEN RVOG.TypeTest(x, T.base, FALSE, guard); x.type := T
        ELSE RVOS.Mark("not an extension")
        END
      ELSIF (xt.form = RVOB.Record) & (T.form = RVOB.Record) & (x.mode = RVOB.Par) THEN
        IF IsExtension(xt, T) THEN  RVOG.TypeTest(x, T, TRUE, guard); x.type := T
        ELSE RVOS.Mark("not an extension")
        END
      ELSE RVOS.Mark("incompatible types")
      END
    ELSIF ~guard THEN RVOG.MakeConstItem(x, RVOB.boolType, 1)
    END ;
    IF ~guard THEN x.type := RVOB.boolType END
  END TypeTest;

  PROCEDURE selector(VAR x: RVOG.Item);
    VAR y: RVOG.Item; obj: RVOB.Object;
  BEGIN
    WHILE (sym = RVOS.lbrak) OR (sym = RVOS.period) OR (sym = RVOS.arrow)
        OR (sym = RVOS.lparen) & (x.type.form IN {RVOB.Record, RVOB.Pointer}) DO
      IF sym = RVOS.lbrak THEN
        REPEAT RVOS.Get(sym); expression(y);
          IF x.type.form = RVOB.Array THEN
            CheckInt(y); RVOG.Index(x, y); x.type := x.type.base
          ELSE RVOS.Mark("not an array")
          END
        UNTIL sym # RVOS.comma;
        Check(RVOS.rbrak, "no ]")
      ELSIF sym = RVOS.period THEN RVOS.Get(sym);
        IF sym = RVOS.ident THEN
          IF x.type.form = RVOB.Pointer THEN RVOG.DeRef(x); x.type := x.type.base END ;
          IF x.type.form = RVOB.Record THEN
            obj := RVOB.thisfield(x.type); RVOS.Get(sym);
            IF obj # NIL THEN RVOG.Field(x, obj); x.type := obj.type
            ELSE RVOS.Mark("undef")
            END
          ELSE RVOS.Mark("not a record")
          END
        ELSE RVOS.Mark("ident?")
        END
      ELSIF sym = RVOS.arrow THEN
        RVOS.Get(sym);
        IF x.type.form = RVOB.Pointer THEN RVOG.DeRef(x); x.type := x.type.base
        ELSE RVOS.Mark("not a pointer")
        END
      ELSIF (sym = RVOS.lparen) & (x.type.form IN {RVOB.Record, RVOB.Pointer}) THEN (*type guard*)
        RVOS.Get(sym);
        IF sym = RVOS.ident THEN
          qualident(obj);
          IF obj.class = RVOB.Typ THEN TypeTest(x, obj.type, TRUE)
          ELSE RVOS.Mark("guard type expected")
          END
        ELSE RVOS.Mark("not an identifier")
        END ;
        Check(RVOS.rparen, " ) missing")
      END
    END
  END selector;

  PROCEDURE CompTypes(t0, t1: RVOB.Type; varpar: BOOLEAN): BOOLEAN;

    PROCEDURE EqualSignatures(t0, t1: RVOB.Type): BOOLEAN;
      VAR p0, p1: RVOB.Object; com: BOOLEAN;
    BEGIN com := TRUE;
      IF (t0.base = t1.base) & (t0.nofpar = t1.nofpar) THEN
        p0 := t0.dsc; p1 := t1.dsc;
        WHILE p0 # NIL DO
          IF (p0.class = p1.class) & CompTypes(p0.type, p1.type, TRUE) & (ORD(p0.rdo) = ORD(p1.rdo)) THEN
            IF p0.type.form >= RVOB.Array THEN com := CompTypes(p0.type, p1.type, (p0.class = RVOB.Par)) END ;
            p0 := p0.next; p1 := p1.next
          ELSE p0 := NIL; com := FALSE
          END
        END
      ELSE com := FALSE
      END ;
      RETURN com
    END EqualSignatures;
  
  BEGIN (*Compatible Types*)
    RETURN (t0 = t1)
      OR (t0.form = RVOB.Array) & (t1.form = RVOB.Array) & CompTypes(t0.base, t1.base, varpar)
      OR (t0.form = RVOB.Pointer) & (t1.form = RVOB.Pointer) & IsExtension(t0.base, t1.base)
      OR (t0.form = RVOB.Record) & (t1.form = RVOB.Record) & IsExtension(t0, t1)
      OR (t0.form = RVOB.Proc) & (t1.form = RVOB.Proc) & EqualSignatures(t0, t1)
      OR (t0.form IN {RVOB.Pointer, RVOB.Proc}) & (t1.form = RVOB.NilTyp)
      OR (t0.form = RVOB.NilTyp) & (t1.form IN {RVOB.Pointer, RVOB.Proc})
      OR ~varpar & (t0.form = RVOB.Int) & (t1.form = RVOB.Int)
  END CompTypes;

  PROCEDURE Parameter(par: RVOB.Object);
    VAR x: RVOG.Item; varpar: BOOLEAN;
  BEGIN expression(x);
    IF par # NIL THEN
      varpar := par.class = RVOB.Par;

      IF CompTypes(par.type, x.type, varpar) THEN
        IF ~varpar THEN RVOG.ValueParam(x)
        ELSE (*par.class = Par*)
          IF ~par.rdo THEN CheckReadOnly(x) END ;
          RVOG.VarParam(x, par.type)
        END
      ELSIF ~varpar & (par.type.form = RVOB.Int) & (x.type.form = RVOB.Int) THEN
        RVOG.ValueParam(x) 
      ELSIF (x.type.form = RVOB.String) & (x.b = 2) & (par.class = RVOB.Var) & (par.type.form = RVOB.Char) THEN
        RVOG.StrToChar(x); RVOG.ValueParam(x)
      ELSIF (x.type.form = RVOB.Array) & (par.type.form = RVOB.Array) &
          (x.type.base.form = par.type.base.form) & (par.type.len < 0) THEN
        RVOG.OpenArrayParam(x);
      ELSIF (x.type.form = RVOB.String) & varpar & par.rdo & (par.type.form = RVOB.Array) &
          (par.type.base.form = RVOB.Char) & (par.type.len < 0) THEN RVOG.StringParam(x)
      ELSIF (par.type.form = RVOB.Array) & (par.type.base.form = RVOB.Int) & (par.type.size = x.type.size) THEN
        RVOG.VarParam(x, par.type)
      ELSE RVOS.Mark("incompatible parameters")
      END
    END
  END Parameter;

  PROCEDURE ParamList(VAR x: RVOG.Item);
    VAR n: INTEGER; par: RVOB.Object;
  BEGIN par := x.type.dsc; n := 0;
    IF sym # RVOS.rparen THEN
      Parameter(par); n := 1;
      WHILE sym <= RVOS.comma DO
        Check(sym, "comma?");
        IF par # NIL THEN par := par.next END ;
        INC(n); Parameter(par)
      END ;
      Check(RVOS.rparen, ") missing")
    ELSE RVOS.Get(sym);
    END ;
    IF n < x.type.nofpar THEN RVOS.Mark("too few params")
    ELSIF n > x.type.nofpar THEN RVOS.Mark("too many params")
    END
  END ParamList;

  PROCEDURE StandFunc(VAR x: RVOG.Item; fct: LONGINT; restyp: RVOB.Type);
    VAR y: RVOG.Item; n, npar: LONGINT;
  BEGIN Check(RVOS.lparen, "no (");
    npar := fct MOD 10; fct := fct DIV 10; expression(x); n := 1;
    WHILE sym = RVOS.comma DO RVOS.Get(sym); expression(y); INC(n) END ;
    Check(RVOS.rparen, "no )");
    IF n = npar THEN
      IF fct = 0 THEN (*ABS*)
        IF x.type.form IN {RVOB.Int, RVOB.Real} THEN RVOG.Abs(x); restyp := x.type ELSE RVOS.Mark("bad type") END
      ELSIF fct = 1 THEN (*ODD*) CheckInt(x); RVOG.Odd(x)
      ELSIF fct = 2 THEN (*FLOOR*) CheckReal(x); RVOG.Floor(x)
      ELSIF fct = 3 THEN (*FLT*) CheckInt(x); RVOG.Float(x)
      ELSIF fct = 4 THEN (*ORD*)
        IF x.type.form <= RVOB.Proc THEN RVOG.Ord(x)
        ELSIF (x.type.form = RVOB.String) & (x.b = 2) THEN RVOG.StrToChar(x)
        ELSE RVOS.Mark("bad type")
        END
      ELSIF fct = 5 THEN (*CHR*) CheckInt(x); RVOG.Ord(x)
      ELSIF fct = 6 THEN (*LEN*)
          IF x.type.form = RVOB.Array THEN RVOG.Len(x) ELSE RVOS.Mark("not an array") END
      ELSIF fct IN {7, 8, 9} THEN (*LSL, ASR, ROR*) CheckInt(y);
        IF x.type.form IN {RVOB.Int, RVOB.Set} THEN RVOG.Shift(fct-7, x, y); restyp := x.type ELSE RVOS.Mark("bad type") END
      ELSIF fct = 11 THEN (*ADC*) RVOS.Mark("no ADC")
      ELSIF fct = 12 THEN (*SBC*) RVOS.Mark("no SBC")
      ELSIF fct = 13 THEN (*UML*) RVOS.Mark("no UML")
      ELSIF fct = 14 THEN (*BIT*) CheckInt(x); CheckInt(y); RVOG.Bit(x, y)
      ELSIF fct = 15 THEN (*REG*) CheckConst(x); CheckInt(x); RVOG.Register(x)
      ELSIF fct = 16 THEN (*VAL*)
        IF (x.mode= RVOB.Typ) & (x.type.size <= y.type.size) THEN restyp := x.type; x := y
        ELSE RVOS.Mark("casting not allowed")
        END
      ELSIF fct = 17 THEN (*ADR*) RVOG.Adr(x)
      ELSIF fct = 18 THEN (*SIZE*)
        IF x.mode = RVOB.Typ THEN RVOG.MakeConstItem(x, RVOB.intType, x.type.size)
        ELSE RVOS.Mark("must be a type")
        END
      ELSIF fct IN {19, 20, 21} THEN
        CheckConst(x); CheckInt(x); CheckIntOrSet(y); RVOG.CSRop(fct-19, x, y);
      ELSIF fct = 19 THEN (*COND*) RVOS.Mark("no COND")
      ELSIF fct = 20 THEN (*H*) RVOS.Mark("no H")
      END ;
      x.type := restyp
    ELSE RVOS.Mark("wrong nof params")
    END
  END StandFunc;

  PROCEDURE element(VAR x: RVOG.Item);
    VAR y: RVOG.Item;
  BEGIN expression(x); CheckSetVal(x);
    IF sym = RVOS.upto THEN RVOS.Get(sym); expression(y); CheckSetVal(y); RVOG.Set(x, y)
    ELSE RVOG.Singleton(x)
    END ;
    x.type := RVOB.setType
  END element;
  
  PROCEDURE set(VAR x: RVOG.Item);
    VAR y: RVOG.Item;
  BEGIN
    IF sym >= RVOS.if THEN
      IF sym # RVOS.rbrace THEN RVOS.Mark(" } missing") END ;
      RVOG.MakeConstItem(x, RVOB.setType, 0) (*empty set*)
    ELSE element(x);
      WHILE (sym < RVOS.rparen) OR (sym > RVOS.rbrace) DO
        IF sym = RVOS.comma THEN RVOS.Get(sym)
        ELSIF sym # RVOS.rbrace THEN RVOS.Mark("missing comma")
        END ;
        element(y); RVOG.SetOp(RVOS.plus, x, y)
      END
    END
  END set; 

  PROCEDURE factor(VAR x: RVOG.Item);
    VAR obj: RVOB.Object; rx: LONGINT;
  BEGIN (*sync*)
    IF (sym < RVOS.char) OR (sym > RVOS.ident) THEN RVOS.Mark("expression expected");
      REPEAT RVOS.Get(sym) UNTIL (sym >= RVOS.char) & (sym <= RVOS.ident)
    END ;
    IF sym = RVOS.ident THEN
      qualident(obj);  
      IF obj.class = RVOB.SFunc THEN StandFunc(x, obj.val, obj.type)
      ELSE RVOG.MakeItem(x, obj, level); selector(x);
        IF sym = RVOS.lparen THEN
          RVOS.Get(sym);
          IF (x.type.form = RVOB.Proc) & (x.type.base.form # RVOB.NoTyp) THEN
            RVOG.PrepCall(x, rx); ParamList(x); RVOG.Call(x, rx); x.type := x.type.base
          ELSE RVOS.Mark("not a function"); ParamList(x)
          END
        END
      END
    ELSIF sym = RVOS.int THEN RVOG.MakeConstItem(x, RVOB.intType, RVOS.ival); RVOS.Get(sym)
      (*ELSIF sym = RVOS.real THEN RVOG.MakeRealItem(x, RVOS.rval); RVOS.Get(sym)*)
    ELSIF sym = RVOS.char THEN RVOG.MakeConstItem(x, RVOB.charType, RVOS.ival); RVOS.Get(sym)
    ELSIF sym = RVOS.nil THEN RVOS.Get(sym); RVOG.MakeConstItem(x, RVOB.nilType, 0)
    ELSIF sym = RVOS.string THEN RVOG.MakeStringItem(x, RVOS.slen); RVOS.Get(sym)
    ELSIF sym = RVOS.lparen THEN RVOS.Get(sym); expression(x); Check(RVOS.rparen, "no )")
    ELSIF sym = RVOS.lbrace THEN RVOS.Get(sym); set(x); Check(RVOS.rbrace, "no }")
    ELSIF sym = RVOS.not THEN RVOS.Get(sym); factor(x); CheckBool(x); RVOG.Not(x)
    ELSIF sym = RVOS.false THEN RVOS.Get(sym); RVOG.MakeConstItem(x, RVOB.boolType, 0)
    ELSIF sym = RVOS.true THEN RVOS.Get(sym); RVOG.MakeConstItem(x, RVOB.boolType, 1)
    ELSE RVOS.Mark("not a factor"); RVOG.MakeItem(x, NIL, level)
    END
  END factor;

  PROCEDURE term(VAR x: RVOG.Item);
    VAR y: RVOG.Item; op, f: INTEGER;
  BEGIN factor(x); f := x.type.form;
    WHILE (sym >= RVOS.times) & (sym <= RVOS.and) DO
      op := sym; RVOS.Get(sym);
      IF op = RVOS.times THEN
        IF f = RVOB.Int THEN factor(y); CheckInt(y); RVOG.MulOp(x, y)
        ELSIF f = RVOB.Real THEN factor(y); CheckReal(y); RVOG.RealOp(op, x, y)
        ELSIF f = RVOB.Set THEN factor(y); CheckSet(y); RVOG.SetOp(op, x, y)
        ELSE RVOS.Mark("bad type")
        END
      ELSIF (op = RVOS.div) OR (op = RVOS.mod) THEN
        CheckInt(x); factor(y); CheckInt(y); RVOG.DivOp(op, x, y)
      ELSIF op = RVOS.rdiv THEN
        IF f = RVOB.Real THEN factor(y); CheckReal(y); RVOG.RealOp(op, x, y)
        ELSIF f = RVOB.Set THEN factor(y); CheckSet(y); RVOG.SetOp(op, x, y)
        ELSE RVOS.Mark("bad type")
        END
      ELSE (*op = and*) CheckBool(x); RVOG.And1(x); factor(y); CheckBool(y); RVOG.And2(x, y)
      END
    END
  END term;

  PROCEDURE SimpleExpression(VAR x: RVOG.Item);
    VAR y: RVOG.Item; op: INTEGER;
  BEGIN
    IF sym = RVOS.minus THEN RVOS.Get(sym); term(x);
      IF x.type.form IN {RVOB.Int, RVOB.Real, RVOB.Set} THEN RVOG.Neg(x) ELSE CheckInt(x) END
    ELSIF sym = RVOS.plus THEN RVOS.Get(sym); term(x);
    ELSE term(x)
    END ;
    WHILE (sym >= RVOS.plus) & (sym <= RVOS.or) DO
      op := sym; RVOS.Get(sym);
      IF op = RVOS.or THEN RVOG.Or1(x); CheckBool(x); term(y); CheckBool(y); RVOG.Or2(x, y)
      ELSIF x.type.form = RVOB.Int THEN term(y); CheckInt(y); RVOG.AddOp(op, x, y)
      ELSIF x.type.form = RVOB.Real THEN term(y); CheckReal(y); RVOG.RealOp(op, x, y)
      ELSE CheckSet(x); term(y); CheckSet(y); RVOG.SetOp(op, x, y)
      END
    END
  END SimpleExpression;

  PROCEDURE expression0(VAR x: RVOG.Item);
    VAR y: RVOG.Item; obj: RVOB.Object; rel, xf, yf: INTEGER;
  BEGIN SimpleExpression(x);
    IF (sym >= RVOS.eql) & (sym <= RVOS.geq) THEN
      rel := sym; RVOS.Get(sym); SimpleExpression(y); xf := x.type.form; yf := y.type.form;
      IF CompTypes(x.type, y.type, FALSE) OR
          (xf = RVOB.Pointer) & (yf = RVOB.Pointer) & IsExtension(y.type.base, x.type.base) THEN
        IF (xf IN {RVOB.Char, RVOB.Int}) THEN RVOG.IntRelation(rel, x, y)
        ELSIF xf = RVOB.Real THEN RVOG.RealRelation(rel, x, y)
        ELSIF xf = RVOB.Set THEN RVOG.SetRelation(rel, x, y)
        ELSIF (xf IN {RVOB.Pointer, RVOB.Proc, RVOB.NilTyp}) THEN
          IF rel <= RVOS.neq THEN RVOG.IntRelation(rel, x, y) ELSE RVOS.Mark("only = or #") END
        ELSIF (xf = RVOB.Array) & (x.type.base.form = RVOB.Char) OR (xf = RVOB.String) THEN
          RVOG.StringRelation(rel, x, y)
        ELSE RVOS.Mark("illegal comparison")
        END
      ELSIF (xf = RVOB.Array) & (x.type.base.form = RVOB.Char) &
            ((yf = RVOB.String) OR (yf = RVOB.Array) & (y.type.base.form = RVOB.Char))
          OR (yf = RVOB.Array) & (y.type.base.form = RVOB.Char) & (xf = RVOB.String) THEN
        RVOG.StringRelation(rel, x, y)
      ELSIF (xf = RVOB.Char) & (yf = RVOB.String) & (y.b = 2) THEN
        RVOG.StrToChar(y); RVOG.IntRelation(rel, x, y)
      ELSIF (yf = RVOB.Char) & (xf = RVOB.String) & (x.b = 2) THEN
        RVOG.StrToChar(x); RVOG.IntRelation(rel, x, y)
      ELSE RVOS.Mark("illegal comparison")
      END ;
      x.type := RVOB.boolType
    ELSIF sym = RVOS.in THEN
      RVOS.Get(sym); SimpleExpression(y);
      IF (x.type.form = RVOB.Int) & (y.type.form = RVOB.Set) THEN RVOG.In(x, y)
      ELSE RVOS.Mark("illegal operands of IN")
      END ;
      x.type := RVOB.boolType
    ELSIF sym = RVOS.is THEN
      RVOS.Get(sym); qualident(obj); TypeTest(x, obj.type, FALSE) ;
      x.type := RVOB.boolType
    END
  END expression0;

  (* statements *)

  PROCEDURE StandProc(pno: LONGINT);
    VAR nap, npar: LONGINT; (*nof actual/formal parameters*)
      x, y, z: RVOG.Item;
  BEGIN Check(RVOS.lparen, "no (");
    npar := pno MOD 10; pno := pno DIV 10; expression(x); nap := 1;
    IF sym = RVOS.comma THEN
      RVOS.Get(sym); expression(y); nap := 2; z.type := RVOB.noType;
      WHILE sym = RVOS.comma DO RVOS.Get(sym); expression(z); INC(nap) END
    ELSE y.type := RVOB.noType
    END ;
    Check(RVOS.rparen, "no )");
    IF (npar = nap) OR (pno IN {0, 1}) THEN 
      IF pno IN {0, 1} THEN (*INC, DEC*)
        CheckInt(x); CheckReadOnly(x);
        IF y.type # RVOB.noType THEN CheckInt(y) END ;
        RVOG.Increment(pno, x, y)
      ELSIF pno IN {2, 3} THEN (*INCL, EXCL*)
        CheckSet(x); CheckReadOnly(x); CheckInt(y); RVOG.Include(pno-2, x, y)
      ELSIF pno = 4 THEN CheckBool(x); RVOG.Assert(x)
      ELSIF pno = 5 THEN(*NEW*) CheckReadOnly(x);
         IF (x.type.form = RVOB.Pointer) & (x.type.base.form = RVOB.Record) THEN RVOG.New(x)
         ELSE RVOS.Mark("not a pointer to record")
         END
      ELSIF pno = 6 THEN CheckReal(x); CheckInt(y); CheckReadOnly(x); RVOG.Pack(x, y)
      ELSIF pno = 7 THEN CheckReal(x); CheckInt(y); CheckReadOnly(x); RVOG.Unpk(x, y)
      ELSIF pno = 8 THEN
        IF x.type.form <= RVOB.Set THEN RVOG.Led(x) ELSE RVOS.Mark("bad type") END
      ELSIF pno = 10 THEN CheckInt(x); RVOG.Get(x, y)
      ELSIF pno = 11 THEN CheckInt(x); RVOG.Put(x, y)
      ELSIF pno = 12 THEN CheckInt(x); CheckInt(y); CheckInt(z); RVOG.Copy(x, y, z)
      ELSIF pno = 13 THEN CheckConst(x); CheckInt(x); RVOG.LDPSR(x)
      ELSIF pno = 14 THEN CheckInt(x); RVOG.LDREG(x, y)
      END
    ELSE RVOS.Mark("wrong nof parameters")
    END
  END StandProc;

  PROCEDURE StatSequence;
    VAR obj: RVOB.Object;
      orgtype: RVOB.Type; (*original type of case var*)
      x, y, z, w: RVOG.Item;
      L0, L1, rx: LONGINT;

    PROCEDURE TypeCase(obj: RVOB.Object; VAR x: RVOG.Item);
      VAR typobj: RVOB.Object;
    BEGIN
      IF sym = RVOS.ident THEN
        qualident(typobj); RVOG.MakeItem(x, obj, level);
        IF typobj.class # RVOB.Typ THEN RVOS.Mark("not a type") END ;
        TypeTest(x, typobj.type, FALSE); obj.type := typobj.type;
        RVOG.CFJump(x); Check(RVOS.colon, ": expected"); StatSequence
      ELSE RVOG.CFJump(x); RVOS.Mark("type id expected")
      END
     END TypeCase;

    PROCEDURE SkipCase;
    BEGIN 
      WHILE sym # RVOS.colon DO RVOS.Get(sym) END ;
      RVOS.Get(sym); StatSequence
    END SkipCase;

  BEGIN (* StatSequence *)
    REPEAT (*sync*) obj := NIL;
      IF ~((sym = RVOS.ident) OR (sym >= RVOS.if) & (sym <= RVOS.for) OR (sym >= RVOS.semicolon)) THEN
        RVOS.Mark("statement expected");
        REPEAT RVOS.Get(sym) UNTIL (sym = RVOS.ident) OR (sym >= RVOS.if)
      END ;
      IF sym = RVOS.ident THEN
        qualident(obj); RVOG.MakeItem(x, obj, level);
        IF x.mode = RVOB.SProc THEN StandProc(obj.val)
        ELSE selector(x);
          IF sym = RVOS.becomes THEN (*assignment*)
            RVOS.Get(sym); CheckReadOnly(x); expression(y);
            IF CompTypes(x.type, y.type, FALSE) OR (x.type.form = RVOB.Int) & (y.type.form = RVOB.Int) THEN
              IF (x.type.form <= RVOB.Pointer) OR (x.type.form = RVOB.Proc) THEN RVOG.Store(x, y)
              ELSIF y.type.size # 0 THEN RVOG.StoreStruct(x, y)
              END
            ELSIF (x.type.form = RVOB.Char) & (y.type.form = RVOB.String) & (y.b = 2) THEN
              RVOG.StrToChar(y); RVOG.Store(x, y)
            ELSIF (x.type.form = RVOB.Array) & (x.type.base.form = RVOB.Char) &
                (y.type.form = RVOB.String) THEN RVOG.CopyString(y, x)
            ELSE RVOS.Mark("illegal assignment")
            END
          ELSIF sym = RVOS.eql THEN RVOS.Mark("should be :="); RVOS.Get(sym); expression(y)
          ELSIF sym = RVOS.lparen THEN (*procedure call*)
            RVOS.Get(sym);
            IF (x.type.form = RVOB.Proc) & (x.type.base.form = RVOB.NoTyp) THEN
              RVOG.PrepCall(x, rx); ParamList(x); RVOG.Call(x, rx)
            ELSE RVOS.Mark("not a procedure"); ParamList(x)
            END
          ELSIF x.type.form = RVOB.Proc THEN (*procedure call without parameters*)
            IF x.type.nofpar > 0 THEN RVOS.Mark("missing parameters") END ;
            IF x.type.base.form = RVOB.NoTyp THEN RVOG.PrepCall(x, rx); RVOG.Call(x, rx) ELSE RVOS.Mark("not a procedure") END
          ELSIF x.mode = RVOB.Typ THEN RVOS.Mark("illegal assignment")
          ELSE RVOS.Mark("not a procedure")
          END
        END
      ELSIF sym = RVOS.if THEN
        RVOS.Get(sym); expression(x); CheckBool(x); RVOG.CFJump(x);
        Check(RVOS.then, "no THEN");
        StatSequence; L0 := 0;
        WHILE sym = RVOS.elsif DO
          RVOS.Get(sym); RVOG.FJump(L0); RVOG.Fixup(x); expression(x); CheckBool(x);
          RVOG.CFJump(x); Check(RVOS.then, "no THEN"); StatSequence
        END ;
        IF sym = RVOS.else THEN RVOS.Get(sym); RVOG.FJump(L0); RVOG.Fixup(x); StatSequence
        ELSE RVOG.Fixup(x)
        END ;
        RVOG.FixLink(L0); Check(RVOS.end, "no END")
      ELSIF sym = RVOS.while THEN
        RVOS.Get(sym); L0 := RVOG.Here(); expression(x); CheckBool(x); RVOG.CFJump(x);
        Check(RVOS.do, "no DO"); StatSequence; RVOG.BJump(L0);
        WHILE sym = RVOS.elsif DO
          RVOS.Get(sym); RVOG.Fixup(x); expression(x); CheckBool(x); RVOG.CFJump(x);
          Check(RVOS.do, "no DO"); StatSequence; RVOG.BJump(L0)
        END ;
        RVOG.Fixup(x); Check(RVOS.end, "no END")
      ELSIF sym = RVOS.repeat THEN
        RVOS.Get(sym); L0 := RVOG.Here(); StatSequence;
        IF sym = RVOS.until THEN
          RVOS.Get(sym); expression(x); CheckBool(x); RVOG.CBJump(x, L0)
        ELSE RVOS.Mark("missing UNTIL")
        END
      ELSIF sym = RVOS.for THEN
        RVOS.Get(sym);
        IF sym = RVOS.ident THEN
          qualident(obj); RVOG.MakeItem(x, obj, level); CheckInt(x); CheckReadOnly(x);
          IF sym = RVOS.becomes THEN
            RVOS.Get(sym); expression(y); CheckInt(y); RVOG.For0(x, y); L0 := RVOG.Here();
            Check(RVOS.to, "no TO"); expression(z); CheckInt(z); obj.rdo := TRUE;
            IF sym = RVOS.by THEN RVOS.Get(sym); expression(w); CheckConst(w); CheckInt(w)
            ELSE RVOG.MakeConstItem(w, RVOB.intType, 1)
            END ;
            Check(RVOS.do, "no DO"); RVOG.For1(x, y, z, w, L1);
            StatSequence; Check(RVOS.end, "no END");
            RVOG.For2(x, y, w); RVOG.BJump(L0); RVOG.FixLink(L1); obj.rdo := FALSE
          ELSE RVOS.Mark(":= expected")
          END
        ELSE RVOS.Mark("identifier expected")
        END
      ELSIF sym = RVOS.case THEN
        RVOS.Get(sym);
        IF sym = RVOS.ident THEN
          qualident(obj); orgtype := obj.type;
          IF (orgtype.form = RVOB.Pointer) OR (orgtype.form = RVOB.Record) & (obj.class = RVOB.Par) THEN
            Check(RVOS.of, "OF expected"); TypeCase(obj, x); L0 := 0;
            WHILE sym = RVOS.bar DO
              RVOS.Get(sym); RVOG.FJump(L0); RVOG.Fixup(x); obj.type := orgtype; TypeCase(obj, x)
            END ;
            RVOG.Fixup(x); RVOG.FixLink(L0); obj.type := orgtype
          ELSE RVOS.Mark("numeric case not implemented");
            Check(RVOS.of, "OF expected"); SkipCase;
            WHILE sym = RVOS.bar DO SkipCase END
          END
        ELSE RVOS.Mark("ident expected")
        END ;
        Check(RVOS.end, "no END")
      END ;
      RVOG.CheckRegs;
      IF sym = RVOS.semicolon THEN RVOS.Get(sym)
      ELSIF sym < RVOS.semicolon THEN RVOS.Mark("missing semicolon?")
      END
    UNTIL sym > RVOS.semicolon
  END StatSequence;

  (* Types and declarations *)

  PROCEDURE IdentList(class: INTEGER; VAR first: RVOB.Object);
    VAR obj: RVOB.Object;
  BEGIN
    IF sym = RVOS.ident THEN
      RVOB.NewObj(first, RVOS.id, class); RVOS.Get(sym); CheckExport(first.expo);
      WHILE sym = RVOS.comma DO
        RVOS.Get(sym);
        IF sym = RVOS.ident THEN RVOB.NewObj(obj, RVOS.id, class); RVOS.Get(sym); CheckExport(obj.expo)
        ELSE RVOS.Mark("ident?")
        END
      END;
      IF sym = RVOS.colon THEN RVOS.Get(sym) ELSE RVOS.Mark(":?") END
    ELSE first := NIL
    END
  END IdentList;
  
  PROCEDURE ArrayType(VAR type: RVOB.Type);
    VAR x: RVOG.Item; typ: RVOB.Type; len: LONGINT;
  BEGIN NEW(typ); typ.form := RVOB.NoTyp;
    IF sym = RVOS.of THEN (*dynamic array*) len := -1
    ELSE expression(x);
      IF (x.mode = RVOB.Const) & (x.type.form = RVOB.Int) & (x.a >= 0) THEN len := x.a
      ELSE len := 0; RVOS.Mark("not a valid length")
      END
    END ;
    IF sym = RVOS.of THEN RVOS.Get(sym); Type(typ.base);
      IF (typ.base.form = RVOB.Array) & (typ.base.len < 0) THEN RVOS.Mark("dyn array not allowed") END
    ELSIF sym = RVOS.comma THEN RVOS.Get(sym); ArrayType(typ.base)
    ELSE RVOS.Mark("missing OF"); typ.base := RVOB.intType
    END ;
    IF len >= 0 THEN typ.size := RoundUp(len * typ.base.size) ELSE typ.size := 2*RVOB.IntegerSize  (*array desc*) END ;
    typ.form := RVOB.Array; typ.len := len; type := typ
  END ArrayType;

  PROCEDURE RecordType(VAR type: RVOB.Type);
    VAR obj, obj0, new, bot, base: RVOB.Object;
      typ, tp: RVOB.Type;
      offset, off, n: LONGINT;
  BEGIN NEW(typ); typ.form := RVOB.NoTyp; typ.base := NIL; typ.mno := -level; typ.nofpar := 0; offset := 0; bot := NIL;
    IF sym = RVOS.lparen THEN
      RVOS.Get(sym); (*record extension*)
      IF level # 0 THEN RVOS.Mark("extension of local types not implemented") END ;
      IF sym = RVOS.ident THEN
        qualident(base);
        IF base.class = RVOB.Typ THEN
          IF base.type.form = RVOB.Record THEN typ.base := base.type
          ELSE typ.base := RVOB.intType; RVOS.Mark("invalid extension")
          END ;
          typ.nofpar := typ.base.nofpar + 1; (*"nofpar" here abused for extension level*)
          bot := typ.base.dsc; offset := typ.base.size
        ELSE RVOS.Mark("type expected")
        END
      ELSE RVOS.Mark("ident expected")
      END ;
      Check(RVOS.rparen, "no )")
    END ;
    WHILE sym = RVOS.ident DO  (*fields*)
      n := 0; obj := bot;
      WHILE sym = RVOS.ident DO
        obj0 := obj;
        WHILE (obj0 # NIL) & (obj0.name # RVOS.id) DO obj0 := obj0.next END ;
        IF obj0 # NIL THEN RVOS.Mark("mult def") END ;
        NEW(new); RVOS.CopyId(new.name); new.class := RVOB.Fld; new.next := obj; obj := new; INC(n);
        RVOS.Get(sym); CheckExport(new.expo);
        IF (sym # RVOS.comma) & (sym # RVOS.colon) THEN RVOS.Mark("comma expected")
        ELSIF sym = RVOS.comma THEN RVOS.Get(sym)
        END
      END ;
      Check(RVOS.colon, "colon expected"); Type(tp);
      IF (tp.form = RVOB.Array) & (tp.len < 0) THEN RVOS.Mark("dyn array not allowed") END ;
      IF tp.size > 1 THEN offset := RoundUp(offset) END ;
      offset := offset + n * tp.size; off := offset; obj0 := obj;
      WHILE obj0 # bot DO obj0.type := tp; obj0.lev := 0; off := off - tp.size; obj0.val := off; obj0 := obj0.next END ;
      bot := obj;
      IF sym = RVOS.semicolon THEN RVOS.Get(sym) ELSIF sym # RVOS.end THEN RVOS.Mark(" ; or END") END
    END ;
    typ.form := RVOB.Record; typ.dsc := bot; typ.size := RoundUp(offset); type := typ
  END RecordType;

  PROCEDURE FPSection(VAR adr: LONGINT; VAR nofpar: INTEGER);
    VAR obj, first: RVOB.Object; tp: RVOB.Type;
      parsize: LONGINT; cl: INTEGER; rdo: BOOLEAN;
  BEGIN
    IF sym = RVOS.var THEN RVOS.Get(sym); cl := RVOB.Par ELSE cl := RVOB.Var END ;
    IdentList(cl, first); FormalType(tp, 0); rdo := FALSE;
    IF (cl = RVOB.Var) & (tp.form >= RVOB.Array) THEN cl := RVOB.Par; rdo := TRUE END ;
    IF (tp.form = RVOB.Array) & (tp.len < 0) OR (tp.form = RVOB.Record) THEN
      parsize := 2*RVOB.IntegerSize  (*open array or record, needs second word for length or type tag*)
    ELSE parsize := RVOB.IntegerSize
    END ;
    obj := first;
    WHILE obj # NIL DO
      INC(nofpar); obj.class := cl; obj.type := tp; obj.rdo := rdo; obj.lev := level; obj.val := adr;
      adr := adr + parsize; obj := obj.next
    END ;
    IF adr >= BytesForParameters THEN RVOS.Mark("too many parameters") END
  END FPSection;

  PROCEDURE ProcedureType(ptype: RVOB.Type; VAR parblksize: LONGINT);
    VAR obj: RVOB.Object; size: LONGINT; nofpar: INTEGER;
  BEGIN ptype.base := RVOB.noType; size := parblksize; nofpar := 0; ptype.dsc := NIL;
    IF sym = RVOS.lparen THEN
      RVOS.Get(sym);
      IF sym = RVOS.rparen THEN RVOS.Get(sym)
      ELSE FPSection(size, nofpar);
        WHILE sym = RVOS.semicolon DO RVOS.Get(sym); FPSection(size, nofpar) END ;
        Check(RVOS.rparen, "no )")
      END ;
      ptype.nofpar := nofpar; parblksize := size;
      IF sym = RVOS.colon THEN  (*function*)
        RVOS.Get(sym);
        IF sym = RVOS.ident THEN qualident(obj);
          IF (obj.class = RVOB.Typ) & (obj.type.form IN {RVOB.Byte .. RVOB.Pointer, RVOB.Proc}) THEN ptype.base := obj.type
          ELSE RVOS.Mark("illegal function type")
          END
        ELSE RVOS.Mark("type identifier expected")
        END
      END
    END
  END ProcedureType;

  PROCEDURE FormalType0(VAR typ: RVOB.Type; dim: INTEGER);
    VAR obj: RVOB.Object; dmy: LONGINT;
  BEGIN
    IF sym = RVOS.ident THEN
      qualident(obj);
      IF obj.class = RVOB.Typ THEN typ := obj.type ELSE RVOS.Mark("not a type"); typ := RVOB.intType END
    ELSIF sym = RVOS.array THEN
      RVOS.Get(sym); Check(RVOS.of, "OF ?");
      IF dim >= 1 THEN RVOS.Mark("multi-dimensional open arrays not implemented") END ;
      NEW(typ); typ.form := RVOB.Array; typ.len := -1; typ.size := 2*RVOB.IntegerSize;
      FormalType(typ.base, dim+1)
    ELSIF sym = RVOS.procedure THEN
      RVOS.Get(sym); RVOB.OpenScope;
      NEW(typ); typ.form := RVOB.Proc; typ.size := RVOB.PtrSize; dmy := 0; ProcedureType(typ, dmy);
      typ.dsc := RVOB.topScope.next; RVOB.CloseScope
    ELSE RVOS.Mark("identifier expected"); typ := RVOB.noType
    END
  END FormalType0;

  PROCEDURE CheckRecLevel(lev: INTEGER);
  BEGIN
    IF lev # 0 THEN RVOS.Mark("ptr base must be global") END
  END CheckRecLevel;

  PROCEDURE Type0(VAR type: RVOB.Type);
    VAR dmy: LONGINT; obj: RVOB.Object; ptbase: PtrBase;
  BEGIN type := RVOB.intType; (*sync*)
    IF (sym # RVOS.ident) & (sym < RVOS.array) THEN RVOS.Mark("not a type");
      REPEAT RVOS.Get(sym) UNTIL (sym = RVOS.ident) OR (sym >= RVOS.array)
    END ;
    IF sym = RVOS.ident THEN
      qualident(obj);
      IF obj.class = RVOB.Typ THEN
        IF (obj.type # NIL) & (obj.type.form # RVOB.NoTyp) THEN type := obj.type END
      ELSE RVOS.Mark("not a type or undefined")
      END
    ELSIF sym = RVOS.array THEN RVOS.Get(sym); ArrayType(type)
    ELSIF sym = RVOS.record THEN
      RVOS.Get(sym); RecordType(type); Check(RVOS.end, "no END")
    ELSIF sym = RVOS.pointer THEN
      RVOS.Get(sym); Check(RVOS.to, "no TO");
      NEW(type);  type.form := RVOB.Pointer; type.size := RVOB.PtrSize; type.base := RVOB.intType;
      IF sym = RVOS.ident THEN
        obj := RVOB.thisObj(); RVOS.Get(sym);
        IF obj # NIL THEN
          IF (obj.class = RVOB.Typ) & (obj.type.form IN {RVOB.Record, RVOB.NoTyp}) THEN
            CheckRecLevel(obj.lev); type.base := obj.type
          ELSE RVOS.Mark("no valid base type")
          END
        ELSE CheckRecLevel(level); (*enter into list of forward references to be fixed in Declarations*)
          NEW(ptbase); RVOS.CopyId(ptbase.name); ptbase.type := type; ptbase.next := pbsList; pbsList := ptbase
        END
      ELSE Type(type.base);
        IF type.base.form # RVOB.Record THEN RVOS.Mark("must point to record") END ;
        CheckRecLevel(level)
      END
    ELSIF sym = RVOS.procedure THEN
      RVOS.Get(sym); RVOB.OpenScope;
      NEW(type); type.form := RVOB.Proc; type.size := RVOB.PtrSize; dmy := 0;
      ProcedureType(type, dmy); type.dsc := RVOB.topScope.next; RVOB.CloseScope
    ELSE RVOS.Mark("illegal type")
    END
  END Type0;

  PROCEDURE Declarations(VAR varsize: LONGINT);
    VAR obj, first: RVOB.Object;
      x: RVOG.Item; tp: RVOB.Type; ptbase: PtrBase;
      expo: BOOLEAN; id: RVOS.Ident;
  BEGIN (*sync*) pbsList := NIL;
    IF (sym < RVOS.const) & (sym # RVOS.end) THEN RVOS.Mark("declaration?");
      REPEAT RVOS.Get(sym) UNTIL (sym >= RVOS.const) OR (sym = RVOS.end)
    END ;
    IF sym = RVOS.const THEN
      RVOS.Get(sym);
      WHILE sym = RVOS.ident DO
        RVOS.CopyId(id); RVOS.Get(sym); CheckExport(expo);
        IF sym = RVOS.eql THEN RVOS.Get(sym) ELSE RVOS.Mark("= ?") END;
        expression(x);
        IF (x.type.form = RVOB.String) & (x.b = 2) THEN RVOG.StrToChar(x) END ;
        RVOB.NewObj(obj, id, RVOB.Const); obj.expo := expo;
        IF x.mode = RVOB.Const THEN obj.val := x.a; obj.lev := x.b; obj.type := x.type
        ELSE RVOS.Mark("expression not constant"); obj.type := RVOB.intType
        END;
        Check(RVOS.semicolon, "; missing")
      END
    END ;
    IF sym = RVOS.type THEN
      RVOS.Get(sym);
      WHILE sym = RVOS.ident DO
        RVOS.CopyId(id); RVOS.Get(sym); CheckExport(expo);
        IF sym = RVOS.eql THEN RVOS.Get(sym) ELSE RVOS.Mark("=?") END ;
        Type(tp);
        RVOB.NewObj(obj, id, RVOB.Typ); obj.type := tp; obj.expo := expo; obj.lev := level; tp.typobj := obj;
        IF expo & (obj.type.form = RVOB.Record) THEN obj.exno := exno; INC(exno) ELSE obj.exno := 0 END ;
        IF tp.form = RVOB.Record THEN
          ptbase := pbsList;  (*check whether this is base of a pointer type; search and fixup*)
          WHILE ptbase # NIL DO
            IF obj.name = ptbase.name THEN ptbase.type.base := obj.type END ;
            ptbase := ptbase.next
          END ;
          IF level = 0 THEN RVOG.BuildTD(tp, dc) END    (*type descriptor; len used as its address*)
        END ;
        Check(RVOS.semicolon, "; missing")
      END
    END ;
    IF sym = RVOS.var THEN
      RVOS.Get(sym);
      WHILE sym = RVOS.ident DO
        IdentList(RVOB.Var, first); Type(tp);
        obj := first;
        WHILE obj # NIL DO
          obj.type := tp; obj.lev := level;
          IF tp.size > 1 THEN varsize := RoundUp(varsize) END ;
          obj.val := varsize; varsize := varsize + obj.type.size;
          IF obj.expo THEN obj.exno := exno; INC(exno) END ;
          obj := obj.next
        END ;
        Check(RVOS.semicolon, "; missing")
      END
    END ;
    varsize := RoundUp(varsize);
    ptbase := pbsList;
    WHILE ptbase # NIL DO
      IF ptbase.type.base.form = RVOB.Int THEN RVOS.Mark("undefined pointer base of") END ;
      ptbase := ptbase.next
    END ;
    IF (sym >= RVOS.const) & (sym <= RVOS.var) THEN RVOS.Mark("declaration in bad order") END
  END Declarations;

  PROCEDURE ProcedureDecl;
    VAR proc: RVOB.Object;
      type: RVOB.Type;
      procid: RVOS.Ident;
      x: RVOG.Item;
      locblksize, parblksize, L: LONGINT;
      int: BOOLEAN;
  BEGIN (* ProcedureDecl *) int := FALSE; RVOS.Get(sym);
    IF sym = RVOS.times THEN RVOS.Get(sym); int := TRUE END ;
    IF sym = RVOS.ident THEN
      RVOS.CopyId(procid); RVOS.Get(sym);
      RVOB.NewObj(proc, RVOS.id, RVOB.Const); parblksize := RVOB.PtrSize;
      NEW(type); type.form := RVOB.Proc; type.size := RVOB.IntegerSize; proc.type := type;
      CheckExport(proc.expo);
      IF proc.expo THEN proc.exno := exno; INC(exno) END ;
      RVOB.OpenScope; INC(level); proc.val := -1; type.base := RVOB.noType;
      ProcedureType(type, parblksize);  (*formal parameter list*)
      Check(RVOS.semicolon, "no ;"); locblksize := parblksize;
      Declarations(locblksize);
      proc.val := RVOG.Here() * InsnSize; proc.type.dsc := RVOB.topScope.next;
      IF sym = RVOS.procedure THEN
        L := 0; RVOG.FJump(L);
        REPEAT ProcedureDecl; Check(RVOS.semicolon, "no ;") UNTIL sym # RVOS.procedure;
        RVOG.FixLink(L); proc.val := RVOG.Here() * InsnSize; proc.type.dsc := RVOB.topScope.next
      END ;
      RVOG.Enter(parblksize, locblksize, int);
      IF sym = RVOS.begin THEN RVOS.Get(sym); StatSequence END ;
      IF sym = RVOS.return THEN
        RVOS.Get(sym); expression(x);
        IF type.base = RVOB.noType THEN RVOS.Mark("this is not a function")
        ELSIF ~CompTypes(type.base, x.type, FALSE) THEN RVOS.Mark("wrong result type")
        END
      ELSIF type.base.form # RVOB.NoTyp THEN
        RVOS.Mark("function without result"); type.base := RVOB.noType
      END ;
      RVOG.Return(type.base.form, x, locblksize, int);
      RVOB.CloseScope; DEC(level); Check(RVOS.end, "no END");
      IF sym = RVOS.ident THEN
        IF RVOS.id # procid THEN RVOS.Mark("no match") END ;
        RVOS.Get(sym)
      ELSE RVOS.Mark("no proc id")
      END
    END ;
    int := FALSE
  END ProcedureDecl;

  PROCEDURE Module;
    VAR key: LONGINT;
      obj: RVOB.Object;
      impid, impid1: RVOS.Ident;
  BEGIN Texts.WriteString(W, "  compiling "); RVOS.Get(sym);
    IF sym # RVOS.module THEN RVOS.Mark("must start with MODULE")
    ELSE
      RVOS.Get(sym);
      IF sym = RVOS.times THEN version := 0; Texts.Write(W, "*"); RVOS.Get(sym) ELSE version := 1 END ;
      RVOB.Init; RVOB.OpenScope;
      IF sym = RVOS.ident THEN
        RVOS.CopyId(modid); RVOS.Get(sym);
        Texts.WriteString(W, modid); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
      ELSE RVOS.Mark("identifier expected")
      END ;
      Check(RVOS.semicolon, "no ;"); level := 0; dc := 0; exno := 1; key := 0;
      IF sym = RVOS.import THEN
        RVOS.Get(sym);
        WHILE sym = RVOS.ident DO
          RVOS.CopyId(impid); RVOS.Get(sym);
          IF sym = RVOS.becomes THEN
            RVOS.Get(sym);
            IF sym = RVOS.ident THEN RVOS.CopyId(impid1); RVOS.Get(sym)
            ELSE RVOS.Mark("id expected")
            END
          ELSE impid1 := impid
          END ;
          RVOB.Import(impid, impid1);
          IF sym = RVOS.comma THEN RVOS.Get(sym)
          ELSIF sym = RVOS.ident THEN RVOS.Mark("comma missing")
          END
        END ;
        Check(RVOS.semicolon, "no ;")
      END ;
      obj := RVOB.topScope.next;
      RVOG.Open(version, modid); Declarations(dc); RVOG.SetDataSize(RoundUp(dc));
      WHILE sym = RVOS.procedure DO ProcedureDecl; Check(RVOS.semicolon, "no ;") END ;
      RVOG.Header;
      IF sym = RVOS.begin THEN RVOS.Get(sym); StatSequence END ;
      Check(RVOS.end, "no END");
      IF sym = RVOS.ident THEN
        IF RVOS.id # modid THEN RVOS.Mark("no match") END ;
        RVOS.Get(sym)
      ELSE RVOS.Mark("identifier missing")
      END ;
      IF sym # RVOS.period THEN RVOS.Mark("period missing") END ;
      IF (RVOS.errcnt = 0) & (version # 0) THEN
        RVOB.Export(modid, newSF, key);
        IF newSF THEN Texts.WriteString(W, " new symbol file") END
      END ;
      IF RVOS.errcnt = 0 THEN
        RVOG.CheckRegs();
        RVOG.Close(modid, key, exno);
        Texts.WriteInt(W, RVOG.pc, 6); Texts.WriteInt(W, dc, 6); Texts.WriteHex(W, key)
      ELSE Texts.WriteLn(W); Texts.WriteString(W, "compilation FAILED")
      END ;
      Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
      RVOB.CloseScope; pbsList := NIL
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
        IF time >= 0 THEN RVOS.Init(T, beg); Module END
      ELSIF S.c = "^" THEN
        Option(S); Oberon.GetSelection(T, beg, end, time);
        IF time >= 0 THEN
          Texts.OpenScanner(S, T, beg); Texts.Scan(S);
          IF S.class = Texts.Name THEN
            Texts.WriteString(W, S.s); NEW(T); Texts.Open(T, S.s);
            IF T.len > 0 THEN RVOS.Init(T, 0); Module END
          END
        END
      END
    ELSE 
      WHILE S.class = Texts.Name DO
        NEW(T); Texts.Open(T, S.s);
        IF T.len > 0 THEN Option(S); RVOS.Init(T, 0); Module
        ELSE Texts.WriteString(W, S.s); Texts.WriteString(W, " not found");
          Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
        END ;
        IF (T.len # 0) & (RVOS.errcnt = 0) THEN Texts.Scan(S) ELSE S.class := 0 END
      END
    END ;
    Oberon.Collect(0)
  END Compile;

BEGIN Texts.OpenWriter(W); Texts.WriteString(W, "RISC-V OR Compiler  2020-09-23");
  Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
  NEW(dummy); dummy.class := RVOB.Var; dummy.type := RVOB.intType;
  expression := expression0; Type := Type0; FormalType := FormalType0
END RVOP.
