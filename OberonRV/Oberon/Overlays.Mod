MODULE Overlays;
  IMPORT SYSTEM, Kernel, FileDir, Files;
  CONST numRegions = 1;
    numOverlays = 100;
    numIndices = 2; (* maximum number of overlays possible to map at once *)
    maxNumProcs* = 60;
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
    Node* = POINTER TO NodeDesc;
    Procedure* = POINTER TO ProcedureDesc;
    Edge* = POINTER TO EdgeDesc; (*outgoing calls*)
    Func = PROCEDURE(a,b,c,d,e,f,g,h,i,j,l,m: INTEGER): INTEGER;
    OverlayModule* = POINTER TO OverlayModuleDesc;
    Overlay* = POINTER TO OverlayDesc;
    FileName* = ARRAY 32 OF CHAR;
    ModuleName* = ARRAY 32 OF CHAR;

    ModDesc* = RECORD
      name*: ModuleName;
      next*: Module;
      rootNode*: Node;
      key*, num*, size*, refcnt*: INTEGER;
      data*, procs*, stubs*, code*, imp*, cmd*, ent*, ptr*: INTEGER  (*addresses*)
    END ;

    (* TODO: the data structures Node and Procedure overlap in some rather *)
    (* nasty ways. In particular, although Procedure is per-procedure in an overlay, *)
    (* a lot of its information will be duplicated as a procedure is shared across overlays. *)
    (* Ideally, this duplicated information shall be held in the node, and the Overlay-specific *)
    (* information will be stored along with a pointer to the more general node. *)
    (* node in inter-module call graph *)
    NodeDesc* = RECORD
      dsc*: Edge;
      size*: INTEGER; (* size of modules *)
      index: INTEGER;
      nummods: INTEGER;
      mods*: ARRAY maxNumMods OF OverlayModule;
    END;

    EdgeDesc* = RECORD
      next*: Edge;
      node*: Node;
      weight*: INTEGER; (* TODO: Make this a Byte? *)
    END;

    (* procedure in overlay *)
    ProcedureDesc* = RECORD
      addr*: INTEGER; (* relative address within module; i.e. proc address assuming overlay starts at address 0 *)
      index*: INTEGER; (* toc index of proc for module *)
    END;

    OverlayModuleDesc* = RECORD
      sec*: INTEGER; (* start sector on disk *)
      size*: INTEGER; (* pos size; needed to load into overlay *)
      mod*: Module;
      numprocs: INTEGER;
      proc*: ARRAY maxNumProcs OF Procedure;
    END;

    OverlayDesc* = RECORD
      sector: INTEGER;
      mapped*: INTEGER; (*address: start of mapped overlay*)
      size: INTEGER; (* length of code segment; excludes footer *)
      nummods: INTEGER;
      mods*: ARRAY maxNumMods OF OverlayModule;
      entryMno*: SET;
    END;

  VAR overlays: ARRAY numOverlays OF Overlay;
    numGeneratedOverlays, lastMapped, numMapped,
      stackLoc: INTEGER;
    overlayIndex: INTEGER;
    mappedSector: INTEGER;
    mappedIndices: ARRAY numIndices OF INTEGER;  (* index into table of overlay that is currently mapped *)
    addressOVM*: INTEGER; (* address of the overlay manager *)

    (*
  PROCEDURE FindIncidentEdges(root, n: Node): ARRAY 10 OF Edge;
    VAR edges: ARRAY 10 OF Edge; numedges: INTEGER;
      m: Node;
  BEGIN
    numedges := 0; m := NIL;
    WHILE
  END FindIncidentEdges; *)

    (*
  (* merges node m into node n *)
  (* does not take care of edges! *)
  PROCEDURE MergeNodes(VAR n: Node; m: Node);
    VAR i, j: INTEGER; ovMod, newOvMod: OverlayModule;
  BEGIN
    FOR i := 0 TO m.nummods-1 DO
      ovMod := m.mods[i];
      (* TODO this can be made more efficient with SYSTEM.COPY, if need be *)
      NEW(newOvMod); newOvMod.size := ovMod.size; newOvMod.mod := ovMod.mod; newOvMod.numprocs := ovMod.numprocs;
      FOR j := 0 TO ovMod.numprocs-1 DO
        NEW(newOvMod.proc[j]);
        newOvMod.proc[j].addr := ovMod.proc[j].addr + n.size;
        newOvMod.proc[j].index := ovMod.proc[j].index;
      END;
      n.mods[n.nummods + i] := newOvMod;
      (* assume no duplication *)
      m.mods[i].mod.rootNode := n;
    END;
    INC(n.nummods, i+1);
    n.size := n.size + m.size;
  END MergeNodes;

  PROCEDURE RedirectEdges(VAR top, dyingnode, newnode: Node);
    VAR e: Edge;
  BEGIN
    e := top.dsc;
    WHILE e # NIL DO
      IF e.node = dyingnode THEN
        e.node := newnode;
      ELSE
        RedirectEdges(e.node, dyingnode, newnode);
      END;
      e := e.next;
    END;
  END RedirectEdges;

  PROCEDURE CollapseNodes(VAR root, top: Node): BOOLEAN;
    VAR prev, e: Edge; isLeaf, isChildLeaf: BOOLEAN;
  BEGIN
    e := root.dsc; isLeaf := FALSE;
    IF e = NIL THEN
      (* "leaf" in DAG *)
      isLeaf := TRUE;
    ELSE
      prev := NIL;
      WHILE e # NIL DO
        isChildLeaf := CollapseNodes(e.node, top);
        IF (isChildLeaf) THEN
          MergeNodes(root, e.node);
          RedirectEdges(top, e.node, root);
          (* remove e from linked list *)
          IF prev # NIL THEN
            (* this will also work if e.next is the last edge in the LL, as then *)
            (* prev.next := NIL *)
            prev.next := e.next;
          ELSE
            root.dsc := e.next;
          END;
        ELSE
          prev := e;
        END;
        e := e.next;
      END;
      (* if, after collapsing all child nodes, there are none left, *)
      (* this is now a leaf *)
      IF root.dsc = NIL THEN
        isLeaf := TRUE;
      END;
    END;
    SYSTEM.PUT(-60, 0FFFH);
    SYSTEM.PUT(-60, root.size);
    RETURN isLeaf
  END CollapseNodes;

  PROCEDURE CollapseNode*(VAR root: Node);
    VAR b: BOOLEAN;
  BEGIN
    b := CollapseNodes(root, root);
  END CollapseNode; *)

  PROCEDURE WriteFixedModule*(mod: Module; size: INTEGER): INTEGER;
    VAR i, sec: INTEGER;
  BEGIN
    sec := mappedSector;
    FOR i := 0 TO size BY 1024 DO
      Kernel.PutMemToSector(mappedSector*29, mod.code + i, 1024);
      INC(mappedSector);
    END;
    RETURN sec * 29
  END WriteFixedModule;

  PROCEDURE GetFixModFile(ovmod: OverlayModule): Files.File;
    VAR i: INTEGER;
      mod: Module;
      filename: FileDir.FileName;
  BEGIN
    i := 0;
    mod := ovmod.mod;
    WHILE mod.name[i] # 0X DO filename[i] := mod.name[i]; INC(i) END ;
    (*
    filename[i] := "_";
    filename[i+1] := CHR(proc.index + 65); (* make files somewhat human readable *) *)
    filename[i] := "."; filename[i+1] := "f"; filename[i+2] := "i"; filename[i+3] := "x";
    filename[i+4] := 0X;
    RETURN Files.Old(filename)
  END GetFixModFile;

  PROCEDURE FillTOC(ov: Overlay; evict: BOOLEAN);
    VAR i, j, addr: INTEGER; modOv: OverlayModule; proc: Procedure;
  BEGIN
    FOR i := 0 TO ov.nummods-1 DO
      modOv := ov.mods[i];
      FOR j := 0 TO modOv.numprocs-1 DO
        proc := modOv.proc[j];
        IF evict THEN
          addr := addressOVM;
        ELSE
          addr := ov.mapped + proc.addr;
        END;
        SYSTEM.PUT(modOv.mod.data + proc.index, addr);
      END
    END
  END FillTOC;

  PROCEDURE OverlayManager*(a,b,c,d,e,f,g,h,i,j,l,m: INTEGER): INTEGER;
    VAR k, ovindex, offset, pno, addr, size, oldmapped, oldIndex: INTEGER;
      found: BOOLEAN;
      ov, old: Overlay;
      proc: Procedure; body: Func;

    PROCEDURE LoadOverlay(ov, old: Overlay);
    VAR F: Files.File; R: Files.Rider; 
      i, j, addr, u, seccnt, lim: INTEGER;
      proc: Procedure;
    BEGIN
      (*F := Files.Old(ov.filename);*)
      (*
      IF old # NIL THEN
          Kernel.FreeOverlay(old.mapped, old.size);
      END;
      *)
      (*IF ov.size MOD 256 # 0 THEN SYSTEM.EBREAK(); END;*)
      Kernel.NewOverlay(ov.mapped, ov.size);
      (*ASSERT(ov.mapped + ov.size < Kernel.heapOrg);*)
      (*Files.ReadFileToMem(R, ov.mapped);*)
      (*
      IF old # NIL THEN
          FillTOC(old, TRUE);
      END; *)
      seccnt := ov.size DIV FileDir.SectorSize;
      SYSTEM.PUT(-60, ov.size);
      SYSTEM.PUT(-60, ov.mapped);
      SYSTEM.PUT(-60, seccnt);
      FOR i := 0 TO seccnt DO
        lim := ov.size - i * FileDir.SectorSize;
        SYSTEM.PUT(-60, lim);
        Kernel.GetSectorToMem((ov.sector + i) * 29, ov.mapped + i * FileDir.SectorSize, lim);
      END;
      FillTOC(ov, FALSE);
    END LoadOverlay;

  BEGIN
    ovindex := SYSTEM.REG(30) DIV 2 MOD 4000H;
    offset := (SYSTEM.REG(30) DIV 8000H) * 4;

    ov := overlays[ovindex];
    IF ov.mapped = 0 THEN
      IF (mappedIndices[0] >= 0) & (mappedIndices[0] # ovindex) THEN
        old := overlays[mappedIndices[0]];
        oldmapped := old.mapped;
      ELSE old := NIL; oldmapped := -1024;
      END;
      oldIndex := mappedIndices[0];
      mappedIndices[0] := ovindex;
      (*
      ovindex := word DIV 1 MOD 400000H; ov := overlays[ovindex];
      *)
      LoadOverlay(ov, old);

      (* call function in loaded overlay *)
      body := SYSTEM.VAL(Func, ov.mapped + offset);
      k := body(a,b,c,d,e,f,g,h,i,j,l,m);

      (*
      IF (old # NIL) & (old.mapped = 0) THEN
        LoadOverlay(old, ov);
        mappedIndices[0] := oldIndex;
      END; *)
    ELSE
      (* probably indirect function call within same module *)
      body := SYSTEM.VAL(Func, ov.mapped + offset);
      k := body(a,b,c,d,e,f,g,h,i,j,l,m);
    END;
    RETURN k
  END OverlayManager;

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

  (* Return the overlay index corresponding to entry point (mno, pno) *)
  (* Currently only checks mno, TODO *)
  PROCEDURE FindOverlayIndex*(mno, pno: INTEGER): INTEGER;
    VAR index: INTEGER;
  BEGIN
    index := numGeneratedOverlays-1;
    SYSTEM.PUT(-60, 0FF000000H+index);
    SYSTEM.PUT(-60, SYSTEM.VAL(INTEGER, overlays[index].entryMno));
    WHILE (index >= 0) & ~(mno IN overlays[index].entryMno) DO DEC(index) END;
    ASSERT(overlays[index] # NIL);
    SYSTEM.PUT(-60, index);
    RETURN index
  END FindOverlayIndex;

  (* Return the function offset corresponding to entry point (mno, pno) in given overlay index *)
  PROCEDURE FindProcedureOffset*(mno, pno, index: INTEGER): INTEGER;
    VAR ov: Overlay; proc: Procedure; mod: Module; ovMod: OverlayModule;
      i, j, procIndex, offset, addr: INTEGER;
  BEGIN
    ov := overlays[index];
    addr := -1;
    IF ov # NIL THEN
      i := 0; ovMod := NIL;
      WHILE (i < ov.nummods) & ((ovMod = NIL) OR (ovMod.mod.num # mno)) DO
        ovMod := ov.mods[i]; INC(i);
      END;
      mod := ovMod.mod;
      procIndex := (mod.procs - mod.data) + pno * 4;
      i := 0; proc := NIL;
      (* PROC NOT FOUND HERE *)
      WHILE (i < ovMod.numprocs) & ((proc = NIL) OR (proc.index # procIndex)) DO
        proc := ovMod.proc[i]; INC(i);
      END;

      IF proc # NIL THEN addr := proc.addr;
      ELSE
        SYSTEM.PUT(-60, 0AAAEEEH);
        SYSTEM.EBREAK();
      END;
    ELSE
      SYSTEM.PUT(-60, 0BBBEEEH);
      SYSTEM.PUT(-60, index);
      SYSTEM.EBREAK();
    END;

    (* invariant: if module is not part of inner core, then *)
    (* procedure offset must be discoverable *)
    ASSERT((mno < 7) OR (addr >= 0));
    RETURN addr
  END FindProcedureOffset;

  (* generate overlay for an array of module nodes*)
  (* returns index in overlay table *)
  PROCEDURE NewOverlay*(nodes: ARRAY OF Node; numnodes: INTEGER);
    VAR i, j: INTEGER;
      node: Node;
      ov: Overlay;
  BEGIN
    NEW(ov); ov.nummods := 0; ov.size := 0; ov.entryMno := {};
    i := 0;
    WHILE overlays[i] # NIL DO INC(i) END;
    (* add the overlay we're about to generate to the table *)
    overlays[i] := ov;
    numGeneratedOverlays := i+1;
    (*First, initialise the list of procedures contained in the overlay.*)
    (*Create a linked list of `Procedure` filled in with pointers to procedure addresses; *)
    (*this is later used to fill in the TOC.*)
    FOR i := 0 TO numnodes-1 DO
      node := nodes[i];
      FOR j := 0 TO node.nummods-1 DO
        ov.mods[j] := node.mods[j];
        INC(ov.size, node.mods[j].size);
        INCL(ov.entryMno, node.mods[j].mod.num);
        INC(ov.nummods);
      END;
    END;
    (*ov.size := (ov.size+263) DIV 256 * 256;*)
    SYSTEM.PUT(-60, 0C1AH);
    SYSTEM.PUT(-60, SYSTEM.VAL(INTEGER, ov.entryMno));
    SYSTEM.PUT(-60, ov.size);
    SYSTEM.PUT(-60, ov.nummods);
    ov.mapped := 0;
  END NewOverlay;

  (* generates overlays for a given module's entry points *)
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
  END MakeNode;

  (* Write Overlay.ovl based on index into overlay table *)
  PROCEDURE WriteOverlay*(index: INTEGER);
    VAR i, j, u: INTEGER; mod: Module; ov: Overlay; modOv: OverlayModule;
      ovlFile, fixFile: Files.File; ovlR, fixR: Files.Rider;
      filename: FileName; sec: INTEGER;
  BEGIN
    ov := overlays[index];
    mod := ov.mods[0].mod;
    (*Create the file "mod.ovl"*)
    (* temporary until I come up with a better way to name overlays *)
    (*
    i := 0;
    WHILE mod.name[i] # 0X DO filename[i] := mod.name[i]; INC(i) END;
    filename[i] := "."; filename[i+1] := "o"; filename[i+2] := "v"; filename[i+3] := "l";
    filename[i+4] := 0X; *)
    (*copy contents of module in memory into an overlay file*)
    (*
    ovlFile := Files.New(filename);
    Files.Set(ovlR, ovlFile, 0); *)
    (*ov.size := 0;*)
    sec := mappedSector;
    FOR i := 0 TO ov.nummods-1 DO
      modOv := ov.mods[i];
      (*fixFile := GetFixModFile(modOv);
      Files.Set(fixR, fixFile, 0);
      Files.ReadInt(fixR, u); *)
      SYSTEM.PUT(-60, 0AEEEAAH);
      SYSTEM.PUT(-60, modOv.size);
      FOR j := 0 TO modOv.size-1 BY FileDir.SectorSize DO
        Kernel.PutMemToSector(mappedSector*29, modOv.mod.code + j, modOv.size - j);
        INC(mappedSector);
      END;
      (*INC(ov.size, modOv.size);*)
    END;

    ov.sector := sec;
  END WriteOverlay;

  PROCEDURE Init*;
    VAR i: INTEGER;
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
    (* load location of the overlay manager to predetermined reg *)
    SYSTEM.LDREG(31, SYSTEM.ADR(OverlayManager));
  END Init;

END Overlays.
