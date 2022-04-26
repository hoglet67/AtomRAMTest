;; ******************************************************************
;; Atom RAM Test
;;
;; This program is a RAM test for the Acorn Atom
;;
;; It allows the whole of the lower text area (0x0000-0x7FFF) to be
;; tested with fixed, variable and pseudo random (ish) data.
;;
;; It can be run from ROM (for example, replacing the Atom Kernel)
;; and it doesn't make any use at all of Page Zero or the Stack
;; (as the RAM there may itself be faulty).
;;
;; ******************************************************************

;; The code is assembled from this address, which is passed in from build.sh
test_start       =? &8200

;; The start/end pages in RAM that are tested
page_start       =? &00
page_end         =? &7F

;; Screen base address
screen_base      =? &8000

;; Screen initialization value (8255 PIA port A at #B000)
screen_init      =? &00

;; The Atom's VIA T2 counter is used as a source of pseudo-random(ish) data.
via_base         = &B800
via_tmp1         = via_base + &06
via_tmp2         = via_base + &07
via_t2_counter_l = via_base + &08
via_t2_counter_h = via_base + &09

;; The Atom's ACR is used in interesting ways (!!)
via_acr          = via_base + &0B

;; Screen addresses for particular messages
row_title        = screen_base + &00
row_pass         = screen_base + &A0
row_data         = screen_base + &C0
row_result       = screen_base + &100

;; ACR values for each pass
;;
;; (bit 7 set indicates pass 1)
;; (bit 6 set indicates pass 2)
acr_pass1        = &A0
acr_pass2        = &60
acr_pass3        = &00

;; ******************************************************************
;; Macros
;; ******************************************************************

;; The write_data macro writes a byte of data (in A) to an offset in
;; a memory page, using Y as the index within the page.
;;
;; In the first pass of the test, the VIA T2 counter is forced to FFFF,
;; so the value in A is written directly.
;;
;; In the second pass of the test, the VIA T2 counter is forced to 00FF,
;; so the value in A is incremented by 1 each time.
;;
;; In the third pass of the test, the VIA T2 counter is free-running,
;; so the value in A is perturbed by ADCing with the current counter
;; value, which gives a pseudo-random(ish) stream of data.
;;
;; This macro is 9 bytes and is cascaded 128 times (once for each page
;; begin tested) which adds up to 1152 bytes.
;;
;; This macro takes 17 cycles, regardless of alignment.
;;
;; (17 is not a power of 2, which helps avoid obvious repeating patterns)

;; Entered with C=1, exits with C=1

MACRO write_data page
    ADC via_t2_counter_l + (page AND 1) ; 4 - pass 1: T2-L/H loaded with FF, so A unchanged
    STA page * &100, Y                  ; 5
    CMP (0, X)                          ; 6 - waste 6 cycles with a few bytes as possible
    SEC                                 ; 2
ENDMACRO

;; The compare_data macro compares the data in a memory page to a reference
;; value (in A), using Y as the index within the page.
;;
;; This macro mirrors the read_data macro
;;
;; In the final pass, it's critical that the VIA T2 counter values
;; exactly match those used when the data was written. This means the
;; macro must also take exactly 11 cycles. As it contains a forward
;; branch instruction, this must never cross a page boundary. The
;; easiest way to guarantee this is to pad the macro to 16 bytes,
;; and then carefully pick an initial alignment.
;;
;; This macro is 16 bytes and is cascaded 128 times (once for each page
;; begin tested) which adds up to 2048 bytes.
;;
;; This macro takes 17 cycles, in the happy case, and if the branch
;; does not cross a page boundary.
;;
;; Entered with C=1, exits with C=1
;;
;; (1) and (2) must be in the same page to avoid page crossing penatly
;; => macro must be aligned to xxx6 -> xxx0
;;
MACRO compare_data page
    ADC via_t2_counter_l + (page AND 1) ; 4 +00 - pass 1: T2-L/H loaded with FF, so A unchanged
    SEC                                 ; 2 +03
    TAX                                 ; 2 +04 - save the reference value
    EOR page * &100, Y                  ; 4 +05 - use EOR rather than CMP so we have a record of the error
    BEQ next                            ; 3 +08
    TXS                                 ;   +0A - (1)
    LDX #page                           ;   +0B
IF page = page_end
    BCS fail
ELSE
    BCS P%+16                           ;   +0D
ENDIF
.next                                   ;   +0D
    TXA                            ; 8A ; 2 +0F - (2) restore the reference value
ENDMACRO

;; The make_aligned macro forces the next instruction to be 16-byte aligned

MACRO make_aligned
    JMP align
    ALIGN 16
.align
ENDMACRO

;; The loop_header macro is at the start of write or compare pass.
;;
;; It sets the VIA t2 counter to the required value for that pass:
;;    pass 1: ACR=&A0; t2_h=&FF; t2_l=&FF => Data unchanged
;;    pass 2: ACR=&60; t2_h=&00; t2_l=&FF => Data incremented by one
;;    pass 3: ACR=&00; t2_h=&FF; t2_l=&FF => Data randomly perturbed
;;
;; must exit with:
;;   A = test data/anchor/seed
;;   X = unchanged (it's the patten loop counter)
;;   Y = 00
;;   C = 1
;;
;; Alignment must end up between xxx6 and xxx0 to avoid page crossing in write_data
;;
;; Currently alignment ends up at xxxB

MACRO loop_header
    ;; Pass 1 - VIA T2 = FF FF ; A = pattern
    ;; Pass 3 - VIA T2 = FF FF ; A = pattern
    LDY #&FF
    LDA pattern_list, X
    BIT via_acr
    BVC store
    ;; Pass 2 - VIA T2 = 00 00 ; A = FF
    TYA
    INY
.store
    make_aligned
    TXS
    SEC
    STY via_t2_counter_l
    STY via_t2_counter_h
    LDY #&00
ENDMACRO

;; This loop_footer handles looping back for the next memory column
;;

MACRO loop_footer loop_start
    make_aligned
    TSX
    BIT via_acr             ;; Bit 7 of the ACR set indicates pass 1
    BMI skip_correction     ;; Pass 2/3 correct test data at end of each col
IF (screen_base = &8000)
    SBC #(page_end - page_start + 2)
ELSE
    SBC #(page_end - page_start + 1)
ENDIF
    CLC
    ADC increment_list, X
    SEC
.skip_correction
    INY
    BEQ loop_exit
    JMP loop_start
.loop_exit
ENDMACRO

;; The out_message macro writes a zero-terminated message directly
;; to screen memory. The messages are stored using 6847 character
;; codes rather than ASCII.

MACRO out_message screen
    LDY #&00
.loop
    LDA messages, X
    BEQ done
    CMP #'?'
    BEQ skip
    STA screen, Y
.skip
    INX
    INY
    BNE loop
.done
ENDMACRO

;; A more complex version of out_message that deals with line breaks
;; (which are encoded as characters with bit 7 set).

MACRO out_message_multiline screen
.loop
    LDA messages, X
    BEQ done
    BMI newline
    STA screen, Y
    INY
.next
    INX
    BNE loop
.newline
    TYA
    ADC #&20
    AND #&E0
    TAY
    BNE next
.done
ENDMACRO

;; The out_hex_digit macro writes a single hex digit in A (00-0F) to
;; screen memory, converting to 6847 character codes on the fly:
;;   00->09 => 30->39
;;   0A->0F => 01->06

MACRO out_hex_digit screen
    ORA #&30
    CMP #&3A
    BCC store
    SBC #&39
.store
    STA screen
ENDMACRO

;; Same as above, but writes to screen, Y

MACRO out_hex_digit_iy screen
    ORA #&30
    CMP #&3A
    BCC store
    SBC #&39
.store
    STA screen, Y
ENDMACRO

;; The out_hex_a macro writes two hex digits in A (00-FF) to
;; screen memory, using the above out_hex_digit for each nibble.

macro out_hex_a screen
    TXS
    TAX
    LSR A
    LSR A
    LSR A
    LSR A
    out_hex_digit screen
    TXA
    AND #&0F
    out_hex_digit screen+1
    TSX
ENDMACRO

;; Same as above, but writes to screen, Y

macro out_hex_a_iy screen
    TXS
    TAX
    LSR A
    LSR A
    LSR A
    LSR A
    out_hex_digit_iy screen
    TXA
    AND #&0F
    out_hex_digit_iy screen+1
    TSX
ENDMACRO

;; The out_clear_screen macro is used to clear the screen
;;
;; The top/bottom parameters, together with the value of Y,
;; control how much of the screen to clear.
;;
;; To clear the whole screen, top=TRUE, bottom=TRUE, Y=&00

MACRO out_clear_screen top,bottom
    LDA #&20
.loop
IF (top)
    STA screen_base, Y
ENDIF
IF (bottom)
    STA screen_base + &100, Y
ENDIF
    INY
    BNE loop
ENDMACRO


;; The re_read_yyxx macro reads the failed location additional times
;; using self-modifying code witten into the screen memory
MACRO re_read_failed
    ;; LDA XXYY; JMP continue
    LDA #&AD
    STA row_result
    LDA via_tmp2
    STA row_result+1
    LDA via_tmp1
    STA row_result+2
    LDA #&4C
    STA row_result+3
    LDA #<continue
    STA row_result+4
    LDA #>continue
    STA row_result+5
    ;; Execute it
    JMP row_result
.continue
    ;; And output the value read
ENDMACRO

;; ******************************************************************
;; Atom ATM file Header
;; ******************************************************************

    ORG test_start-22

.atm_header
    EQUS "RAMTEST"
    EQUB 0,0,0,0,0,0,0,0,0
    EQUW test_start
    EQUW test_start
    EQUW (test_end - test_start)

;; ******************************************************************
;; Start of main RAM Test program
;; ******************************************************************

   ORG test_start
   GUARD test_start + &FFA

.test

;; The main RAM Test Program should also act as a valid 6502 reset handler

.RST_HANDLER

;; disable interrupts (only needed if invoked as a program)
    SEI
    CLD

;; Clear the screen

    LDY #&00
    out_clear_screen TRUE, TRUE

;; initialize the Atom 8255 PIA (exactly as the Atom Reset handler would)
    LDA #&8A
    STA &B003
    LDA #&07
    STA &B002
    LDA #screen_init
    STA &B000

    ;; In pass 1 the VIA T2 counter is set to pulse counting mode (VIA ACR=0xA0)
    ;; so it doesn't change. The counter is preloaded with FFFF, which causes the test
    ;; data to remain fixed.
    ;;
    ;; In pass 2 the VIA T2 counter is set to pulse counting mode (VIA ACR=0x60)
    ;; so it doesn't change. The counter is preloaded with 00FF, which causes the test
    ;; data to increment by one each row (page).
    ;;
    ;; In pass 3 the VIA T2 counter is set to free running counter mode (VIA ACR=0x00)
    ;; so it decrements at 1MHz. The counter is preloaded with FFFF, which causes the test data
    ;; to be psuedo-random(ish)
    ;;
    ;; The ACR is also in effect tracking whether we are in pass 1, 2 or 3
    ;; (as we don't want to assume any RAM is useable).

    LDA #acr_pass1
    LDX #(msg_pass1 - messages)
    LDY #(row_title - screen_base)

.test_loop1
    STA via_acr

    out_message_multiline row_title

    ;; X is the loop iterator for the different fixed patterns
    LDX #&00

.test_loop2

    ;; Output the current pattern to the right place on the screen
    LDA pattern_list, X
    BIT via_acr
    BVC not_pass2
    LDA increment_list, X
.not_pass2
    out_hex_a row_data+&08

    ;; At the start of a write pass, reset the VIA T2 counter to a deterministic state
    loop_header

.write_loop

    ;; First write sample to the bottom half of the screen to keep it interesting!
IF (screen_base = &8000)
    write_data &81
ENDIF

    ;; Cascade the write_data macro N times, once per page being tested
    ;; A = test data value
    ;; Y = index within the page
FOR page, page_start, page_end
    write_data page
NEXT

    ;; Loop back for the next index (Y) within the page. 16-byte alignment is
    ;; important here to avoid the done branch crossing a page)
    loop_footer write_loop

    ;; We are now ready to read back and compare the written data...

    ;; At the start of a compare pass, reset the VIA T2 counter to a deterministic state
    loop_header

.compare_loop

    ;; First compare sample in bottom half of the screen
IF (screen_base = &8000)
    compare_data &81
ENDIF

    ;; Cascade the compare_data macro N times, once per page being tested
    ;; A = reference data value
    ;; Y = index within the page
FOR page, page_start, page_end
    compare_data page
NEXT

    ;; Loop back for the next index (Y) within the page. 16-byte alignment is
    ;; important here to avoid the done branch crossing a page)
    loop_footer compare_loop

    ;; All the time critical stuff is over now

    ;; Move on to the next pattern
    INX
    CPX #pattern_list_end - pattern_list
    BEQ next_pass
    JMP test_loop2

.next_pass
    ;; The ACR is used to distingish the pass (as we have no RAM and no spare registers)
    LDY #(row_pass - screen_base)
    LDA via_acr
    CMP #acr_pass1
    BEQ pass2
    CMP #acr_pass2
    BEQ pass3

.success
    ;; Yeeehhh! All the tests have passed
    JMP test

.pass2
    ;; Get setup for pass 2
    LDA #acr_pass2
    LDX #(msg_pass2 - messages)
    JMP test_loop1

.pass3
    ;; Get setup for pass 3
    LDA #acr_pass3
    LDX #(msg_pass3 - messages)
    JMP test_loop1

.fail
    ;; Boooh! One of the tests has failed, at this point the compare_data macro has set:
    ;;        A = error value (value read EOR value written)
    ;;        X = high byte of failed address
    ;;        Y = low  byte of failed address
    ;;        S = reference value (written to memory)
    ;; via_tmp1 = spage
    ;; via_tmp2 = spare

    ;; 0123456789abcdef0123456789abcdef
    ;; FAILED AT ???? W:?? R:??
    STX via_tmp1      ;; via_tmp1 = MSB of address
    STA via_tmp2      ;; via_tmp2 = error

    ;; Reference value
    TSX
    TXA               ;; X = reference value
    out_hex_a row_result+&11

    ;; High byte of address
    LDA via_tmp1
    out_hex_a row_result+&0A

    ;; Low byta of address
    TYA
    out_hex_a row_result+&0C

    ;; read value
    TXA
    EOR via_tmp2

    STY via_tmp2    ;; via_tmp2 = LSB of address
    ;;        A = hold value read from memory
    ;;        X = spare
    ;;        Y = spare
    ;; via_tmp1 = low byte of failed address
    ;; via_tmp2 = high byte of failed address
    LDY #&00

.loop
    out_hex_a_iy row_result+&16
    re_read_failed
    INY
    INY
    INY
    CPY #3*3
    BNE loop

    LDX #(msg_failed - messages)
    ;; fall through to

.halt_message

    ;; Output final message
    out_message row_result

    ;; Clear the bottom of the screen
    out_clear_screen FALSE, TRUE

.halt
    ;; Loop forever....
    BEQ halt

;; We don't expect IRQ to occur, but just in case....

.IRQ_HANDLER
    LDX #(msg_irq - messages)
    BNE halt_message

;; We don't expect NMI to occur, but just in case....

.NMI_HANDLER
    LDX #(msg_nmi - messages)
    BNE halt_message

;; ******************************************************************
;; Text Messages
;; ******************************************************************

MAPCHAR &40,&5F,&00

.messages

.msg_pass1
    EQUS "ATOM RAM TEST"
    EQUB &80, &80

    EQUS "TESTING #"
    EQUS STR$~(page_start DIV &10 MOD &10)
    EQUS STR$~(page_start         MOD &10)
    EQUS "00-#"
    EQUS STR$~(page_end  DIV &10 MOD &10)
    EQUS STR$~(page_end          MOD &10)
    EQUS "FF"
    EQUB &80

    EQUS "RUNNING #"
    EQUS STR$~(test_start DIV &1000 MOD &10)
    EQUS STR$~(test_start DIV &0100 MOD &10)
    EQUS STR$~(test_start DIV &0010 MOD &10)
    EQUS STR$~(test_start           MOD &10)
    EQUB &80, &80

    EQUS "PASS 1: FIXED DATA"
    EQUB &80

    EQUS "  DATA: "
    EQUB 0

.msg_pass2
    EQUS "PASS 2: INCREMENTING DATA"
    EQUB &80

    EQUS "  SKEW: "
    EQUB 0

.msg_pass3
    EQUS "PASS 3: PSEUDO-RANDOM DATA"
    EQUB &80

    EQUS "  SEED: "
    EQUB 0

.msg_passed
    EQUS "PASSED"
    EQUB 0

.msg_failed
    EQUS "FAILED AT ???? W:?? R:??:??:??"
    EQUB 0

.msg_irq
    EQUS "IRQ!!"
    EQUB 0

.msg_nmi
    EQUS "NMI!!"
    EQUB 0


;; ******************************************************************
;; Increment data
;; ******************************************************************

.increment_list
    EQUB &00
    EQUB &01
    EQUB &02
    EQUB &03
    EQUB &04
    EQUB &05
    EQUB &06
    EQUB &07
    EQUB &08
    EQUB &09
    EQUB &0A
    EQUB &0B
    EQUB &0C
    EQUB &0D
    EQUB &0E
    EQUB &0F
    EQUB &10
    EQUB &11
    EQUB &12
    EQUB &13


;; ******************************************************************
;; Pattern data
;; ******************************************************************

.pattern_list
    EQUB &00
    EQUB &FF
    EQUB &55
    EQUB &AA
    EQUB &01
    EQUB &02
    EQUB &04
    EQUB &08
    EQUB &10
    EQUB &20
    EQUB &40
    EQUB &80
    EQUB &FE
    EQUB &FD
    EQUB &FB
    EQUB &F7
    EQUB &EF
    EQUB &DF
    EQUB &BF
    EQUB &7F
.pattern_list_end

;; ******************************************************************
;; 6502 Vectors (at the end of the 4K ROM)
;; ******************************************************************

    PRINT "Free Space: ", test_start + &FFA - pattern_list_end

    CLEAR test_start + &FFA, test_start + &FFF

    ORG test_start + &FFA

    EQUW NMI_HANDLER
    EQUW RST_HANDLER
    EQUW IRQ_HANDLER

.test_end

SAVE     test_start - 22, test_end
