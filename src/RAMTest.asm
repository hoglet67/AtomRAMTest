test_start       = &8200

page_start       = &00
page_end         = &7F

via_base         = &B800
via_t2_counter_l = via_base + &08
via_t2_counter_h = via_base + &09
via_acr          = via_base + &0B

;; Macro exactly 16 bytes long

MACRO write_data address
.loop
EOR via_t2_counter_l ; 4
STA address, Y       ; 5
NOP                  ; 2
.next
INY                  ; 2
BNE loop             ; 2/3
JMP done             ; 3
NOP
NOP
NOP
.done

ENDMACRO

;; Macro exactly 16 bytes long

MACRO compare_data address
.loop
EOR via_t2_counter_l ; 4
CMP address, Y       ; 4
BEQ next             ; 3
JMP fail
.next
INY                  ; 2
BNE loop             ; 2/3
.done
BIT &00              ; 3
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

;; reset the stack
    LDX #&FF
    TXS


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
    out_message &8020, msg_fixed
    out_message &8040, msg_data

    LDA #&20        ; pass 1 doesn't use the t1 timer

.test_loop1
    STA via_acr

    LDX #&00        ; iterator for fixed patterns

.test_loop2

    LDA pattern_list, X
    TAY
    out_hex_y &8046

;; Align on a 16 byte boundary to avoid page crossing cycles in inner loops

   JMP aligned
ALIGN &10
.aligned

    NOP
    NOP
    NOP
    NOP
    NOP
    LDA pattern_list, X
    LDY #&00
    STY via_t2_counter_l
    STY via_t2_counter_h

;; Still 16-byte aligned

FOR page, page_start, page_end
    write_data page * &100
NEXT

;; Still 16-byte aligned

    NOP
    NOP
    NOP
    NOP
    NOP
    LDA pattern_list, X
    LDY #&00
    STY via_t2_counter_l
    STY via_t2_counter_h

FOR page, page_start, page_end
    compare_data page * &100
NEXT

    INX
    CPX #pattern_list_end - pattern_list
    BEQ pass2
    JMP test_loop2

.pass2
    LDA via_acr
    AND #&20
    BEQ pass

    out_message &8020, msg_rolling

    LDA #&00
    JMP test_loop1

.pass
    out_message &8060, msg_passed
    JMP halt

.fail
    out_message &8060, msg_failed

.halt
    JMP halt

.msg_title
    EQUS "ATOM RAM TEST"
    EQUB 0

.msg_fixed
    EQUS "PASS 1: FIXED DATA"
    EQUB 0

.msg_rolling
    EQUS "PASS 2: ROLLING DATA"
    EQUB 0

.msg_data
    EQUS "DATA: "
    EQUB 0

.msg_passed
    EQUS "PASSED"
    EQUB 0

.msg_failed
    EQUS "FAILED"
    EQUB 0

.pattern_list
    EQUB &00
    EQUB &FF
    EQUB &55
    EQUB &AA
    EQUB &01
    EQUB &FE
    EQUB &02
    EQUB &FD
    EQUB &04
    EQUB &FB
    EQUB &08
    EQUB &F7
    EQUB &10
    EQUB &EF
    EQUB &20
    EQUB &DF
    EQUB &40
    EQUB &BF
    EQUB &80
    EQUB &7F
.pattern_list_end

.test_end

SAVE    "RAMTEST", test_start - 22, test_end
