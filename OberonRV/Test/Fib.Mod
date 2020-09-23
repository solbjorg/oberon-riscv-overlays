MODULE* Fib;
IMPORT SYSTEM;
CONST led = -60;

VAR a, b: INTEGER;

PROCEDURE Fibonacci(VAR x, y: INTEGER; n: INTEGER);
BEGIN
IF (n > 0) THEN
y := x + y; x := y - x; SYSTEM.PUT(led, x);
Fibonacci(x, y, n-1);
END;
END Fibonacci;

BEGIN a := 1; b := 1; Fibonacci(a,b,10);
END Fib.
