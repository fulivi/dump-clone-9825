                NAM Dump25
! **** DUMP9825 ****
! Copyright (c) 2022 F.Ulivi
!
! Licensed under the 3-Clause BSD License
!
! Any resemblance to test ROM code is purely coincidental ;)
!
                EXT Isr_access,Get_value,Get_info,Put_value
                EXT Put_elem_bytes,Printer_select,Print_no_lf
!
! Bits in option bitmap
Opt_track_b:    EQU 1
Opt_hi_thr_rd:  EQU 2
Opt_hi_thr_gap: EQU 4
Opt_no_display: EQU 8
!
! Offset for indirect jumps @ISR level
Indirect_off:   EQU 100000B
!
! TACO Commands
TACO_Stop:      EQU 10000B
TACO_Set_Track: EQU 14000B
TACO_Mod:       EQU 100B
TACO_track_B:   EQU TACO_Mod
TACO_Clear:     EQU 34000B
TACO_forward:   EQU 100000B
TACO_Rd_9825:   EQU 73000B+TACO_forward
TACO_Csum_9825: EQU 77000B+TACO_forward
TACO_Int_n_tach:EQU 74000B+TACO_forward
TACO_Int_gap:   EQU 00000B+TACO_forward
TACO_Int_n_22:  EQU 64000B+TACO_forward
!
Tach_skip_post: EQU -8          ! Tach ticks to skip postamble (8)
Tach_skip_gap:  EQU -16         ! Tach ticks for 1" gap searching (16)
Gap_1in_cnt:    EQU 25          ! Count of Tach_skip_gap in 1" of tape
!
! T15 PA
T15:            EQU 15
!
R34:            EQU 34B
R35:            EQU 35B
Save_R35:       BSS 1
Isr_jump:       BSS 1
Err_code:       BSS 1
Exp_rec_no:     BSS 1           ! Expected rec. number
Rec_header:     BSS 7           ! Record header
Rec_no:         EQU Rec_header  ! Record number
Rec_asize:      EQU Rec_header+1 ! Absolute size
Rec_csize:      EQU Rec_header+2 ! Current size
Rec_rtype:      EQU Rec_header+3 ! Record type
Rec_rewrite_no: EQU Rec_header+4 ! Rewrite number
Rec_header_end: EQU *
Hdr_ptr:        BSS 1           ! Pointer to header
Exp_part_no:    BSS 1           ! Expected partition number
Part_header:    BSS 3           ! Partition header
Part_no:        EQU Part_header ! Partition number
Part_size:      EQU Part_header+1 ! Partition size
Part_rewrite_no:EQU Part_header+2 ! Rewrite number
Part_header_end:EQU *
Gap_cnt:        BSS 1
TACO_mod_rd:    BSS 1
TACO_mod_gap:   BSS 1
Good_recs:      BSS 1
!
! ************
! * TACO ISR *
! ************
Dump_Isr:       LDA R35
                STA Save_R35
                LDA R34
                STA R35
                LDA Err_code
                RZA Err_n_end   ! Abort if errors
                JMP Isr_jump,I
Cmd_n_set_Int:  JSM Wait_Flg
                STA R5
Set_next_Int:   STB Isr_jump
Leave_Isr:      LDA Save_R35
                STA R35
                RET 1
!
! Error codes
ERR_none:       EQU 0           ! No error
ERR_evd:        EQU 1           ! EVD reached
ERR_null_rec:   EQU 2           ! Null record reached
ERR_stopped:    EQU 3           ! Stopped by user
ERR_OOM:        EQU 5           ! No space left in output string
ERR_ovf:        EQU 6           ! Exchange buffer overflow
ERR_par:        EQU 7           ! Bad parameters
ERR_no_isr:     EQU 8           ! Couldn't acquire ISR
ERR_state0:     EQU 10          ! Error in state 0
!
Err_n_end:      STA Err_code
                JSM Clear_TACO
                LDA =TACO_Stop
                JSM Cmd_TACO
                LDA Save_R35
                STA R35
                JSM End_isr_high,I
                RET 1
!
Tmp1:           BSS 1
!
Wait_Flg:       STA Tmp1
                LDA =65511
Wait1:          SFS Wait2
                RIA Wait1
Wait2:          LDA Tmp1
                RET 1
!
Clear_TACO:     LDA =TACO_Clear
Cmd_TACO:       JSM Wait_Flg
                STA R5
                RET 1
!
! Put regA into exchange buffer
! RET 1: overflow
! RET 2: OK
Exch_buffer:    BSS 2
Exch_cnt:       BSS 1
!
Put_exchange:   LDB Exch_cnt
                CPB =2
                JMP Put2        ! Buffer overflow
                ISZ Exch_cnt    ! 1 more word in buffer
                SZB Put1
                STA Exch_buffer+1       ! Put 2nd word
                RET 2
