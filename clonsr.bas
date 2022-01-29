10 ICOM 1000
100 ISOURCE                 NAM Clon25
110 ISOURCE ! **** CLONE9825 ****
120 ISOURCE ! Copyright (c) 2022 F.Ulivi
130 ISOURCE !
140 ISOURCE ! Licensed under the 3-Clause BSD License
150 ISOURCE !
160 ISOURCE ! Any resemblance to test ROM code is purely coincidental ;)
170 ISOURCE !
180 ISOURCE                 EXT Isr_access,Get_value,Get_info,Put_value
190 ISOURCE !
200 ISOURCE ! Bits in option bitmap
210 ISOURCE Opt_track_b:    EQU 1
220 ISOURCE !
230 ISOURCE ! Operation codes
240 ISOURCE Op_terminate:   EQU 0
250 ISOURCE Op_wr_words:    EQU 1
260 ISOURCE Op_wr_gap:      EQU 2
270 ISOURCE Op_wr_repeat:   EQU 3
280 ISOURCE !
290 ISOURCE ! Error codes
300 ISOURCE ERR_none:       EQU 0           ! No error
310 ISOURCE ERR_normal:     EQU 1           ! Normal end
320 ISOURCE ERR_underf:     EQU 2           ! Exchange buffer underflow
330 ISOURCE ERR_prem_end:   EQU 3           ! Premature end of data
340 ISOURCE ERR_no_space:   EQU 4           ! No more space on tape
350 ISOURCE ERR_taco:       EQU 5           ! TACO error
360 ISOURCE ERR_par:        EQU 6           ! Bad parameters
370 ISOURCE ERR_no_isr:     EQU 7           ! Couldn't acquire ISR
380 ISOURCE !
390 ISOURCE ! Offset for indirect jumps @ISR level
400 ISOURCE Indirect_off:   EQU 100000B
410 ISOURCE !
420 ISOURCE ! TACO Commands
430 ISOURCE TACO_Stop:      EQU 10000B
440 ISOURCE TACO_Set_Track: EQU 14000B
450 ISOURCE TACO_Mod:       EQU 100B
460 ISOURCE TACO_track_B:   EQU TACO_Mod
470 ISOURCE TACO_Clear:     EQU 34000B
480 ISOURCE TACO_forward:   EQU 100000B
490 ISOURCE TACO_wr_9825:   EQU 07000B+TACO_forward
500 ISOURCE TACO_wr_gap:    EQU 54000B+TACO_forward
510 ISOURCE TACO_force_irq: EQU 15000B
520 ISOURCE !
530 ISOURCE ! Precompensation
540 ISOURCE TACO_precomp:   EQU 60000B
550 ISOURCE !
560 ISOURCE ! T15 PA
570 ISOURCE T15:            EQU 15
580 ISOURCE !
590 ISOURCE R34:            EQU 34B
600 ISOURCE R35:            EQU 35B
610 ISOURCE Save_R35:       BSS 1
620 ISOURCE Isr_jump:       BSS 1
630 ISOURCE Err_code:       BSS 1
640 ISOURCE !
650 ISOURCE ! ************
660 ISOURCE ! * TACO ISR *
670 ISOURCE ! ************
680 ISOURCE Clone_Isr:      LDA R35
690 ISOURCE                 STA Save_R35
700 ISOURCE                 LDA R34
710 ISOURCE                 STA R35
720 ISOURCE                 LDA Err_code
730 ISOURCE                 RZA Err_n_end   ! Abort if errors
740 ISOURCE !
750 ISOURCE ! Check TACO state
760 ISOURCE                 LDA R5
770 ISOURCE                 AND =15
780 ISOURCE                 SZA Check2
790 ISOURCE                 SLA Check1
800 ISOURCE                 LDA =ERR_no_space       ! Met hole: no more space on tape
810 ISOURCE                 JMP Err_n_end
820 ISOURCE Check1:         LDA =ERR_taco   ! TACO error: no cartridge, write protection or servo failure
830 ISOURCE                 JMP Err_n_end
840 ISOURCE Check2:         JMP Isr_jump,I  ! TACO ok, jump to current state
850 ISOURCE !
860 ISOURCE Cmd_n_set_Int:  JSM Wait_Flg
870 ISOURCE                 STA R5
880 ISOURCE                 STB Isr_jump
890 ISOURCE Leave_Isr:      LDA Save_R35
900 ISOURCE                 STA R35
910 ISOURCE                 RET 1
920 ISOURCE !
930 ISOURCE Err_n_end:      STA Err_code
940 ISOURCE                 JSM Clear_TACO
950 ISOURCE                 LDA =TACO_Stop
960 ISOURCE                 JSM Cmd_TACO
970 ISOURCE                 LDA Save_R35
980 ISOURCE                 STA R35
990 ISOURCE                 JSM End_isr_high,I
1000 ISOURCE                 RET 1
1010 ISOURCE !
1020 ISOURCE Tmp1:           BSS 1
1030 ISOURCE !
1040 ISOURCE Wait_Flg:       STA Tmp1
1050 ISOURCE                 LDA =65511
1060 ISOURCE Wait1:          SFS Wait2
1070 ISOURCE                 RIA Wait1
1080 ISOURCE Wait2:          LDA Tmp1
1090 ISOURCE                 RET 1
1100 ISOURCE !
1110 ISOURCE Clear_TACO:     LDA =TACO_Clear
1120 ISOURCE Cmd_TACO:       JSM Wait_Flg
1130 ISOURCE                 STA R5
1140 ISOURCE                 RET 1
1150 ISOURCE !
1160 ISOURCE ! Get op/word into exchange buffer
1170 ISOURCE ! RET 1: underflow
1180 ISOURCE ! RET 2: OK
1190 ISOURCE Exch_op:        BSS 1
1200 ISOURCE Exch_word:      BSS 1
1210 ISOURCE Exch_flag:      BSS 1
1220 ISOURCE Curr_op:        BSS 1
1230 ISOURCE Curr_word:      BSS 1
1240 ISOURCE !
1250 ISOURCE Get_exchange:   LDA Exch_flag
1260 ISOURCE                 SLA Get_ex1,C
1270 ISOURCE                 STA Exch_flag
1280 ISOURCE                 LDA Exch_word
1290 ISOURCE                 STA Curr_word   ! Xfer word
1300 ISOURCE                 LDA Exch_op     ! Get new op
1310 ISOURCE                 RET 2
1320 ISOURCE Get_ex1:        LDA =ERR_underf ! Underflow
1330 ISOURCE                 RET 1
1340 ISOURCE !
1350 ISOURCE State_start:    JSM Get_exchange
1360 ISOURCE                 JMP Err_n_end
1370 ISOURCE !
1380 ISOURCE ! Start a new op (code in A)
1390 ISOURCE Start_op:       STA Curr_op
1400 ISOURCE                 ADA =Jump_tb+Indirect_off
1410 ISOURCE                 JMP A,I
1420 ISOURCE Jump_tb:        JMP Start_op0
1430 ISOURCE                 JMP Start_op1
1440 ISOURCE                 JMP Start_op2
1450 ISOURCE ! Op=0: terminate
1460 ISOURCE Start_op0:      LDA =ERR_normal
1470 ISOURCE                 JMP Err_n_end
1480 ISOURCE ! Op=1: write words
1490 ISOURCE Start_op1:      LDA Val_threshold
1500 ISOURCE                 ADA =TACO_precomp
1510 ISOURCE                 JSM Wait_Flg
1520 ISOURCE                 STA R7          ! Write timing & precompensation
1530 ISOURCE                 LDA Curr_word   ! First word
1540 ISOURCE                 JSM Wait_Flg
1550 ISOURCE                 STA R4
1560 ISOURCE                 LDA =TACO_wr_9825
1570 ISOURCE                 LDB =State_wr_words+Indirect_off
1580 ISOURCE                 JMP Cmd_n_set_Int
1590 ISOURCE ! Op=2: write gap
1600 ISOURCE Start_op2:      LDA Curr_word
1610 ISOURCE                 TCA
1620 ISOURCE                 JSM Wait_Flg
1630 ISOURCE                 STA R6          ! Load length of gap from Curr_word
1640 ISOURCE                 LDA =TACO_wr_gap
1650 ISOURCE                 LDB =State_wr_gap+Indirect_off
1660 ISOURCE                 JMP Cmd_n_set_Int
1670 ISOURCE !
1680 ISOURCE ! State_wr_words: write words
1690 ISOURCE State_wr_words: JSM Get_exchange
1700 ISOURCE                 JMP Err_n_end
1710 ISOURCE                 CPA Curr_op
1720 ISOURCE                 JMP State_ww_1
1730 ISOURCE                 JMP Start_op
1740 ISOURCE State_ww_1:     LDA Curr_word
1750 ISOURCE                 JSM Wait_Flg
1760 ISOURCE                 STA R4
1770 ISOURCE                 JMP Leave_Isr
1780 ISOURCE !
1790 ISOURCE ! State_wr_gap: write gap
1800 ISOURCE State_wr_gap:   JSM Get_exchange
1810 ISOURCE                 JMP Err_n_end
1820 ISOURCE                 JMP Start_op
1830 ISOURCE !
1840 ISOURCE ! Start writing
1850 ISOURCE ! RET 1: failure
1860 ISOURCE ! RET 2: OK
1870 ISOURCE Start_wr:       LDA =State_start+Indirect_off
1880 ISOURCE                 STA Isr_jump
1890 ISOURCE                 LDA Pa
1900 ISOURCE                 AND =15
1910 ISOURCE                 ADA =256+(3*16) ! 1 attempt, synch. access
1920 ISOURCE                 STA B
1930 ISOURCE                 LDA =Clone_Isr
1940 ISOURCE                 JSM Isr_access
1950 ISOURCE                 RET 1           ! Failed
1960 ISOURCE                 JSM Clear_TACO
1970 ISOURCE                 LDA =TACO_Set_Track
1980 ISOURCE                 LDB Val_options
1990 ISOURCE                 SLB Start1
2000 ISOURCE                 IOR =TACO_track_B
2010 ISOURCE Start1:         JSM Cmd_TACO    ! Set track A/B
2020 ISOURCE                 LDA =TACO_force_irq     ! Force IRQ to start FSM
2030 ISOURCE                 JSM Cmd_TACO    ! Off we go!
2040 ISOURCE                 RET 2
2050 ISOURCE !
2060 ISOURCE ! ********************************
2070 ISOURCE ! * ICALL Entry point: Clone9825 *
2080 ISOURCE ! ********************************
2090 ISOURCE !
2100 ISOURCE                 SUB
2110 ISOURCE Par_options:    INT             ! Option bitmap
2120 ISOURCE Par_threshold:  INT             ! Threshold
2130 ISOURCE Par_data:       STR(*)          ! Input data
2140 ISOURCE Par_error:      INT             ! Out: error code
2150 ISOURCE !
2160 ISOURCE Clone9825:      LDA =Val_options
2170 ISOURCE                 LDB =Par_options
2180 ISOURCE                 JSM Get_value
2190 ISOURCE                 LDA =Val_threshold
2200 ISOURCE                 LDB =Par_threshold
2210 ISOURCE                 JSM Get_value
2220 ISOURCE                 LDA =Data_info
2230 ISOURCE                 LDB =Par_data
2240 ISOURCE                 JSM Get_info
2250 ISOURCE                 LDA Data_info
2260 ISOURCE                 CPA =12         ! String array
2270 ISOURCE                 JMP Clone1
2280 ISOURCE                 JMP Bad_par
2290 ISOURCE Clone1:         LDA Data_info+1
2300 ISOURCE                 CPA =1
2310 ISOURCE                 JMP Clone2
2320 ISOURCE                 JMP Bad_par
2330 ISOURCE Clone2:         LDA Dim_size
2340 ISOURCE                 SLA Clone3      ! Dimensioned size must be even
2350 ISOURCE                 JMP Bad_par
2360 ISOURCE Clone3:         CLA
2370 ISOURCE                 STA Err_code
2380 ISOURCE                 LDA =First_block
2390 ISOURCE                 JSM New_el_block
2400 ISOURCE                 JMP Exit_err
2410 ISOURCE                 JSM Get_op      ! Get 1st op
2420 ISOURCE                 JMP Prem_end
2430 ISOURCE                 LDA Data_word   ! Prepare 1st op & word for ISR
2440 ISOURCE                 STA Exch_word
2450 ISOURCE                 LDA Op_to_exch
2460 ISOURCE                 STA Exch_op
2470 ISOURCE                 LDA =1
2480 ISOURCE                 STA Exch_flag
2490 ISOURCE                 LDA =T15
2500 ISOURCE                 STA Pa
2510 ISOURCE                 JSM Start_wr
2520 ISOURCE                 JMP No_isr
2530 ISOURCE ! Main loop
2540 ISOURCE Clone4:         DIR
2550 ISOURCE                 LDA Exch_flag
2560 ISOURCE                 RLA Clone5,S
2570 ISOURCE                 STA Exch_flag
2580 ISOURCE                 LDA Data_word
2590 ISOURCE                 STA Exch_word
2600 ISOURCE                 LDA Op_to_exch
2610 ISOURCE                 STA Exch_op
2620 ISOURCE                 EIR
2630 ISOURCE                 JSM Advance_op
2640 ISOURCE                 JMP Exit_err
2650 ISOURCE                 JMP Clone4
2660 ISOURCE Clone5:         LDA Err_code
2670 ISOURCE                 EIR
2680 ISOURCE                 SZA Clone4
2690 ISOURCE                 JMP Exit_err
2700 ISOURCE Prem_end:       LDA =ERR_prem_end
2710 ISOURCE                 JMP Exit_err
2720 ISOURCE No_isr:         LDA =ERR_no_isr
2730 ISOURCE                 JMP Exit_err
2740 ISOURCE Bad_par:        LDA =ERR_par
2750 ISOURCE Exit_err:       STA Err_code
2760 ISOURCE                 LDA =Err_code
2770 ISOURCE                 LDB =Par_error
2780 ISOURCE                 JSM Put_value
2790 ISOURCE                 RET 1
2800 ISOURCE !
2810 ISOURCE ! Get a word from data array
2820 ISOURCE ! RET 1: no more words
2830 ISOURCE ! RET 2: OK
2840 ISOURCE Get_data:       LDA C
2850 ISOURCE                 CPA El_end
2860 ISOURCE                 JMP Get1                ! Array element exhausted
2870 ISOURCE Get3:           WWC A,I                 ! Get word & adv pointer
2880 ISOURCE                 STA Data_word
2890 ISOURCE                 RET 2
2900 ISOURCE Get1:           DSZ El_count
2910 ISOURCE                 JMP Get4
2920 ISOURCE Get2:           LDA =ERR_prem_end       ! All elements read
2930 ISOURCE                 STA Err_code
2940 ISOURCE                 RET 1
2950 ISOURCE Get4:           LDA Last_el
2960 ISOURCE                 RZA Get2                ! Last element consumed
2970 ISOURCE                 ISZ Curr_ptr_block,I
2980 ISOURCE                 JMP Get5
2990 ISOURCE                 LDA Curr_ptr_block      ! Move to next block of elements
3000 ISOURCE                 ADA =3
3010 ISOURCE                 JSM New_el_block
3020 ISOURCE                 RET 1
3030 ISOURCE                 JMP Get3
3040 ISOURCE Get5:           JSM New_el
3050 ISOURCE                 RET 1
3060 ISOURCE                 JMP Get3
3070 ISOURCE !
3080 ISOURCE ! Prepare for a new element block
3090 ISOURCE ! A=ptr to pointer block
3100 ISOURCE ! RET 1: Error
3110 ISOURCE ! RET 2: OK
3120 ISOURCE New_el_block:   STA Curr_ptr_block
3130 ISOURCE                 ADA =1
3140 ISOURCE                 LDB A,I
3150 ISOURCE                 STB C                   ! Set starting address of new el
3160 ISOURCE                 ADA =1
3170 ISOURCE                 LDA A,I
3180 ISOURCE                 STA R35                 ! Set BSC of new el
3190 ISOURCE New_el:         WWC A,I                 ! Get el length and move to 1st word
3200 ISOURCE                 SZA Get2                ! 0-sized el
3210 ISOURCE                 RLA Get2                ! Element with odd size
3220 ISOURCE                 LDB =1
3230 ISOURCE                 CPA Dim_size
3240 ISOURCE                 LDB =0
3250 ISOURCE                 STB Last_el             ! Last el if length < dimensioned size
3260 ISOURCE                 SAR 1
3270 ISOURCE                 ADA C
3280 ISOURCE                 STA El_end              ! Compute end of new el
3290 ISOURCE                 RET 2
3300 ISOURCE !
3310 ISOURCE ! Advance current op
3320 ISOURCE Advance_op:     LDA Op_curr
3330 ISOURCE                 ADA =Op_adv_table
3340 ISOURCE                 JMP A,I
3350 ISOURCE Op_adv_table:   RET 2                   ! Op_terminate doesn't advance
3360 ISOURCE                 JMP Adv_op_ww
3370 ISOURCE                 JMP Get_op              ! Op_wr_gap: move to next op
3380 ISOURCE                 DSZ Op_cnt              ! Op_wr_repeat
3390 ISOURCE                 RET 2                   ! Keep repeating word in Data_word
3400 ISOURCE                 JMP Get_op              ! No more repetitions
3410 ISOURCE Adv_op_ww:      DSZ Op_cnt              ! Op_wr_words
3420 ISOURCE                 JMP Get_data            ! Get next word
3430 ISOURCE !
3440 ISOURCE ! Get a new op
3450 ISOURCE Get_op:         JSM Get_data
3460 ISOURCE                 RET 1
3470 ISOURCE                 STA B
3480 ISOURCE                 AND =37777B
3490 ISOURCE                 STA Op_cnt
3500 ISOURCE                 LDA B
3510 ISOURCE                 SAR 14
3520 ISOURCE                 STA Op_curr
3530 ISOURCE                 STA Op_to_exch
3540 ISOURCE                 ADA =Op_table
3550 ISOURCE                 JMP A,I
3560 ISOURCE Op_table:       RET 2                   ! Op_terminate
3570 ISOURCE                 JMP Get_data            ! Op_wr_words: get 1st word
3580 ISOURCE                 JMP Get_op_wg           ! Op_wr_gap
3590 ISOURCE                 LDA =Op_wr_words        ! Op_wr_repeat
3600 ISOURCE                 STA Op_to_exch          ! Fake Op_wr_words for ISR
3610 ISOURCE                 JMP Get_data            ! Get word to be repeated
3620 ISOURCE Get_op_wg:      LDA Op_cnt
3630 ISOURCE                 STA Data_word           ! Set gap size
3640 ISOURCE                 RET 2
3650 ISOURCE !
3660 ISOURCE Val_options:    BSS 1
3670 ISOURCE Val_threshold:  BSS 1
3680 ISOURCE Data_info:      BSS 39
3690 ISOURCE Dim_size:       EQU Data_info+2
3700 ISOURCE El_count:       EQU Data_info+3
3710 ISOURCE First_block:    EQU Data_info+18
3720 ISOURCE Curr_ptr_block: BSS 1
3730 ISOURCE El_end:         BSS 1
3740 ISOURCE Last_el:        BSS 1
3750 ISOURCE Data_word:      BSS 1
3760 ISOURCE Op_curr:        BSS 1
3770 ISOURCE Op_to_exch:     BSS 1
3780 ISOURCE Op_cnt:         BSS 1
3790 ISOURCE !
3800 ISOURCE                 LIT 64
3810 ISOURCE !
3820 ISOURCE                 END Clon25
6000 IASSEMBLE Clon25;LIST,XREF
6010 ISTORE Clon25;"CLON25"
6020 END
