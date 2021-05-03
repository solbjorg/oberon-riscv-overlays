MODULE Overlays;
  IMPORT SYSTEM, Kernel, FileDir, Files;
  CONST numRegions = 1;
    numOverlays = 300;
    numIndices = 1; (* maximum number of overlays possible to map at once *)
    maxNumProcs* = 200;
    maxNumMods* = 10;
    (*regionSize* = 0D000H;*)
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

  TYPE Module* = POINTER TO ModDesc;
    Procedure* = POINTER TO ProcedureDesc;
    Func = PROCEDURE(a,b,c,d,e,f,g,h,i,j,l,m: INTEGER): INTEGER;
    Overlay* = POINTER TO OverlayDesc;
    OverlayList* = POINTER TO OverlayListDesc;
    ModuleName* = ARRAY 32 OF CHAR;

    ModDesc* = RECORD
      name*: ModuleName;
      next*: Module;
      key*, num*, size*, refcnt*: INTEGER;
      data*, procs*, stubs*, code*, imp*, cmd*, ent*, ptr*: INTEGER  (*addresses*)
    END ;

    (* procedure in overlay *)
    ProcedureDesc* = RECORD
      addr*: INTEGER; (* relative address within module; i.e. proc address assuming overlay starts at address 0 *)
      size*: INTEGER;
      index*: INTEGER; (* toc index of proc for module *)
    END;

    OverlayDesc* = RECORD
      mapped*: INTEGER; (*address: start of mapped overlay*)
      sector: INTEGER;
      heapsize: INTEGER; (* size in terms of blocks in the heap (i.e. at 256B granularity)*)
      size: INTEGER; (* length of code segment *)
      mod: Module;
      pno: INTEGER;
    END;

    (* make this a linked list, TODO *)
    OverlayListDesc = RECORD
      list: ARRAY numOverlays OF Overlay;
    END;

  VAR overlays: OverlayList;
    mappedIndices: ARRAY numIndices OF INTEGER;  (* index into table of overlay that is currently mapped *)
    numGeneratedOverlays*, lastMapped, numMapped, stackLoc: INTEGER;
    overlayIndex: INTEGER;
    mappedSector, addressOVM*: INTEGER;
    GarbageCollector: PROCEDURE;

  PROCEDURE FillTOC(ov: Overlay; evict: BOOLEAN);
    VAR addr: INTEGER;
  BEGIN
    IF evict THEN
      addr := addressOVM;
    ELSE
      addr := ov.mapped;
    END;
    SYSTEM.PUT(ov.mod.procs + ov.pno * 4, addr);
  END FillTOC;

  PROCEDURE WriteFixedModule*(mod: Module; size: INTEGER): INTEGER;
    VAR i, sec: INTEGER;
  BEGIN
    sec := mappedSector;
    FOR i := 0 TO size BY FileDir.SectorSize DO
      Kernel.PutMemToSector(mappedSector*29, mod.code + i, FileDir.SectorSize);
      INC(mappedSector);
    END;
    RETURN sec * 29
  END WriteFixedModule;

  PROCEDURE EvictCollectedOverlays*();
    VAR i, mark: INTEGER; ov: Overlay;
      evictedSize: INTEGER;
  BEGIN
    evictedSize := 0;
    FOR i := 0 TO numGeneratedOverlays-1 DO
      ov := overlays.list[i];
      IF ov.mapped > 0 THEN
        SYSTEM.GET(ov.mapped-4, mark);
        SYSTEM.PUT(-60, mark);
        IF mark = 0 THEN
          ov.mapped := 0;
          FillTOC(ov, TRUE);
          INC(evictedSize, ov.heapsize);
        END;
      END;
    END;
    SYSTEM.PUT(-60, 0CAFEBABEH);
    SYSTEM.PUT(-60, evictedSize);
  END EvictCollectedOverlays;

  PROCEDURE CheckMarks*();
    VAR ov: Overlay; i, mark: INTEGER;
  BEGIN
          SYSTEM.PUT(-60, 0CAFECAFEH);
    FOR i := 0 TO numGeneratedOverlays-1 DO
      ov := overlays.list[i];
      IF ov.mapped > 0 THEN
        SYSTEM.GET(ov.mapped-4, mark);
        IF mark # 0 THEN
          SYSTEM.PUT(-60, mark);
        END;
      END;
    END;
  END CheckMarks;

  PROCEDURE FreeModule*(mno: INTEGER);
    VAR i: INTEGER; ov: Overlay;
  BEGIN
    FOR i := numGeneratedOverlays-1 TO 0 DO
      IF overlays.list[i].mod.num = mno THEN
        overlays.list[i] := NIL;
      END;
    END;
  END FreeModule;

  (* changes the mark on the overlay, to communicate with the garbage collector *)
  PROCEDURE ChangeMark(ptr: LONGINT; increase: BOOLEAN);
    VAR mark: INTEGER;
  BEGIN
    SYSTEM.GET(ptr-4, mark);
    IF increase THEN INC(mark) ELSE DEC(mark) END;
    SYSTEM.PUT(-60, 0CCC00000H);
    SYSTEM.PUT(-60, mark);
    SYSTEM.PUT(ptr-4, mark);
  END ChangeMark;

  PROCEDURE LoadOverlay(ov: Overlay);
  VAR F: Files.File; R: Files.Rider;
    i, j, addr, u, seccnt, lim: INTEGER;
    proc: Procedure;
  BEGIN
    IF (Kernel.allocated + ov.heapsize >= Kernel.heapLim - Kernel.heapOrg) THEN
      GarbageCollector;
      IF (Kernel.allocated + ov.heapsize >= Kernel.heapLim - Kernel.heapOrg) THEN
        (* panic! out of memory *)
        SYSTEM.PUT(-60, 0AFFFFAFFH);
        SYSTEM.EBREAK();
      END;
    END;
    Kernel.NewOverlay(ov.mapped, ov.heapsize);
    IF ov.mapped = 0 THEN
      SYSTEM.PUT(-60, 0AAEEEH);
      SYSTEM.EBREAK();
    END;
    FOR i := 0 TO ov.size BY FileDir.SectorSize DO
      Kernel.GetSectorToMem((ov.sector + i DIV FileDir.SectorSize) * 29, ov.mapped + i, ov.size - i);
    END;
    FillTOC(ov, FALSE);
  END LoadOverlay;

  PROCEDURE GetOverlayToken*(index: INTEGER): LONGINT;
  BEGIN
    RETURN LSL(-1, 15) + LSL(index MOD 8000H, 1) + 1
  END GetOverlayToken;

  PROCEDURE OverlayManager*(a,b,c,d,e,f,g,h,i,j,l,m: INTEGER): INTEGER;
    VAR k, ra, ovindex, callerindex, pno, addr, size, oldmapped, oldIndex: INTEGER;
      found: BOOLEAN;
      ov, old, temp: Overlay;
      proc: Procedure; body: Func;
  BEGIN
    ra := SYSTEM.REG(1);
    ovindex     := SYSTEM.REG(30) DIV 2 MOD 4000H;
    callerindex := SYSTEM.REG(30) DIV 8000H;

    old := NIL;
    ov := overlays.list[ovindex];
    IF callerindex < 0 THEN
      IF ra >= Kernel.heapOrg THEN
        i := 0; found := FALSE;
        WHILE (i < numGeneratedOverlays) & (old = NIL) DO
          temp := overlays.list[i];
          oldmapped := temp.mapped;
          IF (ra > oldmapped) & (ra < oldmapped + temp.size)  THEN
            old := temp;
          END;
          INC(i);
        END;
      END;
    END;

    IF ov.mapped = 0 THEN
      LoadOverlay(ov);
    ELSE
      (* need a more accurate way of knowing whether the information we have is accurate or not ! *)
      (* in indirect function calls, we don't have accurate information on the overlay index of *)
      (* the calling procedure. so we brute force it *)
    END;
    body := SYSTEM.VAL(Func, ov.mapped);
    ChangeMark(ov.mapped, FALSE);
    k := body(a,b,c,d,e,f,g,h,i,j,l,m);
    ChangeMark(ov.mapped, TRUE);
    IF (old # NIL) & (old.mapped = 0) THEN
      SYSTEM.GET(SYSTEM.REG(2), old.mapped);
      LoadOverlay(old);
      SYSTEM.PUT(-60, old.mapped);
      SYSTEM.EBREAK();
      SYSTEM.PUT(SYSTEM.REG(2), old.mapped);
    END;
    RETURN k
  END OverlayManager;

  (*
  PROCEDURE EvictMappedOverlay*;
    VAR ov: Overlay;
  BEGIN
    IF mappedIndices[0] >= 0 THEN
      ov := overlays[mappedIndices[0]];
      FillTOC(ov, TRUE);
      ov.mapped := 0;
      mappedIndices[0] := -1;
    END
  END EvictMappedOverlay;
  *)

  (* Return the overlay index corresponding to entry point (mno, pno) *)
  PROCEDURE FindOverlayIndex*(mno, pno: INTEGER): INTEGER;
    VAR index: INTEGER;
  BEGIN
    index := numGeneratedOverlays-1;
    SYSTEM.PUT(-60, mno);
    SYSTEM.PUT(-60, pno);
    WHILE (index > 0) & ((mno # overlays.list[index].mod.num) OR (pno # overlays.list[index].pno)) DO
      SYSTEM.PUT(-60, overlays.list[index].mod.num);
      SYSTEM.PUT(-60, overlays.list[index].pno);
      DEC(index)
    END;
    ASSERT((overlays.list[index].mod.num = mno) & (overlays.list[index].pno = pno))
    RETURN index
  END FindOverlayIndex;

  (* takes a module, generates an overlay for every proc in the module *)
  PROCEDURE NewOverlay*(mod: Module; procs: ARRAY OF Procedure; numprocs: INTEGER);
    VAR i, j: INTEGER;
      ov: Overlay;
  BEGIN
    FOR i := 0 TO numprocs-1 DO
      NEW(ov); ov.mapped := 0;
      ov.mod := mod; ov.pno := procs[i].index;
      ov.size := procs[i].size;
      (*
      IF ov.size <= 20 THEN ov.heapsize := 32;
      ELSIF ov.size <= 52 THEN ov.heapsize := 64
      ELSIF ov.size <= 116 THEN ov.heapsize := 128
      ELSE ov.heapsize := (ov.size+271) DIV 256 * 256
      END ; *)

      ov.heapsize := (ov.size+271) DIV 256 * 256;
      overlays.list[numGeneratedOverlays] := ov;
      INC(numGeneratedOverlays);
    END;
  END NewOverlay;

  (* generates overlays for a given module's entry points *)
  (*
  PROCEDURE MakeOverlayModule*(mod: Module; procs: ARRAY OF Procedure; numprocs, size: INTEGER): OverlayModule;
  VAR i: INTEGER; modOverlay: OverlayModule;
  BEGIN
    NEW(modOverlay); ASSERT(modOverlay # NIL);
    modOverlay.size := size;
    modOverlay.mod := mod;
    FOR i := 0 TO numprocs-1 DO
      modOverlay.proc[i] := procs[i];
    END;
    modOverlay.numprocs := numprocs;

    (*NewOverlay(nodes, i);*)
    RETURN modOverlay
  END MakeOverlayModule;

  PROCEDURE MakeNode*(mod: Module; procs: ARRAY OF Procedure; numprocs, size: INTEGER): Node;
    VAR node: Node; modOverlay: OverlayModule;
  BEGIN
    modOverlay := MakeOverlayModule(mod, procs, numprocs, size);
    NEW(node); node.size := size;
    node.nummods := 1;
    node.index := overlayIndex; INC(overlayIndex);
    node.mods[0] := modOverlay;
    RETURN node
  END MakeNode; *)

  (* Write Overlay.ovl based on index into overlay table *)
  (* index: index into ov table; addr: relative address within module; mod: relevant module *)
  PROCEDURE WriteOverlay*(index, addr: INTEGER; mod: Module);
    VAR i, sec: INTEGER; ov: Overlay;
  BEGIN
    ov := overlays.list[index];
    sec := mappedSector;
    FOR i := 0 TO ov.size BY FileDir.SectorSize DO
      Kernel.PutMemToSector(mappedSector*29, mod.code + addr + i, ov.size - i);
      INC(mappedSector);
    END;

    ov.sector := sec;
  END WriteOverlay;

  PROCEDURE SetGC*(gc: PROCEDURE);
  BEGIN GarbageCollector := gc;
  END SetGC;

  PROCEDURE Init*;
    VAR i: INTEGER;
      l: OverlayList;
  BEGIN
    FOR i := 0 TO LEN(mappedIndices)-1 DO
      mappedIndices[i] := -1;
    END;
    numGeneratedOverlays := 0;
    overlayIndex := 0;
    lastMapped := -1;
    stackLoc := 0;
    mappedSector := Kernel.filemapsize + 1;
    addressOVM := SYSTEM.ADR(OverlayManager);
    NEW(l); overlays := l;
    (* load location of the overlay manager to predetermined reg *)
    SYSTEM.LDREG(31, SYSTEM.ADR(OverlayManager));
  END Init;

END Overlays.
