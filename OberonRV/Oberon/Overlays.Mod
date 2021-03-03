MODULE Overlays;
  IMPORT SYSTEM, FileDir, Files, Modules;
  CONST numRegions = 1;
    numOverlays = 100;
    regionSize = 1000H;
    addi = 19; load = 3; store = 35;

    (* Useful constants for bit manip *)
    C28 = 10000000H;
    C24 = 1000000H;
    C20 = 100000H;
    C16 = 10000H;
    C12 = 1000H;
    C10 = 400H;
    C8  = 100H;
    C4  = 10H;

  TYPE
    Func = PROCEDURE(a,b,c,d,e,f,g,h: INTEGER): INTEGER;
    Procedure* = POINTER TO ProcedureDesc;
    Overlay* = POINTER TO OverlayDesc;
    FileName = ARRAY 20 OF CHAR;

    ProcedureDesc* = RECORD
      addr*: INTEGER; (* relative address within overlay; i.e. proc address assuming overlay starts at address 0 *)
      mod*: Modules.Module; (* module this proc belongs to *)
      index*: INTEGER; (* toc index of proc for module *)
      next*: Procedure;
    END;

    OverlayDesc* = RECORD
      filename: FileName;
      mapped*: INTEGER; (*address: start of mapped overlay*)
      size: INTEGER; (* length of code segment; excludes footer *)
      numproc: INTEGER; (* number of procedures covered by this overlay *)
      proc*: Procedure; (* list of procedures in overlay *)
    END;

  VAR regions: ARRAY numRegions OF INTEGER; (*reserved addresses to map overlays onto*)
    overlays: ARRAY numOverlays OF Overlay;
    mappedIndex, stackLoc: INTEGER; (* index into table of overlay that is currently mapped *)

  PROCEDURE ThisFile(proc: Procedure): Files.File;
    VAR i: INTEGER;
      mod: Modules.Module;
      filename: FileDir.FileName;
  BEGIN
    i := 0;
    mod := proc.mod;
    WHILE mod.name[i] # 0X DO filename[i] := mod.name[i]; INC(i) END ;
    filename[i] := "_";
    filename[i+1] := CHR(proc.index + 65); (* make files somewhat human readable *)
    filename[i+2] := "."; filename[i+3] := "o"; filename[i+4] := "v"; filename[i+5] := "l"; filename[i+6] := 0X;
    RETURN Files.Old(filename)
  END ThisFile;

  (* TODO, we need to fixup SB references every time we load an overlay ... *)
  PROCEDURE OverlayManager(a,b,c,d,e,f,g,h: INTEGER): INTEGER;
    VAR i, mno, pno, addr, oldmapped, oldIndex: INTEGER;
      ov, old: Overlay;
      proc: Procedure; body: Func;

    PROCEDURE LoadOverlay(ov, old: Overlay; mno, pno: INTEGER): Func;
    VAR F: Files.File; R: Files.Rider; found: BOOLEAN;
      i, u, addr: INTEGER;
      proc: Procedure; body: Func;

    BEGIN
      F := Files.Old(ov.filename);
      SYSTEM.PUT(-60, 0F0000FH);
      SYSTEM.PUT(-60, pno);
      SYSTEM.PUT(-60, ov.proc.mod.key);
      SYSTEM.PUT(-60, ov.size);
      IF F # NIL THEN
        i := ov.proc.mod.key;
        ov.mapped := regions[0]; IF old # NIL THEN old.mapped := 0; END;
        Files.Set(R, F, 0);
        i := 0;
        WHILE i < ov.size DO
          Files.ReadInt(R, u); SYSTEM.PUT(ov.mapped + i, u);
          INC(i, 4);
        END;
        i := ov.proc.mod.key;
        IF old # NIL THEN
          proc := old.proc;
          WHILE proc # NIL DO
            SYSTEM.PUT(proc.mod.data + proc.index, SYSTEM.ADR(OverlayManager));
            proc := proc.next;
          END;
        END;
        proc := ov.proc;
        (* Fill in correct addresses to TOC *)
        found := FALSE; (* these are temporarily here, just to make dev work easier *)
        WHILE proc # NIL DO
          addr := proc.mod.data + proc.index;
          SYSTEM.PUT(addr, proc.addr + ov.mapped);
          IF proc.index = pno THEN
            u := proc.addr + ov.mapped;
            body := SYSTEM.VAL(Func, u);
            found := TRUE;
          END;

          proc := proc.next;
        END;
      ELSE SYSTEM.PUT(-60, 0FAFAFAH);
      END;
      ASSERT((pno < 0) OR (found));
      RETURN body
    END LoadOverlay;

  BEGIN
    SYSTEM.PUT(-60, 0AABBCCDDH);
    mno := SYSTEM.REG(30) DIV C12 MOD C12;
    pno := SYSTEM.REG(30) DIV C24 MOD C8;
    i := 0;
    (* TODO we will later store /the actual overlay index/ in the address token *)
    (* this is just a stopgap so we can test small parts at a time*)
    (* this is currently ~guaranteed(!) to find a hit, hence the lack of safety *)
    (* TODO: MAKE THIS SAFE *)
    SYSTEM.PUT(-60, SYSTEM.REG(30));
    WHILE overlays[i].proc.mod.num # mno DO INC(i) END;
    ov := overlays[i];
    pno := (ov.proc.mod.procs - ov.proc.mod.data) + pno * 4;
    IF ov.mapped = 0 THEN
      IF (mappedIndex >= 0) & (mappedIndex # i) THEN
        old := overlays[mappedIndex];
        oldmapped := old.mapped;
      ELSE old := NIL; oldmapped := -1024;
      END;
      oldIndex := mappedIndex;
      mappedIndex := i;
      (*
      ovindex := word DIV 1 MOD 400000H; ov := overlays[ovindex];
      *)
      body := LoadOverlay(ov, old, mno, pno);
      i := body(a,b,c,d,e,f,g,h);
      IF (old # NIL) & (oldmapped = ov.mapped) THEN
        body := LoadOverlay(old, ov, -1, -1);
        mappedIndex := oldIndex;
      END;
    ELSE
      (* this shouldn't happen in the current system *)
      SYSTEM.PUT(-60, 0DADA1H);
    END;
    RETURN i
  END OverlayManager;

  (* generate overlay for given module already in memory*)
  PROCEDURE GenerateOverlay*(mod: Modules.Module; numproc: INTEGER);
    VAR i, u, tocoffset, adr, inst, mno, disp, op: INTEGER;
      root, proc: Procedure; impmod: Modules.Module;
      F: Files.File; R: Files.Rider;
      filename: FileName;
      ov: Overlay;
  BEGIN
    NEW(ov); i := 0;
    WHILE overlays[i] # NIL DO INC(i) END;
    overlays[i] := ov;
    (*First, initialise the list of procedures contained in the overlay.*)
    (*Create a linked list of `Procedure` filled in with pointers to procedure addresses; *)
    (*this is later used to fill in the TOC.*)
    tocoffset := mod.procs - mod.data;
    i := 0;
    NEW(root); root.mod := mod; root.index := tocoffset + i; SYSTEM.GET(mod.procs, root.addr);
    WHILE i < numproc * 4 DO
      (*assume procs is ordered*)
      NEW(proc); proc.mod := mod; proc.index := tocoffset + i; SYSTEM.GET(mod.procs + i, proc.addr);
      (* for now, assume that upon generating an overlay, it is safe to replace all calls to procs *)
      (* contained in the overlay with calls to the overlay manager. *)
      (* NOTE: this will break if we generate a new overlay that includes a function that is currently loaded*)
      SYSTEM.PUT(mod.procs + i, SYSTEM.ADR(OverlayManager));
      proc.next := root; root := proc;
      INC(i, 4);
    END;

    (*Create the file "mod.ovl"*)
    i := 0;
    WHILE mod.name[i] # 0X DO filename[i] := mod.name[i]; INC(i) END;
    filename[i] := "."; filename[i+1] := "o"; filename[i+2] := "v"; filename[i+3] := "l";
    filename[i+4] := 0X;
    F := Files.New(filename);
    Files.Set(R, F, 0);

    (* generate stubs for loading outgoing overlays *)
    (*
    i := mod.imp;
    WHILE i < mod.cmd DO
      SYSTEM.GET(i, impmod);

      INC(i, 4);
    END; *)
    (* TODO generate stubs here ? *)
    (*Copy code into "mod.ovl"*)
    i := mod.code;
    WHILE i < mod.imp DO SYSTEM.GET(i, u); Files.WriteInt(R, u); INC(i, 4) END;
    Files.Register(F);
    (* initialise overlay object, add it to overlay table *)
    ov.filename := filename;
    ov.size := i - mod.code; (* identifies the length of the code segment to be loaded *)
    ov.numproc := numproc;
    ov.proc := root;
    ov.mapped := 0;
  END GenerateOverlay;

  (*
  PROCEDURE SerializeProc(VAR R: Files.Rider; p: Procedure);
  BEGIN
    Files.WriteInt(R, p.addr);
    Files.WriteInt(R, p.mod.key);
    Files.WriteInt(R, p.index); (*this will not be portable if the source code changes but the smb file doesn't, TODO*)
  END SerializeProc;

  PROCEDURE SerializeOverlay*(VAR R: Files.Rider; ov: Overlay);
    VAR p: Procedure;
  BEGIN
    Files.WriteString(R, ov.filename);
    Files.WriteInt(R, ov.numproc);
    p := ov.proc;
    WHILE p # NIL DO SerializeProc(R, p); p := p.next END;
  END SerializeOverlay;
  *)
  PROCEDURE Init*;
    VAR i: INTEGER;
  BEGIN
    Modules.Init;
    regions[0] := Modules.limit;
    mappedIndex := -1;
    stackLoc := 0;
    (* load location of the overlay manager *)
    SYSTEM.LDREG(31, SYSTEM.ADR(OverlayManager));
  END Init;

END Overlays.
