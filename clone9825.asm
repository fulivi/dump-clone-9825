                NAM Clon25
! **** CLONE9825 ****
! Copyright (c) 2022 F.Ulivi
!
! Licensed under the 3-Clause BSD License
!
! Any resemblance to test ROM code is purely coincidental ;)
!
                EXT Isr_access,Get_value,Get_info,Put_value
!
! Bits in option bitmap
Opt_track_b:    EQU 1
!
! Operation codes
Op_terminate:   EQU 0
Op_wr_words:    EQU 1
Op_wr_gap:      EQU 2
Op_wr_repeat:   EQU 3
!
! Error codes
ERR_none:       EQU 0           ! No error
ERR_normal:     EQU 1           ! Normal end
ERR_underf:     EQU 2           ! Exchange buffer underflow
ERR_prem_end:   EQU 3           ! Premature end of data
ERR_no_space:   EQU 4           ! No more space on tape
ERR_taco:       EQU 5           ! TACO error
ERR_par:        EQU 6           ! Bad parameters
ERR_no_isr:     EQU 7           ! Couldn't acquire ISR
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
TACO_wr_9825:   EQU 07000B+TACO_forward
TACO_wr_gap:    EQU 54000B+TACO_forward
TACO_force_irq: EQU 15000B
!
! Precompensation
TACO_precomp:   EQU 60000B
!
! T15 PA
T15:            EQU 15
!
R34:            EQU 34B
R35:            EQU 35B
Save_R35:       BSS 1
Isr_jump:       BSS 1
Err_code:       BSS 1
!
! ************
! * TACO ISR *
! ************
Clone_Isr:      LDA R35
                STA Save_R35
                LDA R34
                STA R35
                LDA Err_code
                RZA Err_n_end   ! Abort if errors
!
! Check TACO state
                LDA R5
                AND =15
                SZA Check2
                SLA Check1
                LDA =ERR_no_space       ! Met hole: no more space on tape
                JMP Err_n_end
Check1:         LDA =ERR_taco   ! TACO error: no cartridge, write protection or servo failure
                JMP Err_n_end
Check2:         JMP Isr_jump,I  ! TACO ok, jump to current state
!
Cmd_n_set_Int:  JSM Wait_Flg
                STA R5
                STB Isr_jump
Leave_Isr:      LDA Save_R35
                STA R35
                RET 1
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
! Get op/word into exchange buffer
! RET 1: underflow
! RET 2: OK
Exch_op:        BSS 1
Exch_word:      BSS 1
Exch_flag:      BSS 1
Curr_op:        BSS 1
Curr_word:      BSS 1
!
Get_exchange:   LDA Exch_flag
                SLA Get_ex1,C
                STA Exch_flag
                LDA Exch_word
                STA Curr_word   ! Xfer word
                LDA Exch_op     ! Get new op
                RET 2
Get_ex1:        LDA =ERR_underf ! Underflow
                RET 1
!
State_start:    JSM Get_exchange
                JMP Err_n_end
!
! Start a new op (code in A)
Start_op:       STA Curr_op
                ADA =Jump_tb+Indirect_off
                JMP A,I
Jump_tb:        JMP Start_op0
                JMP Start_op1
                JMP Start_op2
! Op=0: terminate
Start_op0:      LDA =ERR_normal
                JMP Err_n_end
! Op=1: write words
Start_op1:      LDA Val_threshold
                ADA =TACO_precomp
                JSM Wait_Flg
                STA R7          ! Write timing & precompensation
                LDA Curr_word   ! First word
                JSM Wait_Flg
                STA R4
                LDA =TACO_wr_9825
                LDB =State_wr_words+Indirect_off
                JMP Cmd_n_set_Int
! Op=2: write gap
Start_op2:      LDA Curr_word
                TCA
                JSM Wait_Flg
                STA R6          ! Load length of gap from Curr_word
                LDA =TACO_wr_gap
                LDB =State_wr_gap+Indirect_off
                JMP Cmd_n_set_Int
!
! State_wr_words: write words
State_wr_words: JSM Get_exchange
                JMP Err_n_end
                CPA Curr_op
                JMP State_ww_1
                JMP Start_op
State_ww_1:     LDA Curr_word
                JSM Wait_Flg
                STA R4
                JMP Leave_Isr
!
! State_wr_gap: write gap
State_wr_gap:   JSM Get_exchange
                JMP Err_n_end
                JMP Start_op
!
! Start writing
! RET 1: failure
! RET 2: OK
Start_wr:       LDA =State_start+Indirect_off
                STA Isr_jump
                LDA Pa
                AND =15
                ADA =256+(3*16) ! 1 attempt, synch. access
                STA B
                LDA =Clone_Isr
                JSM Isr_access
                RET 1           ! Failed
                JSM Clear_TACO
                LDA =TACO_Set_Track
                LDB Val_options
                SLB Start1
                IOR =TACO_track_B
Start1:         JSM Cmd_TACO    ! Set track A/B
                LDA =TACO_force_irq     ! Force IRQ to start FSM
                JSM Cmd_TACO    ! Off we go!
                RET 2
!
! ********************************
! * ICALL Entry point: Clone9825 *
! ********************************
!
                SUB
