test_start       =? &8200

page_start       =? &00
page_end         =? &7F

via_base         = &B800
via_t2_counter_l = via_base + &08
via_t2_counter_h = via_base + &09
via_acr          = via_base + &0B

;; Macro takes 11 cycles
;;
;; Doesn't contain any branches, so alignment doesn't matter

MACRO write_data address
EOR via_t2_counter_l ; 4
STA address, Y       ; 5
NOP                  ; 2
.next

ENDMACRO

;; Macro takes 11 cycles (in the good case)
;;
;; If aligned to xxxB then the branch will not cross a page boundary

MACRO compare_data address
EOR via_t2_counter_l ; 4 +FB
CMP address, Y       ; 4 +FE
BEQ next             ; 3 +01
LDA #>address        ;   +05
JMP fail             ;   +05
NOP                  ;   +08
NOP                  ;   +09
NOP                  ;   +0A
.next
ENDMACRO

MACRO make_aligned
      JMP align
      ALIGN 16
.align
ENDMACRO


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


;; Convert a hex digit in A (00-0F) to Screen ASCII
;; 00->09 => 30->39
;; 0A->0F => 01->06
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

    ORG test_start-22

.atm_header
    EQUS "RAMTEST"
    EQUB 0,0,0,0,0,0,0,0,0
    EQUW test_start
    EQUW test_start
    EQUW (test_end - test_start)

.test
    JMP RST_HANDLER

.IRQ_HANDLER
    out_message &8000, msg_irq
    JMP halt

.NMI_HANDLER
    out_message &8000, msg_nmi
    JMP halt

.RST_HANDLER

;; reset the stack
    LDX #&FF
    TXS

;; disable interrupts
    SEI

;; initialize the hardware (as the Atom Reset handler would)
   LDA #&8A
   STA &B003
   LDA #&07
   STA &B002
   LDA #&00
   STA &B000

;; Clear the screen

    LDA #&20
    LDX #&00
.clear_loop
    STA &8000, X
    STA &8100, X
    INX
    BNE clear_loop

;; Print the fixed data

    out_message &8000, msg_title
    out_message &8040, msg_fixed
    out_message &8060, msg_data

    LDA #&20        ; pass 1 doesn't use the t1 timer

.test_loop1
    STA via_acr

    LDX #&00        ; iterator for fixed patterns

.test_loop2

    LDA pattern_list, X
    TAY
    out_hex_y &8068

    LDA pattern_list, X
    LDY #&00
    STY via_t2_counter_l
    STY via_t2_counter_h

.write_loop

FOR page, page_start, page_end
    write_data page * &100
NEXT

    make_aligned
    INY
    BEQ write_done
    JMP write_loop
.write_done

;; Aligned to xxx0
    make_aligned
    LDA pattern_list, X
    LDY #&00
    STY via_t2_counter_l
    STY via_t2_counter_h
;; Aligned to xxxB

.compare_loop

FOR page, page_start, page_end
    compare_data page * &100
NEXT

    make_aligned
    INY
    BEQ compare_done
    JMP compare_loop
.compare_done

    INX
    CPX #pattern_list_end - pattern_list
    BEQ pass2
    JMP test_loop2

.pass2
    LDA via_acr
    AND #&20
    BEQ pass

    out_message &8040, msg_random
    out_message &8060, msg_seed

    LDA #&00
    JMP test_loop1

.pass
    out_message &80A0, msg_passed
    JMP halt

.fail
    ;; A = high byte of failed address
    ;; Y = low byte of failed address

    ;;                 A C
    ;; 8060: FAILED AT AAYY
    TAX
    out_hex_y &80AC
    TXA
    TAY
    out_hex_y &80AA

    out_message &80A0, msg_failed

.halt
    JMP halt

.msg_title
    EQUS "ATOM RAM TEST"
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


ORG test_start + &FFA
    EQUW NMI_HANDLER
    EQUW RST_HANDLER
    EQUW IRQ_HANDLER

.test_end

SAVE    "", test_start - 22, test_end
