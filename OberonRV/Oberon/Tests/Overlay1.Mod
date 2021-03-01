MODULE Overlay1;
  IMPORT SYSTEM, Kernel, Display, Modules, Viewers, Fonts, Texts, Overlay4, Overlay2;

  TYPE Painter* = PROCEDURE (x, y: INTEGER);
    Marker* = RECORD Fade*, Draw*: Painter END;

    Cursor* = RECORD
        marker*: Marker; on*: BOOLEAN; X*, Y*: INTEGER
    END;

    InputMsg* = RECORD (Display.FrameMsg)
      id*: INTEGER;
      keys*: SET;
      X*, Y*: INTEGER;
      ch*: CHAR;
      fnt*: Fonts.Font;
      col*, voff*: INTEGER
    END;

    SelectionMsg* = RECORD (Display.FrameMsg)
      time*: LONGINT;
      text*: Texts.Text;
      beg*, end*: LONGINT
    END;

    ControlMsg* = RECORD (Display.FrameMsg)
      id*, X*, Y*: INTEGER
    END;

    CopyMsg* = RECORD (Display.FrameMsg)
      F*: Display.Frame
    END;

    Task* = POINTER TO TaskDesc;

    Handler* = PROCEDURE;

    TaskDesc* = RECORD
      state, nextTime, period*: INTEGER;
      next: Task;
      handle: Handler
    END;

  VAR User*: ARRAY 8 OF CHAR; Password*: LONGINT;
        Arrow*, Star*: Marker;
    Mouse, Pointer: Cursor;
    FocusViewer*: Viewers.Viewer;
    Log*: Texts.Text;

    Par*: RECORD
      vwr*: Viewers.Viewer;
      frame*: Display.Frame;
      text*: Texts.Text;
      pos*: LONGINT
    END;

    CurFnt*: Fonts.Font;
    CurCol*, CurOff*: INTEGER;
    NofTasks*: INTEGER;

    CurTask: Task;
    DW, DH, CL: INTEGER;
    ActCnt: INTEGER; (*action count for GC*)
    Mod: Modules.Module;

  PROCEDURE TestFunctionCall;
  BEGIN SYSTEM.PUT(-60, 0AA3H);
  END TestFunctionCall;

  PROCEDURE TestLoad*;
  BEGIN SYSTEM.PUT(-60, 0AA2H);
    TestFunctionCall;
    SYSTEM.PUT(-60, 0AA400000H + Kernel.Time());
  END TestLoad;

  PROCEDURE CallOverlay*(a, b, c, d: INTEGER): INTEGER;
    VAR t: Task;
  BEGIN SYSTEM.PUT(-60, 0BB1H);
    Overlay2.Test;
    SYSTEM.PUT(-60, 0BB20H);
    Overlay2.TestArguments(0BB21H, 0BB22H);
    SYSTEM.PUT(-60, 0BB23H);
    NEW(t); ASSERT(t # NIL);
    SYSTEM.PUT(-60, a); SYSTEM.PUT(-60, b);
    SYSTEM.PUT(-60, c); SYSTEM.PUT(-60, d);
    RETURN 5
  END CallOverlay;

BEGIN
  SYSTEM.PUT(-60, 0AA1H); TestLoad;
  SYSTEM.PUT(-60, 0AA5H); SYSTEM.PUT(-60, CallOverlay(1, 2, 3, 4));

  SYSTEM.PUT(-60, 0BB30H);
END Overlay1.