Par_options:    INT             ! Option bitmap
Par_threshold:  INT             ! Threshold
Par_data:       STR(*)          ! Input data
Par_error:      INT             ! Out: error code
!
Clone9825:      LDA =Val_options
                LDB =Par_options
                JSM Get_value
                LDA =Val_threshold
                LDB =Par_threshold
                JSM Get_value
                LDA =Data_info
                LDB =Par_data
                JSM Get_info
                LDA Data_info
                CPA =12         ! String array
                JMP Clone1
                JMP Bad_par
Clone1:         LDA Data_info+1
                CPA =1
                JMP Clone2
                JMP Bad_par
Clone2:         LDA Dim_size
                SLA Clone3      ! Dimensioned size must be even
                JMP Bad_par
Clone3:         CLA
                STA Err_code
                LDA =First_block
                JSM New_el_block
                JMP Exit_err
                JSM Get_op      ! Get 1st op
                JMP Prem_end
                LDA Data_word   ! Prepare 1st op & word for ISR
                STA Exch_word
                LDA Op_to_exch
                STA Exch_op
                LDA =1
                STA Exch_flag
                LDA =T15
                STA Pa
                JSM Start_wr
                JMP No_isr
! Main loop
Clone4:         DIR
                LDA Exch_flag
                RLA Clone5,S
                STA Exch_flag
                LDA Data_word
                STA Exch_word
                LDA Op_to_exch
                STA Exch_op
                EIR
                JSM Advance_op
                JMP Exit_err
                JMP Clone4
Clone5:         LDA Err_code
                EIR
                SZA Clone4
                JMP Exit_err
Prem_end:       LDA =ERR_prem_end
                JMP Exit_err
No_isr:         LDA =ERR_no_isr
                JMP Exit_err
Bad_par:        LDA =ERR_par
Exit_err:       STA Err_code
                LDA =Err_code
                LDB =Par_error
                JSM Put_value
                RET 1
!
! Get a word from data array
! RET 1: no more words
! RET 2: OK
Get_data:       LDA C
                CPA El_end
                JMP Get1                ! Array element exhausted
Get3:           WWC A,I                 ! Get word & adv pointer
                STA Data_word
                RET 2
Get1:           DSZ El_count
                JMP Get4
Get2:           LDA =ERR_prem_end       ! All elements read
                STA Err_code
                RET 1
Get4:           LDA Last_el
                RZA Get2                ! Last element consumed
                ISZ Curr_ptr_block,I
                JMP Get5
                LDA Curr_ptr_block      ! Move to next block of elements
                ADA =3
                JSM New_el_block
                RET 1
                JMP Get3
Get5:           JSM New_el
                RET 1
                JMP Get3
!
! Prepare for a new element block
! A=ptr to pointer block
! RET 1: Error
! RET 2: OK
New_el_block:   STA Curr_ptr_block
                ADA =1
                LDB A,I
                STB C                   ! Set starting address of new el
                ADA =1
                LDA A,I
                STA R35                 ! Set BSC of new el
New_el:         WWC A,I                 ! Get el length and move to 1st word
                SZA Get2                ! 0-sized el
                RLA Get2                ! Element with odd size
                LDB =1
                CPA Dim_size
                LDB =0
                STB Last_el             ! Last el if length < dimensioned size
                SAR 1
                ADA C
                STA El_end              ! Compute end of new el
                RET 2
!
! Advance current op
Advance_op:     LDA Op_curr
                ADA =Op_adv_table
                JMP A,I
Op_adv_table:   RET 2                   ! Op_terminate doesn't advance
                JMP Adv_op_ww
                JMP Get_op              ! Op_wr_gap: move to next op
                DSZ Op_cnt              ! Op_wr_repeat
                RET 2                   ! Keep repeating word in Data_word
                JMP Get_op              ! No more repetitions
Adv_op_ww:      DSZ Op_cnt              ! Op_wr_words
                JMP Get_data            ! Get next word
!
! Get a new op
Get_op:         JSM Get_data
                RET 1
                STA B
                AND =37777B
                STA Op_cnt
                LDA B
                SAR 14
                STA Op_curr
                STA Op_to_exch
                ADA =Op_table
                JMP A,I
Op_table:       RET 2                   ! Op_terminate
                JMP Get_data            ! Op_wr_words: get 1st word
                JMP Get_op_wg           ! Op_wr_gap
                LDA =Op_wr_words        ! Op_wr_repeat
                STA Op_to_exch          ! Fake Op_wr_words for ISR
                JMP Get_data            ! Get word to be repeated
Get_op_wg:      LDA Op_cnt
                STA Data_word           ! Set gap size
                RET 2
!
Val_options:    BSS 1
Val_threshold:  BSS 1
Data_info:      BSS 39
Dim_size:       EQU Data_info+2
El_count:       EQU Data_info+3
First_block:    EQU Data_info+18
Curr_ptr_block: BSS 1
El_end:         BSS 1
Last_el:        BSS 1
Data_word:      BSS 1
Op_curr:        BSS 1
Op_to_exch:     BSS 1
Op_cnt:         BSS 1
!
                LIT 64
!
                END Clon25
