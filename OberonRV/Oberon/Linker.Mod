MODULE Linker;  (*Link and load on RISC; NW 20.10.2013 / 8.1.2019*)
  IMPORT SYSTEM, Kernel, Overlays, Files;
  CONST versionkey = 1X; MT = 4; DescSize = 88;
    addi = 19; load = 3; store = 35;
    SB = 3;
    MTOrg* = 20H;
    (* Useful constants for bit manip *)
    C28 = 10000000H;
    C24 = 1000000H;
    C20 = 100000H;
    C16 = 10000H;
    C12 = 1000H;
    C10 = 400H;
    C8  = 100H;
    C4  = 10H;

  TYPE Command* = PROCEDURE;

  VAR root*, M: Overlays.Module;
    AllocPtr*, res*: INTEGER;
    importing*, imported*: Overlays.ModuleName;
    limit*: INTEGER;

  PROCEDURE error(n: INTEGER; name: ARRAY OF CHAR);
  BEGIN res := n; importing := name;
    IF res > 0 THEN
      SYSTEM.PUT(-60, 0F00H + res);
    END;
  END error;

  (* writes a file Module.fix from fixed-up memory *)
  (*
  PROCEDURE WriteFixedModule*(mod: Overlays.Module; size: INTEGER);
    VAR i, u: INTEGER;
      F: Files.File; R: Files.Rider;
      filename: Overlays.FileName;
  BEGIN
    i := 0;
    WHILE mod.name[i] # 0X DO filename[i] := mod.name[i]; INC(i) END;
    filename[i] := "."; filename[i+1] := "f"; filename[i+2] := "i"; filename[i+3] := "x";
    filename[i+4] := 0X;
    (*copy contents of module in memory into an overlay file*)
    F := Files.New(filename);
    Files.Set(R, F, 0);
    i := mod.code;
    WHILE i < mod.code + size DO
      SYSTEM.GET(i, u); Files.WriteInt(R, u); INC(i, 4)
    END;
    Files.Register(F);
  END WriteFixedModule;
  *)

  (* ---------- Linker helper functions ----------*)
  (* Returns a `jal ra, imm` instruction. *)
  PROCEDURE Jal(imm: INTEGER) : INTEGER;
    VAR imm20, imm19to12, imm11, imm10to1: INTEGER;
  BEGIN
    imm20 := imm DIV 100000H;
    imm19to12 := (imm - imm20 * 100000H) DIV 1000H;
    imm11 := (imm - (imm20 * 100000H + imm19to12 * 1000H)) DIV 800H;
    imm10to1 := (imm - (imm20 * 100000H + imm19to12 * 1000H + imm11 * 800H)) DIV 2H;
    RETURN ((((imm20 * 400H + imm10to1) * 2H + imm11) * 100H + imm19to12) * 20H + 1) * 80H + 111
  END Jal;

  PROCEDURE Jalr(imm: INTEGER) : INTEGER;
  BEGIN
    (* lw SB, (imm+20H)(0) *)
    RETURN ((((imm + 20H) * 20H + 0) * 8H + 2) * 20H + 3) * 80H + 67 (*jalr opcode = 67*)
  END Jalr;

  (* TODO remove these simple helper functions? readability vs compact code *)
  (* ideally they should be in-lined, but Oberon doesn't support that *)
  PROCEDURE Addi(reg, imm: INTEGER) : INTEGER;
  BEGIN
    (*addi reg, reg, imm*)
    RETURN (((imm * 20H + reg) * 8H + 0) * 20H + reg) * 80H + addi
  END Addi;

  PROCEDURE Lw(imm: INTEGER) : INTEGER;
  BEGIN
    (* lw SB, (imm+20H)(0) *)
    RETURN ((((imm + 20H) * 20H + 0) * 8H + 2) * 20H + 3) * 80H + 3 (* opcode for all loads is 3 *)
  END Lw;

  (* Linking functions *)

  (* create a file to hold the fixed-up version of a module *)
  (* TODO: verify that this works if the file already exists! *)
  PROCEDURE ThisFile(name: ARRAY OF CHAR): Files.File;
    VAR i: INTEGER;
      filename: Overlays.ModuleName;
  BEGIN
    i := 0;
    WHILE name[i] # 0X DO filename[i] := name[i]; INC(i) END ;
    filename[i] := "."; filename[i+1] := "f"; filename[i+2] := "i"; filename[i+3] := "x"; filename[i+4] := 0X;
    RETURN Files.New(filename)
  END ThisFile;

  (* Linearly search through procs (assumed sorted) to find the index of *)
  (* the proc that PC is currently at. *)
  (* procs is an address *)
  (*
  PROCEDURE FindIndex(pc, procs, numprocs: INTEGER): INTEGER;
    VAR i, p: INTEGER; found: BOOLEAN;
  BEGIN
    i := 0;
    WHILE (~found) & (i < numprocs) DO
      SYSTEM.GET(procs + i * 4, p);
      IF pc > p THEN
        found := TRUE;
      END
    END;
    RETURN p
  END FindIndex;

  PROCEDURE FindProcCalls(mod: Overlays.Module; fixorgS: INTEGER);
    VAR adr, imm, mno, pno, inst, index, disp: INTEGER;
      impmod: Overlays.Module;
  BEGIN
    adr := mod.code + fixorgS*4;
    WHILE adr # mod.code DO
      SYSTEM.GET(adr-4, inst);
      imm := inst DIV C12;
      mno := imm MOD C12;
      pno := imm DIV C12;
      IF mno <= 0 THEN
        mno := mod.num;
      ELSE
        SYSTEM.GET(mod.imp + (mno-1)*4, impmod); mno := impmod.num;
        (* TODO: too much indirection! *)
        SYSTEM.GET(impmod.ent + pno*4, pno);
        (*pno := (mod.procs - mod.data) + pno * 4;*)
        (*SYSTEM.PUT(-60, 0E000000H + pno);*)
      END;

      SYSTEM.GET(adr, inst);

      disp := inst DIV 10000H;
      adr := mod.code + disp*4;
    END ;
  END FindProcCalls;
  *)

  PROCEDURE FixupOverlayTokens(mod: Overlays.Module; fixorgS, numprocs: INTEGER);
    VAR adr, mno, pno, imm, inst, reg, callerIndex, index, callerPno, disp: INTEGER;
      generating: BOOLEAN;
      impmod: Overlays.Module;
  BEGIN
    adr := mod.code + fixorgS*4; (* fixup of overlay address tokens *)
    WHILE adr # mod.code DO
      SYSTEM.GET(adr, inst);
      disp := inst DIV 10000H;
      callerPno := inst DIV 100H MOD 100H;
      generating := SYSTEM.VAL(BOOLEAN, inst MOD 2);
      reg  := inst DIV 2 MOD 20H;
      (* fixup LUI *)
      SYSTEM.GET(adr-4, inst);
      imm := inst DIV C12;
      mno := imm MOD C12;
      pno := imm DIV C12;
      IF mno <= 0 THEN
        mno := mod.num;
      ELSE
        SYSTEM.GET(mod.imp + (mno-1)*4, impmod); mno := impmod.num;
        (* TODO: too much indirection! *)
        SYSTEM.GET(impmod.ent + pno*4, pno);
      END;
      IF mno > 6 THEN
        index := Overlays.FindOverlayIndex(mno, pno);
        IF ~generating THEN
          IF callerPno # 0FFH THEN callerIndex := Overlays.FindOverlayIndex(mod.num, callerPno)
          ELSE callerIndex := -1;
          END;
        ELSE callerIndex := -1;
        END;
        (*offset := Overlays.FindProcedureOffset(mno, pno, index);*)
      ELSE
        (* in inner core; no overlays exist *)
        index := 0; callerIndex := 0;
      END;
      (*ASSERT(offset DIV 4 < 1000H);*)
      inst := (inst - LSL(imm MOD C20, 12)) + LSL(callerIndex, 15) + LSL(index DIV 800H MOD 8H, 12);
      SYSTEM.PUT(adr-4, inst);

      inst := LSL(index MOD 800H, 1) + 1;
      SYSTEM.PUT(adr, Addi(reg, inst));
      (* if MSB of the imm in the addi instruction is 1, it *)
      (* will be sign extended; so we need to change the imm*)
      (* in the lui instruction to compensate by adding 1   *)
      IF inst >= 2048 THEN
        SYSTEM.GET(adr-4, inst);
        imm := inst DIV C12;
        inst := (inst - LSL(imm MOD C20, 12)) + LSL(imm + 1 MOD C20, 12);
        SYSTEM.PUT(adr-4, inst);
      END;
      adr := mod.code + disp*4;
    END ;
  END FixupOverlayTokens;

  PROCEDURE SetRoot(r: Overlays.Module);
  BEGIN root := r;
    Overlays.SetRoot(r);
  END SetRoot;

  PROCEDURE Load*(name: ARRAY OF CHAR; VAR newmod: Overlays.Module; VAR numprocs, nofimps, size: INTEGER; VAR import: ARRAY OF Overlays.Module; VAR R: Files.Rider): Command;
    (*search module in list; if not found, load module.
      res = 0: already present or loaded; res = 2: file not available; res = 3: key conflict;
      res = 4: bad file version; res = 5: corrupted file; res = 7: no space*)
    VAR mod, impmod: Overlays.Module;
      i, n, m, impkey, mno: INTEGER;
      p, u, v, w: INTEGER;  (*addresses*)
      ch: CHAR;
      body: Command;
      fixorgP, fixorgD, fixorgT, fixorgS: INTEGER;
      op, imm, disp, adr, inst, pno, vno, dest, offset, index: INTEGER;
      impname: Overlays.ModuleName;
      (* used for constructing call graph *)
      procs: ARRAY Overlays.maxNumProcs OF Overlays.Procedure;
      tempProc: Overlays.Procedure;

  BEGIN
    error(0, name); SYSTEM.PUT(-60, 0F0ADH);
    IF res = 0 THEN (*search for a hole in the list allocate and link*)
      INC(size, DescSize); mod := root;
      WHILE (mod # NIL) & ~((mod.name[0] = 0X) & (mod.size >= size)) DO mod := mod.next END ;
      IF mod = NIL THEN (*no large enough hole was found*)
        IF AllocPtr + size < limit THEN (*allocate*)
          p := AllocPtr; mod := SYSTEM.VAL(Overlays.Module, p);
          AllocPtr := (p + size) DIV 20H * 20H; mod.size := AllocPtr - p; mod.num := root.num + 1;
          mod.next := root; SetRoot(mod);
        ELSE error(7, name)
        END
      ELSE (*fill hole*) p := SYSTEM.VAL(INTEGER, mod)
      END
    END ;
    IF res = 0 THEN (*read file*)
      error(0, name);
      mod.name := name; mod.refcnt := 0;
      numprocs := 0;
      INC(p, DescSize); (*allocate descriptor*)
      mod.data := p;  (*data*)
      SYSTEM.PUT(MTOrg + mod.num * 4, p);  (*module table entry*)
      Files.ReadInt(R, n);
      WHILE n > 0 DO Files.ReadInt(R, w); SYSTEM.PUT(p, w); INC(p, 4); DEC(n, 4) END ;  (*type descriptors*)
      Files.ReadInt(R, n);
      WHILE n > 0 DO SYSTEM.PUT(p, 0); INC(p, 4); DEC(n, 4) END ;  (*variable space*)
      (*procedures*)
      mod.procs := p;
      Files.ReadInt(R, n);
      numprocs := n DIV 4;
      (* use u both to calculate the size of each procedure, *)
      (* as well as to ensure that the procedure list is monotonically *)
      (* increasing. This is necessary, because there may be certain _padding words_ *)
      i := 0; u := -1;
      WHILE (n > 0) DO
        Files.ReadInt(R, w);
        (* until a proc is in a loaded overlay, all calls should go *)
        (* through the OVM *)
        SYSTEM.PUT(p, Overlays.addressOVM); INC(p, 4);
        IF w # -1 THEN
          NEW(tempProc); tempProc.addr := w; tempProc.index := i;
          Files.ReadInt(R, disp); (* size *)
          SYSTEM.PUT(-60, 0EEEAEAEH);
          tempProc.size := disp;
          SYSTEM.PUT(-60, disp);
          procs[i] := tempProc; INC(i);
        ELSE DEC(numprocs); (* padding word *)
          Files.ReadInt(R, w); (* throwaway result in disp *)
        END;
        u := w;
        DEC(n, 4);
      END ;
      Files.ReadInt(R, n);
      WHILE n > 0 DO Files.Read(R, ch); SYSTEM.PUT(p, ch); INC(p); DEC(n) END ;   (*strings*)
      mod.imp := p;  (*copy imports*)
      i := 0;
      WHILE i < nofimps DO
        SYSTEM.PUT(p, import[i]); INC(p, 4); INC(i)
      END ;
      mod.cmd := p;  (*commands*) Files.Read(R, ch);
      WHILE ch # 0X DO
        REPEAT SYSTEM.PUT(p, ch); INC(p); Files.Read(R, ch) UNTIL ch = 0X;
        REPEAT SYSTEM.PUT(p, 0X); INC(p) UNTIL p MOD 4 = 0;
        Files.ReadInt(R, n); SYSTEM.PUT(p, n); INC(p, 4); Files.Read(R, ch)
      END ;
      REPEAT SYSTEM.PUT(p, 0X); INC(p) UNTIL p MOD 4 = 0;
      mod.ent := p;  (*entries*)
      Files.ReadInt(R, n);
      WHILE n > 0 DO Files.ReadInt(R, w); SYSTEM.PUT(p, w); INC(p, 4); DEC(n) END ;
      mod.ptr := p;  (*pointer references*)
      Files.ReadInt(R, w);
      WHILE w >= 0 DO SYSTEM.PUT(p, mod.data + w); INC(p, 4); Files.ReadInt(R, w) END ;
      SYSTEM.PUT(p, 0); INC(p, 4);
      mod.code := p;  (*program*)
      (* WHILE m > 0 DO SYSTEM.GET(u, w); SYSTEM.PUT(u, w + p); INC(u, 4); DEC(m, 4) END ;   (*procedures fixup*) *)
      Files.ReadInt(R, n); (*) Files.Set(R, F, Files.Pos(R) + n); (*skip code*)*)
      WHILE n > 0 DO Files.ReadInt(R, w); SYSTEM.PUT(p, w); INC(p, 4); DEC(n) END ;  (*program code*)
      Files.ReadInt(R, fixorgP); Files.ReadInt(R, fixorgD); Files.ReadInt(R, fixorgT); Files.ReadInt(R, fixorgS);
      Files.ReadInt(R, w);
      body := SYSTEM.VAL(Command, mod.code + w);
      (* generate node for linked module *)
      Files.Read(R, ch);
      IF ch # "O" THEN (*corrupted file*) mod := NIL; error(4, name) END;
      (* set alloc ptr such that the next loaded module will overwrite this one *)
      AllocPtr := mod.code;
      Kernel.SetAllocPtr(AllocPtr);
    END ;
    IF res = 0 THEN
      (*fixup of LDR/STR/ADD*)
      adr := mod.code + fixorgD*4;
      WHILE adr # mod.code DO
        SYSTEM.GET(adr, inst);
        mno := inst DIV 10H MOD 128;
        disp := inst DIV 10000H;
        IF mno = 0 THEN (*global*)
          SYSTEM.PUT(adr, Lw(mod.num * 4))
        ELSE (*import*)
          SYSTEM.GET(mod.imp + (mno-1)*4, impmod); v := impmod.num;
          SYSTEM.PUT(adr, Lw(v * 4));
          SYSTEM.GET(adr+4, inst);
          op := inst MOD 80H;
          IF (op = addi) OR (op = load) THEN
            imm := inst DIV 100000H;
          ELSIF op = store THEN
            imm := LSL(inst DIV 2000000H MOD 80H, 5) + (inst DIV 80H MOD 20H);
          END;
          vno := imm MOD 100H;
          SYSTEM.GET(impmod.ent + vno*4, offset);
          (* If the bit at (imm DIV 100H) is 1, then we are referring to a procedure in a different module *)
          IF ODD(imm DIV 100H) THEN
            offset := offset * 4 + impmod.procs - impmod.data
          END;
          IF (op = store) THEN
            SYSTEM.PUT(adr+4, (inst - LSL(imm MOD 20H, 7) - LSL(imm DIV 20H, 25)) + LSL(offset MOD 20H, 7) + LSL(offset DIV 20H, 25));
          ELSE
            SYSTEM.PUT(adr+4, (inst - LSL(imm, 20)) + LSL(offset, 20));
          END;
        END ;
        adr := mod.code + disp*4
      END ;
      (* iterate over procs in module *)
      (*FindProcCalls(mod, fixorgS);*)
      (*Overlays.CollapseNode(nodes[0]);*)
      SYSTEM.PUT(-60, numprocs);
      FOR i := 0 TO numprocs-1 DO
        SYSTEM.PUT(-60, procs[i].size)
      END;
      Overlays.NewOverlay(mod, procs, numprocs);
      (* fixup overlay tokens with overlay indices *)
      FixupOverlayTokens(mod, fixorgS, numprocs);
      (* write Module.fix *)
      (*nodes[0].mods[0].sec := Overlays.WriteFixedModule(mod, w);*)
      (* after fixups are done, write overlay file *)
      FOR i := 0 TO numprocs-1 DO
        Overlays.WriteOverlay(Overlays.FindOverlayIndex(mod.num, i), procs[i].addr, mod);
      END;
      (*fixup of type descriptors*)
      adr := mod.data + fixorgT*4;
      WHILE adr # mod.data DO
        SYSTEM.GET(adr, inst);
        mno := inst DIV 1000000H MOD 10H;
        vno := inst DIV 1000H MOD 1000H;
        disp := inst MOD 1000H;
        IF mno = 0 THEN (*global*)
          inst := mod.data + vno
        ELSE (*import*)
          SYSTEM.GET(mod.imp + (mno-1)*4, impmod);
          SYSTEM.GET(impmod.ent + vno*4, offset);
          inst := impmod.data + offset
        END ;
        SYSTEM.PUT(adr, inst); adr := adr - disp*4
      END ;
    ELSIF res >= 3 THEN importing := name;
      WHILE nofimps > 0 DO DEC(nofimps); DEC(import[nofimps].refcnt) END;
    END;
    newmod := mod;
    SYSTEM.PUT(-60, 0DA0FH);
    RETURN body
  END Load;

  PROCEDURE ThisCommand*(mod: Overlays.Module; name: ARRAY OF CHAR): Command;
    VAR k, adr, w: INTEGER; ch: CHAR;
      s: ARRAY 32 OF CHAR;
  BEGIN res := 5; w := 0;
    IF mod # NIL THEN
      adr := mod.cmd; SYSTEM.GET(adr, ch);
      WHILE (ch # 0X) & (res # 0) DO k := 0; (*read command name*)
        REPEAT s[k] := ch; INC(k); INC(adr); SYSTEM.GET(adr, ch) UNTIL ch = 0X;
        s[k] := 0X;
        REPEAT INC(adr) UNTIL adr MOD 4 = 0;
        SYSTEM.GET(adr, k); INC(adr, 4);
        IF s = name THEN
          res := 0;
          w := Overlays.FindOverlayIndex(mod.num, k);
          w := Overlays.GetOverlayToken(w);
        ELSE SYSTEM.GET(adr, ch) END
      END
    END
    RETURN SYSTEM.VAL(Command, w)
  END ThisCommand;

  PROCEDURE Free*(name: ARRAY OF CHAR);
    VAR mod, imp: Overlays.Module; p, q: INTEGER;
  BEGIN mod := root; res := 0;
    WHILE (mod # NIL) & (mod.name # name) DO mod := mod.next END ;
    IF mod # NIL THEN
      IF mod.refcnt = 0 THEN
        mod.name[0] := 0X; p := mod.imp; q := mod.cmd;
        (*Overlays.FreeModule(mod.num);*)
        WHILE p < q DO SYSTEM.GET(p, imp); DEC(imp.refcnt); INC(p, 4) END ;
      ELSE res := 1
      END
    END
  END Free;

  PROCEDURE Init*;
  BEGIN
    Files.Init;
    Overlays.Init;
    (*NEW(rootOverlay); rootOverlay.size := 0; rootOverlay.next := NIL;*)
    SYSTEM.GET(16, AllocPtr); SYSTEM.GET(20, root); limit := Kernel.heapOrg;
    Overlays.SetRoot(root);
  END Init;

END Linker.
