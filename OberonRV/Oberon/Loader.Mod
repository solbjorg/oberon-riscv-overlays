MODULE Loader;
  IMPORT SYSTEM, Files, Overlays, Linker;
  CONST versionkey = 1X;

  VAR M: Overlays.Module;
    importing: Overlays.ModuleName;
    res: INTEGER;

  PROCEDURE error(n: INTEGER; name: ARRAY OF CHAR);
  BEGIN res := n; importing := name;
    IF res > 0 THEN
      SYSTEM.PUT(-60, 0F00H + res);
    END;
  END error;

  PROCEDURE ThisFile(name: ARRAY OF CHAR): Files.File;
    VAR i: INTEGER;
      filename: Overlays.ModuleName;
  BEGIN
    i := 0;
    WHILE name[i] # 0X DO filename[i] := name[i]; INC(i) END ;
    filename[i] := "."; filename[i+1] := "r"; filename[i+2] := "s"; filename[i+3] := "c"; filename[i+4] := 0X;
    RETURN Files.Old(filename)
  END ThisFile;

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

  PROCEDURE Load*(name: ARRAY OF CHAR; VAR newmod: Overlays.Module);
    VAR ov: Overlays.Overlay; entry: Linker.Command;
        numprocs, impkey, nofimps, key, size: INTEGER;
        name1, impname: Overlays.ModuleName;
        mod, impmod: Overlays.Module;
        F: Files.File; R: Files.Rider;
        ch: CHAR;
        import: ARRAY 16 OF Overlays.Module;
  BEGIN
    mod := Linker.root; error(0, name); nofimps := 0;
    WHILE (mod # NIL) & (name # mod.name) DO mod := mod.next END ;
    IF mod = NIL THEN
      SYSTEM.PUT(-60, 0ABCDEFH);
      Check(name);
      IF res = 0 THEN F := ThisFile(name) ELSE F := NIL END ;
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
      IF res = 0 THEN
        entry := Linker.Load(name, mod, numprocs, nofimps, size, import, R);
        Overlays.GenerateOverlay(mod, numprocs);
        mod.key := key;
        SYSTEM.PUT(-60, 0FE3H);
        entry;
        SYSTEM.PUT(-60, 03EFH);
      ELSE SYSTEM.PUT(-60, res); REPEAT UNTIL FALSE;
      END;
    END;
    newmod := mod;
  END Load;

  PROCEDURE Init;
  BEGIN Linker.Init;
  END Init;

BEGIN SYSTEM.PUT(-60, 86H); Init; SYSTEM.PUT(-60, 88H); Load("Oberon", M); SYSTEM.PUT(-60, 0F000H + res); REPEAT UNTIL FALSE
END Loader.