Put1:           STA Exch_buffer ! Put 1st word
                RET 2
Put2:           LDA =ERR_ovf
                RET 1
!
! Start reading
! RET 1: failure
! RET 2: OK
Start_rd:       LDA =State12+Indirect_off
                STA Isr_jump
                CLA
                STA Exch_cnt
                STA Exp_rec_no
                STA Good_recs
                STA Chase_rec_no
                STA Chase_good_recs
                LDA Pa
                AND =15
                ADA =256+(3*16) ! 1 attempt, synch. access
                STA B
                LDA =Dump_Isr
                JSM Isr_access
                RET 1           ! Failed
                JSM Clear_TACO
                LDA =TACO_Set_Track
                LDB Val_options
                SLB Start1
                IOR =TACO_track_B
Start1:         JSM Cmd_TACO    ! Set track A/B
                CLA
                SBR 1
                SLB Start2
                LDA =TACO_Mod
Start2:         STA TACO_mod_rd
                CLA
                SBR 1
                SLB Start3
                LDA =TACO_Mod
Start3:         STA TACO_mod_gap
                LDA =Gap_1in_cnt
                STA Gap_cnt             ! Start 1" gap search
                LDA =Tach_skip_gap
                JSM Wait_Flg
                STA R6
                LDA =TACO_Int_n_22
                IOR TACO_mod_gap
                JSM Cmd_TACO    ! Off we go!
                RET 2
!
! State 3: Read 1st word of rec header
State3:         LDA R5          ! Check for hole
                SLA State3_2
                LDA =(30+0)*256
                JSM Put_exchange
                JMP Err_n_end
                JSM Clear_TACO  ! Hole reached, restart gap search
                JMP State_to_12
State3_2:       SSS State3_1
EVD_reached:    LDA =ERR_evd
                JMP Err_n_end   ! STS=0, EVD reached
State3_1:       LDA R4
                JSM Put_exchange
                JMP Err_n_end
                STA Rec_header
                LDA =Rec_header+1
                STA Hdr_ptr
                LDB =State4+Indirect_off
                JMP Set_next_Int
!
! State 4: Read rec header
State4:         LDA R4
                STA Hdr_ptr,I
                JSM Put_exchange
                JMP Err_n_end
                ISZ Hdr_ptr
                LDA Hdr_ptr
                CPA =Rec_header_end
                JMP State4_to_5
                JMP Leave_Isr
State4_to_5:    LDA =TACO_Csum_9825
                IOR TACO_mod_rd
                LDB =State5+Indirect_off
                JMP Cmd_n_set_Int
!
! State 5: Read rec header csum
State5:         LDA R4
                JSM Put_exchange
                JMP Err_n_end
                CPA R7
                JMP State5_1
                JMP Next_rec            ! Header csum not matching, skip record
! TODO: Checks on rec header
State5_1:       LDA Rec_asize
                IOR Rec_csize
                IOR Rec_rtype
                RZA State5_2
                ISZ Good_recs
                LDA =ERR_null_rec       ! Track terminated by null rec
                JMP Err_n_end
State5_2:       LDA Rec_no
                CPA Exp_rec_no
                JMP State5_3
                JMP Next_rec
State5_3:       LDA Rec_csize
                SZA Good_rec_ends       ! 0-sized record
                CLA
                STA Exp_part_no
State_to_6:     LDA =Tach_skip_post
                JSM Wait_Flg
                STA R6
                LDA =TACO_Int_n_tach
                LDB =State6+Indirect_off
                JMP Cmd_n_set_Int
Good_rec_ends:  ISZ Good_recs
Next_rec:       ISZ Exp_rec_no
State_to_12:    LDA =Gap_1in_cnt
                STA Gap_cnt             ! Start 1" gap search
                LDA =TACO_Int_gap
                IOR TACO_mod_gap
                LDB =State12+Indirect_off
                JMP Cmd_n_set_Int
!
! State 6: Skip record header postamble
State6:         LDA =Part_header
                STA Hdr_ptr
State6_1:       LDA R7          ! Clear csum
                LDA =TACO_Rd_9825       ! Start part. reading
                IOR TACO_Mod_rd
                LDB =State7+Indirect_off
                JMP Cmd_n_set_Int
!
! State 7: Read partition header
State7:         LDA R4
                LDB R5
                RBR 4
                SLB State7_2
                JSM Clear_TACO  ! Got a gap, clear & restart
                JMP State6_1
State7_2:       SSS State7_1
                JMP EVD_reached
State7_1:       STA Hdr_ptr,I
                JSM Put_exchange
                JMP Err_n_end
                ISZ Hdr_ptr
                LDA Hdr_ptr
                CPA =Part_header_end
                JMP State7_to_8
                JMP Leave_Isr
