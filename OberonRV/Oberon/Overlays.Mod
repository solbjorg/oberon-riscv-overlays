MODULE Overlays;
  IMPORT SYSTEM, Kernel, FileDir, Files;
  CONST numBaseOverlays = 300;
    numExtendOverlays = 50;
    maxNumProcs* = 200;
    maxNumMods* = 10;
    overlayDescSize = 24;
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
    Func = PROCEDURE;
    Overlay = POINTER TO OverlayDesc;
    OverlayList = POINTER TO OverlayListDesc;
    ModuleName* = ARRAY 32 OF CHAR;
    ResetFunc = PROCEDURE(trap: INTEGER; mod: Module);

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

    OverlayDesc = RECORD
      sector: INTEGER;
      mapped: INTEGER; (*address: start of mapped overlay*)
      heapsize: INTEGER; (* size in terms of blocks in the heap (i.e. at 256B granularity)*)
      size: INTEGER; (* size in terms of blocks in the heap (i.e. at 256B granularity)*)
      mod: Module;
      pno: INTEGER;
    END;

    (* make this a linked list, TODO *)
    OverlayListDesc = RECORD
      list: ARRAY numBaseOverlays OF OverlayDesc;
    END;

  VAR numGeneratedOverlays*, allocated*: INTEGER;
    overlayTableRoot: INTEGER;
    mappedSector, addressOVM*: INTEGER;
    root: Module;
    OberonReset: ResetFunc;

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

  PROCEDURE Evict(ov: Overlay);
  BEGIN
    IF ov.mapped > 0 THEN
      (*
      IF (ov.mod.num = 11) & (ov.pno = 40) THEN
        SYSTEM.PUT(-60, 0FAH);
        SYSTEM.EBREAK();
      END; *)
      SYSTEM.PUT(ov.mapped-8, SYSTEM.ADR(ov.heapsize));
      SYSTEM.PUT(ov.mapped-4, 0);
      ov.mapped := 0;
      (*FillTOC(ov, TRUE);*)
      DEC(allocated, ov.heapsize);
    END;
  END Evict;

  (*
  PROCEDURE FindOutlier(minSize: INTEGER; newest: BOOLEAN): Overlay;
    VAR i, timestamp, lruTime: INTEGER; ov, lruOv: Overlay;
      found: BOOLEAN;
  BEGIN
    (* first find a baseline for "oldest", doesn't matter what it is *)
    (* it might as well be 0, in which case this part can be cut out *)
    found := FALSE; i := 0; lruOv := NIL;
    SYSTEM.PUT(-60, 0FFFF4321H);
    REPEAT
      ov := overlays[i];
      IF (ov # NIL) & (ov.mapped > 0) & (ov.heapsize >= minSize) THEN
        found := TRUE;
        lruOv := ov;
        SYSTEM.GET(lruOv.mapped-4, lruTime);
      END;
      INC(i);
    UNTIL (found) OR (i = numGeneratedOverlays);
    (* iterate through every overlay from then on, to find the least recently used *)
    WHILE i < numGeneratedOverlays DO
      ov := overlays[i];
      IF ov # NIL THEN
        IF (ov.mapped > 0) & (ov.heapsize >= minSize) THEN
          SYSTEM.GET(ov.mapped-4, timestamp);
          IF ((lruTime < 0) & (newest)) OR ((lruTime > 0) & (~newest)) THEN
            IF timestamp < lruTime THEN
              lruTime := timestamp;
            END;
          ELSE
            IF timestamp > lruTime THEN
              lruTime := timestamp;
            END;
          END;
        END;
      END;
      INC(i);
    END;
    RETURN lruOv
  END FindOutlier; *)


  (*
  PROCEDURE EvictLRUOverlay*(minSize: INTEGER);
    VAR lruOv: Overlay;
  BEGIN
    lruOv := FindOutlier(minSize, FALSE); (* find oldest *)
    IF lruOv # NIL THEN Evict(lruOv) END;
  END EvictLRUOverlay; *)

  PROCEDURE GetOverlay(index: INTEGER): Overlay;
  BEGIN
    RETURN SYSTEM.VAL(Overlay, overlayTableRoot + index * overlayDescSize)
  END GetOverlay;

  PROCEDURE CollectOverlays;
    VAR mark, i: INTEGER;
      ov: Overlay;
  BEGIN
    FOR i := 0 TO numGeneratedOverlays-1 DO
      ov := GetOverlay(i);
      IF ov.mapped > 0 THEN
        SYSTEM.GET(ov.mapped-4, mark);
        IF mark = -1 THEN
          SYSTEM.PUT(-60, 0AEAEAH);
          SYSTEM.PUT(-60, ov.mapped-8);
          Evict(ov);
        END;
      END;
    END;
  END CollectOverlays;

  PROCEDURE LocateMod*(loc: INTEGER): Module;
    VAR m: Overlay; i: INTEGER;
      result: Module;
  BEGIN result := NIL;
    IF loc >= Kernel.heapOrg THEN
      i := 0;
      WHILE (i < numGeneratedOverlays) & (result = NIL) DO
        m := GetOverlay(i);
        IF (loc > m.mapped) & (loc < m.mapped + m.heapsize)  THEN
          result := m.mod;
        END;
        INC(i);
      END;
    ELSE
      result := root;
      WHILE (result # NIL) & ((loc < result.code) OR (loc >= result.imp)) DO result := result.next END ;
    END;
    RETURN result
  END LocateMod;

  PROCEDURE EvictAllOverlays*;
    VAR i, mark: INTEGER; ov: Overlay;
  BEGIN
    FOR i := 0 TO numGeneratedOverlays-1 DO
      ov := GetOverlay(i);
      IF ov.mapped > 0 THEN
        Evict(ov);
      END;
    END;
  END EvictAllOverlays;

  (*
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
  END EvictCollectedOverlays; *)

  PROCEDURE GC*(blockSizeNeeded: INTEGER; isData: BOOLEAN);
    VAR mod: Module; ov: Overlay;
  BEGIN
    SYSTEM.PUT(-60, 06CH);
    (*SYSTEM.EBREAK();*)
    mod := root;
    WHILE mod # NIL DO
      IF mod.name[0] # 0X THEN
        SYSTEM.PUT(-60, 0ABCDEFH);
        SYSTEM.PUT(-60, mod.num);
        Kernel.MarkMod(mod.ptr)
      END ;
      mod := mod.next
    END ;
    Kernel.MarkStack;
    Files.RestoreList;
    CollectOverlays;
    SYSTEM.PUT(-60, 5C43H);
    Kernel.Scan;
    (*
    IF Kernel.largestFreeBlock < blockSizeNeeded THEN
      ov := FindOutlier(blockSizeNeeded, FALSE);
      IF ov # NIL THEN
        Evict(ov);
        GC(blockSizeNeeded, isData);
      END;
    END; *)
    SYSTEM.PUT(-60, 0C6H);
  END GC;

  PROCEDURE Reset*(trap, loc: INTEGER);
    VAR mod: Module;
  BEGIN
    mod := LocateMod(loc);
    EvictAllOverlays;
    GC(0, FALSE);
    OberonReset(trap, mod);
  END Reset;


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
      SYSTEM.PUT(-60, 0F417H);
      (*EvictLRUOverlay(ov.heapsize);*)
      GC(ov.heapsize, FALSE);
      SYSTEM.PUT(-60, 0E417H);
      SYSTEM.PUT(-60, allocated);
      Kernel.NewOverlay(ov.mapped, ov.heapsize);
      IF ov.mapped = 0 THEN
        (* allocation failed again - no contiguous memory can be allocated. panic. *)
        Reset(0, 0);
      END;
    END;
    FOR i := 0 TO ov.size BY FileDir.SectorSize DO
      Kernel.GetSectorToMem((ov.sector + i DIV FileDir.SectorSize) * 29, ov.mapped + i, ov.size - i);
    END;
    (*FillTOC(ov, FALSE);*)
    INC(allocated, ov.heapsize);
    SYSTEM.PUT(-60, 0CC417H);
  END LoadOverlay;

  PROCEDURE GetOverlayToken*(index: INTEGER): LONGINT;
  BEGIN
    RETURN LSL(-1, 15) + LSL(index MOD 8000H, 1) + 1
  END GetOverlayToken;

  PROCEDURE ChangeMark(ov: Overlay; increase: BOOLEAN);
    VAR mark: INTEGER;
  BEGIN
    SYSTEM.GET(ov.mapped-4, mark);
    SYSTEM.PUT(-60, mark);
    IF increase THEN
      IF mark < -1 THEN
        INC(mark)
      END;
    ELSE DEC(mark)
    END;
    SYSTEM.PUT(ov.mapped-4, mark);
  END ChangeMark;

  PROCEDURE OverlayManager*();
    VAR k, offset: INTEGER;
      ov, old: Overlay; body: Func;
  BEGIN
    SYSTEM.REGSTACK(20);

    k := SYSTEM.REG(30) DIV 8000H; (* k = the overlay index of the calling function *)
    old := NIL;

    (* calculate location of ov in overlay table *)
    ov := SYSTEM.VAL(Overlay, overlayTableRoot + (SYSTEM.REG(30) DIV 2 MOD 4000H) * overlayDescSize);
    SYSTEM.PUT(-60, 0EAEAH);
    IF ov.mapped = 0 THEN
      LoadOverlay(ov);
      SYSTEM.PUT(-60, 1);
    ELSE
      SYSTEM.PUT(-60, 0);
    END;

    SYSTEM.PUT(-60, ov.mod.num);
    SYSTEM.PUT(-60, ov.pno);
    SYSTEM.PUT(-60, ov.mapped);
    body := SYSTEM.VAL(Func, ov.mapped);
    ChangeMark(ov, FALSE);
    SYSTEM.VIRTUALARGS(); body();
    (* discard the saved registers now that they are no longer needed *)
    SYSTEM.REGSTACK(9);
    ChangeMark(ov, TRUE);
    SYSTEM.PUT(-60, 01234H);
    IF old # NIL THEN
      SYSTEM.PUT(-60, old.mapped);
      SYSTEM.PUT(-60, old.mod.num);
      SYSTEM.PUT(-60, old.pno);
      SYSTEM.PUT(-60, old.heapsize);
    END;
    (*
    IF old # NIL THEN
      SYSTEM.PUT(-60, old.mapped);
      SYSTEM.PUT(-60, old.mod.num);
      SYSTEM.PUT(-60, old.pno);
      SYSTEM.PUT(-60, mark);
    END; *)
    (*
    IF (old # NIL) & (old.mapped = 0) THEN
      LoadOverlay(old);
      (* replace RA on the stack with the correct position in the relocated function *)
      SYSTEM.PUT(SYSTEM.REG(2), old.mapped + offset);
      SYSTEM.PUT(-60, 0113H);
      SYSTEM.PUT(-60, old.mapped);
      SYSTEM.PUT(-60, offset);
      SYSTEM.EBREAK();
    END; *)
  END OverlayManager;

  (*
  PROCEDURE OverlayManager*(): INTEGER;
    VAR k: INTEGER; ov: Overlay; body: Func;
  BEGIN
    (* get index into the list of overlay pointers from overlay token *)
    SYSTEM.REGSTACK(20);
    ov := overlays.list[SYSTEM.REG(30) DIV 2 MOD 4000H];

    (* if overlay is not loaded into memory, call overlay loader *)
    IF ov.mapped = 0 THEN LoadOverlay(ov); END;

    body := SYSTEM.VAL(Func, ov.mapped);
    SYSTEM.VIRTUALARGS();
    k := body();
    RETURN k
  END OverlayManager; *)

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
    VAR index: INTEGER; ov: Overlay;
  BEGIN
    index := numGeneratedOverlays-1; ov := GetOverlay(index);
    WHILE (index > 0) & ((mno # ov.mod.num) OR (pno # ov.pno)) DO
      DEC(index); ov := GetOverlay(index);
    END;
    ASSERT((ov.mod.num = mno) & (ov.pno = pno))
    RETURN index
  END FindOverlayIndex;

  (* takes a module, generates an overlay for every proc in the module *)
  PROCEDURE NewOverlay*(mod: Module; procs: ARRAY OF Procedure; numprocs: INTEGER);
    VAR i, j: INTEGER;
      ov: Overlay;
  BEGIN
    FOR i := 0 TO numprocs-1 DO
      ov := SYSTEM.VAL(Overlay, overlayTableRoot + numGeneratedOverlays * overlayDescSize);
      ov.mapped := 0;
      ov.mod := mod; ov.pno := procs[i].index;
      ov.size := procs[i].size;

      IF ov.size <= 20 THEN ov.heapsize := 32;
      ELSIF ov.size <= 52 THEN ov.heapsize := 64
      ELSIF ov.size <= 116 THEN ov.heapsize := 128
      ELSE ov.heapsize := (ov.size+271) DIV 256 * 256
      END ;

      (*ov.heapsize := (ov.size+271) DIV 256 * 256;*)
      SYSTEM.PUT(-60, ov.size);
      SYSTEM.PUT(-60, ov.heapsize);
      (*SYSTEM.EBREAK();*)
      (*overlays[numGeneratedOverlays] := ov;*)
      IF numGeneratedOverlays < numBaseOverlays-1 THEN
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
    ov := GetOverlay(index);
    sec := mappedSector;
    FOR i := 0 TO ov.size BY FileDir.SectorSize DO
      Kernel.PutMemToSector(mappedSector*29, mod.code + addr + i, ov.size - i);
      INC(mappedSector);
    END;

    ov.sector := sec;
  END WriteOverlay;

  PROCEDURE SetReset*(reset: ResetFunc);
  BEGIN OberonReset := reset;
  END SetReset;

  PROCEDURE SetRoot*(r: Module);
  BEGIN root := r;
  END SetRoot;

  PROCEDURE Init*;
    VAR i: INTEGER;
      l: OverlayList;
  BEGIN
    Kernel.SetGC(SYSTEM.ADR(GC));
    Kernel.SetReset(SYSTEM.ADR(Reset));
    numGeneratedOverlays := 0;
    allocated := 0;
    overlayTableRoot := Kernel.stackOrg;
    mappedSector := Kernel.filemapsize + 1;
    addressOVM := SYSTEM.ADR(OverlayManager);
    (* load location of the overlay manager to predetermined reg *)
    (* note: needs cooperation from the compiler *)
    SYSTEM.LDREG(31, SYSTEM.ADR(OverlayManager));
  END Init;

END Overlays.
