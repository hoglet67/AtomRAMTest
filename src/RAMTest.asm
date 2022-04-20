;; ******************************************************************
;; Atom RAM Test
;;
;; This program is a RAM test for the Acorn Atom
;;
;; It allows the whole of the lower text area (0x0000-0x7FFF) to be
;; tested with both fixed data and pseudo random (ish) data.
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

;; Screen
screen_base      =? &8000

;; Screen init
screen_init      =? &00

;; The Atom's VIA T2 counter is used as a source of pseudo-random(ish) data.
via_base         = &B800
via_t2_counter_l = via_base + &08
via_t2_counter_h = via_base + &09
via_acr          = via_base + &0B


row_title        = screen_base + &00
row_testing      = screen_base + &40
row_running      = screen_base + &80
row_fixed        = screen_base + &C0
row_data         = screen_base + &E0
row_result       = screen_base + &120

;; ******************************************************************
;; Macros
;; ******************************************************************

;; The write_data macro writes a byte of data (in A) to an offset in
;; a memory page, using Y as the index within the page.
;;
;; In the first pass of the test, the VIA T2 counter is forced to zero,
;; so the value in A is written directly.
;;
;; In the second pass of the test, the VIA T2 counter is free-running,
;; so the value in A is perturbed by ADCing with the current counter
;; value, which gives a pseudo-random(ish) stream of data.
;;
;; This macro is 10 bytes and is cascaded 128 times (once for each page
;; begin tested) which adds up to 1280 bytes.
;;
;; This macro takes 15 cycles, regardless of alignment.
;;
;; (15 is not a power of 2, which helps avoid obvious repeating patterns)

;; Entered with C=1, exits with C=1

MACRO write_data address
ADC via_t2_counter_l ; 4 - pass 1: T2-L loaded with FF, so A unchanged
ADC via_t2_counter_h ; 4 - pass 1: T2-H loaded with FF, so A unchanged
STA address, Y       ; 5
SEC                  ; 2
ENDMACRO

;; The compare_data macro compares the data in a memory page to a reference
;; value (in A), using Y as the index within the page.
;;
;; This macro mirrors the read_data macro
;;
;; In the second pass, it's critical that the VIA T2 counter values
;; exactly match those used when the data was written. This means the
;; macro must also take exactly 11 cycles. As it contains a forward
;; branch instruction, this must never cross a page boundary. The
;; easiest way to guarantee this is to pad the macro to 16 bytes,
;; and then carefully pick an initial alignment.
;;
;; This macro is 16 bytes and is cascaded 128 times (once for each page
;; begin tested) which adds up to 2048 bytes.
;;
;; This macro takes 15 cycles, in the happy case, and if the bramch
;; does not cross a page boundary.
;;
;; If aligned to xxxA then the branch will neve cross a page boundary

;; Entered with C=1, exits with C=1

MACRO compare_data address
ADC via_t2_counter_l ; 4 +FA - pass 1: T2-L loaded with FF, so A unchanged
ADC via_t2_counter_h ; 4 +FD - pass 2: T2-L loaded with FF, so A unchanged
CMP address, Y       ; 4 +00
BEQ next             ; 3 +03 ;; C=1 if branch taken
LDA #>address        ;   +05
JMP fail             ;   +07
.next
ENDMACRO

;; The make_aligned macro forces the next instruction to be 16-byte aligned

MACRO make_aligned
      JMP align
      ALIGN 16
.align
ENDMACRO

;; The out_message macro writes a zero-terminated message directly
;; to screen memory, translating the ASCII characters to 6847 character
;; codes on the fly.

MACRO out_message screen,message
      LDX #&00
.loop
      LDA message, X
      BEQ done
      CLC
      ADC #&20
      BMI skipeor
      EOR #&60
.skipeor
      STA screen, X
      INX
      BNE loop
.done
ENDMACRO

;; The out_hex_digit macro writes a single hex digit in A (00-0F) to
;; screen memory, converting to 6847 character codes on the fly:
;;   00->09 => 30->39
;;   0A->0F => 01->06

MACRO out_hex_digit screen
      CMP #&0A
      BCC digit09
      SBC #&09
      BNE digitAF
.digit09
      ORA #&30
.digitAF
      STA screen
ENDMACRO

;; The out_hex_y macro writes two hex digits in Y (00-FF) to
;; screen memory, using the above out_hex_digit for each nibble.

MACRO out_hex_y screen
      TYA
      LSR A
      LSR A
      LSR A
      LSR A
      out_hex_digit screen
      TYA
      AND #&0F
      out_hex_digit screen+1
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

.test
    JMP RST_HANDLER

;; We don't expect IRQ to occur, but just in case....

.IRQ_HANDLER
    out_message row_title, msg_irq
    JMP halt

;; We don't expect NMI to occur, but just in case....

.NMI_HANDLER
    out_message row_title, msg_nmi
    JMP halt

;; The main RAM Test Program should also act as a valid 6502 reset handler

.RST_HANDLER