State7_to_8:    LDA =TACO_Csum_9825
                IOR TACO_Mod_rd
                LDB =State8+Indirect_off
                JMP Cmd_n_set_Int
!
! State8: Read part header csum
State8:         LDA R4
                JSM Put_exchange
                JMP Err_n_end
                CPA R7
                JMP State8_1
                JMP Next_rec
State8_1:       LDA Part_no
                CPA Exp_part_no ! Check for matching part no
                JMP State8_2
State8_3:       JMP Next_rec
State8_2:       LDA Part_rewrite_no
                CPA Rec_rewrite_no
                JMP State8_4    ! Check for rewrite #
                JMP Next_rec
State8_4:       LDA Part_size
                SZA State8_3    ! Size = 0 is invalid
                TCA
                ADA Rec_csize
                SAM State8_3    ! Size should be <= residual rec csize
                STA Rec_csize   ! Update count of words to be read
                LDB =State9+Indirect_off
                JMP Set_next_Int
!
! State 9: Read and discard preamble word
State9:         LDA R4          ! We trust it to be 1
                LDA R7          ! Clear csum
                LDA =TACO_Rd_9825       ! Start reading data from partition
                IOR TACO_Mod_rd
                LDB =State10+Indirect_off
                JMP Cmd_n_set_Int
!
! State 10: Read partition data
State10:        SSS State10_1
                LDA =ERR_state0+10
                JMP Err_n_end
State10_1:      LDA R4
                JSM Put_exchange
                JMP Err_n_end
                DSZ Part_size
                JMP Leave_Isr
                LDA =TACO_Csum_9825
                IOR TACO_Mod_rd
                LDB =State11+Indirect_off
                JMP Cmd_n_set_Int
!
! State 11: Read part data csum
State11:        LDA R4
                JSM Put_exchange
                JMP Err_n_end
                CPA R7
                JMP State11_1
                JMP Next_rec
State11_1:      LDA Rec_csize
                SZA State11_2
                ISZ Exp_part_no ! More partitions to read
                JMP State_to_6
State11_2:      JMP Good_rec_ends       ! No more partitions, move to next rec
!
! State 12: Search for next 1" gap (IRG)
State12:        LDA R5          ! Check for hole
                SLA State12_5
                LDA =(120+0)*256
                JSM Put_exchange
                JMP Err_n_end
                JSM Clear_TACO  ! Hole reached, restart gap search
                JMP State_to_12
State12_5:      SSS State12_1
                LDA =ERR_state0+12
                JMP Err_n_end
State12_1:      LDA R5
                AND =16         ! Get GAP bit
                SZA State12_2
                DSZ Gap_cnt
                JMP State12_3   ! More skipping to do
! Done: 1" gap found, read next rec
                LDA R7          ! Clear csum
                JSM Clear_TACO
                LDA Val_threshold
                JSM Wait_Flg
                STA R7          ! Set threshold
                LDA =(120+3)*256
                JSM Put_exchange
                JMP Err_n_end
                LDA =TACO_Rd_9825
                IOR TACO_Mod_rd
                LDB =State3+Indirect_off
                JMP Cmd_n_set_Int       ! Start rd
State12_2:      LDA =(120+1)*256
                ADA Gap_cnt
                JSM Put_exchange
                JMP Err_n_end
                JMP State_to_12 ! Restart search if GAP=0
! Skip forward 16 ticks at time when GAP=1 until 1" of gap is reached
State12_3:      LDA =Tach_skip_gap
                JSM Wait_Flg
                STA R6
                LDA =TACO_Int_n_tach
                IOR TACO_mod_gap
                LDB =State12+Indirect_off
                JMP Cmd_n_set_Int
!
! *******************************
! * ICALL Entry point: Dump9825 *
! *******************************
!
                SUB
Par_options:    INT             ! Option bitmap
Par_threshold:  INT             ! Threshold
Par_error:      INT             ! Out: error code
Par_last_rec:   INT             ! Out: Last record number
Par_good_rec:   INT             ! Out: Good records
Par_output:     STR(*)          ! Out: dumped data
!
Dump9825:       LDA =Val_options
                LDB =Par_options
                JSM Get_value
                LDA =Val_threshold
                LDB =Par_threshold
                JSM Get_value
                LDA =Output_info
                LDB =Par_output
                JSM Get_info
                LDA Output_info
                CPA =12         ! String array
                JMP Dump1
                JMP Bad_par
Dump1:          LDA Output_info+1
                CPA =1
                JMP Dump2
                JMP Bad_par
Dump2:          LDA Dim_size
                SLA Dump9       ! Dimensioned size must be even
                JMP Bad_par
