MODULE Overlays;
  IMPORT SYSTEM, Kernel, FileDir, Files;
  CONST numBaseOverlays = 500;
    numExtendOverlays = 50;
    maxNumProcs* = 60;
    maxNumMods* = 10;
    overlayDescSize = 16;
    overlayPrefixSize = 8;
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
      data*, procs*, code*, imp*, cmd*, ent*, ptr*: INTEGER  (*addresses*)
    END ;

    (* procedure in overlay *)
    ProcedureDesc* = RECORD
      addr*: INTEGER; (* relative address within module; i.e. proc address assuming overlay starts at address 0 *)
      size*: INTEGER;
      index*: INTEGER; (* toc index of proc for module *)
    END;

    OverlayDesc = RECORD
      mapped: INTEGER; (*address: start of mapped overlay*)
      sector: INTEGER; (*sector on disk*)
      heapsize: INTEGER; (*size in terms of blocks in the heap (i.e. at 256B granularity)*)
      mno: BYTE;
      pno: BYTE;
    END;

    (* make this a linked list, TODO *)
    OverlayListDesc = RECORD
      list: ARRAY numBaseOverlays OF OverlayDesc;
    END;

  VAR numGeneratedOverlays*, allocated*: INTEGER;
    overlayTableRoot: INTEGER; (* base of the overlay table, which is placed between the stack and the heap *)
    (* current sector on the disk that overlays have been written into *)
    (* incremented whenever a new overlay is written *)
    mappedSector: INTEGER;
    addressOVM*: INTEGER; (* address of the overlay manager. constant *)
    root: Module;
    OberonReset: ResetFunc;

  (* evict overlay `ov`, marking it as garbage and marking it as not mapped *)
  (* in the overlay table *)
  PROCEDURE Evict(ov: Overlay);
  BEGIN
    IF ov.mapped > 0 THEN
      SYSTEM.PUT(ov.mapped-overlayPrefixSize, SYSTEM.ADR(ov.heapsize));
      SYSTEM.PUT(ov.mapped-4, 0);
      ov.mapped := 0;
      DEC(allocated, ov.heapsize);
    END;
  END Evict;

  (* get the Overlay record of the overlay at `index` in the table *)
  PROCEDURE GetOverlay(index: INTEGER): Overlay;
  BEGIN
    RETURN SYSTEM.VAL(Overlay, overlayTableRoot + index * overlayDescSize)
  END GetOverlay;

  (* mark overlays not in the call tree as garbage, evict them *)
  PROCEDURE CollectOverlays;
    VAR mark, i: INTEGER;
      ov: Overlay;
  BEGIN
    FOR i := 0 TO numGeneratedOverlays-1 DO
      ov := GetOverlay(i);
      IF ov.mapped > 0 THEN
        SYSTEM.GET(ov.mapped-4, mark);
        IF mark = -1 THEN
          Evict(ov);
        END;
      END;
    END;
  END CollectOverlays;

  (* find out which module a trap occured in; only used for error reporting. *)
  (* takes a `loc` which indicates the position of PC in memory *)
  PROCEDURE LocateMod*(loc: INTEGER): Module;
    VAR m: Overlay; i: INTEGER;
      result: Module;
  BEGIN result := NIL;
    IF loc >= Kernel.heapOrg THEN
      i := 0;
      WHILE (i < numGeneratedOverlays) & (result = NIL) DO
        m := GetOverlay(i);
        IF (loc > m.mapped) & (loc < m.mapped + m.heapsize)  THEN
          result := root;
          WHILE (result # NIL) & (result.num # m.mno) DO
            result := result.next;
          END;
        END;
        INC(i);
      END;
    ELSE
      result := root;
      WHILE (result # NIL) & ((loc < result.code) OR (loc >= result.imp)) DO result := result.next END ;
    END;
    RETURN result
  END LocateMod;

  (* evicts all currently mapped overlays *)
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

  (* garbage collection *)
  PROCEDURE GC*();
    VAR mod: Module; ov: Overlay;
  BEGIN
    mod := root;
    (* mark every loaded module *)
    WHILE mod # NIL DO
      IF mod.name[0] # 0X THEN
        Kernel.MarkMod(mod.ptr);
      END ;
      mod := mod.next
    END ;
    (* mark the stack *)
    Kernel.MarkStack;
    (* special handling for the files list *)
    Files.RestoreList;
    (* remove currently unmarked overlays *)
    CollectOverlays;
    Kernel.Scan;
  END GC;

  PROCEDURE Reset*(trap, loc: INTEGER);
    VAR mod: Module;
  BEGIN
    (* find module in which the trap occured (may be NIL) *)
    mod := LocateMod(loc);
    (* reset state *)
    EvictAllOverlays;
    GC;
    IF OberonReset # NIL THEN OberonReset(trap, mod);
    ELSE REPEAT UNTIL FALSE
    END;
  END Reset;

  PROCEDURE LoadOverlay(ov: Overlay);
    VAR i: INTEGER;
  BEGIN
    Kernel.NewOverlay(ov.mapped, ov.heapsize);
    IF ov.mapped = 0 THEN
      (* allocation failed - run garbage collection and try again *)
      GC;
      Kernel.NewOverlay(ov.mapped, ov.heapsize);
      IF ov.mapped = 0 THEN
        (* allocation failed again - no contiguous memory can be allocated on the heap. panic *)
        (* uncomment the below line if you want to inspect system state in the emulator upon panic: *)
        (*SYSTEM.EBREAK();*)
        Reset(0, 0);
      END;
    END;
    FOR i := 0 TO ov.heapsize BY FileDir.SectorSize DO
      Kernel.GetSectorToMem((ov.sector + i DIV FileDir.SectorSize) * 29, ov.mapped + i, ov.heapsize-12 - i);
    END;
  END LoadOverlay;

  PROCEDURE GetOverlayToken*(index: INTEGER): LONGINT;
  BEGIN
    RETURN LSL(-1, 15) + LSL(index MOD 8000H, 1) + 1
  END GetOverlayToken;

  PROCEDURE OverlayManager*();
    VAR ov: Overlay; k: INTEGER;
  BEGIN
    SYSTEM.REGSTACK(20);

    (*k := SYSTEM.REG(30) DIV 8000H; (* k = the overlay index of the calling function *)*)

    (* calculate location of ov in overlay table *)
    ov := SYSTEM.VAL(Overlay, overlayTableRoot + (SYSTEM.REG(30) DIV 2 MOD 4000H) * overlayDescSize);
    IF ov.mapped = 0 THEN LoadOverlay(ov); END;

    (*ChangeMark(ov, FALSE);*)
    SYSTEM.GET(ov.mapped - 4, k);
    SYSTEM.PUT(ov.mapped - 4, k-1);
    (*SYSTEM.VIRTUALARGS(); body();*)
    SYSTEM.JUMP(ov.mapped);
    (* discard the saved registers now that they are no longer needed *)
    SYSTEM.REGSTACK(9);
    SYSTEM.GET(ov.mapped - 4, k);
    SYSTEM.PUT(ov.mapped - 4, k+1);
    (*ChangeMark(ov, TRUE);*)
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
    WHILE (index > 0) & ((mno # ov.mno) OR (pno # ov.pno)) DO
      DEC(index); ov := GetOverlay(index);
    END;
    ASSERT((ov.mno = mno) & (ov.pno = pno))
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
      ov.mno := mod.num; ov.pno := procs[i].index;

      IF procs[i].size <= 20 THEN ov.heapsize := 32;
      ELSIF procs[i].size <= 52 THEN ov.heapsize := 64
      ELSIF procs[i].size <= 116 THEN ov.heapsize := 128
      ELSE ov.heapsize := (procs[i].size+271) DIV 256 * 256
      END ;

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

  (* Write overlay currently at memory address `mapped` into overlay table *)
  (* index: index into ov table; mapped: memory address overlay is loaded into *)
  PROCEDURE WriteOverlay*(index, mapped: INTEGER);
    VAR i: INTEGER; ov: Overlay;
  BEGIN
    ov := GetOverlay(index);
    ov.sector := mappedSector;
    FOR i := 0 TO ov.heapsize-overlayPrefixSize BY FileDir.SectorSize DO
      Kernel.PutMemToSector(mappedSector*29, mapped + i, ov.heapsize-overlayPrefixSize - i);
      INC(mappedSector);
    END;
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
    OberonReset := NIL;
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
