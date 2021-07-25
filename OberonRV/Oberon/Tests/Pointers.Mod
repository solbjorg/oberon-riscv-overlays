MODULE Pointers;
  IMPORT SYSTEM;
  TYPE Ptr = POINTER TO Node;
    Node = RECORD
      num: INTEGER;
      next: Ptr;
    END;

  VAR allocated*: INTEGER;
    heapOrg*, heapLim*: INTEGER;
    stackOrg* ,  stackSize*, MemLim*: INTEGER;
    list0, list1, list2, list3: INTEGER;  (*lists of free blocks of size n*256, 128, 64, 32 bytes*)
    p, q: Ptr;
    i: INTEGER;

  PROCEDURE GetBlock(VAR p: LONGINT; len: LONGINT);
    (*len is multiple of 256*)
    VAR q0, q1, q2, size: LONGINT; done: BOOLEAN;
  BEGIN q0 := 0; q1 := list0; done := FALSE;
    WHILE ~done & (q1 # 0) DO
      SYSTEM.GET(q1, size); SYSTEM.GET(q1+8, q2);
      IF size < len THEN (*no fit*) q0 := q1; q1 := q2
      ELSIF size = len THEN (*extract -> p*)
        done := TRUE; p := q1;
        IF q0 # 0 THEN SYSTEM.PUT(q0+8, q2) ELSE list0 := q2 END
      ELSE (*reduce size*)
        done := TRUE; p := q1; q1 := q1 + len;
        SYSTEM.PUT(q1, size-len); SYSTEM.PUT(q1+4, -1); SYSTEM.PUT(q1+8, q2);
        IF q0 # 0 THEN SYSTEM.PUT(q0+8, q1) ELSE list0 := q1 END
      END
    END ;
    IF ~done THEN p := 0 END
  END GetBlock;

  PROCEDURE GetBlock128(VAR p: LONGINT);
    VAR q: LONGINT;
  BEGIN
    IF list1 # 0 THEN p := list1; SYSTEM.GET(list1+8, list1)
    ELSE GetBlock(q, 256); SYSTEM.PUT(q+128, 128); SYSTEM.PUT(q+132, -1); SYSTEM.PUT(q+136, list1);
      list1 := q + 128; p := q
    END
  END GetBlock128;

  PROCEDURE GetBlock64(VAR p: LONGINT);
    VAR q: LONGINT;
  BEGIN
    IF list2 # 0 THEN p := list2; SYSTEM.GET(list2+8, list2)
    ELSE GetBlock128(q); SYSTEM.PUT(q+64, 64); SYSTEM.PUT(q+68, -1); SYSTEM.PUT(q+72, list2);
      list2 := q + 64; p := q
    END
  END GetBlock64;

  PROCEDURE GetBlock32(VAR p: LONGINT);
    VAR q: LONGINT;
  BEGIN
    IF list3 # 0 THEN p := list3; SYSTEM.GET(list3+8, list3)
    ELSE GetBlock64(q); SYSTEM.PUT(q+32, 32); SYSTEM.PUT(q+36, -1); SYSTEM.PUT(q+40, list3);
      list3 := q + 32; p := q
    END
  END GetBlock32;

  PROCEDURE New*(VAR ptr: LONGINT; tag: LONGINT);
    (*called by NEW via MT[0]; ptr and tag are pointers*)
    VAR p, size, lim: LONGINT;
  BEGIN SYSTEM.GET(tag, size);
    SYSTEM.PUT(-60, 1234H);
    IF size = 32 THEN GetBlock32(p)
    ELSIF size = 64 THEN GetBlock64(p)
    ELSIF size = 128 THEN GetBlock128(p)
    ELSE GetBlock(p, (size+255) DIV 256 * 256)
    END ;
    IF p = 0 THEN ptr := 0
    ELSE ptr := p+8; SYSTEM.PUT(p, tag); lim := p + size; INC(p, 4); INC(allocated, size);
      WHILE p < lim DO SYSTEM.PUT(p, 0); INC(p, 4) END
    END
  END New;

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

  PROCEDURE Trap(VAR a: INTEGER; b: INTEGER);
    VAR u, v, w: INTEGER;
    (* In RISC5, bits were conveniently unused in the reg jump instruction, which Oberon *)
    (* then used to encode trap numbers. We don't have that luxury, so we deposit the trap *)
    (* number _after_ the instruction instead. It can't be executed, so it will cause *)
    (* errors if jumped to (and confuse any disassembler!). *)
  BEGIN u := SYSTEM.REG(1); SYSTEM.GET(u + 4, v); w := v DIV 1000000H MOD 10H; (*trap number*)
    IF w = 0 THEN New(a, b)
    (* Note: 192 sets the top two LEDs. This indicates that a trap was hit. *)
    ELSE (*stop*) SYSTEM.PUT(-60, v); REPEAT UNTIL FALSE
    END;
    SYSTEM.PUT(-60, 7CH);
    (* Ok, more explanation of some of the low-level hacks in use here. *)
    (* We had to deposit the trap number _after_ the instruction, which means if we *)
    (* return to that location, we're in trouble, as it will execute gobbledygook. *)
    (* Ideal solution: we just add 4 to RA, and we'll jump to after the trap number. *)
    (* That doesn't work, as the function epilogue overwrites RA... *)
    (* Note that this will never execute if trapnum > 0; but we had to do *)
    (* this for NEW() to work as it's supposed to. *)
    (* There may be a better scheme for RISC-V! TODO. *)
  END Trap;

BEGIN
  Install(SYSTEM.ADR(Trap), 20H);
  SYSTEM.GET(12, MemLim); SYSTEM.GET(24, heapOrg);
  stackOrg := heapOrg; stackSize := 8000H; heapLim := MemLim;
  list1 := 0; list2 := 0; list3 := 0; list0 := heapOrg;
  SYSTEM.PUT(list0, heapLim - heapOrg); SYSTEM.PUT(list0+4, -1); SYSTEM.PUT(list0+8, 0);
  allocated := 0;
  SYSTEM.GET(20H, i);
  NEW(p);
  SYSTEM.GET(20H, i);
  IF q = NIL THEN
    SYSTEM.PUT(-60, 0AAH);
  END;
  NEW(q);
  p.num  := 1;
  q.num  := 2;
  p.next := q;
  q.next := p;
  SYSTEM.PUT(-60, p.num);
  SYSTEM.PUT(-60, p.next.num);
  SYSTEM.PUT(-60, p.next.next.num);
END Pointers.
