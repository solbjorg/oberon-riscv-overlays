MODULE Modules;  (*Link and load on RISC; NW 20.10.2013 / 8.1.2019*)
  IMPORT SYSTEM, Kernel, Overlays, Files;
  CONST versionkey = 1X; MT = 4; DescSize = 84;
    addi = 19; load = 3; store = 35;
    SB = 3;
    MTOrg* = 20H; maxProcSize = 1134H; maxProcSizeSmall = 89AH;
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

    (* To avoid stressing the heap too much while loading, we would ideally only allocate as *)
    (* much space as is needed on the heap to load each procedure in the module, i.e. the size *)
    (* of the largest procedure in the module. However, as Oberon does not support allocating *)
    (* blocks of variable size on the heap, a workaround is needed. maxProcSize represents the *)
    (* largest procedure size of which linking is supported; maxProcSizeSmall is a more average *)
    (* case which works for most modules. Depending on the module being loaded, one or the other *)
    (* can be used, with a preference towards allocating a smaller block. *)
    FixupProcedureLarge = RECORD
      inst: ARRAY maxProcSize DIV 4 OF INTEGER;
    END;

    FixupProcedureSmall = RECORD
      inst: ARRAY maxProcSizeSmall DIV 4 OF INTEGER;
    END;

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
  PROCEDURE ThisFile(name, extension: ARRAY OF CHAR; new: BOOLEAN): Files.File;
    VAR i: INTEGER;
      F: Files.File;
      filename: Overlays.ModuleName;
  BEGIN
    i := 0;
    WHILE name[i] # 0X DO filename[i] := name[i]; INC(i) END ;
    filename[i] := "."; filename[i+1] := extension[0]; filename[i+2] := extension[1]; filename[i+3] := extension[2]; filename[i+4] := 0X;
    IF new THEN F := Files.New(filename);
    ELSE F := Files.Old(filename);
    END;
    RETURN F
  END ThisFile;

  PROCEDURE SetRoot(r: Overlays.Module);
  BEGIN root := r;
    Overlays.SetRoot(r);
  END SetRoot;

  PROCEDURE Check(s: ARRAY OF CHAR);
    VAR i: INTEGER; ch: CHAR;
  BEGIN ch := s[0]; res := 1; i := 1;
    IF (ch >= "A") & (ch <= "Z") OR (ch >= "a") & (ch <= "z") THEN
      REPEAT ch := s[i]; INC(i)
      UNTIL ~((ch >= "0") & (ch <= "9") OR (ch >= "A") & (ch <= "Z")
        OR (ch >= "a") & (ch <= "z") OR (ch = ".")) OR (i = 32);
      IF (i < 32) & (ch = 0X) THEN res := 0 END
    END
  END Check;

  PROCEDURE FixupOverlayTokens(mapped, adr: INTEGER; VAR fixorgS: INTEGER; mod: Overlays.Module);
    VAR mno, pno, imm, inst, reg, callerIndex, index, callerPno, disp: INTEGER;
      procVar: BOOLEAN;
      impmod: Overlays.Module;
  BEGIN
    WHILE fixorgS > adr DO
      SYSTEM.GET(mapped + fixorgS - adr, inst);
      disp := inst DIV 10000H;
      callerPno := inst DIV 100H MOD 100H;
      procVar := SYSTEM.VAL(BOOLEAN, inst MOD 2);
      reg  := inst DIV 2 MOD 20H;
      (* fixup LUI *)
      SYSTEM.GET(mapped + fixorgS - adr-4, inst);
      imm := inst DIV C12;
      mno := imm MOD C12;
      pno := imm DIV C12;
      IF mno <= 0 THEN
        mno := mod.num;
      ELSE
        SYSTEM.GET(mod.imp + (mno-1)*4, impmod); mno := impmod.num;
        SYSTEM.GET(impmod.ent + pno*4, pno);
      END;
      IF mno > 5 THEN
        index := Overlays.FindOverlayIndex(mno, pno);
        IF ~procVar THEN
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
      SYSTEM.PUT(mapped + fixorgS - adr-4, inst);

      inst := LSL(index MOD 800H, 1) + 1;
      SYSTEM.PUT(mapped + fixorgS - adr, Addi(reg, inst));
      (* if MSB of the imm in the addi instruction is 1, it *)
      (* will be sign extended; so we need to change the imm*)
      (* in the lui instruction to compensate by adding 1   *)
      IF inst >= 2048 THEN
        SYSTEM.GET(mapped + fixorgS - adr-4, inst);
        imm := inst DIV C12;
        inst := (inst - LSL(imm MOD C20, 12)) + LSL(imm + 1 MOD C20, 12);
        SYSTEM.PUT(mapped + fixorgS - adr-4, inst);
      END;
      fixorgS := disp*4;
    END ;
  END FixupOverlayTokens;

  (* mapped: location the procedure has been written to in memory *)
  (* adr: address in code in which this procedure begins *)
  (* fixorgD: the current part of the list. VAR so that they can be preserved for next call *)
  PROCEDURE FixupProcD(mapped, adr: INTEGER; VAR fixorgD: INTEGER; mod: Overlays.Module);
    VAR v, inst, mno, disp, offset, op, vno, imm: INTEGER; impmod: Overlays.Module;
  BEGIN
    WHILE fixorgD > adr DO
      (* fixorgD is given with respect to the location in the module's code file *)
      (* To convert it from the position of the module's code file to the proc's position *)
      (* in memory, take fixorgD - adr; as fixorgD > adr is guaranteed to hold, this gives *)
      (* the specific location in the procedure. Add that to mapped to get the actual location *)
      (* in memory *)
      SYSTEM.GET(mapped + fixorgD - adr, inst);
      mno := inst DIV 10H MOD 128;
      disp := inst DIV 10000H;
      IF mno = 0 THEN (*global*)
        SYSTEM.PUT(mapped + fixorgD - adr, Lw(mod.num * 4))
      ELSE (*import*)
        SYSTEM.GET(mod.imp + (mno-1)*4, impmod); v := impmod.num;
        SYSTEM.PUT(mapped + fixorgD - adr, Lw(v * 4));
        SYSTEM.GET(mapped + fixorgD - adr + 4, inst);
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
          SYSTEM.PUT(mapped + fixorgD - adr + 4, (inst - LSL(imm MOD 20H, 7) - LSL(imm DIV 20H, 25)) + LSL(offset MOD 20H, 7) + LSL(offset DIV 20H, 25));
        ELSE
          SYSTEM.PUT(mapped + fixorgD - adr + 4, (inst - LSL(imm, 20)) + LSL(offset, 20));
        END;
      END ;
      fixorgD := disp*4;
    END ;
  END FixupProcD;

  (* confusing variable naming is due to trying to compress space on stack; TODO fix *)
  PROCEDURE Load*(name: ARRAY OF CHAR; VAR newmod: Overlays.Module);
    (*search module in list; if not found, load module.
      res = 0: already present or loaded; res = 2: file not available; res = 3: key conflict;
      res = 4: bad file version; res = 5: corrupted file; res = 7: no space*)
    VAR mod, impmod: Overlays.Module;
      i, j, n, m, key, impkey, mno, numprocs, nofimps, size: INTEGER;
      p, u, v, w: INTEGER;  (*addresses*)
      ch: CHAR;
      body: Command;
      F: Files.File; R: Files.Rider;
      fixorgP, fixorgD, fixorgT, fixorgS: INTEGER;
      mapped, op, imm, disp, adr, inst, pno, vno, dest, offset, index, codeFilePos, largest: INTEGER;
      name1, impname: Overlays.ModuleName;
      procs: ARRAY Overlays.maxNumProcs OF Overlays.Procedure;
      tempProc: Overlays.Procedure;
      dummyLarge: POINTER TO FixupProcedureLarge;
      dummySmall: POINTER TO FixupProcedureSmall;
      import: ARRAY 16 OF Overlays.Module;

  BEGIN
    mod := root; error(0, name); nofimps := 0;
    i := 0;
    WHILE name[i] # 0X DO INC(i) END ;
    WHILE (mod # NIL) & (name # mod.name) DO mod := mod.next END ;
    IF mod = NIL THEN
      Check(name);
      IF res = 0 THEN F := ThisFile(name, "rsc", FALSE) ELSE F := NIL END ;
      IF F # NIL THEN
        Files.Set(R, F, 0); Files.ReadString(R, name1); Files.ReadInt(R, key); Files.Read(R, ch);
        Files.ReadInt(R, size); importing := name1;
        IF ch = versionkey THEN
          Files.ReadString(R, impname);   (*imports*)
          WHILE (impname[0] # 0X) & (res = 0) DO
            Files.ReadInt(R, impkey);
            Load(impname, impmod); import[nofimps] := impmod; importing := name1;
            IF res = 0 THEN
              IF impmod.key = impkey THEN INC(impmod.refcnt); INC(nofimps)
              ELSE error(3, name1);
              END
            END;
            Files.ReadString(R, impname)
          END;
        ELSE error(2, name1)
        END;
      ELSE error(1, name)
      END;
      IF res = 0 THEN (*search for a hole in the list allocate and link*)
        INC(size, DescSize); mod := root;
        (* TODO: Since mod.size is no longer a good indication of the actual size required in static data section, *)
        (* this will no longer accurately locate potential holes. *)
        WHILE (mod # NIL) & ~((mod.name[0] = 0X) & (mod.size >= size)) DO mod := mod.next END ;
        IF mod = NIL THEN (*no large enough hole was found*)
          p := AllocPtr; mod := SYSTEM.VAL(Overlays.Module, p);
          AllocPtr := (p + size) DIV 20H * 20H; mod.size := AllocPtr - p; mod.num := root.num + 1;
          mod.next := root; SetRoot(mod);
        ELSE (*fill hole*) p := SYSTEM.VAL(INTEGER, mod)
        END
      END ;
      IF res = 0 THEN (*read file*)
        error(0, name);
        mod.name := name; mod.refcnt := 0; mod.key := key;
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
        i := 0; j := 0; (* j = largest proc, i = index*)
        WHILE (n > 0) DO
          Files.ReadInt(R, w);
          (* until a proc is in a loaded overlay, all calls should go *)
          (* through the OVM *)
          SYSTEM.PUT(p, Overlays.addressOVM); INC(p, 4);
          IF w # -1 THEN
            NEW(tempProc); tempProc.addr := w; tempProc.index := i;
            Files.ReadInt(R, disp); (* size *)
            tempProc.size := disp;
            IF disp > j THEN j := disp END;
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
        body := SYSTEM.VAL(Command, mod.code);
        (* set AllocPtr here so that entry code gets overwritten by the next module that is loaded *)
        AllocPtr := mod.code;
        Kernel.SetAllocPtr(AllocPtr);
        Files.ReadInt(R, n);
        codeFilePos := Files.Pos(R);
        (* TODO: This can be made more elegant by reorganising the order in which data is given in the header/footer *)
        Files.Set(R, F, codeFilePos + n * 4); (* jump past all code *)
        Files.ReadInt(R, fixorgP); Files.ReadInt(R, fixorgD); Files.ReadInt(R, fixorgT); Files.ReadInt(R, fixorgS);
        Files.ReadInt(R, w);
        Files.Read(R, ch);
        Files.Set(R, F, codeFilePos + w); (* jump to entry *)
        (* write entry into end of linker space *)
        i := w;
        WHILE i < n*4 DO
          Files.ReadInt(R, m); SYSTEM.PUT(p, m);
          INC(p, 4); INC(i, 4)
        END ;  (*entry code*)
        (* generate node for linked module *)
        IF ch # "O" THEN (*corrupted file*) mod := NIL; error(4, name) END;
      END ;
      (* - fixups - *)
      IF res = 0 THEN
        (* generate an overlay for each procedure in the module *)
        Overlays.NewOverlay(mod, procs, numprocs);
        (*fixup of LDR/STR/ADD*)
        fixorgD := fixorgD * 4; fixorgS := fixorgS * 4;
        (* fixup entry code *)
        FixupProcD(mod.code, w, fixorgD, mod);
        FixupOverlayTokens(mod.code, w, fixorgS, mod);
        (* j = largest proc *)
        (* allocate space on the heap into which procedures that will be fixed up are written *)
        IF j > maxProcSizeSmall THEN
          NEW(dummyLarge); ASSERT(dummyLarge # NIL);
          mapped := SYSTEM.ADR(dummyLarge.inst);
        ELSE
          NEW(dummySmall); ASSERT(dummySmall # NIL);
          mapped := SYSTEM.ADR(dummySmall.inst);
        END;
        m := 07FFFFFFFH; largest := 0;
        FOR i := numprocs-1 TO 0 BY -1 DO
          (* Find the next procedure that needs to be fixed up *)
          (* This has to be done because nested procs mess up the *)
          (* ordering of procs[], as the outer proc will appear *before* *)
          (* the nested procs in procs[] but *after* them in code. So we should *)
          (* fixup the outer one before the inner ones. *)
          (* Nested procedures cause a lot of trouble. *)
          (* TODO, this can be made more elegant *)
          largest := 0;
          FOR j := numprocs-1 TO 0 BY -1 DO
            IF (procs[j].addr < m) & (procs[j].addr > largest) THEN
              largest := procs[j].addr;
              index := j;
            END;
          END;
          m := largest;
          Files.Set(R, F, codeFilePos + (procs[index].addr)); (*jump to the part we want to write into memory*)
          (* read procedure into memory *)
          FOR p := 0 TO procs[index].size BY 4 DO
            Files.ReadInt(R, w); SYSTEM.PUT(mapped + p, w);
          END ;

          (* fixups for that procedure *)
          FixupProcD(mapped, procs[index].addr, fixorgD, mod);
          FixupOverlayTokens(mapped, procs[index].addr, fixorgS, mod);
          (* write that procedure onto disk as an overlay *)
          Overlays.WriteOverlay(Overlays.FindOverlayIndex(mod.num, procs[index].index), mapped);
        END;
        (* set these to NIL so GC can clean them up *)
        dummySmall := NIL; dummyLarge := NIL;
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
        (* allow GC to clean these up *)
        FOR i := 0 TO numprocs DO procs[i] := NIL END;
        body();
      ELSIF res >= 3 THEN importing := name;
        WHILE nofimps > 0 DO DEC(nofimps); DEC(import[nofimps].refcnt) END;
      END;
    END;
    newmod := mod;
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

BEGIN SYSTEM.PUT(-60, 86H); Init; SYSTEM.PUT(-60, 88H); Load("Oberon", M);
  (* the below will only run in the case of an error *)
  SYSTEM.PUT(-60, 0F00H + res); REPEAT UNTIL FALSE
END Modules.
