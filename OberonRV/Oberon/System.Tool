System.Open ^  System.Recall  System.Watch  System.Collect
Edit.Open ^  Edit.Recall

System.Directory ^
  *.Mod  *.Bak  *.Tool  *.Text  *.Scn.Fnt  *.smb  *.rsc

RVOP.Compile @  RVOP.Compile @/s  RVOP.Compile name~
System.Free ~
System.Open Draw.Tool
System.CopyFiles ~
System.RenameFiles ~
System.DeleteFiles ~

System.ShowModules  System.ShowCommands ^ 

PCLink1.Run
RVOP.Compile Hilbert.Mod
Hilbert.Draw  Sierpinski.Draw  Blink.Run  Stars.Open

Tools.Inspect 0
Tools.Sector 1
Tools.ShowFile 
Tools.Recall  Tools.Clear

TestArrays.Test
TestFileCorruption.Test
TestSets.Test
TestBigIf.Test

Permutations.Generate 2 3 4~
Powers.Generate 8
PrimeNumbers.Generate 12

To make the compiler compile itself, perform the below commands:
RVOP.Compile RVOS.Mod/s RVOB.Mod/s
RVOP.Compile RVAssem.Mod/s
RVOP.Compile RVOG.Mod/s
RVOP.Compile RVOP.Mod/s
If it fails, the garbage collector may not have run yet;
making this a little smoother is TODO.
