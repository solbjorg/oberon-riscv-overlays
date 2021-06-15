MODULE Kernel;  (*NW/PR  11.4.86 / 27.12.95 / 4.2.2014*)
  IMPORT SYSTEM;
  CONST SectorLength* = 1024;
    timer = -64; led = -60; spiData = -48; spiCtrl = -44;
    CARD0 = 1; SPIFAST = 4;
    (*dataAllocationLimit = 5000H; (* how much space on the heap is reserved for code *)*)
    dataAllocationLimit = 2000H; (* how much space on the heap is reserved for code *)
    FSoffset = 80000H; (*256MB in 512-byte blocks*)
    filemapsize* = 08000H; (*500 sectors, 32MB*)
    overlaymapsize = 08000H; (*500 sectors, 32MB*)
    RA = 1; SP = 2;

  TYPE Sector* = ARRAY SectorLength OF BYTE;
    SectorMap* = POINTER TO SectorMapDesc;
    Command*   = PROCEDURE;
    ResetFunc* = PROCEDURE(trap, loc: INTEGER);
    GCFunc*    = PROCEDURE(blockSizeNeeded: INTEGER; isData: BOOLEAN);

    SectorMapDesc = RECORD
        map: ARRAY filemapsize DIV 32 OF SET;
    END;

  VAR allocated*, NofSectors*: INTEGER;
    heapOrg*, heapLim*: INTEGER; 
    stackOrg*, stackSize*, MemLim*: INTEGER;
    clock, AllocPtr: INTEGER;
    list0, list1, list2, list3: INTEGER;  (*lists of free blocks of size n*256, 128, 64, 32 bytes*)
    largestFreeBlock*: INTEGER;
    data: INTEGER; (*SPI data in*)
    sectorMap: SectorMap;
    GC: GCFunc;
    Reset: ResetFunc;
    