;; reset the stack pointer (even though it's not used, just in case)
;; (for debugging it helps to replace the JMP in compare_data with JSR)
    LDX #&FF
    TXS

;; disable interrupts
    SEI

;; initialize the Atom 8255 PIA (exactly as the Atom Reset handler would)
   LDA #&8A
   STA &B003
   LDA #&07
   STA &B002
   LDA #screen_init
   STA &B000

;; Clear the screen

    LDA #&20
    LDX #&00
.clear_loop
    STA screen_base, X
    STA screen_base + &100, X
    INX
    BNE clear_loop

;; Print the fixed messages

    out_message row_title,   msg_title
    out_message row_testing, msg_testing
    out_message row_running, msg_running
    out_message row_fixed,   msg_fixed
    out_message row_data,    msg_data

;; Print the test parameters (page_start, page_end, test_start)

    ;; 0123456789abcdef0123456789abcdef
    ;; TESTING #0000-#FFFF"
    ;; RUNNING FROM #0000"
    LDY #page_start
    out_hex_y row_testing+&09
    LDY #page_end
    out_hex_y row_testing+&0F
    LDY #>test_start
    out_hex_y row_running+&0E

    ;; In pass 1 the VIA T2 counter is set to pulse counting mode
    ;; (VIA ACR=0x20) so it doesn't change, and then the counter is cleared.
    ;;
    ;; In pass 2 the VIA T2 counter is set to free running counter mode
    ;; (VIA ACR=0x00) so it decrements at 1MHz.
    ;;
    ;; This causes the test data in pass 2 to be psuedo-random(ish)
    ;;
    ;; The ACR is also in effect tracking whether we are in pass 1 or 2
    ;; (as we don't want to assume any RAM is useable).

    LDA #&20

.test_loop1
    STA via_acr

    ;; X is the loop iterator for the differnt fixed patterns
    LDX #&00

.test_loop2

    ;; Output the current pattern to the right place on the screen
    LDA pattern_list, X
    TAY
    out_hex_y row_data+&08

    ;; The write_data macro requires the write data to be in A
    LDA pattern_list, X

    ;; At the start of a write pass, reset the VIA T2 counter to a deterministic state
    SEC
    LDY #&FF
    STY via_t2_counter_l
    STY via_t2_counter_h
    INY

.write_loop

    ;; Cascade the write_data macro N times, once per page being tested
    ;; A = test data value
    ;; Y = index within the page
FOR page, page_start, page_end
    write_data page * &100
NEXT

    ;; Loop back for the next index (Y) within the page. 16-byte alignment is
    ;; important here to avoid the done branch crossing a page)
    make_aligned
    INY
    BEQ write_done
    JMP write_loop
.write_done

    ;; The compare_data macro requires the data to be checked to be in A
    LDA pattern_list, X

    ;; We are now ready to read back and compare the written data...

    ;; Make sure we start 16-byte aligned (xxx0)
    make_aligned

    ;; At the start of a compare pass, reset the VIA T2 counter to a deterministic state
    SEC
    LDY #&FF
    STY via_t2_counter_l
    STY via_t2_counter_h
    INY

    ;; Now aligned to xxxA, so the branch within compare_data never crosses a page boundary

.compare_loop

    ;; Cascade the compare_data macro N times, once per page being tested
    ;; A = reference data value
    ;; Y = index within the page
FOR page, page_start, page_end
    compare_data page * &100
NEXT

    ;; Loop back for the next index (Y) within the page. 16-byte alignment is
    ;; important here to avoid the done branch crossing a page)
    make_aligned
    INY
    BEQ compare_done
    JMP compare_loop
.compare_done

    ;; All the time critical stuff is over now

    ;; Move on to the next pattern
    INX
    CPX #pattern_list_end - pattern_list
    BEQ pass2
    JMP test_loop2

.pass2
    ;; The ACR (bit 5) is used to distingish pass 1 from pass 2
    ;; (pass 1: ACR=0x20; pass 2: ACR=0x00)
    LDA via_acr
    AND #&20
    BEQ success

    ;; Update the screen to show pass 2 (random data)
    out_message row_fixed, msg_random
    out_message row_data, msg_seed

    ;; A will be written to the ACR so VIA T2 is in free-running mode in pass 2
    LDA #&00
    JMP test_loop1

.success
    ;; Yeeehhh! All the tests have passed
    out_message row_result, msg_passed
    JMP halt

.fail
    ;; Boooh! One of the tests has failed, at this point the compare_data macro has set:
    ;; A = high byte of failed address
    ;; Y = low  byte of failed address

    ;; 0123456789abcdef0123456789abcdef
    ;; FAILED AT AAYY
    TAX
    out_hex_y row_result+&0C
    TXA
    TAY
    out_hex_y row_result+&0A

    out_message row_result, msg_failed

.halt
    ;; Loop forever....
    JMP halt

;; ******************************************************************
;; Text Messages
;; ******************************************************************

.msg_title
    EQUS "ATOM RAM TEST"
    EQUB 0

.msg_testing
    EQUS "TESTING #0000-#FFFF"
    EQUB 0

.msg_running
    EQUS "RUNNING FROM #0000"
    EQUB 0

.msg_fixed
    EQUS "PASS 1: FIXED DATA"
    EQUB 0

.msg_random
    EQUS "PASS 2: RANDOM DATA"
    EQUB 0

.msg_data
    EQUS "  DATA: "
    EQUB 0

.msg_seed
    EQUS "  SEED: "
    EQUB 0

.msg_passed
    EQUS "PASSED"
    EQUB 0

.msg_failed
    EQUS "FAILED AT "
    EQUB 0

.msg_irq
    EQUS "IRQ!!"
    EQUB 0

.msg_nmi
    EQUS "NMI!!"
    EQUB 0

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

ORG test_start + &FFA
    EQUW NMI_HANDLER
    EQUW RST_HANDLER
    EQUW IRQ_HANDLER

.test_end

SAVE     test_start - 22, test_end
