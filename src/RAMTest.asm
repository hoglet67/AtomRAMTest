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

;; ******************************************************************
;; Build parameters, optionally passed in from build.sh
;; ******************************************************************

;; The code is assembled from this address
exec_page        =? &82

;; Size for the build (normally 4K)
rom_size         =? &1000

;; Screen base address
screen_base      =? &8000

;; Screen initialization value (8255 PIA port A at #B000)
screen_init      =? &00

;; The start/end pages in RAM that are tested, block 1
page_start1      =? &00
page_end1        =? &7F

;; The start/end pages in RAM that are tested, block 2
page_start2      =? &FF
page_end2        =? &FE

;; The start/end pages in RAM that are tested, block 3
page_start3      =? &FF
page_end3        =? &FE

;; Whether to display test cycles count (set to zero to disable this feature)
count_digits     =? 3

;; Whether to read the CPU speed from BFFE (assuming YARRB)
include_speed    =? TRUE

;; ******************************************************************
;; Calculated parameters
;; ******************************************************************

;; Calculate the code start address
test_start = exec_page * &100

;; Total number of pages
IF (screen_base = &8000)
    num_pages = (page_end1 - page_start1 + 1) + (page_end2 - page_start2 + 1) + (page_end3 - page_start3 + 1) + 1
ELSE
    num_pages = (page_end1 - page_start1 + 1) + (page_end2 - page_start2 + 1) + (page_end3 - page_start3 + 1)
ENDIF

;; The last page being tested
IF (page_start3 <= page_end3)
    page_end = page_end3
ELIF (page_start2 <= page_end2)
    page_end = page_end2
ELSE
    page_end = page_end1
ENDIF

;; The Atom's VIA T2 counter is used as a source of pseudo-random(ish) data.
via_base         = &B800
via_iorb         = via_base + &00
via_iora         = via_base + &01
via_ddrb         = via_base + &02
via_ddra         = via_base + &03
via_tmp1         = via_base + &06
via_tmp2         = via_base + &07
via_t2_counter_l = via_base + &08
via_t2_counter_h = via_base + &09

;; The Atom's ACR is used in interesting ways (!!)
via_acr          = via_base + &0B

;; Screen addresses for particular messages
row_title        = screen_base + &00
row_pass         = screen_base + &80
row_test         = screen_base + &A0
row_data         = screen_base + &C0
row_result       = screen_base + &100

;; ACR values for each test
;;
;; (bit 7 set indicates test 1)
;; (bit 6 set indicates test 2)
acr_test1        = &A0
acr_test2        = &60
acr_test3        = &00

;; ******************************************************************
;; Macros
;; ******************************************************************

;; The write_data macro writes a byte of data (in A) to an offset in
;; a memory page, using Y as the index within the page.
;;
;; In the first test, the VIA T2 counter is forced to FFFF,
;; so the value in A is written directly.
;;
;; In the second test, the VIA T2 counter is forced to 00FF,
;; so the value in A is incremented by 1 each time.
;;
;; In the third test, the VIA T2 counter is free-running,
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
    ADC via_t2_counter_l + (page AND 1) ; 4 - test 1: T2-L/H loaded with FF, so A unchanged
    STA page * &100, Y                  ; 5
    CMP (0, X)                          ; 6 - waste 6 cycles with a few bytes as possible
    SEC                                 ; 2
ENDMACRO

;; The compare_data macro compares the data in a memory page to a reference
;; value (in A), using Y as the index within the page.
;;
;; This macro mirrors the read_data macro
;;
;; In the final test, it's critical that the VIA T2 counter values
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
    ADC via_t2_counter_l + (page AND 1) ; 4 +00 - test 1: T2-L/H loaded with FF, so A unchanged
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

;; The loop_header macro is at the start of write or compare phase.
;;
;; It sets the VIA t2 counter to the required value for that test:
;;    test 1: ACR=&A0; t2_h=&FF; t2_l=&FF => Data unchanged
;;    test 2: ACR=&60; t2_h=&00; t2_l=&FF => Data incremented by one
;;    test 3: ACR=&00; t2_h=&FF; t2_l=&FF => Data randomly perturbed
;;
;; must exit with:
;;   A = test data/anchor/seed
;;   X = unchanged (it's the patten loop counter)
;;   Y = 00
;;   C = 1
;;
;; Alignment must end up between xxx6 and xxx0 to avoid page crossing in write_data
;;
;; Currently alignment ends up at xxxA

MACRO loop_header
    ;; Test 1 - VIA T2 = FF FF ; A = pattern
    ;; Test 3 - VIA T2 = FF FF ; A = pattern
    LDY #&FF
    LDA pattern_list, X
    BIT via_acr
    BVC store
    ;; Test 2 - VIA T2 = 00 00 ; A = FF
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
    BIT via_acr             ;; Bit 7 of the ACR set indicates test 1
    BMI skip_correction     ;; Test 2/3 correct test data at end of each col
    SBC #num_pages
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
   GUARD test_start + rom_size - 6

.test

;; The main RAM Test Program should also act as a valid 6502 reset handler

.RST_HANDLER

;; disable interrupts (only needed if invoked as a program)
    SEI
    CLD

;; initialize the Atom 8255 PIA (exactly as the Atom Reset handler would)
    LDA #&8A
    STA &B003
    LDA #&07
    STA &B002
    LDA #screen_init
    STA &B000

;; Clear the screen
    LDY #&00
    out_clear_screen TRUE, TRUE

    LDX #(msg_title - messages)
    LDY #(row_title - screen_base)
    JMP test_first_time

.test_loop0

;; Increment the pass count
IF (count_digits > 0)
{
    LDX #count_digits
.loop
    INC row_pass + 5, X
    LDA row_pass + 5, X
    CMP #'9'+1
    BCC done
    LDA #'0'
    STA row_pass + 5, X
    DEX
    BNE loop
.done
}
ENDIF

    ;; In test 1 the VIA T2 counter is set to pulse counting mode (VIA ACR=0xA0)
    ;; so it doesn't change. The counter is preloaded with FFFF, which causes the test
    ;; data to remain fixed.
    ;;
    ;; In test 2 the VIA T2 counter is set to pulse counting mode (VIA ACR=0x60)
    ;; so it doesn't change. The counter is preloaded with 00FF, which causes the test
    ;; data to increment by one each row (page).
    ;;
    ;; In test 3 the VIA T2 counter is set to free running counter mode (VIA ACR=0x00)
    ;; so it decrements at 1MHz. The counter is preloaded with FFFF, which causes the test data
    ;; to be psuedo-random(ish)
    ;;
    ;; The ACR is also in effect tracking whether we are in test 1, 2 or 3
    ;; (as we don't want to assume any RAM is useable).

    LDX #(msg_test1 - messages)
    LDY #(row_test - screen_base)

.test_first_time
    LDA #acr_test1

.test_loop1
    STA via_acr

    out_message_multiline row_title

IF (include_speed)
    ;; Fill in the speed, assuming YARRB
    ;; x00x xxxx -> 1MHz
    ;; x10x xxxx -> 2MHz
    ;; xx1x xxxx -> 4MHz
    LDA &BFFE
    AND #&60
    BEQ skip_update_speed
    AND #&20
    ASL A
    ASL A
    ASL A    ;; C=0 for 2MHz, 1 for 4MHz
    ADC #&33
    AND #&FE
    STA row_title + &10
.skip_update_speed
ENDIF

    ;; X is the loop iterator for the different fixed patterns
    LDX #&00

.test_loop2

    ;; Output the current pattern to the right place on the screen
    LDA pattern_list, X
    BIT via_acr
    BVC not_test2
    LDA increment_list, X
.not_test2
    out_hex_a row_data+&06

    ;; At the start of a write phase, reset the VIA T2 counter to a deterministic state
    loop_header

.write_loop

    ;; First write sample to the bottom half of the screen to keep it interesting!
IF (screen_base = &8000)
    write_data &81
ENDIF

    ;; Cascade the write_data macro N times, once per page being tested
    ;; A = test data value
    ;; Y = index within the page
IF (page_start1 <= page_end1)
    FOR page, page_start1, page_end1
        write_data page
    NEXT
ENDIF
IF (page_start2 <= page_end2)
    FOR page, page_start2, page_end2
        write_data page
    NEXT
ENDIF
IF (page_start3 <= page_end3)
     FOR page, page_start3, page_end3
        write_data page
     NEXT
ENDIF

    ;; Loop back for the next index (Y) within the page. 16-byte alignment is
    ;; important here to avoid the done branch crossing a page)
    loop_footer write_loop

    ;; We are now ready to read back and compare the written data...

    ;; At the start of a compare phase, reset the VIA T2 counter to a deterministic state
    loop_header

.compare_loop

    ;; First compare sample in bottom half of the screen
IF (screen_base = &8000)
    compare_data &81
ENDIF

    ;; Cascade the compare_data macro N times, once per page being tested
    ;; A = reference data value
    ;; Y = index within the page
IF (page_start1 <= page_end1)
    FOR page, page_start1, page_end1
        compare_data page
    NEXT
ENDIF
IF (page_start2 <= page_end2)
     FOR page, page_start2, page_end2
        compare_data page
     NEXT
ENDIF
IF (page_start3 <= page_end3)
    FOR page, page_start3, page_end3
        compare_data page
    NEXT
ENDIF

    ;; Loop back for the next index (Y) within the page. 16-byte alignment is
    ;; important here to avoid the done branch crossing a page)
    loop_footer compare_loop

    ;; All the time critical stuff is over now

    ;; Test for EEPT key
    BIT &B002
    BVC exit

    ;; Move on to the next pattern
    INX
    CPX #pattern_list_end - pattern_list
    BEQ next_test
    JMP test_loop2

    ;; Exiting the F000 rom version is complicated because you need
    ;; need to switch ROM banks, which can only be safely done from RAM
.exit
    LDX #exit_end - exit_start - 1
.exit_loop
    LDA exit_start, X
    STA row_result, X
    DEX
    BPL exit_loop
    JMP row_result

    ;; Code to switch back to the default ROM bank at 1MHz
.exit_start
    LDA #&06
    STA &BFFE
    JMP (&FFFC)
.exit_end

.next_test
    ;; The ACR is used to distingish the test (as we have no RAM and no spare registers)
    LDY #(row_test - screen_base)
    LDA via_acr
    CMP #acr_test1
    BEQ test2
    CMP #acr_test2
    BEQ test3

.success
    ;; Yeeehhh! All the tests have passed
    JMP test_loop0

.test2
    ;; Get setup for test 2
    LDA #acr_test2
    LDX #(msg_test2 - messages)
    JMP test_loop1

.test3
    ;; Get setup for test 3
    LDA #acr_test3
    LDX #(msg_test3 - messages)
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
    ;; These NOPs can act as a trigger
    NOP
    NOP
    NOP
    NOP
.haltloop
    ;; Loop until Shift pressed
    BIT &B001
    BMI haltloop
    ;; Restart the test again
    JMP test

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

.msg_title
    EQUS "ATOM RAM TEST"
IF (include_speed)
    EQUS " - 1MHZ"
ENDIF
    EQUB &80

    EQUS "TESTING PAGES "
    EQUS STR$~(page_start1 DIV &10 MOD &10)
    EQUS STR$~(page_start1         MOD &10)
    EQUS "-"
    EQUS STR$~(page_end1  DIV &10 MOD &10)
    EQUS STR$~(page_end1          MOD &10)
IF (page_start2 <= page_end2)
    EQUS ","
    EQUS STR$~(page_start2 DIV &10 MOD &10)
    EQUS STR$~(page_start2         MOD &10)
    EQUS "-"
    EQUS STR$~(page_end2  DIV &10 MOD &10)
    EQUS STR$~(page_end2          MOD &10)
ENDIF
IF (page_start3 <= page_end3)
    EQUS ","
    EQUS STR$~(page_start3 DIV &10 MOD &10)
    EQUS STR$~(page_start3         MOD &10)
    EQUS "-"
    EQUS STR$~(page_end3  DIV &10 MOD &10)
    EQUS STR$~(page_end3          MOD &10)
ENDIF
    EQUB &80

    EQUS "RUNNING FROM PAGES "
    EQUS STR$~(test_start DIV &1000 MOD &10)
    EQUS STR$~(test_start DIV  &100 MOD &10)
    EQUS "-"
    EQUS STR$~((test_end-1) DIV &1000 MOD &10)
    EQUS STR$~((test_end-1) DIV  &100 MOD &10)
    EQUB &80, &80

IF (count_digits > 0)
    EQUS "PASS: "
    IF (count_digits > 1)
        FOR i, 1, count_digits-1
            EQUS "0"
        NEXT
    ENDIF
    EQUS "1"
ENDIF
    EQUB &80

.msg_test1
    EQUS "TEST: FIXED DATA        "
    EQUB &80

    EQUS "DATA:"
    EQUB 0

.msg_test2
    EQUS "TEST: INCREMENTING DATA "
    EQUB &80

    EQUS "SKEW:"
    EQUB 0

.msg_test3
    EQUS "TEST: PSEUDO-RANDOM DATA"
    EQUB &80

    EQUS "SEED:"
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

    PRINT "Free Space: ", test_start + rom_size - 6 - pattern_list_end

    CLEAR test_start + rom_size - 6, test_start + rom_size - 1

    ORG test_start + rom_size - 6

    EQUW NMI_HANDLER
    EQUW RST_HANDLER
    EQUW IRQ_HANDLER

.test_end

SAVE     test_start - 22, test_end
