MODULE TestIfNil;
  IMPORT SYSTEM;

  TYPE Module = POINTER TO ModDesc;
    ModuleName* = ARRAY 32 OF CHAR;
    ModDesc* = RECORD
        name*: ModuleName;
        next*: Module;
        key*, num*, size*, refcnt*: INTEGER;
        data*, code*, imp*, cmd*, ent*, ptr*, unused: INTEGER  (*addresses*)
      END ;

  VAR root: Module;

  PROCEDURE Test;
    VAR mod: Module;
  BEGIN
    mod := root;
    IF root = NIL THEN
      SYSTEM.PUT(-60, 0AAH);
    END;
    SYSTEM.PUT(-60, 0BBH);
  END Test;

BEGIN Test();
END TestIfNil.
