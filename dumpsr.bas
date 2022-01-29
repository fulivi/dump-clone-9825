10 ICOM 1000
100 ISOURCE                 NAM Dump25
110 ISOURCE ! **** DUMP9825 ****
120 ISOURCE ! Copyright (c) 2022 F.Ulivi
130 ISOURCE !
140 ISOURCE ! Licensed under the 3-Clause BSD License
150 ISOURCE !
160 ISOURCE ! Any resemblance to test ROM code is purely coincidental ;)
170 ISOURCE !
180 ISOURCE                 EXT Isr_access,Get_value,Get_info,Put_value
190 ISOURCE                 EXT Put_elem_bytes,Printer_select,Print_no_lf
200 ISOURCE !
210 ISOURCE ! Bits in option bitmap
220 ISOURCE Opt_track_b:    EQU 1
230 ISOURCE Opt_hi_thr_rd:  EQU 2
240 ISOURCE Opt_hi_thr_gap: EQU 4
250 ISOURCE Opt_no_display: EQU 8
260 ISOURCE !
270 ISOURCE ! Offset for indirect jumps @ISR level
280 ISOURCE Indirect_off:   EQU 100000B
290 ISOURCE !
300 ISOURCE ! TACO Commands
310 ISOURCE TACO_Stop:      EQU 10000B
320 ISOURCE TACO_Set_Track: EQU 14000B
330 ISOURCE TACO_Mod:       EQU 100B
340 ISOURCE TACO_track_B:   EQU TACO_Mod
350 ISOURCE TACO_Clear:     EQU 34000B
360 ISOURCE TACO_forward:   EQU 100000B
370 ISOURCE TACO_Rd_9825:   EQU 73000B+TACO_forward
380 ISOURCE TACO_Csum_9825: EQU 77000B+TACO_forward
390 ISOURCE TACO_Int_n_tach:EQU 74000B+TACO_forward
400 ISOURCE TACO_Int_gap:   EQU 00000B+TACO_forward
410 ISOURCE TACO_Int_n_22:  EQU 64000B+TACO_forward
420 ISOURCE !
430 ISOURCE Tach_skip_post: EQU -8          ! Tach ticks to skip postamble (8)
440 ISOURCE Tach_skip_gap:  EQU -16         ! Tach ticks for 1" gap searching (16)
450 ISOURCE Gap_1in_cnt:    EQU 25          ! Count of Tach_skip_gap in 1" of tape
460 ISOURCE !
470 ISOURCE ! T15 PA
480 ISOURCE T15:            EQU 15
490 ISOURCE !
500 ISOURCE R34:            EQU 34B
510 ISOURCE R35:            EQU 35B
520 ISOURCE Save_R35:       BSS 1
530 ISOURCE Isr_jump:       BSS 1
540 ISOURCE Err_code:       BSS 1
550 ISOURCE Exp_rec_no:     BSS 1           ! Expected rec. number
560 ISOURCE Rec_header:     BSS 7           ! Record header
570 ISOURCE Rec_no:         EQU Rec_header  ! Record number
580 ISOURCE Rec_asize:      EQU Rec_header+1 ! Absolute size
590 ISOURCE Rec_csize:      EQU Rec_header+2 ! Current size
600 ISOURCE Rec_rtype:      EQU Rec_header+3 ! Record type
610 ISOURCE Rec_rewrite_no: EQU Rec_header+4 ! Rewrite number
620 ISOURCE Rec_header_end: EQU *
630 ISOURCE Hdr_ptr:        BSS 1           ! Pointer to header
640 ISOURCE Exp_part_no:    BSS 1           ! Expected partition number
650 ISOURCE Part_header:    BSS 3           ! Partition header
660 ISOURCE Part_no:        EQU Part_header ! Partition number
670 ISOURCE Part_size:      EQU Part_header+1 ! Partition size
680 ISOURCE Part_rewrite_no:EQU Part_header+2 ! Rewrite number
690 ISOURCE Part_header_end:EQU *
700 ISOURCE Gap_cnt:        BSS 1
710 ISOURCE TACO_mod_rd:    BSS 1
720 ISOURCE TACO_mod_gap:   BSS 1
730 ISOURCE Good_recs:      BSS 1
740 ISOURCE !
750 ISOURCE ! ************
760 ISOURCE ! * TACO ISR *
770 ISOURCE ! ************
780 ISOURCE Dump_Isr:       LDA R35
790 ISOURCE                 STA Save_R35
800 ISOURCE                 LDA R34
810 ISOURCE                 STA R35
820 ISOURCE                 LDA Err_code
830 ISOURCE                 RZA Err_n_end   ! Abort if errors
840 ISOURCE                 JMP Isr_jump,I
850 ISOURCE Cmd_n_set_Int:  JSM Wait_Flg
860 ISOURCE                 STA R5
870 ISOURCE Set_next_Int:   STB Isr_jump
880 ISOURCE Leave_Isr:      LDA Save_R35
890 ISOURCE                 STA R35
900 ISOURCE                 RET 1
910 ISOURCE !
920 ISOURCE ! Error codes
930 ISOURCE ERR_none:       EQU 0           ! No error
940 ISOURCE ERR_evd:        EQU 1           ! EVD reached
950 ISOURCE ERR_null_rec:   EQU 2           ! Null record reached
960 ISOURCE ERR_stopped:    EQU 3           ! Stopped by user
970 ISOURCE ERR_OOM:        EQU 5           ! No space left in output string
980 ISOURCE ERR_ovf:        EQU 6           ! Exchange buffer overflow
990 ISOURCE ERR_par:        EQU 7           ! Bad parameters
1000 ISOURCE ERR_no_isr:     EQU 8           ! Couldn't acquire ISR
1010 ISOURCE ERR_state0:     EQU 10          ! Error in state 0
1020 ISOURCE !
1030 ISOURCE Err_n_end:      STA Err_code
1040 ISOURCE                 JSM Clear_TACO
1050 ISOURCE                 LDA =TACO_Stop
1060 ISOURCE                 JSM Cmd_TACO
1070 ISOURCE                 LDA Save_R35
1080 ISOURCE                 STA R35
1090 ISOURCE                 JSM End_isr_high,I
1100 ISOURCE                 RET 1
1110 ISOURCE !
1120 ISOURCE Tmp1:           BSS 1
1130 ISOURCE !
1140 ISOURCE Wait_Flg:       STA Tmp1
1150 ISOURCE                 LDA =65511
1160 ISOURCE Wait1:          SFS Wait2
1170 ISOURCE                 RIA Wait1
1180 ISOURCE Wait2:          LDA Tmp1
1190 ISOURCE                 RET 1
1200 ISOURCE !
1210 ISOURCE Clear_TACO:     LDA =TACO_Clear
1220 ISOURCE Cmd_TACO:       JSM Wait_Flg
1230 ISOURCE                 STA R5
1240 ISOURCE                 RET 1
1250 ISOURCE !
1260 ISOURCE ! Put regA into exchange buffer
1270 ISOURCE ! RET 1: overflow
1280 ISOURCE ! RET 2: OK
1290 ISOURCE Exch_buffer:    BSS 2
1300 ISOURCE Exch_cnt:       BSS 1
1310 ISOURCE !
1320 ISOURCE Put_exchange:   LDB Exch_cnt
1330 ISOURCE                 CPB =2
1340 ISOURCE                 JMP Put2        ! Buffer overflow
1350 ISOURCE                 ISZ Exch_cnt    ! 1 more word in buffer
1360 ISOURCE                 SZB Put1
1370 ISOURCE                 STA Exch_buffer+1       ! Put 2nd word
1380 ISOURCE                 RET 2
1390 ISOURCE Put1:           STA Exch_buffer ! Put 1st word
1400 ISOURCE                 RET 2
1410 ISOURCE Put2:           LDA =ERR_ovf
1420 ISOURCE                 RET 1
1430 ISOURCE !
1440 ISOURCE ! Start reading
1450 ISOURCE ! RET 1: failure
1460 ISOURCE ! RET 2: OK
1470 ISOURCE Start_rd:       LDA =State12+Indirect_off
1480 ISOURCE                 STA Isr_jump
1490 ISOURCE                 CLA
1500 ISOURCE                 STA Exch_cnt
1510 ISOURCE                 STA Exp_rec_no
1520 ISOURCE                 STA Good_recs
1530 ISOURCE                 STA Chase_rec_no
1540 ISOURCE                 STA Chase_good_recs
1550 ISOURCE                 LDA Pa
1560 ISOURCE                 AND =15
1570 ISOURCE                 ADA =256+(3*16) ! 1 attempt, synch. access
1580 ISOURCE                 STA B
1590 ISOURCE                 LDA =Dump_Isr
1600 ISOURCE                 JSM Isr_access
1610 ISOURCE                 RET 1           ! Failed
1620 ISOURCE                 JSM Clear_TACO
1630 ISOURCE                 LDA =TACO_Set_Track
1640 ISOURCE                 LDB Val_options
1650 ISOURCE                 SLB Start1
1660 ISOURCE                 IOR =TACO_track_B
1670 ISOURCE Start1:         JSM Cmd_TACO    ! Set track A/B
1680 ISOURCE                 CLA
1690 ISOURCE                 SBR 1
1700 ISOURCE                 SLB Start2
1710 ISOURCE                 LDA =TACO_Mod
1720 ISOURCE Start2:         STA TACO_mod_rd
1730 ISOURCE                 CLA
1740 ISOURCE                 SBR 1
1750 ISOURCE                 SLB Start3
1760 ISOURCE                 LDA =TACO_Mod
1770 ISOURCE Start3:         STA TACO_mod_gap
1780 ISOURCE                 LDA =Gap_1in_cnt
1790 ISOURCE                 STA Gap_cnt             ! Start 1" gap search
1800 ISOURCE                 LDA =Tach_skip_gap
1810 ISOURCE                 JSM Wait_Flg
1820 ISOURCE                 STA R6
1830 ISOURCE                 LDA =TACO_Int_n_22
1840 ISOURCE                 IOR TACO_mod_gap
1850 ISOURCE                 JSM Cmd_TACO    ! Off we go!
1860 ISOURCE                 RET 2
1870 ISOURCE !
1880 ISOURCE ! State 3: Read 1st word of rec header
1890 ISOURCE State3:         LDA R5          ! Check for hole
1900 ISOURCE                 SLA State3_2
1910 ISOURCE                 LDA =(30+0)*256
1920 ISOURCE                 JSM Put_exchange
1930 ISOURCE                 JMP Err_n_end
1940 ISOURCE                 JSM Clear_TACO  ! Hole reached, restart gap search
1950 ISOURCE                 JMP State_to_12
1960 ISOURCE State3_2:       SSS State3_1
1970 ISOURCE EVD_reached:    LDA =ERR_evd
1980 ISOURCE                 JMP Err_n_end   ! STS=0, EVD reached
1990 ISOURCE State3_1:       LDA R4
2000 ISOURCE                 JSM Put_exchange
2010 ISOURCE                 JMP Err_n_end
2020 ISOURCE                 STA Rec_header
2030 ISOURCE                 LDA =Rec_header+1
2040 ISOURCE                 STA Hdr_ptr
2050 ISOURCE                 LDB =State4+Indirect_off
2060 ISOURCE                 JMP Set_next_Int
2070 ISOURCE !
2080 ISOURCE ! State 4: Read rec header
2090 ISOURCE State4:         LDA R4
2100 ISOURCE                 STA Hdr_ptr,I
2110 ISOURCE                 JSM Put_exchange
2120 ISOURCE                 JMP Err_n_end
2130 ISOURCE                 ISZ Hdr_ptr
2140 ISOURCE                 LDA Hdr_ptr
2150 ISOURCE                 CPA =Rec_header_end
2160 ISOURCE                 JMP State4_to_5
2170 ISOURCE                 JMP Leave_Isr
2180 ISOURCE State4_to_5:    LDA =TACO_Csum_9825
2190 ISOURCE                 IOR TACO_mod_rd
2200 ISOURCE                 LDB =State5+Indirect_off
2210 ISOURCE                 JMP Cmd_n_set_Int
2220 ISOURCE !
2230 ISOURCE ! State 5: Read rec header csum
2240 ISOURCE State5:         LDA R4
2250 ISOURCE                 JSM Put_exchange
2260 ISOURCE                 JMP Err_n_end
2270 ISOURCE                 CPA R7
2280 ISOURCE                 JMP State5_1
2290 ISOURCE                 JMP Next_rec            ! Header csum not matching, skip record
2300 ISOURCE ! TODO: Checks on rec header
2310 ISOURCE State5_1:       LDA Rec_asize
2320 ISOURCE                 IOR Rec_csize
2330 ISOURCE                 IOR Rec_rtype
2340 ISOURCE                 RZA State5_2
2350 ISOURCE                 ISZ Good_recs
2360 ISOURCE                 LDA =ERR_null_rec       ! Track terminated by null rec
2370 ISOURCE                 JMP Err_n_end
2380 ISOURCE State5_2:       LDA Rec_no
2390 ISOURCE                 CPA Exp_rec_no
2400 ISOURCE                 JMP State5_3
2410 ISOURCE                 JMP Next_rec
2420 ISOURCE State5_3:       LDA Rec_csize
2430 ISOURCE                 SZA Good_rec_ends       ! 0-sized record
2440 ISOURCE                 CLA
2450 ISOURCE                 STA Exp_part_no
2460 ISOURCE State_to_6:     LDA =Tach_skip_post
2470 ISOURCE                 JSM Wait_Flg
2480 ISOURCE                 STA R6
2490 ISOURCE                 LDA =TACO_Int_n_tach
2500 ISOURCE                 LDB =State6+Indirect_off
2510 ISOURCE                 JMP Cmd_n_set_Int
2520 ISOURCE Good_rec_ends:  ISZ Good_recs
2530 ISOURCE Next_rec:       ISZ Exp_rec_no
2540 ISOURCE State_to_12:    LDA =Gap_1in_cnt
2550 ISOURCE                 STA Gap_cnt             ! Start 1" gap search
2560 ISOURCE                 LDA =TACO_Int_gap
2570 ISOURCE                 IOR TACO_mod_gap
2580 ISOURCE                 LDB =State12+Indirect_off
2590 ISOURCE                 JMP Cmd_n_set_Int
2600 ISOURCE !
2610 ISOURCE ! State 6: Skip record header postamble
2620 ISOURCE State6:         LDA =Part_header
2630 ISOURCE                 STA Hdr_ptr
2640 ISOURCE State6_1:       LDA R7          ! Clear csum
2650 ISOURCE                 LDA =TACO_Rd_9825       ! Start part. reading
2660 ISOURCE                 IOR TACO_Mod_rd
2670 ISOURCE                 LDB =State7+Indirect_off
2680 ISOURCE                 JMP Cmd_n_set_Int
2690 ISOURCE !
2700 ISOURCE ! State 7: Read partition header
2710 ISOURCE State7:         LDA R4
2720 ISOURCE                 LDB R5
2730 ISOURCE                 RBR 4
2740 ISOURCE                 SLB State7_2
2750 ISOURCE                 JSM Clear_TACO  ! Got a gap, clear & restart
2760 ISOURCE                 JMP State6_1
2770 ISOURCE State7_2:       SSS State7_1
2780 ISOURCE                 JMP EVD_reached
2790 ISOURCE State7_1:       STA Hdr_ptr,I
2800 ISOURCE                 JSM Put_exchange
2810 ISOURCE                 JMP Err_n_end
2820 ISOURCE                 ISZ Hdr_ptr
2830 ISOURCE                 LDA Hdr_ptr
2840 ISOURCE                 CPA =Part_header_end
2850 ISOURCE                 JMP State7_to_8
2860 ISOURCE                 JMP Leave_Isr
2870 ISOURCE State7_to_8:    LDA =TACO_Csum_9825
2880 ISOURCE                 IOR TACO_Mod_rd
2890 ISOURCE                 LDB =State8+Indirect_off
2900 ISOURCE                 JMP Cmd_n_set_Int
2910 ISOURCE !
2920 ISOURCE ! State8: Read part header csum
2930 ISOURCE State8:         LDA R4
2940 ISOURCE                 JSM Put_exchange
2950 ISOURCE                 JMP Err_n_end
2960 ISOURCE                 CPA R7
2970 ISOURCE                 JMP State8_1
2980 ISOURCE                 JMP Next_rec
2990 ISOURCE State8_1:       LDA Part_no
3000 ISOURCE                 CPA Exp_part_no ! Check for matching part no
3010 ISOURCE                 JMP State8_2
3020 ISOURCE State8_3:       JMP Next_rec
3030 ISOURCE State8_2:       LDA Part_rewrite_no
3040 ISOURCE                 CPA Rec_rewrite_no
3050 ISOURCE                 JMP State8_4    ! Check for rewrite #
3060 ISOURCE                 JMP Next_rec
3070 ISOURCE State8_4:       LDA Part_size
3080 ISOURCE                 SZA State8_3    ! Size = 0 is invalid
3090 ISOURCE                 TCA
3100 ISOURCE                 ADA Rec_csize
3110 ISOURCE                 SAM State8_3    ! Size should be <= residual rec csize
3120 ISOURCE                 STA Rec_csize   ! Update count of words to be read
3130 ISOURCE                 LDB =State9+Indirect_off
3140 ISOURCE                 JMP Set_next_Int
3150 ISOURCE !
3160 ISOURCE ! State 9: Read and discard preamble word
3170 ISOURCE State9:         LDA R4          ! We trust it to be 1
3180 ISOURCE                 LDA R7          ! Clear csum
3190 ISOURCE                 LDA =TACO_Rd_9825       ! Start reading data from partition
3200 ISOURCE                 IOR TACO_Mod_rd
3210 ISOURCE                 LDB =State10+Indirect_off
3220 ISOURCE                 JMP Cmd_n_set_Int
3230 ISOURCE !
3240 ISOURCE ! State 10: Read partition data
3250 ISOURCE State10:        SSS State10_1
3260 ISOURCE                 LDA =ERR_state0+10
3270 ISOURCE                 JMP Err_n_end
3280 ISOURCE State10_1:      LDA R4
3290 ISOURCE                 JSM Put_exchange
3300 ISOURCE                 JMP Err_n_end
3310 ISOURCE                 DSZ Part_size
3320 ISOURCE                 JMP Leave_Isr
3330 ISOURCE                 LDA =TACO_Csum_9825
3340 ISOURCE                 IOR TACO_Mod_rd
3350 ISOURCE                 LDB =State11+Indirect_off
3360 ISOURCE                 JMP Cmd_n_set_Int
3370 ISOURCE !
3380 ISOURCE ! State 11: Read part data csum
3390 ISOURCE State11:        LDA R4
3400 ISOURCE                 JSM Put_exchange
3410 ISOURCE                 JMP Err_n_end
3420 ISOURCE                 CPA R7
3430 ISOURCE                 JMP State11_1
3440 ISOURCE                 JMP Next_rec
3450 ISOURCE State11_1:      LDA Rec_csize
3460 ISOURCE                 SZA State11_2
3470 ISOURCE                 ISZ Exp_part_no ! More partitions to read
3480 ISOURCE                 JMP State_to_6
3490 ISOURCE State11_2:      JMP Good_rec_ends       ! No more partitions, move to next rec
3500 ISOURCE !
3510 ISOURCE ! State 12: Search for next 1" gap (IRG)
3520 ISOURCE State12:        LDA R5          ! Check for hole
3530 ISOURCE                 SLA State12_5
3540 ISOURCE                 LDA =(120+0)*256
3550 ISOURCE                 JSM Put_exchange
3560 ISOURCE                 JMP Err_n_end
3570 ISOURCE                 JSM Clear_TACO  ! Hole reached, restart gap search
3580 ISOURCE                 JMP State_to_12
3590 ISOURCE State12_5:      SSS State12_1
3600 ISOURCE                 LDA =ERR_state0+12
3610 ISOURCE                 JMP Err_n_end
3620 ISOURCE State12_1:      LDA R5
3630 ISOURCE                 AND =16         ! Get GAP bit
3640 ISOURCE                 SZA State12_2
3650 ISOURCE                 DSZ Gap_cnt
3660 ISOURCE                 JMP State12_3   ! More skipping to do
3670 ISOURCE ! Done: 1" gap found, read next rec
3680 ISOURCE                 LDA R7          ! Clear csum
3690 ISOURCE                 JSM Clear_TACO
3700 ISOURCE                 LDA Val_threshold
3710 ISOURCE                 JSM Wait_Flg
3720 ISOURCE                 STA R7          ! Set threshold
3730 ISOURCE                 LDA =(120+3)*256
3740 ISOURCE                 JSM Put_exchange
3750 ISOURCE                 JMP Err_n_end
3760 ISOURCE                 LDA =TACO_Rd_9825
3770 ISOURCE                 IOR TACO_Mod_rd
3780 ISOURCE                 LDB =State3+Indirect_off
3790 ISOURCE                 JMP Cmd_n_set_Int       ! Start rd
3800 ISOURCE State12_2:      LDA =(120+1)*256
3810 ISOURCE                 ADA Gap_cnt
3820 ISOURCE                 JSM Put_exchange
3830 ISOURCE                 JMP Err_n_end
3840 ISOURCE                 JMP State_to_12 ! Restart search if GAP=0
3850 ISOURCE ! Skip forward 16 ticks at time when GAP=1 until 1" of gap is reached
3860 ISOURCE State12_3:      LDA =Tach_skip_gap
3870 ISOURCE                 JSM Wait_Flg
3880 ISOURCE                 STA R6
3890 ISOURCE                 LDA =TACO_Int_n_tach
3900 ISOURCE                 IOR TACO_mod_gap
3910 ISOURCE                 LDB =State12+Indirect_off
3920 ISOURCE                 JMP Cmd_n_set_Int
3930 ISOURCE !
3940 ISOURCE ! *******************************
3950 ISOURCE ! * ICALL Entry point: Dump9825 *
3960 ISOURCE ! *******************************
3970 ISOURCE !
3980 ISOURCE                 SUB
3990 ISOURCE Par_options:    INT             ! Option bitmap
4000 ISOURCE Par_threshold:  INT             ! Threshold
4010 ISOURCE Par_error:      INT             ! Out: error code
4020 ISOURCE Par_last_rec:   INT             ! Out: Last record number
4030 ISOURCE Par_good_rec:   INT             ! Out: Good records
4040 ISOURCE Par_output:     STR(*)          ! Out: dumped data
4050 ISOURCE !
4060 ISOURCE Dump9825:       LDA =Val_options
4070 ISOURCE                 LDB =Par_options
4080 ISOURCE                 JSM Get_value
4090 ISOURCE                 LDA =Val_threshold
4100 ISOURCE                 LDB =Par_threshold
4110 ISOURCE                 JSM Get_value
4120 ISOURCE                 LDA =Output_info
4130 ISOURCE                 LDB =Par_output
4140 ISOURCE                 JSM Get_info
4150 ISOURCE                 LDA Output_info
4160 ISOURCE                 CPA =12         ! String array
4170 ISOURCE                 JMP Dump1
4180 ISOURCE                 JMP Bad_par
4190 ISOURCE Dump1:          LDA Output_info+1
4200 ISOURCE                 CPA =1
4210 ISOURCE                 JMP Dump2
4220 ISOURCE                 JMP Bad_par
4230 ISOURCE Dump2:          LDA Dim_size
4240 ISOURCE                 SLA Dump9       ! Dimensioned size must be even
4250 ISOURCE                 JMP Bad_par
4260 ISOURCE Dump9:          CLA
4270 ISOURCE                 STA El_offset
4280 ISOURCE                 STA Output_idx
4290 ISOURCE                 STA Err_code
4300 ISOURCE                 LDA Val_options
4310 ISOURCE                 IOR =(250+0)*256
4320 ISOURCE                 JSM Put_output  ! Store options as trace entry
4330 ISOURCE                 LDA =17         ! Select DISP area for output
4340 ISOURCE                 LDB =80
4350 ISOURCE                 JSM Printer_select
4360 ISOURCE                 STA Prev_select
4370 ISOURCE                 STB Prev_width
4380 ISOURCE                 LDA Val_options
4390 ISOURCE                 AND =Opt_no_display
4400 ISOURCE                 RZA Dump11
4410 ISOURCE                 LDA ="00"
4420 ISOURCE                 STA Msg_good
4430 ISOURCE                 STA Msg_total   ! Clear good/total display
4440 ISOURCE                 JSM Display
4450 ISOURCE Dump11:         LDA =T15
4460 ISOURCE                 STA Pa
4470 ISOURCE                 JSM Start_rd
4480 ISOURCE                 JMP No_isr
4490 ISOURCE ! Main loop
4500 ISOURCE Dump3:          DIR
4510 ISOURCE                 LDA Exch_cnt    ! A could be 0,1 or 2
4520 ISOURCE                 SZA Dump4       ! A=0: no data in buffer
4530 ISOURCE                 DSZ Exch_cnt    ! 1 less word in buffer
4540 ISOURCE                 JMP Dump5       ! Skip if A=2
4550 ISOURCE                 LDA Exch_buffer ! A=1: get 1st word
4560 ISOURCE                 EIR
4570 ISOURCE                 JSM Put_output
4580 ISOURCE                 JMP Dump3
4590 ISOURCE Dump5:          LDA Exch_buffer ! A=2: get 1st word
4600 ISOURCE                 LDB Exch_buffer+1
4610 ISOURCE                 STB Exch_buffer ! Shift down 2nd word
4620 ISOURCE                 EIR
4630 ISOURCE                 JSM Put_output
4640 ISOURCE                 JMP Dump3
4650 ISOURCE Dump4:          LDA Err_code
4660 ISOURCE                 EIR
4670 ISOURCE                 RZA Exit_err
4680 ISOURCE                 LDA Val_options
4690 ISOURCE                 AND =Opt_no_display
4700 ISOURCE                 RZA Dump3
4710 ISOURCE                 LDA Exp_rec_no
4720 ISOURCE                 CPA Chase_rec_no
4730 ISOURCE                 JMP Dump3
4740 ISOURCE                 ISZ Chase_rec_no
4750 ISOURCE                 LDA Msg_total
4760 ISOURCE                 JSM Twodigit_inc
4770 ISOURCE                 STA Msg_total
4780 ISOURCE                 LDA Good_recs
4790 ISOURCE                 CPA Chase_good_recs
4800 ISOURCE                 JMP Dump10
4810 ISOURCE                 ISZ Chase_good_recs
4820 ISOURCE                 LDA Msg_good
4830 ISOURCE                 JSM Twodigit_inc
4840 ISOURCE                 STA Msg_good
4850 ISOURCE Dump10:         JSM Display
4860 ISOURCE                 JMP Dump3
4870 ISOURCE No_isr:         LDA =ERR_no_isr
4880 ISOURCE                 JMP Exit_err
4890 ISOURCE Bad_par:        LDA =ERR_par
4900 ISOURCE Exit_err:       STA Err_code
4910 ISOURCE                 IOR =(250+1)*256
4920 ISOURCE                 JSM Put_output  ! Store error code
4930 ISOURCE                 LDA =Err_code
4940 ISOURCE                 LDB =Par_error
4950 ISOURCE                 JSM Put_value
4960 ISOURCE                 LDA =Exp_rec_no
4970 ISOURCE                 LDB =Par_last_rec
4980 ISOURCE                 JSM Put_value
4990 ISOURCE                 LDA =Good_recs
5000 ISOURCE                 LDB =Par_good_rec
5010 ISOURCE                 JSM Put_value
5020 ISOURCE ! Fix size of string array elements
5030 ISOURCE                 LDA Output_idx
5040 ISOURCE                 STA Output_word
5050 ISOURCE                 CLA
5060 ISOURCE                 STA Output_byte
5070 ISOURCE                 LDA =Output_byte
5080 ISOURCE                 LDB =Output_info
5090 ISOURCE                 JSM Put_elem_bytes
5100 ISOURCE Fix_array:      LDA El_offset
5110 ISOURCE                 SZA Leave
5120 ISOURCE                 DSZ El_offset
5130 ISOURCE                 NOP
5140 ISOURCE                 LDA Dim_size
5150 ISOURCE                 STA Output_word
5160 ISOURCE                 CLA
5170 ISOURCE                 STA Output_byte
5180 ISOURCE                 LDA =Output_byte
5190 ISOURCE                 LDB =Output_info
5200 ISOURCE                 JSM Put_elem_bytes
5210 ISOURCE                 JMP Fix_array
5220 ISOURCE Leave:          LDA Prev_select
5230 ISOURCE                 LDB Prev_width
5240 ISOURCE                 JSM Printer_select
5250 ISOURCE                 RET 1
5260 ISOURCE !
5270 ISOURCE ! Store A in output array
5280 ISOURCE Put_output:     STA Output_word
5290 ISOURCE ! Check for overflow
5300 ISOURCE                 LDA Output_idx
5310 ISOURCE                 CPA Dim_size
5320 ISOURCE                 JMP Dump6               ! Array element exhausted
5330 ISOURCE Dump8:          ADA =2
5340 ISOURCE                 STA Output_byte
5350 ISOURCE                 STA Output_idx
5360 ISOURCE                 LDA =Output_byte
5370 ISOURCE                 LDB =Output_info
5380 ISOURCE                 JMP Put_elem_bytes      ! Write word into string array
5390 ISOURCE Dump6:          LDA El_offset
5400 ISOURCE                 ADA =1
5410 ISOURCE                 CPA El_count
5420 ISOURCE                 JMP Dump7               ! No space left in array
5430 ISOURCE                 STA El_offset
5440 ISOURCE                 CLA
5450 ISOURCE                 JMP Dump8
5460 ISOURCE Dump7:          LDA =ERR_OOM
5470 ISOURCE                 STA Err_code
5480 ISOURCE                 RET 1
5490 ISOURCE !
5500 ISOURCE Twodigit_inc:   ADA =1                  ! Increment LS digit
5510 ISOURCE                 STA B
5520 ISOURCE                 AND =255
5530 ISOURCE                 CPA ='9+1               ! Roll over from 9 to 0?
5540 ISOURCE                 JMP Twodigit_1
5550 ISOURCE                 LDA B
5560 ISOURCE                 RET 1
5570 ISOURCE Twodigit_1:     LDA B                   ! Roll back LS digit from 9 to 0 and
5580 ISOURCE                 ADA =246                ! increment MS digit
5590 ISOURCE                 STA B
5600 ISOURCE                 AND =177400B
5610 ISOURCE                 CPA =('9+1)*256         ! MS digit went past 9?
5620 ISOURCE                 JMP Twodigit_2
5630 ISOURCE                 LDA B                   ! No, leave it alone
5640 ISOURCE                 RET 1
5650 ISOURCE Twodigit_2:     LDA B                   ! Yes, bring it back to 0
5660 ISOURCE                 ADA =173000B
5670 ISOURCE                 RET 1
5680 ISOURCE !
5690 ISOURCE Display:        LDA =Message
5700 ISOURCE                 JSM Print_no_lf
5710 ISOURCE                 NOP
5720 ISOURCE                 JMP Display1            ! Overflow or STOP
5730 ISOURCE                 RET 1                   ! Normal exit
5740 ISOURCE Display1:       LDA =ERR_stopped
5750 ISOURCE                 STA Err_code
5760 ISOURCE                 RET 1
5770 ISOURCE !
5780 ISOURCE Val_options:    BSS 1
5790 ISOURCE Val_threshold:  BSS 1
5800 ISOURCE Output_info:    BSS 39
5810 ISOURCE Dim_size:       EQU Output_info+2
5820 ISOURCE El_count:       EQU Output_info+3
5830 ISOURCE El_offset:      EQU Output_info+16
5840 ISOURCE Output_idx:     BSS 1
5850 ISOURCE Output_byte:    BSS 1
5860 ISOURCE Output_size:    DAT 2
5870 ISOURCE Output_word:    BSS 1
5880 ISOURCE Message:        DAT 5
5890 ISOURCE Msg_good:       BSS 1
5900 ISOURCE Msg_total:      BSS 1
5910 ISOURCE                 DAT 13*256
5920 ISOURCE Prev_select:    BSS 1
5930 ISOURCE Prev_width:     BSS 1
5940 ISOURCE Chase_rec_no:   BSS 1
5950 ISOURCE Chase_good_recs:BSS 1
5960 ISOURCE !
5970 ISOURCE                 LIT 64
5980 ISOURCE !
5990 ISOURCE                 END Dump25
6000 IASSEMBLE Dump25;LIST,XREF
6010 ISTORE Dump25;"DUMP25"
6020 END