(* ---------- New: heap allocation ----------*)

  (* make a block ready to be merged by removing it from the *)
  (* free-list and fixing up the free-list to be without this block *)
    (*
  PROCEDURE MergeBlock(p: INTEGER);
    VAR size, q0, q1, q2: INTEGER;
  BEGIN
    SYSTEM.GET(p+8, q2);
    (* first, check to see if this is already the head of the free-list *)
    (* if so, simply replace it *)
    IF    p = list0 THEN list0 := q2
    ELSIF p = list1 THEN list1 := q2
    ELSIF p = list2 THEN list2 := q2
    ELSIF p = list3 THEN list3 := q2
    ELSE
      SYSTEM.PUT(-60, 05678H);
      (* search through corresponding free-list, and remove block from it by *)
      (* pointing the previous block to the next block *)
      q0 := 0;
      SYSTEM.GET(p, size);
      IF    size = 32  THEN q1 := list3;
      ELSIF size = 64  THEN q1 := list2;
      ELSIF size = 128 THEN q1 := list1;
      ELSE                  q1 := list0;
      END;
      SYSTEM.GET(q1+8, q2);
      WHILE (q1 # p) & (q2 # 0) DO
        q0 := q1; q1 := q2;
        SYSTEM.GET(q1+8, q2);
      END;
      SYSTEM.PUT(q0+8, q2);
      SYSTEM.PUT(-60, 8765H);
    END;
    (* TODO just a test *)
    IF    size = 32  THEN q1 := list3;
    ELSIF size = 64  THEN q1 := list2;
    ELSIF size = 128 THEN q1 := list1;
    ELSE                  q1 := list0;
    END;
    SYSTEM.GET(q1+8, q2);
    WHILE (q2 # 0) DO
      q0 := q1; q1 := q2;
      SYSTEM.GET(q1+8, q2);
      SYSTEM.PUT(-60, q2);
    END;
  END MergeBlock; *)

  PROCEDURE GetBlock(VAR p: LONGINT; len: LONGINT);
    (*len is multiple of 256*)
    VAR q0, q1, q2, size: LONGINT; done: BOOLEAN;
  BEGIN
    q0 := 0; q1 := list0; done := FALSE;
    ASSERT(q1 # 0);
    ASSERT(len MOD 256 = 0);
    WHILE ~done & (q1 # 0) DO
      SYSTEM.GET(q1, size); SYSTEM.GET(q1+8, q2);
      IF size < len THEN (*no fit*) q0 := q1; q1 := q2
      ELSIF size = len THEN (*extract -> p*)
        done := TRUE; p := q1;
        IF q0 # 0 THEN SYSTEM.PUT(q0+8, q2) ELSE list0 := q2; END
      ELSE (*reduce size*)
        done := TRUE; p := q1; q1 := q1 + len;
        SYSTEM.PUT(q1, size-len); SYSTEM.PUT(q1+4, -1); SYSTEM.PUT(q1+8, q2);
        IF q0 # 0 THEN SYSTEM.PUT(q0+8, q1) ELSE list0 := q1; SYSTEM.GET(list0, size); END
      END
    END ;
    IF ~done THEN
      p := 0
    END
  END GetBlock;

  PROCEDURE GetBlock128(VAR p: LONGINT);
    VAR q: LONGINT;
  BEGIN
    p := 0;
    IF list1 # 0 THEN p := list1; SYSTEM.GET(list1+8, list1)
    ELSE GetBlock(q, 256);
      IF q # 0 THEN
        SYSTEM.PUT(q+128, 128); SYSTEM.PUT(q+132, -1); SYSTEM.PUT(q+136, list1);
        list1 := q + 128; p := q
      END;
    END
  END GetBlock128;

  PROCEDURE GetBlock64(VAR p: LONGINT);
    VAR q: LONGINT;
  BEGIN
    p := 0;
    IF list2 # 0 THEN p := list2; SYSTEM.GET(list2+8, list2)
    ELSE GetBlock128(q);
      IF q # 0 THEN
        SYSTEM.PUT(q+64, 64); SYSTEM.PUT(q+68, -1); SYSTEM.PUT(q+72, list2);
        list2 := q + 64; p := q
      END;
    END
  END GetBlock64;

  PROCEDURE GetBlock32(VAR p: LONGINT);
    VAR q: LONGINT;
  BEGIN
    IF list3 # 0 THEN p := list3; SYSTEM.GET(list3+8, list3)
    ELSE GetBlock64(q);
      IF q # 0 THEN
        SYSTEM.PUT(q+32, 32); SYSTEM.PUT(q+36, -1); SYSTEM.PUT(q+40, list3);
        list3 := q + 32;
      END;
      p := q;
    END
  END GetBlock32;

  PROCEDURE NewPtr*(VAR ptr: LONGINT; tag: LONGINT);
    (*called by NEW via MT[0]; ptr and tag are pointers*)
    VAR p, size, lim: LONGINT; collected: BOOLEAN;
  BEGIN
    ptr := 0; collected := FALSE;
    SYSTEM.GET(tag, size);
    lim := (heapLim - heapOrg) - dataAllocationLimit;
    IF allocated + size > lim THEN GC(size, TRUE); collected := TRUE; END;
    IF allocated + size <= lim THEN
      IF size = 32 THEN GetBlock32(p)
      ELSIF size = 64 THEN GetBlock64(p)
      ELSIF size = 128 THEN GetBlock128(p)
      ELSE GetBlock(p, (size+255) DIV 256 * 256)
      END ;
      IF (p = 0) & ~collected THEN
        (* run garbage collection if not enough space *)
        GC(size, TRUE);
        IF size = 32 THEN GetBlock32(p)
        ELSIF size = 64 THEN GetBlock64(p)
        ELSIF size = 128 THEN GetBlock128(p)
        ELSE GetBlock(p, (size+255) DIV 256 * 256)
        END ;
      END;
      IF p # 0 THEN
        ptr := p+8; SYSTEM.PUT(p, tag); lim := p + size; INC(p, 4); INC(allocated, size);
        WHILE p < lim DO SYSTEM.PUT(p, 0); INC(p, 4) END
      END;
    END;
  END NewPtr;

  (* allocates a block of `size` to heap and writes this address to `ptr` *)
  PROCEDURE NewOverlay*(VAR ptr: LONGINT; VAR size: LONGINT);
    VAR s: INTEGER;
  BEGIN
    (*
    IF size = 32 THEN GetBlock32(ptr)
    ELSIF size = 64 THEN GetBlock64(ptr)
    ELSIF size = 128 THEN GetBlock128(ptr)
    ELSE GetBlock(ptr, (size+255) DIV 256 * 256)
    END ; *)
    GetBlock(ptr, (size+255) DIV 256 * 256);
    (* if ptr = 0, then allocation failed. *)
    IF ptr # 0 THEN
      SYSTEM.PUT(ptr, SYSTEM.ADR(size)); (* set the "tag" *)
      SYSTEM.PUT(ptr+4, 0); (* set mark to -1, will be handled within overlay system *)
      (*SYSTEM.PUT(ptr+8, 0); (* set timestamp to 0; will automatically be set upon calling *)*)
      ptr := ptr + 8;
      INC(allocated, size);
    END;
  END NewOverlay;

  (* deallocates overlay from heap *)
(*
  PROCEDURE FreeOverlay*(VAR ptr: LONGINT; size: INTEGER);
  BEGIN
    DEC(allocated, size);
    SYSTEM.PUT(ptr-8, size); SYSTEM.PUT(ptr-4, -1); SYSTEM.PUT(ptr, list0);
    list0 := ptr-8; ptr := 0;
  END FreeOverlay;
*)
(* ---------- Garbage collector ----------*)

  PROCEDURE Mark*(p: LONGINT);
    VAR offadr, offset, tag, q, r: LONGINT;
  BEGIN
    SYSTEM.GET(p-4, offadr);
    IF (p >= heapOrg) & (offadr = 0) THEN q := p;   (*mark elements in data structure with root p*)
      REPEAT SYSTEM.GET(p-4, offadr);
        IF offadr = 0 THEN SYSTEM.GET(p-8, tag); offadr := tag + 16; ELSE INC(offadr, 4) END ;
        SYSTEM.PUT(p-4, offadr);
        SYSTEM.GET(offadr, offset);
        IF offset # -1 THEN (*down*)
          SYSTEM.GET(p+offset, r); SYSTEM.GET(r-4, offadr);
          IF (r >= heapOrg) & (offadr = 0) THEN
            SYSTEM.PUT(p+offset, q); q := p; p := r;
            SYSTEM.PUT(-60, 0D0H);
          END
        ELSE (*up*) SYSTEM.GET(q-4, offadr); SYSTEM.GET(offadr, offset);
          IF p # q THEN
            SYSTEM.GET(q+offset, r); SYSTEM.PUT(q+offset, p); p := q; q := r;
            SYSTEM.PUT(-60, 0F00H);
          END
        END
      UNTIL (p = q) & (offset = -1)
    END ;
  END Mark;

  PROCEDURE MarkMod*(pref: LONGINT);
    VAR pvadr, p, off, tag: LONGINT;
  BEGIN SYSTEM.GET(pref, pvadr); (*pointers < heapOrg considered NIL*)
    off := 0;
    WHILE pvadr # 0 DO
      SYSTEM.GET(pvadr, p);
      SYSTEM.PUT(-60, off);
      SYSTEM.GET(p-8, tag); SYSTEM.GET(tag, tag);
      SYSTEM.PUT(-60, tag);
      SYSTEM.PUT(-60, p);
      Mark(p);
      INC(off, 4); SYSTEM.GET(pref+off, pvadr)
    END
  END MarkMod;

  (* mark what looks like pointers on the stack *)
  PROCEDURE MarkStack*;
    VAR i, lim, tag, word, p, mark: LONGINT;
  BEGIN
    (* look through the whole stack, except for this procedure *)
    lim := SYSTEM.REG(SP)+28;
    SYSTEM.PUT(-60, 0F07DH);
    FOR i := stackOrg TO lim BY -4 DO
      SYSTEM.GET(i, word);
      IF (word >= heapOrg) & (word < heapLim) THEN
        SYSTEM.GET(word-4, tag);
        IF tag = 0 THEN (* can't be a dynamically allocated var if it isn't currently unmarked *)
          SYSTEM.PUT(-60, i);
          SYSTEM.GET(word-8, tag); (* check tag to ascertain whether it's actually allocated on the heap *)
          IF (tag >= 100H) & (tag < AllocPtr) THEN
            p := heapOrg;
            WHILE (p+8 < word) & (tag > 0) DO
              SYSTEM.GET(p, tag); SYSTEM.GET(p+4, mark);
              IF mark # -1 THEN SYSTEM.GET(tag, tag); END;
              INC(p, tag);
            END ;
            IF p+8 = word THEN
              Mark(word);
            END;
          END;
        END;
      END;
    END;
    SYSTEM.PUT(-60, 0F17DH);
  END MarkStack;

  PROCEDURE Scan*;
    VAR p, q, mark, tag, size: LONGINT;
  BEGIN p := heapOrg;
    REPEAT
      SYSTEM.GET(p+4, mark); q := p;
      WHILE (mark = 0) DO
        SYSTEM.GET(p, tag); SYSTEM.GET(tag, size);
        INC(p, size);
        SYSTEM.GET(p+4, mark);
      END ;
      size := p - q; DEC(allocated, size);  (*size of free block*)
      IF size > 0 THEN
        IF size MOD 64 # 0 THEN
          SYSTEM.PUT(q, 32); SYSTEM.PUT(q+4, -1); SYSTEM.PUT(q+8, list3); list3 := q; INC(q, 32); DEC(size, 32)
        END ;
        IF size MOD 128 # 0 THEN
          SYSTEM.PUT(q, 64); SYSTEM.PUT(q+4, -1); SYSTEM.PUT(q+8, list2); list2 := q; INC(q, 64); DEC(size, 64)
        END ;
        IF size MOD 256 # 0 THEN
          SYSTEM.PUT(q, 128); SYSTEM.PUT(q+4, -1); SYSTEM.PUT(q+8,  list1); list1 := q; INC(q, 128); DEC(size, 128)
        END ;
        IF size > 0 THEN
          SYSTEM.PUT(q, size); SYSTEM.PUT(q+4, -1); SYSTEM.PUT(q+8, list0); list0 := q; INC(q, size)
        END
      END ;
      IF mark > 0 THEN SYSTEM.PUT(-60, 0FECCH); SYSTEM.PUT(-60, p); SYSTEM.GET(p, tag); SYSTEM.GET(tag, size); SYSTEM.PUT(p+4, 0); INC(p, size)
      ELSE (*free*) SYSTEM.GET(p, size); INC(p, size)
      END
    UNTIL p >= heapLim;
  END Scan;

(* ---------- Disk storage management ----------*)

  PROCEDURE SPIIdle(n: INTEGER); (*send n FFs slowly with no card selected*)
  BEGIN SYSTEM.PUT(spiCtrl, 0);
    WHILE n > 0 DO DEC(n); SYSTEM.PUT(spiData, -1);
      REPEAT UNTIL SYSTEM.BIT(spiCtrl, 0);
      SYSTEM.GET(spiData, data)
    END
  END SPIIdle;

  PROCEDURE SPI(n: INTEGER); (*send&rcv byte slowly with card selected*)
  BEGIN SYSTEM.PUT(spiCtrl, CARD0); SYSTEM.PUT(spiData, n);
    REPEAT UNTIL SYSTEM.BIT(spiCtrl, 0);
    SYSTEM.GET(spiData, data)
  END SPI;

  PROCEDURE SPICmd(n, arg: INTEGER);
    VAR i, crc: INTEGER;
  BEGIN (*send cmd*)
    REPEAT SPIIdle(1) UNTIL data = 255; (*flush while unselected*)
    REPEAT SPI(255) UNTIL data = 255; (*flush while selected*)
    IF n = 8 THEN crc := 135 ELSIF n = 0 THEN crc := 149 ELSE crc := 255 END;
    SPI(n MOD 64 + 64); (*send command*)
    FOR i := 24 TO 0 BY -8 DO SPI(ROR(arg, i)) END; (*send arg*)
    SPI(crc); i := 32;
    REPEAT SPI(255); DEC(i) UNTIL (data < 80H) OR (i = 0)
  END SPICmd;

  PROCEDURE SDShift(VAR n: INTEGER);
    VAR data: INTEGER;
  BEGIN SPICmd(58, 0);  (*CMD58 get card capacity bit*)
    SYSTEM.GET(spiData, data); SPI(-1);
    IF (data # 0) OR ~SYSTEM.BIT(spiData, 6) THEN n := n * 512 END ;  (*non-SDHC card*)
    SPI(-1); SPI(-1); SPIIdle(1)  (*flush response*)
  END SDShift;

  PROCEDURE ReadSDLim(src, dst, lim: INTEGER);
    VAR i: INTEGER;
  BEGIN SDShift(src); SPICmd(17, src); ASSERT(data = 0); (*CMD17 read one block*)
    i := 0; (*wait for start data marker*)
    REPEAT SPI(-1); INC(i) UNTIL data = 254;
    SYSTEM.PUT(spiCtrl, SPIFAST + CARD0);
    FOR i := 0 TO lim BY 4 DO
      SYSTEM.PUT(spiData, -1);
      REPEAT UNTIL SYSTEM.BIT(spiCtrl, 0);
      SYSTEM.GET(spiData, data);
      SYSTEM.PUT(dst, data); INC(dst, 4);
    END;
    IF lim < 508 THEN
      FOR i := lim+4 TO 508 BY 4 DO
        SYSTEM.PUT(spiData, -1);
        REPEAT UNTIL SYSTEM.BIT(spiCtrl, 0);
      END;
    END;
    SPI(255); SPI(255); SPIIdle(1) (*may be a checksum; deselect card*)
  END ReadSDLim;

  PROCEDURE ReadSD(src, dst: INTEGER);
    VAR i: INTEGER;
  BEGIN
    ReadSDLim(src, dst, 508);
  END ReadSD;

  PROCEDURE WriteSDLim(dst, src, lim: INTEGER);
    VAR i, n: INTEGER; x: BYTE;
  BEGIN SDShift(dst); SPICmd(24, dst); ASSERT(data = 0); (*CMD24 write one block*)
    SPI(254); (*write start data marker*)
    SYSTEM.PUT(spiCtrl, SPIFAST + CARD0);
    FOR i := 0 TO lim BY 4 DO
      IF i <= lim THEN SYSTEM.GET(src, n); INC(src, 4);
      ELSE n := 0;
      END;
      SYSTEM.PUT(spiData, n);
      REPEAT UNTIL SYSTEM.BIT(spiCtrl, 0);
    END;
    FOR i := lim+4 TO 508 BY 4 DO
      SYSTEM.PUT(spiData, 0);
      REPEAT UNTIL SYSTEM.BIT(spiCtrl, 0);
    END;
    SPI(255); SPI(255); (*dummy checksum*) i := 0;
    REPEAT SPI(-1); INC(i); UNTIL (data MOD 32 = 5) OR (i = 10000);
    ASSERT(data MOD 32 = 5); SPIIdle(1) (*deselect card*)
  END WriteSDLim;

  PROCEDURE InitSecMap*;
    VAR i: INTEGER;
  BEGIN NofSectors := 0; NEW(sectorMap); sectorMap.map[0] := {0 .. 31}; sectorMap.map[1] := {0 .. 31};
    FOR i := 2 TO filemapsize DIV 32 - 1 DO sectorMap.map[i] := {} END
  END InitSecMap;

  (* Sector numbers are always a multiple of 29 for the purpose of redundancy checks. (p. 110) *)
  PROCEDURE MarkSector*(sec: INTEGER);
  BEGIN ASSERT(sec MOD 29 = 0); sec := sec DIV 29;
    INCL(sectorMap.map[sec DIV 32], sec MOD 32); INC(NofSectors);
  END MarkSector;

  PROCEDURE FreeSector*(sec: INTEGER);
  BEGIN ASSERT(sec MOD 29 = 0); sec := sec DIV 29;
    EXCL(sectorMap.map[sec DIV 32], sec MOD 32); DEC(NofSectors)
  END FreeSector;

  PROCEDURE AllocSector*(hint: INTEGER; VAR sec: INTEGER);
    VAR s: INTEGER;
  BEGIN (*find free sector, starting after hint*)
    ASSERT(hint MOD 29 = 0); hint := hint DIV 29; s := hint;
    REPEAT INC(s);
      IF s = filemapsize THEN s := 1 END ;
    UNTIL ~(s MOD 32 IN sectorMap.map[s DIV 32]);
    INCL(sectorMap.map[s DIV 32], s MOD 32); INC(NofSectors); sec := s * 29
  END AllocSector;

  PROCEDURE GetSector*(src: INTEGER; VAR dst: Sector);
  BEGIN
    ASSERT(src MOD 29 = 0); src := src DIV 29;
    src := src * 2 + FSoffset;
    ReadSD(src, SYSTEM.ADR(dst)); ReadSD(src+1, SYSTEM.ADR(dst)+512)
  END GetSector;

  (* dangerous! *)
  PROCEDURE GetSectorToMem*(src, dst, lim: INTEGER);
  BEGIN
    ASSERT(src MOD 29 = 0); src := src DIV 29;
    src := src * 2 + FSoffset;
    IF lim <= 508 THEN
      ReadSDLim(src, dst, lim);
    ELSIF lim <= 1020 THEN
      ReadSDLim(src, dst, 508); ReadSDLim(src+1, dst+512, lim-512);
    ELSE
      ReadSDLim(src, dst, 508); ReadSDLim(src+1, dst+512, 508);
    END;
  END GetSectorToMem;

  (* dangerous! *)
  PROCEDURE PutMemToSector*(dst, src, lim: INTEGER);
  BEGIN
    ASSERT(dst MOD 29 = 0); dst := dst DIV 29;
    dst := dst * 2 + FSoffset;
    IF lim <= 508 THEN
      WriteSDLim(dst, src, lim);
    ELSIF lim <= 1020 THEN
      WriteSDLim(dst, src, 508); WriteSDLim(dst+1, src+512, lim-512);
    ELSE
      WriteSDLim(dst, src, 508); WriteSDLim(dst+1, src+512, 508);
    END;
  END PutMemToSector;

  
  PROCEDURE PutSector*(dst: INTEGER; VAR src: Sector);
  BEGIN ASSERT(dst MOD 29 = 0); dst := dst DIV 29;
    dst := dst * 2 + FSoffset;
    WriteSDLim(dst, SYSTEM.ADR(src), 508); WriteSDLim(dst+1, SYSTEM.ADR(src)+512, 508)
  END PutSector;

(*-------- Miscellaneous procedures----------*)

  PROCEDURE Time*(): INTEGER;
    VAR t: INTEGER;
  BEGIN SYSTEM.GET(timer, t); RETURN t
  END Time;

  PROCEDURE Clock*(): INTEGER;
  BEGIN RETURN clock
  END Clock;

  PROCEDURE SetClock*(dt: INTEGER);
  BEGIN clock := dt
  END SetClock;

  PROCEDURE SetReset*(reset: LONGINT);
  BEGIN Reset := SYSTEM.VAL(ResetFunc, reset);
  END SetReset;

  PROCEDURE SetGC*(gc: LONGINT);
  BEGIN GC := SYSTEM.VAL(GCFunc, gc);
  END SetGC;

  PROCEDURE SetAllocPtr*(ap: INTEGER);
  BEGIN AllocPtr := ap;
    SYSTEM.PUT(-60, 0BEA7H);
    SYSTEM.PUT(-60, ap);
  END SetAllocPtr;

  (* Deposits a relative offset jump to `Padr` in location `at` *)
  (* Used to install functions at places required for the operating system. *)
  PROCEDURE Install*(Padr, at: INTEGER);
    VAR inst: LONGINT;

     (* Returns a `jal x0, imm` instruction. *)
    PROCEDURE Jal(imm: LONGINT) : LONGINT;
      VAR result, imm20, imm19to12, imm11, imm10to1: LONGINT;
    BEGIN
      imm20 := imm DIV 100000H;
      imm19to12 := (imm - imm20 * 100000H) DIV 1000H;
      imm11 := (imm - (imm20 * 100000H + imm19to12 * 1000H)) DIV 800H;
      imm10to1 := (imm - (imm20 * 100000H + imm19to12 * 1000H + imm11 * 800H)) DIV 2H;
      result := ((((imm20 * 400H + imm10to1) * 2H + imm11) * 100H + imm19to12) * 20H + 0) * 80H + 111;
      RETURN result
    END Jal;

  BEGIN inst := Jal(Padr - at); SYSTEM.PUT(at, inst);
  END Install;

  PROCEDURE AbortTrap(trap, loc: INTEGER);
  BEGIN
    IF Reset # NIL THEN Reset(trap, loc) ELSE REPEAT UNTIL FALSE END;
  END AbortTrap;

  PROCEDURE Abort;
  BEGIN Reset(0, 0);
  END Abort;

  PROCEDURE Trap(VAR a: INTEGER; b: INTEGER);
    VAR u, v, w: INTEGER;
  BEGIN
    (* In RISC5, bits were conveniently unused in the reg jump instruction, which Oberon *)
    (* then used to encode trap numbers. We don't have that luxury, so we deposit the trap *)
    (* number _after_ the instruction instead. It can't be executed, so it will cause *)
    (* errors if jumped to (and confuse any disassembler!). *)
    u := SYSTEM.REG(RA); SYSTEM.GET(u + 4, v); w := v DIV 10000000H MOD 10H; (*trap number*)
    IF w = 0 THEN NewPtr(a, b);
    (* Note: 192 sets the top two LEDs. This indicates that a trap was hit. *)
    (* Note on the note: I currently put the whole trap in the LEDs, for easier debugging *)
    (* with my emulator that supports 32-bit LED output. *)
    ELSE (*stop*) SYSTEM.PUT(led, heapLim - heapOrg); SYSTEM.PUT(led, allocated); SYSTEM.PUT(led, v);
      (* freeze system *)
      AbortTrap(v, u);
    END;
    (* Ok, more explanation of some of the low-level hacks in use here. *)
    (* We had to deposit the trap number _after_ the instruction, which means if we *)
    (* return to that location, we're in trouble, as it will execute gobbledygook. *)
    (* Ideal solution: we just add 4 to RA, as then we'll jump to after the trap number. *)
    (* That doesn't work, as the function epilogue overwrites RA... *)
    (* So currently there is a jump instruction to skip over the trapnum as we return. *)
    (* It is perhaps less than ideal. *)
    (* Note that this will never execute if trapnum > 0; but we had to do this for NEW() to *)
    (* work as it's supposed to. *)
    (* A cleaner scheme for RISC-V would be to use mtvec, but this would require multiple *)
    (* privilege modes. *)
  END Trap;

  PROCEDURE Init*;
  BEGIN
    Install(SYSTEM.ADR(Trap), 20H);  (*install temporary trap; replaced later by System.Mod*)
    Install(SYSTEM.ADR(Abort), 0);
    SYSTEM.GET(12, MemLim); SYSTEM.GET(24, heapOrg);
    stackOrg := heapOrg; stackSize := 8000H;
    (*INC(heapOrg, 050D00H);*)
    INC(heapOrg, 040000H);
    heapLim := 0E0000H;
    list1 := 0; list2 := 0; list3 := 0; list0 := heapOrg;
    SYSTEM.PUT(list0, heapLim - heapOrg); SYSTEM.PUT(list0+4, -1); SYSTEM.PUT(list0+8, 0);
    SYSTEM.PUT(-60, 0AH);
    SYSTEM.PUT(-60, heapLim - heapOrg);
    largestFreeBlock := 0; allocated := 0; clock := 0; InitSecMap
  END Init;

END Kernel.
