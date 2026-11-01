"! <p class="shorttext synchronized">Partner duplicates: Turkish tax numbers (VKN, TCKN)</p>
"! VKN has 10 digits (companies), TCKN 11 digits (persons, also sole
"! proprietors). Only the check digits are calculated; nothing is looked up.
CLASS zcl_che_dupl_tax_id DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Empty if valid, otherwise why not
    CLASS-METHODS check
      IMPORTING
        iv_tax_id         TYPE csequence
      RETURNING
        VALUE(rv_problem) TYPE string.

    CLASS-METHODS is_valid_vkn
      IMPORTING
        iv_vkn          TYPE csequence
      RETURNING
        VALUE(rv_valid) TYPE abap_bool.

    CLASS-METHODS is_valid_tckn
      IMPORTING
        iv_tckn         TYPE csequence
      RETURNING
        VALUE(rv_valid) TYPE abap_bool.

    "! 12345678901 -> 123******01; a TCKN is personal data
    CLASS-METHODS mask
      IMPORTING
        iv_tax_id        TYPE csequence
      RETURNING
        VALUE(rv_masked) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-METHODS digit
      IMPORTING
        iv_text         TYPE csequence
        iv_position     TYPE i
      RETURNING
        VALUE(rv_digit) TYPE i.
ENDCLASS.



CLASS zcl_che_dupl_tax_id IMPLEMENTATION.

  METHOD check.
    DATA(lv_id) = condense( val = iv_tax_id del = ` ` ).
    IF lv_id CN '0123456789'.
      rv_problem = |Tax number { mask( lv_id ) } contains other characters than digits|.
    ELSEIF strlen( lv_id ) = 10.
      IF is_valid_vkn( lv_id ) = abap_false.
        rv_problem = |Tax number (VKN) { mask( lv_id ) }: check digit is wrong|.
      ENDIF.
    ELSEIF strlen( lv_id ) = 11.
      IF is_valid_tckn( lv_id ) = abap_false.
        rv_problem = |Identity number (TCKN) { mask( lv_id ) }: check digits are wrong|.
      ENDIF.
    ELSE.
      rv_problem = |Tax number { mask( lv_id ) } has { strlen( lv_id ) } digits; VKN has 10, TCKN 11|.
    ENDIF.
  ENDMETHOD.


  METHOD is_valid_vkn.
    " For digit i (0 to 8): v = (d + 9 - i) mod 10, p = v * 2^(9 - i) mod 9,
    " p = 9 when v <> 0 and p = 0; the 10th digit is (10 - sum mod 10) mod 10
    IF strlen( iv_vkn ) <> 10 OR iv_vkn CN '0123456789'.
      RETURN.
    ENDIF.
    DATA(lv_sum) = 0.
    DATA(lv_power) = 1024.
    DO 9 TIMES.
      DATA(lv_i) = sy-index - 1.
      lv_power = lv_power DIV 2.
      DATA(lv_v) = ( digit( iv_text = iv_vkn iv_position = lv_i ) + 9 - lv_i ) MOD 10.
      DATA(lv_p) = ( lv_v * lv_power ) MOD 9.
      IF lv_v <> 0 AND lv_p = 0.
        lv_p = 9.
      ENDIF.
      lv_sum = lv_sum + lv_p.
    ENDDO.
    rv_valid = xsdbool( ( 10 - lv_sum MOD 10 ) MOD 10 = digit( iv_text = iv_vkn iv_position = 9 ) ).
  ENDMETHOD.


  METHOD is_valid_tckn.
    " First digit not 0; 10th = (7 * (d1+d3+d5+d7+d9) - (d2+d4+d6+d8)) mod 10;
    " 11th = (d1 + ... + d10) mod 10
    IF strlen( iv_tckn ) <> 11 OR iv_tckn CN '0123456789' OR iv_tckn(1) = '0'.
      RETURN.
    ENDIF.
    DATA(lv_odd) = 0.
    DATA(lv_even) = 0.
    DO 9 TIMES.
      IF sy-index MOD 2 = 1.
        lv_odd = lv_odd + digit( iv_text = iv_tckn iv_position = sy-index - 1 ).
      ELSE.
        lv_even = lv_even + digit( iv_text = iv_tckn iv_position = sy-index - 1 ).
      ENDIF.
    ENDDO.
    " MOD in ABAP is never negative
    DATA(lv_10th) = ( 7 * lv_odd - lv_even ) MOD 10.
    DATA(lv_11th) = ( lv_odd + lv_even + lv_10th ) MOD 10.
    rv_valid = xsdbool( lv_10th = digit( iv_text = iv_tckn iv_position = 9 )
                    AND lv_11th = digit( iv_text = iv_tckn iv_position = 10 ) ).
  ENDMETHOD.


  METHOD mask.
    DATA(lv_len) = strlen( iv_tax_id ).
    IF lv_len <= 5.
      rv_masked = repeat( val = `*` occ = lv_len ).
      RETURN.
    ENDIF.
    rv_masked = substring( val = iv_tax_id len = 3 )
             && repeat( val = `*` occ = lv_len - 5 )
             && substring( val = iv_tax_id off = lv_len - 2 ).
  ENDMETHOD.


  METHOD digit.
    rv_digit = substring( val = iv_text off = iv_position len = 1 ).
  ENDMETHOD.

ENDCLASS.

