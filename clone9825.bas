10 ! **** CLONE9825 ****
20 ! Copyright (c) 2022 F.Ulivi
30 !
40 ! Licensed under the 3-Clause BSD License
50 !
60 ICOM 1000
70 OPTION BASE 1
80 INTEGER A,B,E,I,L,N,T
90 PRINT "**** CLONE9825 ****"
100 PRINT
110 PRINT "v1.0 - F.Ulivi - 2022"
120 PRINT
130 ! To change the amount of allocated 30k-blocks
140 ! modify it in next line
150 DIM A$(4)[30720]
160 N=ROW(A$)
170 PRINT "30k blocks :";N
180 B$="CLONE"
190 INPUT "Name of clone input file?",B$
200 PRINT "Clone file : ";B$
210 ASSIGN B$ TO #1
220 READ #1;T
230 A=(T<>0)
240 PRINT "Track      :";A
250 READ #1;I
260 IF I>0 THEN 290
270 PRINT "Bad clone file (I=";I;")"
280 END
290 IF I<=N THEN 320
300 PRINT "Not enough allocated space (";I;">";N;")"
310 END
320 PRINT "Reading clone file"
330 FOR L=1 TO I
340 READ #1;A$(L)
350 PRINT "LEN(A$(";L;"))=";LEN(A$(L))
360 NEXT L
370 ASSIGN * TO #1
380 B=1565
390 INPUT "Bit length?",B
400 PRINT "Bit length :";B
410 I=1
420 INPUT "Rewind tape (0=no,1=yes)?",I
430 PRINT "Rewind tape:";I
440 IF I=0 THEN 470
450 PRINT "Rewinding tape"
460 REWIND ":T15"
470 PRINT "Writing tape"
480 ILOAD "CLON25"
490 ICALL Clone9825(A,B,A$(*),E)
500 PRINT "Error code :";E
510 PRINT "Done!"
520 END
