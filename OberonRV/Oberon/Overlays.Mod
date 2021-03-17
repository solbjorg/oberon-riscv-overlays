MODULE Overlays;
  IMPORT SYSTEM, FileDir, Files;
  CONST numRegions = 1;
    numOverlays = 100;
    numIndices = 2; (* maximum number of overlays possible to map at once *)
    regionSize = 0B000H;
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
    Edge* = POINTER TO EdgeDesc; (*outgoing calls*)
    Func = PROCEDURE(a,b,c,d,e,f,g,h,i,j,l,m: INTEGER): INTEGER;
    Procedure* = POINTER TO ProcedureDesc;
    Overlay* = POINTER TO OverlayDesc;
    FileName = ARRAY 32 OF CHAR;
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
      prev*, next*: Node; (* move between nodes within a module *)
      dsc*: Edge;
      size*: INTEGER; (* size of procedure *)
      mod*: Module;
      pno*: BYTE;
    END;

    EdgeDesc* = RECORD
      next*: Edge;
      node*: Node;
      weight*: INTEGER; (* TODO: Make this a Byte? *)
    END;

    (* procedure in overlay *)
    ProcedureDesc* = RECORD
      addr*: INTEGER; (* relative address within overlay; i.e. proc address assuming overlay starts at address 0 *)
      filepos*: INTEGER; (* position within module file *)
      size*: INTEGER; (* pos size; needed to load into overlay *)
      mod*: Module; (* module this proc belongs to *)
      index*: INTEGER; (* toc index of proc for module *)
      next*: Procedure;
    END;

    OverlayDesc* = RECORD
      filename: FileName;
      mapped*: INTEGER; (*address: start of mapped overlay*)
      size: INTEGER; (* length of code segment; excludes footer *)
      numproc: INTEGER; (* number of procedures covered by this overlay *)
      proc*: Procedure; (* list of procedures in overlay *)
      entryMno, entryPno: BYTE;
    END;

  VAR regions: ARRAY numRegions OF INTEGER; (*reserved addresses to map overlays onto*)
    overlays: ARRAY numOverlays OF Overlay;
    numGeneratedOverlays, lastMapped, numMapped,
      stackLoc: INTEGER;
    mappedIndices: ARRAY numIndices OF INTEGER;  (* index into table of overlay that is currently mapped *)

  PROCEDURE ThisFile(proc: Procedure): Files.File;
    VAR i: INTEGER;
      mod: Module;
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

  PROCEDURE OverlayManager(a,b,c,d,e,f,g,h,i,j,l,m: INTEGER): INTEGER;
    VAR k, ovindex, pno, addr, size, oldmapped, oldIndex: INTEGER;
      found: BOOLEAN;
      ov, old: Overlay;
      proc: Procedure; body: Func;

    PROCEDURE LoadOverlay(ov, old: Overlay);
    VAR F: Files.File; R: Files.Rider; 
      i, addr, u: INTEGER;
      proc: Procedure;

    BEGIN
      F := Files.Old(ov.filename);
      IF F # NIL THEN
        ov.mapped := regions[0];
        IF old # NIL THEN old.mapped := 0; END;
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
        WHILE proc # NIL DO
          SYSTEM.PUT(proc.mod.data + proc.index, proc.addr + ov.mapped);
          proc := proc.next;
        END;
      ELSE ASSERT(FALSE); (* should never happen! abort *)
      END
    END LoadOverlay;

    (* shift the indices array one to the right depending on *)
    (* where an entry was inserted; index specifies the entered index *)
    (* also kills the last entry, if there is one *)
    (* used for inserting into the middle of the array *)
    PROCEDURE ShiftArray(index: INTEGER);
      VAR i: INTEGER;
    BEGIN
      IF mappedIndices[numIndices-1] >= 0 THEN
        overlays[mappedIndices[numIndices-1]].mapped := 0;
      END;
      FOR i := numIndices - 2 TO index+1 BY -1 DO
        mappedIndices[i] := mappedIndices[i-1];
      END;
    END ShiftArray;

  BEGIN
    ovindex := SYSTEM.REG(30) DIV 2 MOD 200H;
    pno := SYSTEM.REG(30) DIV C24 MOD C8;
    (* TODO we will later store /the actual overlay index/ in the address token *)
    (* this is just a stopgap so we can test small parts at a time *)
    (* this is currently ~guaranteed(!) to find a hit, hence the lack of safety *)
    (* TODO: MAKE THIS SAFE *)
    ov := overlays[ovindex];
    pno := (ov.proc.mod.procs - ov.proc.mod.data) + pno * 4;
    IF ov.mapped = 0 THEN
      (* search for open space *)
      found := FALSE;
      (* don't do this if an overlay has never been loaded before *)
      IF (mappedIndices[0] >= 0) (*OR (mappedIndices[numIndices] >= 0)*) THEN
        k := 1;
        size := overlays[mappedIndices[k-1]].mapped - regions[0] + overlays[mappedIndices[k-1]].size;
        (* assume mappedIndices is sorted according to where the overlays are positioned *)
        WHILE (~found) & (regionSize - size < ov.size) & (k < numIndices) & (mappedIndices[k] >= 0) DO
          IF regionSize - size < ov.size THEN
            lastMapped := k;
            mappedIndices[k] := ovindex;

            ov.mapped := size + regions[0];
            found := TRUE;
          END;
          INC(k);
          size := overlays[mappedIndices[k-1]].mapped - regions[0] + overlays[mappedIndices[k-1]].size;
        END;
      END;
      (* no empty hole found *)
      IF ~found THEN
        (* evict an overlay *)
      END;

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
      ASSERT(pno >= 0);
      LoadOverlay(ov, old);

      (* call function in loaded overlay *)
      proc := ov.proc;
      body := NIL;
      WHILE body = NIL DO
        IF proc.index = pno THEN
          body := SYSTEM.VAL(Func, proc.addr + ov.mapped);
          ASSERT(SYSTEM.VAL(INTEGER, body) >= regions[0]);
          SYSTEM.PUT(-60, 0FE57H);
          k := body(a,b,c,d,e,f,g,h,i,j,l,m);
        END;
        proc := proc.next;
      END;

      IF (old # NIL) & (oldmapped = ov.mapped) THEN
        LoadOverlay(old, ov);
        mappedIndices[0] := oldIndex;
      END;
    ELSE
      (* probably indirect function call within same module *)
      proc := ov.proc;
      body := NIL;
      WHILE body = NIL DO
        IF proc.index = pno THEN
          body := SYSTEM.VAL(Func, proc.addr + ov.mapped);
          ASSERT(SYSTEM.VAL(INTEGER, body) >= regions[0]);
          k := body(a,b,c,d,e,f,g,h,i,j,l,m);
        END;
        proc := proc.next;
      END;
    END;
    RETURN k
  END OverlayManager;

  (* Return the overlay index corresponding to entry point (mno, pno) *)
  (* Currently only checks mno, TODO *)
  PROCEDURE FindOverlayIndex*(mno, pno: INTEGER): INTEGER;
    VAR index: INTEGER;
  BEGIN
    index := 0;
    WHILE (overlays[index] # NIL) & (overlays[index].entryMno # mno) DO INC(index) END;
    RETURN index
  END FindOverlayIndex;

  (* generate overlay for an array of function nodes*)
  (* returns index in overlay table *)
  PROCEDURE NewOverlay*(nodes: ARRAY OF Node; numnodes: INTEGER);
    VAR index, i, u, tocoffset, addr, inst, mno, disp, op: INTEGER;
      root, proc: Procedure; impmod: Module;
      F: Files.File; R: Files.Rider;
      ov: Overlay;
  BEGIN
    NEW(ov); index := 0;
    WHILE overlays[index] # NIL DO INC(index) END;
    (* add the overlay we're about to generate to the table *)
    overlays[index] := ov;
    (*First, initialise the list of procedures contained in the overlay.*)
    (*Create a linked list of `Procedure` filled in with pointers to procedure addresses; *)
    (*this is later used to fill in the TOC.*)
    impmod := nodes[0].mod;
    tocoffset := impmod.procs - nodes[0].mod.data;
    NEW(root); root.mod := impmod; root.index := tocoffset + nodes[0].pno * 4;
    (* assume that if this procedure is being loaded into an overlay, all calls to it have *)
    (* to go through the overlay manager *)
    (* this is a bit of a flawed assumption - but it works for now. *)
    SYSTEM.PUT(impmod.procs + nodes[0].pno * 4, SYSTEM.ADR(OverlayManager));
    FOR i := 1 TO numnodes-1 DO
      impmod := nodes[i].mod;
      tocoffset := impmod.procs - nodes[i].mod.data;
      NEW(proc); proc.mod := impmod; proc.index := tocoffset + nodes[i].pno * 4;
      SYSTEM.PUT(impmod.procs + nodes[i].pno * 4, SYSTEM.ADR(OverlayManager));
      proc.next := root; root := proc;
    END;
    ov.proc := root; (* store which proc is the root *)
    (* fixup sizes and addresses of each procedure in the overlay *)
    proc := root; proc.addr := 0; proc.size := nodes[numnodes-1].size;
    FOR i := numnodes-2 TO 0 BY -1 DO
      root := proc.next;
      root.addr := proc.addr + proc.size;
      root.size := nodes[i].size;
      proc := root;
    END;

    ov.entryMno := nodes[0].mod.num;
    ov.entryPno := nodes[0].pno;
    ov.mapped := 0;
  END NewOverlay;

  (* generates overlays for a given module's entry points *)
  PROCEDURE GenerateOverlays*(mod: Module);
  VAR i: INTEGER;
    nodes: ARRAY 100 OF Node;
    tempNode: Node;
    ov: Overlay;
  BEGIN
    tempNode := mod.rootNode; i := 0;
    WHILE tempNode # NIL DO nodes[i] := tempNode; tempNode := tempNode.next; INC(i); END;
    NewOverlay(nodes, i);
  END GenerateOverlays;

  PROCEDURE WriteOverlay*(index: INTEGER);
    VAR i, u: INTEGER; mod: Module; ov: Overlay;
      F: Files.File; R: Files.Rider;
      filename: FileName;
  BEGIN
    ov := overlays[index];
    mod := ov.proc.mod;
    (*Create the file "mod.ovl"*)
    (* temporary until I come up with a better way to name overlays *)
    i := 0;
    WHILE mod.name[i] # 0X DO filename[i] := mod.name[i]; INC(i) END;
    filename[i] := "."; filename[i+1] := "o"; filename[i+2] := "v"; filename[i+3] := "l";
    filename[i+4] := 0X;
    (*copy contents of module in memory into an overlay file*)
    F := Files.New(filename);
    Files.Set(R, F, 0);
    i := mod.code;
    WHILE i < mod.data + mod.size DO
      SYSTEM.GET(i, u); Files.WriteInt(R, u); INC(i, 4)
    END;
    Files.Register(F);
    ov.size := i - mod.code; (* identifies the length of the code segment to be loaded *)
    ov.filename := filename;
  END WriteOverlay;

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
    SYSTEM.GET(24, regions[0]);
    DEC(regions[0], 0D000H);
    FOR i := 0 TO LEN(mappedIndices)-1 DO
      mappedIndices[i] := -1;
    END;
    numGeneratedOverlays := 0;
    lastMapped := -1;
    stackLoc := 0;
    (* load location of the overlay manager to predetermined reg *)
    SYSTEM.LDREG(31, SYSTEM.ADR(OverlayManager));
  END Init;

END Overlays.
