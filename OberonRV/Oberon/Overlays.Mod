MODULE Overlays;
  IMPORT SYSTEM, FileDir, Files, Modules;
  CONST numRegions = 1;
    regionSize = 1000H;

  TYPE
    Procedure* = POINTER TO ProcedureDesc;
    Overlay* = POINTER TO OverlayDesc;

    ProcedureDesc* = RECORD
      addr*: INTEGER; (* relative address within overlay *)
      mod*: Modules.Module;
      index*: BYTE; (* toc index of proc for module *)
      next*: Procedure;
    END;

    OverlayDesc* = RECORD
      filename: FileDir.FileName;
      mapped*: INTEGER; (*address: start of mapped overlay*)
      size: INTEGER; (* length of code segment; excludes footer *)
      numproc: INTEGER; (* number of procedures covered by this overlay *)
      proc*: Procedure; (* list of procedures in overlay *)
      next*: Overlay;
    END;

  VAR regions: ARRAY numRegions OF INTEGER; (*reserved addresses to map overlays onto*)
    ovroot: Overlay; (* root of overlay list *)

  (* TODO, we need to fixup SB references every time we load an overlay ... *)
  PROCEDURE LoadOverlay*(ov: Overlay);
    VAR F: Files.File; R: Files.Rider;
      i, u, regionx, addr: INTEGER;
      proc: Procedure;
  BEGIN
    F := Files.Old(ov.filename);
    IF F # NIL THEN
      Files.Set(R, F, 0);

      regionx := ov.mapped; i := 0;
      WHILE i < ov.size DO
        SYSTEM.PUT(-60, 0FF0H);
        Files.ReadInt(R, u); SYSTEM.PUT(regionx + i, u);
        INC(i, 4);
      END;
      proc := ov.proc;
      (* Fill in correct addresses to TOC *)
      WHILE proc # NIL DO
        SYSTEM.PUT(-60, 0FF1H);
        addr := proc.mod.procs + proc.index * 4;
        SYSTEM.PUT(addr, proc.addr + regionx);

        proc := proc.next;
      END;
    ELSE SYSTEM.PUT(-60, 0FAFAFAFH);
    END;
  END LoadOverlay;

  (* generate overlay for given module already in memory*)
  PROCEDURE GenerateOverlay*(mod: Modules.Module; VAR ov: Overlay; numproc: INTEGER);
    VAR i, u, tocoffset: INTEGER; root, proc: Procedure;
      F: Files.File; R: Files.Rider;
      filename: FileDir.FileName;
  BEGIN
    tocoffset := (mod.procs - mod.data) DIV 4;
    i := 0;
    NEW(root); root.mod := mod; root.index := tocoffset + i; SYSTEM.GET(mod.procs, root.addr);
    WHILE i < numproc DO
      (*assume procs is ordered*)
      NEW(proc); proc.mod := mod; proc.index := tocoffset + i; SYSTEM.GET(mod.procs + i * 4, proc.addr);
      proc.next := root; root := proc;
      INC(i);
    END;

    i := 0;
    WHILE mod.name[i] # 0X DO filename[i] := mod.name[i]; INC(i) END;
    filename[i] := "."; filename[i+1] := "o"; filename[i+2] := "v"; filename[i+3] := "l";
    filename[i+4] := 0X;

    F := Files.New(filename);
    Files.Set(R, F, 0);

    i := mod.code;
    WHILE i < mod.imp DO SYSTEM.GET(i, u); Files.WriteInt(R, u); INC(i, 4) END;
    (* TODO generate stubs here*)
    Files.Register(F);
    ov.filename := filename;
    ov.size := i - mod.code; (* identifies the length of the code segment to be loaded *)
    ov.numproc := numproc;
    ov.proc := root;
    ov.mapped := regions[0];
    ov.next := ovroot; ovroot := ov;
  END GenerateOverlay;

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

  PROCEDURE LoadModule*(name: ARRAY OF CHAR; VAR newmod: Modules.Module);
  BEGIN

  END LoadModule;


  PROCEDURE Init*;
  BEGIN
    Modules.Init;
    regions[0] := Modules.limit;
  END Init;

END Overlays.
