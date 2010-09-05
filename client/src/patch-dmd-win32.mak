Index: dmd-trunk/src/win32.mak
===================================================================
--- dmd-trunk/src/win32.mak	(revision 659)
+++ dmd-trunk/src/win32.mak	(working copy)
@@ -9,7 +9,7 @@
 #DMDSVN=\svnproj\dmd\branches\dmd-1.x\src
 SCROOT=$D\dm
 INCLUDE=$(SCROOT)\include
-CC=\dm\bin\dmc
+CC=dmc
 LIBNT=$(SCROOT)\lib
 SNN=$(SCROOT)\lib\snn
 DIR=\dmd2
