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
    numGeneratedOverlays*, allocated*, numMapped, stackLoc: INTEGER;
    overlayIndex: INTEGER;
    mappedSector, addressOVM*: INTEGER;
    root: Module;
    Reset: Kernel.ResetFunc;

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

  PROCEDURE Evict(ov: Overlay);
  BEGIN
    SYSTEM.PUT(ov.mapped-8, 0);
    ov.mapped := 0;
    FillTOC(ov, TRUE);
    DEC(allocated, ov.heapsize);
  END Evict;

  PROCEDURE FindOutlier(newest: BOOLEAN): Overlay;
    VAR i, timestamp, lruTime: INTEGER; ov, lruOv: Overlay;
      found: BOOLEAN;
  BEGIN
    (* first find a baseline for "oldest", doesn't matter what it is *)
    (* it might as well be 0, in which case this part can be cut out *)
    found := FALSE; i := 0; lruOv := NIL;
    SYSTEM.PUT(-60, 0FFFF4321H);
    REPEAT
      ov := overlays.list[i];
      IF (ov # NIL) & (ov.mapped > 0) THEN
        found := TRUE;
        lruOv := ov;
        SYSTEM.GET(lruOv.mapped-4, lruTime);
        SYSTEM.PUT(-60, 4321H);
        SYSTEM.PUT(-60, lruOv.mapped);
        SYSTEM.PUT(-60, lruTime);
      END;
      INC(i);
    UNTIL (found) OR (i = numGeneratedOverlays);
    (* iterate through every overlay from then on, to find the least recently used *)
    WHILE i < numGeneratedOverlays DO
      ov := overlays.list[i];
      IF ov # NIL THEN
        IF ov.mapped > 0 THEN
          SYSTEM.GET(ov.mapped-4, timestamp);
          IF ((lruTime < 0) & (newest)) OR ((lruTime > 0) & (~newest)) THEN
            IF timestamp < lruTime THEN
              lruTime := timestamp;
              SYSTEM.PUT(-60, 4321H);
              SYSTEM.PUT(-60, ov.mapped);
              SYSTEM.PUT(-60, timestamp);
            END;
          ELSE
            IF timestamp > lruTime THEN
              lruTime := timestamp;
              SYSTEM.PUT(-60, 4321H);
              SYSTEM.PUT(-60, ov.mapped);
              SYSTEM.PUT(-60, timestamp);
            END;
          END;
        END;
      END;
      INC(i);
    END;
    RETURN lruOv
  END FindOutlier;

  PROCEDURE EvictLRUOverlay*;
    VAR lruOv: Overlay;
  BEGIN
    lruOv := FindOutlier(FALSE); (* find oldest *)
    IF lruOv # NIL THEN Evict(lruOv) END;
  END EvictLRUOverlay;

  PROCEDURE EvictAllOverlays*;
    VAR i, mark: INTEGER; ov: Overlay;
  BEGIN
    FOR i := 0 TO numGeneratedOverlays-1 DO
      ov := overlays.list[i];
      IF ov.mapped > 0 THEN
        Evict(ov);
      END;
    END;
  END EvictAllOverlays;

  PROCEDURE EvictCollectedOverlays*();
    VAR i, mark: INTEGER; ov: Overlay;
  BEGIN
    FOR i := 0 TO numGeneratedOverlays-1 DO
      ov := overlays.list[i];
      IF ov.mapped > 0 THEN
        SYSTEM.GET(ov.mapped-8, mark);
        IF mark = 0 THEN
          ov.mapped := 0;
          FillTOC(ov, TRUE);
          DEC(allocated, ov.heapsize);
        END;
      END;
    END;
  END EvictCollectedOverlays;

  PROCEDURE GC*;
    VAR mod: Module;
  BEGIN
    mod := root;
    WHILE mod # NIL DO
      IF mod.name[0] # 0X THEN Kernel.Mark(mod.ptr) END ;
      mod := mod.next
    END ;
    Files.RestoreList;
    EvictCollectedOverlays;
    Kernel.Scan;
  END GC;

  (* TODO remove this procedure, it is just for debugging *)
  (*
  PROCEDURE FreeModule*(mno: INTEGER);
    VAR i: INTEGER; ov: Overlay;
  BEGIN
    FOR i := numGeneratedOverlays-1 TO 0 DO
      IF overlays.list[i].mod.num = mno THEN
        overlays.list[i] := NIL;
      END;
    END;
  END FreeModule;
 *)

  PROCEDURE LoadOverlay(ov: Overlay);
  VAR i: INTEGER;
  BEGIN
    Kernel.NewOverlay(ov.mapped, ov.heapsize);
    IF ov.mapped = 0 THEN
      (* allocation failed - run garbage collection and try again *)
      SYSTEM.PUT(-60, 0FE7AH);
      REPEAT
        SYSTEM.PUT(-60, 0F417H);
        EvictLRUOverlay;
        GC;
        SYSTEM.PUT(-60, 0E417H);
        SYSTEM.PUT(-60, allocated);
        Kernel.NewOverlay(ov.mapped, ov.heapsize);
      UNTIL (ov.mapped # 0) OR (allocated = 0);
      IF ov.mapped = 0 THEN
        (* allocation failed again - no contiguous memory can be allocated. panic. *)
        Reset(0, 0);
      END;
    END;
    FOR i := 0 TO ov.size BY FileDir.SectorSize DO
      Kernel.GetSectorToMem((ov.sector + i DIV FileDir.SectorSize) * 29, ov.mapped + i, ov.size - i);
    END;
    FillTOC(ov, FALSE);
    INC(allocated, ov.heapsize);
  END LoadOverlay;

  PROCEDURE GetOverlayToken*(index: INTEGER): LONGINT;
  BEGIN
    RETURN LSL(-1, 15) + LSL(index MOD 8000H, 1) + 1
  END GetOverlayToken;

  PROCEDURE OverlayManager*(a,b,c,d,e,f,g,h,i,j,l,m: INTEGER): INTEGER;
    VAR k, ra, ovindex, callerindex, offset: INTEGER;
      ov, old, temp: Overlay; body: Func;
  BEGIN
    ra := SYSTEM.REG(1);
    ovindex     := SYSTEM.REG(30) DIV 2 MOD 4000H;
    callerindex := SYSTEM.REG(30) DIV 8000H;
    ov := overlays.list[ovindex];

    old := NIL;
    (* if an indirect function call, we can't easily determine what function it was called from *)
    (* note: this shouldn't be necessary with a "call tree" approach! *)
    IF callerindex < 0 THEN
      IF ra >= Kernel.heapOrg THEN
        i := 0;
        WHILE (i < numGeneratedOverlays) & (old = NIL) DO
          temp := overlays.list[i];
          IF (ra > temp.mapped) & (ra < temp.mapped + temp.size)  THEN
            old := temp;
          END;
          INC(i);
        END;
      END;
    ELSE old := overlays.list[callerindex];
    END;
    IF old # NIL THEN offset := ra - old.mapped END;

    IF ov.mapped = 0 THEN
      LoadOverlay(ov);
    END;

    body := SYSTEM.VAL(Func, ov.mapped);
    SYSTEM.PUT(-60, 0112H);
    SYSTEM.PUT(-60, ov.mapped);
    k := body(a,b,c,d,e,f,g,h,i,j,l,m);
    IF (old # NIL) & (old.mapped = 0) THEN
      LoadOverlay(old);
      SYSTEM.PUT(-60, old.mod.num);
      SYSTEM.PUT(-60, old.pno);
      SYSTEM.PUT(SYSTEM.REG(2), old.mapped + offset);
    END;
    IF Kernel.stackOrg-SYSTEM.REG(2) > Kernel.stackSize THEN
      SYSTEM.PUT(-60, 0DEADBEEFH);
      SYSTEM.PUT(-60, Kernel.stackOrg-SYSTEM.REG(2));
      SYSTEM.EBREAK();
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
    WHILE (index > 0) & ((mno # overlays.list[index].mod.num) OR (pno # overlays.list[index].pno)) DO
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

      ov.heapsize := (ov.size+275) DIV 256 * 256;
      overlays.list[numGeneratedOverlays] := ov;
      IF numGeneratedOverlays < numOverlays-1 THEN
        INC(numGeneratedOverlays);
      ELSE
        (* panic! *)
        SYSTEM.PUT(-60, 0DEADDEADH);
        SYSTEM.EBREAK();
      END;
    END;
  END NewOverlay;

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

  PROCEDURE SetReset*(reset: Kernel.ResetFunc);
  BEGIN Reset := reset;
  END SetReset;

  PROCEDURE SetRoot*(r: Module);
  BEGIN root := r;
  END SetRoot;

  PROCEDURE LocateMod*(loc: INTEGER): Module;
    VAR m: Overlay; i: INTEGER;
      result: Module;
  BEGIN
    result := NIL;
    IF loc >= Kernel.heapOrg THEN
      i := 0;
      WHILE (i < numGeneratedOverlays) & (result = NIL) DO
        m := overlays.list[i];
        IF (loc > m.mapped) & (loc < m.mapped + m.size)  THEN
          result := m.mod;
        END;
        INC(i);
      END;
    END;
    RETURN result
  END LocateMod;

  PROCEDURE Init*;
    VAR i: INTEGER;
      l: OverlayList;
  BEGIN
    Kernel.SetGC(SYSTEM.ADR(GC));
    numGeneratedOverlays := 0;
    allocated := 0;
    mappedSector := Kernel.filemapsize + 1;
    addressOVM := SYSTEM.ADR(OverlayManager);
    NEW(l); overlays := l;
    (* load location of the overlay manager to predetermined reg *)
    SYSTEM.LDREG(31, SYSTEM.ADR(OverlayManager));
  END Init;

END Overlays.
