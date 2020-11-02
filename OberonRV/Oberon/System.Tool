System.Open ^  System.Recall  System.Watch  System.Collect
Edit.Open ^  Edit.Recall
Edit.ChangeFont Oberon10i.Scn.Fnt
Edit.ChangeFont Oberon10b.Scn.Fnt

System.Directory ^
  *.Mod  *.Bak  *.Tool  *.Text  *.Scn.Fnt  *.smb  *.rsc

ORP.Compile @  ORP.Compile @/s  ORP.Compile name~
RVSystem.Free ~
RVSystem.Open Draw.Tool
RVSystem.CopyFiles ~
RVSystem.RenameFiles ~
RVSystem.DeleteFiles ~

System.ShowModules  System.ShowCommands ^ 

PCLink1.Run
Hilbert.Draw  Sierpinski.Draw  Blink.Run  Stars.Open

Tools.Inspect 0
Tools.Sector 1
Tools.ShowFile 
Tools.Recall  Tools.Clear
