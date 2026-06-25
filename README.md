# LuaNT 4.0, A greatest project in OpenComputers (MC 1.12.2) mod
A Operating System with simple GUI, Launches at minimum 1x 384KB RAM (Tier 2) free 14KB in max usage; for normal use minimum x2 384KB RAM (Tier 2), gets 768KB, free in maximum 266KB.
Have a Winlogon, drivers, services, Registry, multi-task, Plug-and-Play, WinUpdate (custom system), notepad, Device Manager, Task Manager and Console.

!!WARNING!!: Unstardard installation created, for making LuaNT run without cover at OpenOS, he have own **init.lua** and **ntoskrnl.lua**, for initializing every system. Second HDD disk to install needed for separate LuaNT from OpenOS!

## How to install this?
First: Create PC with:
   - Standard components
   - Internet card
   - 2 HDD disks (first for OpenOS, second for LuaNT)

Second: Install OpenOS.

Third: After OpenOS installation, run in command prompt: "pastebin get -f Kv80QkZG luantinstall.lua", and after download enter "luantinstall", and follow all steps in installer,
but select second disk that you plug in PC without files. And wait for installation.

Fourth: After install, shutdown PC, and remove disk with OpenOS. After that start PC and if you see at booting: "Windows NT Boot Manager", you finally install LuaNT!!!
Now you can make with he everything, or update with WinUpdate.

## Some help...
If you don't know how to login, password for Administrator is "admin123", but you can CHANGE he, by start usrman or Start>User Manager, select Administrator, by ^v select Password and ENTER, write own, press < and after reboot, at password "admin123", you can see Login Error.

## How to get updates?
Possibly you can see in Task Manager, strange **WUSvc.exe**, is a Windows Update Service, he checks updates of LuaNT here, if he detect update, you can see in right-top corner blue frame with text, and after next Power On **init.lua** installs updates from Windows/WinSxS and after update WinSxS removed. If you not gets update, you not have **Internet Card**, or LuaNT Update Config at GitHub not updates, or I (RedstoneShel) don't make update. All asks and bugs in Issues.

## How to make my clone and install my friend or at server?
If you install LuaNT 4.0, you can open a **SetupMgr** and if you install Disk Drive, and put in he Floppy, in Setup Mgr you can click ENTER and create **Installation Floppy**
After, you can give this Floppy to other player, and he install this floppy in own PC, boot from he. And by open Menu of MyPC (LMB), click to button **Install to...**, but not on btn, click at 1px higher and this open Windows NT Setup Master, where he select disk to install, and by ENTER install OS, after install click ENTER and reboot, now LuaNT at own disk, and he can give this **Installation Floppy** a second player, he repeat this process... and now you modification everywhere in world!

# How to make drivers and my programs?
You can make own file by creating in external methods as VSCode by opening <minecraft>/saves/<world>/opencomputers/<UUID of HDD where LuaNT>/path_to_make_file. Or use internal command in cmd.exe as "mkfile <path_for_file_with_name_with_extension>" in next update with "notepad <path> (this works)". For help, read ApiDoc.md.
