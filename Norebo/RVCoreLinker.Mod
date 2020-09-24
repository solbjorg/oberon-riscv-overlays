MODULE RVCoreLinker;  (*derived from NW 20.10.2013, and pdewacht's Norebo Corelinker for RISC-5 *)
  IMPORT SYSTEM, Files, Texts, Oberon;
  CONST versionkey = 1X; MT = 12; MTOrg = 20H; DescSize = 80;
    addi = 19; load = 3; store = 35;

  TYPE Module = POINTER TO ModDesc;
    ModuleName* = ARRAY 32 OF CHAR;
    Buffer* = ARRAY 63 * 1024 DIV 4 OF INTEGER;

    ImageModDesc = RECORD
        name: ModuleName;
        next: INTEGER;
        key, num, size, refcnt: INTEGER;
        data, code, imp, cmd, ent, ptr, unused: INTEGER;
      END ;

    ModDesc = RECORD
        next: Module;
        addr: INTEGER;
        desc: ImageModDesc;
      END ;

  VAR W: Texts.Writer;
    root: Module;
    AllocPtr*, res*: INTEGER;
    importing*, imported*: ModuleName;

  PROCEDURE ThisFile(name: ARRAY OF CHAR): Files.File;
    VAR i: INTEGER;
      filename: ModuleName;
  BEGIN i := 0;
    WHILE name[i] # 0X DO filename[i] := name[i]; INC(i) END ;
    filename[i] := "."; filename[i+1] := "r"; filename[i+2] := "s"; filename[i+3] := "x";
    filename[i+4] := 0X;
    Texts.WriteLn(W); Texts.WriteString(W, "Filename: "); Texts.WriteString(W, filename); Texts.Append(Oberon.Log, W.buf);
    RETURN Files.Old(filename)
  END ThisFile;

  PROCEDURE error(n: INTEGER; name: ARRAY OF CHAR);
  BEGIN res := n; importing := name;
    Texts.WriteLn(W); Texts.WriteString(W, "Error "); Texts.WriteHex(W, res); Texts.Append(Oberon.Log, W.buf);
  END error;

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

  PROCEDURE ReadStringPart(VAR R: Files.Rider; VAR n, cnt: INTEGER);
    VAR ch: CHAR;
  BEGIN
    n := 0; cnt := 0; Files.Read(R, ch);
    WHILE (cnt < 4) & (ch # 0X) DO
      INC(n, LSL(ORD(ch), cnt * 8)); INC(cnt);
      IF cnt < 4 THEN Files.Read(R, ch) END
    END
  END ReadStringPart;

  PROCEDURE Load(name: ARRAY OF CHAR; VAR buffer: ARRAY OF INTEGER; VAR newmod: Module);
    (*search module in list; if not found, load module.
      res = 0: already present or loaded; res = 1: file not found;
      res = 2: file not available; res = 3: key conflict;
      res = 4: bad file version; res = 5: corrupted file; res = 7: no space*)
    VAR mod, impmod: Module;
      i, n, key, impkey, mno, nofimps, size: INTEGER;
      p, u, v, w: INTEGER;  (*addresses*)
      ch: CHAR;
      body: INTEGER;
      fixorgP, fixorgD, fixorgT: INTEGER;
      disp, adr, inst, pno, vno, op, imm, dest, offset: INTEGER;
      name1, impname: ModuleName;
      F: Files.File; R: Files.Rider;
      import: ARRAY 16 OF Module;

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

    PROCEDURE Lw(imm: INTEGER) : INTEGER;
      VAR rd, rs1, funct3: INTEGER;
    BEGIN
      rd := 3; (* SB *)
      funct3 := 2; (* lw, not lb or lh *)
      rs1 := 4; (* MT *)
      RETURN (((imm * 20H + rs1) * 8H + funct3) * 20H + rd) * 80H + 3 (* opcode for all loads is 3 *)
    END Lw;

    (* returns immediate of an I-type instruction *)
    PROCEDURE GetIImm(inst: INTEGER) : INTEGER;
    BEGIN
      RETURN inst DIV 100000H
    END GetIImm;

    PROCEDURE GetSImm(inst: INTEGER) : INTEGER;
    BEGIN
      RETURN (inst DIV 2000000H MOD 80H) + (inst DIV 80H MOD 20H)
    END GetSImm;

  BEGIN
    mod := root; res := 0; nofimps := 0;
    WHILE (mod # NIL) & (name # mod.desc.name) DO mod := mod.next END ;
    IF mod = NIL THEN (*load*)
      Check(name);
      IF res = 0 THEN F := ThisFile(name) ELSE F := NIL END ;
      IF F # NIL THEN
        Files.Set(R, F, 0); Files.ReadString(R, name1); Files.ReadInt(R, key); Files.Read(R, ch);
        Files.ReadInt(R, size); importing := name1;
        IF ch = versionkey THEN
          Files.ReadString(R, impname);   (*imports*)
          WHILE (impname[0] # 0X) & (res = 0) DO
            Files.ReadInt(R, impkey);
            Load(impname, buffer, impmod); import[nofimps] := impmod; importing := name1;
            IF res = 0 THEN
              IF impmod.desc.key = impkey THEN INC(impmod.desc.refcnt); INC(nofimps)
              ELSE error(3, name1); imported := impname
              END
            END ;
            Files.ReadString(R, impname)
          END;
          Texts.WriteLn(W); Texts.WriteString(W, "Back to loading "); Texts.WriteString(W, name);
        ELSE error(2, name1)
        END
      ELSE error(1, name)
      END ;
      IF res = 0 THEN (*search for a hole in the list allocate and link*)
        INC(size, DescSize);
        IF AllocPtr + size < LEN(buffer) * 4 THEN
          p := AllocPtr DIV 4;
          AllocPtr := (AllocPtr + size + 100H) DIV 20H * 20H;
          NEW(mod); mod.next := root; root := mod; mod.addr := p * 4;
          mod.desc.size := AllocPtr - p * 4;
          IF mod.next = NIL THEN
            mod.desc.num := 1; mod.desc.next := 0
          ELSE
            mod.desc.num := mod.next.desc.num + 1; mod.desc.next := mod.next.addr
          END
        ELSE error(7, name1)
        END
      END ;
      IF res = 0 THEN (*read file*)
        INC(p, DescSize DIV 4); (*allocate descriptor*)
        (* mod.desc.name := name; *)
        n := 0; WHILE name[n] # 0X DO mod.desc.name[n] := name[n]; INC(n); END ;
        mod.desc.key := key; mod.desc.refcnt := 0;
        mod.desc.data := p * 4;  (*data*)
        buffer[MTOrg DIV 4 + mod.desc.num] := p * 4;  (*module table entry*)
        Files.ReadInt(R, n);
        WHILE n > 0 DO Files.ReadInt(R, w); buffer[p] := w; INC(p); DEC(n, 4) END ;  (*type descriptors*)
        Files.ReadInt(R, n);
        WHILE n > 0 DO buffer[p] := 0; INC(p); DEC(n, 4) END ;  (*variable space*)
        Files.ReadInt(R, n);
        WHILE n > 0 DO Files.ReadInt(R, w); buffer[p] := w; INC(p); DEC(n, 4) END ;  (*strings*)
        mod.desc.code := p * 4;  (*program*)
        Files.ReadInt(R, n);
        WHILE n > 0 DO Files.ReadInt(R, w); buffer[p] := w; INC(p); DEC(n) END ;  (*program code*)
        mod.desc.imp := p * 4;  (*copy imports*)
        i := 0;
        WHILE i < nofimps DO
          buffer[p] := import[i].addr; INC(p); INC(i)
        END ;
        mod.desc.cmd := p * 4;  (*commands*)
        ReadStringPart(R, w, n);
        WHILE n # 0 DO
          WHILE n = 4 DO buffer[p] := w; INC(p); ReadStringPart(R, w, n) END ;
          buffer[p] := w; INC(p);
          Files.ReadInt(R, w); buffer[p] := w; INC(p);
          ReadStringPart(R, w, n)
        END ;
        buffer[p] := 0; INC(p);
        mod.desc.ent := p * 4;  (*entries*)
        Files.ReadInt(R, n);
        WHILE n > 0 DO Files.ReadInt(R, w); buffer[p] := w; INC(p); DEC(n) END ;
        mod.desc.ptr := p * 4;  (*pointer references*)
        Files.ReadInt(R, w);
        WHILE w >= 0 DO buffer[p] := mod.desc.data + w; INC(p); Files.ReadInt(R, w) END ;
        buffer[p] := 0; INC(p);
        Files.ReadInt(R, fixorgP); Files.ReadInt(R, fixorgD); Files.ReadInt(R, fixorgT);
        Texts.WriteLn(W); Texts.WriteString(W, "fixorgP: "); Texts.WriteHex(W, fixorgP);
        Texts.WriteLn(W); Texts.WriteString(W, "fixorgD: "); Texts.WriteHex(W, fixorgD);
        Texts.WriteLn(W); Texts.WriteString(W, "fixorgT: "); Texts.WriteHex(W, fixorgT);
        Texts.Append(Oberon.Log, W.buf);
        Files.ReadInt(R, w); body := mod.desc.code + w;
        Files.Read(R, ch);
        IF ch # "O" THEN (*corrupted file*)  mod := NIL; error(4, name) END
      END ;
      (*
        Below are parts specific to RISC-V architecture.
        Everything else operates on the headers, so it can stay the same. But this needs fixing for RISC-V.
     
        Pseudoinstruction format for call fixups, originally by sam-falvo but with some changes:
          procedureID + LSL(moduleID MOD 128, 8) + LSL(fixupLink MOD 10000H, 16)
        More detail on this can be found in RVOG.Mod.
      *)
      Texts.WriteLn(W); Texts.WriteString(W, "res "); Texts.WriteHex(W, res); Texts.Append(Oberon.Log, W.buf);
      IF res = 0 THEN (*fixup of BL*)
        adr := mod.desc.code + fixorgP*4;
        (* Keep going until the address points to the start of mod.desc.code *)
        Texts.WriteLn(W); Texts.WriteString(W, "Call fixups. mod.desc.code: "); Texts.WriteHex(W, mod.desc.code); Texts.Append(Oberon.Log, W.buf);
        WHILE adr # mod.desc.code DO
          inst := buffer[adr DIV 4];

          disp := inst DIV 10000H MOD 10000H; (* displacement *)
          mno := inst DIV 100H MOD 100H;
          pno := inst MOD 100H;
          impmod := import[mno-1];
          dest := buffer[impmod.desc.ent DIV 4 + pno] + impmod.desc.code;
          offset := (dest - adr);
          buffer[adr DIV 4] := Jal(offset MOD 200000H);
          Texts.WriteLn(W); Texts.WriteString(W, "mno:  "); Texts.WriteHex(W, mno); Texts.WriteString(W, " pno:  "); Texts.WriteHex(W, pno);
          Texts.WriteString(W, " disp: "); Texts.WriteHex(W, disp);
          Texts.WriteString(W, " dest: "); Texts.WriteHex(W, dest); Texts.WriteString(W, " adr: "); Texts.WriteHex(W, adr);
          Texts.WriteString(W, " impname: "); Texts.WriteString(W, impmod.desc.name); Texts.WriteString(W, " offset: "); Texts.WriteHex(W, offset);
          Texts.Append(Oberon.Log, W.buf);
          adr := mod.desc.code + disp*4;
        END ;
        (*fixup of LDR/STR/ADD*)
        (*
          These require loading SB. Similar to the above. The format, specified in RVOG.Mod:
            5H + LSL(moduleID MOD 128, 4) + LSL(link MOD 10000H, 16)
        *)
        adr := mod.desc.code + fixorgD*4;
        Texts.WriteLn(W); Texts.WriteString(W, "SB fixups. mod.desc.code: "); Texts.WriteHex(W, mod.desc.code); Texts.Append(Oberon.Log, W.buf);
        WHILE adr # mod.desc.code DO
          inst := buffer[adr DIV 4];
          IF (inst MOD 8H # 5) THEN Texts.WriteLn(W); Texts.WriteString(W, "Bad magic!"); Texts.Append(Oberon.Log, W.buf) END;
          mno := inst DIV 10H MOD 128;
          disp := inst DIV 10000H;
          Texts.WriteLn(W); Texts.WriteString(W, "mno: "); Texts.WriteHex(W, mno); Texts.WriteString(W, " disp: "); Texts.WriteHex(W, disp); Texts.Append(Oberon.Log, W.buf);
          IF mno = 0 THEN (*global*)
            buffer[adr DIV 4] := Lw(mod.desc.num * 4);
          ELSE (*import*)
            impmod := import[mno-1];
            v := impmod.desc.num;
            buffer[adr DIV 4] := Lw(v * 4);

            (* fixup the offset too *)
            inst := buffer[adr DIV 4 + 1];
            op := inst MOD 80H;
            IF (op = addi) OR (op = load) THEN
              imm := GetIImm(inst);
              Texts.WriteLn(W); Texts.WriteString(W, "Fixing up an IType with imm "); Texts.WriteHex(W, imm); Texts.Append(Oberon.Log, W.buf);
            ELSIF op = store THEN
              imm := GetSImm(inst);
              Texts.WriteLn(W); Texts.WriteString(W, "Fixing up an SType with imm "); Texts.WriteHex(W, imm); Texts.Append(Oberon.Log, W.buf);
            ELSE error(5, name);
            END;
            vno := imm MOD 100H; (* variable number; see p. 23 Pattern 12 *)
            offset := buffer[impmod.desc.ent DIV 4 + vno]; (* crashes here :(  *)
            (* checks if we're looking for a procedure, as then we add 100H. *)
            IF ODD(imm DIV 100H) THEN offset := offset + impmod.desc.code - impmod.desc.data END ;
            Texts.WriteLn(W); Texts.WriteString(W, "offset: "); Texts.WriteHex(W, offset); Texts.Append(Oberon.Log, W.buf);
            (* replace stored imm with calculated offset*)
            IF (op = store) THEN
              buffer[adr DIV 4 + 1] := (inst - LSL(imm MOD 20H, 7) - LSL(imm DIV 20H, 25)) + LSL(offset MOD 20H, 7) + LSL(offset DIV 20H, 25)
            ELSE
              buffer[adr DIV 4 + 1] := (inst - LSL(imm, 20)) + LSL(offset, 20)
            END;
          END ;
          adr := mod.desc.code + disp*4;
        END ;
        (*fixup of type descriptors*)
        Texts.WriteLn(W); Texts.WriteString(W, "Type fixups. mod.desc.code: "); Texts.WriteHex(W, mod.desc.code); Texts.Append(Oberon.Log, W.buf);
        adr := mod.desc.data + fixorgT*4;
        WHILE adr # mod.desc.data DO
          inst := buffer[adr DIV 4];
          mno := inst DIV 1000000H MOD 10H;
          vno := inst DIV 1000H MOD 1000H;
          disp := inst MOD 1000H;
          IF mno = 0 THEN (*global*) inst := mod.desc.data + vno
          ELSE (*import*)
            impmod := import[mno-1];
            offset := buffer[impmod.desc.ent DIV 4 + vno];
            inst := impmod.desc.data + offset
          END ;
          buffer[adr DIV 4] := inst; adr := adr - disp*4
        END ;
        buffer[0] := Jal(body MOD 200000H); (*initialize module*)
      ELSIF res = 3 THEN importing := name;
        WHILE nofimps > 0 DO DEC(nofimps); DEC(import[nofimps].desc.refcnt) END
      END
    END ;
    Texts.WriteLn(W); Texts.WriteString(W, "Done loading "); Texts.WriteString(W, name); Texts.Append(Oberon.Log, W.buf);
    newmod := mod
  END Load;

  PROCEDURE Copy(from, to, words: LONGINT);
    VAR x: INTEGER;
  BEGIN
    WHILE words > 0 DO
      SYSTEM.GET(from, x); SYSTEM.PUT(to, x);
      INC(from, 4); INC(to, 4); DEC(words)
    END
  END Copy;

  PROCEDURE Link*(name: ARRAY OF CHAR; VAR buffer: ARRAY OF INTEGER);
    VAR mod: Module;
      n: LONGINT;
  BEGIN
    FOR n := 0 TO LEN(buffer) - 1 DO buffer[n] := 0 END ;
    AllocPtr := 100H;
    Load(name, buffer, mod);
    Texts.WriteLn(W); Texts.WriteHex(W, res); Texts.Append(Oberon.Log, W.buf);
    buffer[4] := AllocPtr;
    buffer[5] := mod.addr; (* crashes here :(  *)
    buffer[6] := 40000H;  (*module limit*)
    (*store module descriptors*)
    WHILE root # NIL DO
      Copy(SYSTEM.ADR(root.desc), SYSTEM.ADR(buffer) + root.addr, DescSize DIV 4);
      root := root.next
    END
  END Link;

  PROCEDURE LinkDiskImage*(modname: ARRAY OF CHAR; corename: ARRAY OF CHAR);
    VAR buffer: Buffer;
      F: Files.File; R: Files.Rider;
      i: INTEGER;
  BEGIN
    Link(modname, buffer);
    IF res = 0 THEN
      F := Files.New(corename); Files.Set(R, F, 0);
      Files.WriteInt(R, 9B1EA38DH); FOR i := 4 TO 1023 DO Files.WriteByte(R, 0) END ;
      FOR i := 0 TO AllocPtr DIV 4 - 1 DO Files.WriteInt(R, buffer[i]) END ;
      Files.Register(F)
    END
  END LinkDiskImage;

  PROCEDURE LinkSerialImage*(modname: ARRAY OF CHAR; corename: ARRAY OF CHAR);
    VAR buffer: Buffer;
      F: Files.File; R: Files.Rider;
      i: INTEGER;
  BEGIN
    Link(modname, buffer);
    IF res = 0 THEN
      F := Files.New(corename); Files.Set(R, F, 0);
      Files.WriteInt(R, AllocPtr); Files.WriteInt(R, 0);
      FOR i := 0 TO AllocPtr DIV 4 - 1 DO Files.WriteInt(R, buffer[i]) END ;
      Files.WriteInt(R, 0); Files.Register(F)
    END
  END LinkSerialImage;

  PROCEDURE LinkCommand(linkProc: PROCEDURE(modname: ARRAY OF CHAR; corename: ARRAY OF CHAR));
    VAR S: Texts.Scanner;
      modname, corename: ARRAY 32 OF CHAR;
  BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
    IF S.class = Texts.Name THEN modname := S.s; Texts.Scan(S);
      IF S.class = Texts.Name THEN corename := S.s;
        linkProc(modname, corename);
        Texts.WriteString(W, "Linking "); Texts.WriteString(W, corename);
        IF res = 0 THEN
          Texts.WriteInt(W, AllocPtr, 6)
        ELSE
          Texts.WriteString(W, "  error "); Texts.WriteInt(W, res, 0)
        END ;
        Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
      END
    END
  END LinkCommand;

  PROCEDURE LinkDisk*;
  BEGIN LinkCommand(LinkDiskImage)
  END LinkDisk;

  PROCEDURE LinkSerial*;
  BEGIN LinkCommand(LinkSerialImage)
  END LinkSerial;

BEGIN Texts.OpenWriter(W)
END RVCoreLinker.