Dump9:          CLA
                STA El_offset
                STA Output_idx
                STA Err_code
                LDA Val_options
                IOR =(250+0)*256
                JSM Put_output  ! Store options as trace entry
                LDA =17         ! Select DISP area for output
                LDB =80
                JSM Printer_select
                STA Prev_select
                STB Prev_width
                LDA Val_options
                AND =Opt_no_display
                RZA Dump11
                LDA ="00"
                STA Msg_good
                STA Msg_total   ! Clear good/total display
                JSM Display
Dump11:         LDA =T15
                STA Pa
                JSM Start_rd
                JMP No_isr
! Main loop
Dump3:          DIR
                LDA Exch_cnt    ! A could be 0,1 or 2
                SZA Dump4       ! A=0: no data in buffer
                DSZ Exch_cnt    ! 1 less word in buffer
                JMP Dump5       ! Skip if A=2
                LDA Exch_buffer ! A=1: get 1st word
                EIR
                JSM Put_output
                JMP Dump3
Dump5:          LDA Exch_buffer ! A=2: get 1st word
                LDB Exch_buffer+1
                STB Exch_buffer ! Shift down 2nd word
                EIR
                JSM Put_output
                JMP Dump3
Dump4:          LDA Err_code
                EIR
                RZA Exit_err
                LDA Val_options
                AND =Opt_no_display
                RZA Dump3
                LDA Exp_rec_no
                CPA Chase_rec_no
                JMP Dump3
                ISZ Chase_rec_no
                LDA Msg_total
                JSM Twodigit_inc
                STA Msg_total
                LDA Good_recs
                CPA Chase_good_recs
                JMP Dump10
                ISZ Chase_good_recs
                LDA Msg_good
                JSM Twodigit_inc
                STA Msg_good
Dump10:         JSM Display
                JMP Dump3
No_isr:         LDA =ERR_no_isr
                JMP Exit_err
Bad_par:        LDA =ERR_par
Exit_err:       STA Err_code
                IOR =(250+1)*256
                JSM Put_output  ! Store error code
                LDA =Err_code
                LDB =Par_error
                JSM Put_value
                LDA =Exp_rec_no
                LDB =Par_last_rec
                JSM Put_value
                LDA =Good_recs
                LDB =Par_good_rec
                JSM Put_value
! Fix size of string array elements
                LDA Output_idx
                STA Output_word
                CLA
                STA Output_byte
                LDA =Output_byte
                LDB =Output_info
                JSM Put_elem_bytes
Fix_array:      LDA El_offset
                SZA Leave
                DSZ El_offset
                NOP
                LDA Dim_size
                STA Output_word
                CLA
                STA Output_byte
                LDA =Output_byte
                LDB =Output_info
                JSM Put_elem_bytes
                JMP Fix_array
Leave:          LDA Prev_select
                LDB Prev_width
                JSM Printer_select
                RET 1
!
! Store A in output array
Put_output:     STA Output_word
! Check for overflow
                LDA Output_idx
                CPA Dim_size
                JMP Dump6               ! Array element exhausted
Dump8:          ADA =2
                STA Output_byte
                STA Output_idx
                LDA =Output_byte
                LDB =Output_info
                JMP Put_elem_bytes      ! Write word into string array
Dump6:          LDA El_offset
                ADA =1
                CPA El_count
                JMP Dump7               ! No space left in array
                STA El_offset
                CLA
                JMP Dump8
Dump7:          LDA =ERR_OOM
                STA Err_code
                RET 1
!
Twodigit_inc:   ADA =1                  ! Increment LS digit
                STA B
                AND =255
                CPA ='9+1               ! Roll over from 9 to 0?
                JMP Twodigit_1
                LDA B
                RET 1
Twodigit_1:     LDA B                   ! Roll back LS digit from 9 to 0 and
                ADA =246                ! increment MS digit
                STA B
                AND =177400B
                CPA =('9+1)*256         ! MS digit went past 9?
                JMP Twodigit_2
                LDA B                   ! No, leave it alone
                RET 1
Twodigit_2:     LDA B                   ! Yes, bring it back to 0
                ADA =173000B
                RET 1
!
Display:        LDA =Message
                JSM Print_no_lf
                NOP
                JMP Display1            ! Overflow or STOP
                RET 1                   ! Normal exit
Display1:       LDA =ERR_stopped
                STA Err_code
                RET 1
!
Val_options:    BSS 1
Val_threshold:  BSS 1
Output_info:    BSS 39
Dim_size:       EQU Output_info+2
El_count:       EQU Output_info+3
El_offset:      EQU Output_info+16
Output_idx:     BSS 1
Output_byte:    BSS 1
Output_size:    DAT 2
Output_word:    BSS 1
Message:        DAT 5
Msg_good:       BSS 1
Msg_total:      BSS 1
                DAT 13*256
Prev_select:    BSS 1
Prev_width:     BSS 1
Chase_rec_no:   BSS 1
Chase_good_recs:BSS 1
!
                LIT 64
!
                END Dump25
