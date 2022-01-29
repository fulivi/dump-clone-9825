10 ! **** DUMP9825 ****
20 ! Copyright (c) 2022 F.Ulivi
30 !
40 ! Licensed under the 3-Clause BSD License
50 !
60 ICOM 1000
70 OPTION BASE 1
80 INTEGER A,B,E,G,I,L,N
90 REAL T
100 PRINT "**** DUMP9825 ****"
110 PRINT
120 PRINT "v1.0 - F.Ulivi - 2022"
130 PRINT
140 ! To change the amount of allocated 30k-blocks
150 ! modify it in next line
160 DIM A$(4)[30720]
170 N=ROW(A$)
180 PRINT "30k blocks:";N
190 A=0
200 I=0
210 INPUT "Track to dump (0=A,1=B)?",I
220 PRINT "Track     :";I
230 IF I<>0 THEN A=A+1
240 I=0
250 INPUT "Threshold for reading (0=low,1=high)?",I
260 PRINT "Read thr  :";I
270 IF I<>0 THEN A=A+2
280 I=0
290 INPUT "Threshold for gap searching (0=low,1=high)?",I
300 PRINT "Gap thr   :";I
310 IF I<>0 THEN A=A+4
320 I=0
330 INPUT "Counter displayed? (0=no,1=yes)?",I
340 PRINT "Display   :";I
350 IF I=0 THEN A=A+8
360 B=1589
370 INPUT "Demodulation threshold?",B
380 PRINT "Threshold :";B
390 B$="DUMP"
400 INPUT "Name of dump file (will be overwritten if present!)?",B$
410 PRINT "Dump file : ";B$
420 ILOAD "DUMP25"
430 E=0
440 PRINT "Dumping tape"
450 ICALL Dump9825(A,B,E,L,G,A$(*))
460 DISP
470 PRINT "Error code  :";E
480 PRINT "Last record :";L
490 PRINT "Good records:";G
500 T=0
510 FOR I=1 TO N
520 PRINT "LEN(A$(";I;"))=";LEN(A$(I))
530 T=T+LEN(A$(I))
540 NEXT I
550 PRINT "TOTAL LENGTH:";T
560 IF T<>0 THEN 590
570 PRINT "Null dump, no file created"
580 GOTO Out
590 ASSIGN B$ TO #1,Err
600 IF Err=1 THEN No_file
610 PRINT "Purging ";B$
620 PURGE B$
630 IF Err=2 THEN No_file
640 ASSIGN * TO #1
650 No_file: !
660 PRINT "Creating ";B$
670 CREATE B$,N*30+2,1024
680 ASSIGN B$ TO #1
690 PRINT "Writing dump data"
700 FOR I=1 TO N
710 PRINT #1;A$(I)
720 NEXT I
730 PRINT #1;END
740 ASSIGN * TO #1
750 Out: PRINT "Done!"
760 END
