*&---------------------------------------------------------------------*
*& ZCHE_DUPL_FIND: find likely duplicate business partners
*& abap-partner-duplicates 0.4.0, https://github.com/Cheditte/abap-partner-duplicates
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: SE38, create executable program ZCHE_DUPL_FIND, paste this
*& source, configure authorization object ZCHE_DUPL, then activate.
*& No project-specific DDIC tables or text elements are required.
*& Classic ABAP 7.00 syntax; verify APIs and runtime on the target system.
*&
*& Reads only; nothing is merged, blocked or deleted. Settings are on the
*& selection screen; save them as a variant to reuse them or to run the
*& program as a background job. In the list, click "Duplicate" or "Not
*& dup." to record a decision; pairs marked "not a duplicate" are hidden
*& in later runs. Decisions are kept in the standard table INDX
*& (area ZC, ID ZCHE_DUPL_DECISIONS).
*&
*& Another source of partners (for example LFA1/KNA1 without BP): change
*& class LCL_SOURCE_BP.
*&---------------------------------------------------------------------*
REPORT zche_dupl_find.

TYPE-POOLS: abap, icon.

DATA gv_word TYPE c LENGTH 40.
DATA gv_problem TYPE string.

SELECTION-SCREEN BEGIN OF BLOCK b_read WITH FRAME TITLE t_read.
PARAMETERS p_role TYPE bu_partnerrole.
PARAMETERS p_group TYPE bu_group.
PARAMETERS p_cntry TYPE land1.
PARAMETERS p_taxty TYPE bptaxtype DEFAULT 'TR2'.
PARAMETERS p_keydt TYPE d DEFAULT sy-datum OBLIGATORY.
PARAMETERS p_taxchk AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b_read.

SELECTION-SCREEN BEGIN OF BLOCK b_rule WITH FRAME TITLE t_rule.
SELECTION-SCREEN COMMENT /1(75) t_hint.
PARAMETERS p_wtax TYPE i DEFAULT 95.
PARAMETERS p_wiban TYPE i DEFAULT 90.
PARAMETERS p_wname TYPE i DEFAULT 70.
PARAMETERS p_minsim TYPE i DEFAULT 85.
PARAMETERS p_waddr TYPE i DEFAULT 50.
PARAMETERS p_wphone TYPE i DEFAULT 40.
PARAMETERS p_wmail TYPE i DEFAULT 40.
PARAMETERS p_thresh TYPE i DEFAULT 60.
PARAMETERS p_maxblk TYPE i DEFAULT 200.
SELECT-OPTIONS s_stop FOR gv_word NO INTERVALS LOWER CASE.
SELECTION-SCREEN END OF BLOCK b_rule.

SELECTION-SCREEN BEGIN OF BLOCK b_out WITH FRAME TITLE t_out.
PARAMETERS p_unmask AS CHECKBOX.
PARAMETERS p_decid AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b_out.
DATA gs_stop LIKE LINE OF s_stop.


*----------------------------------------------------------------------*
* Types and constants
*----------------------------------------------------------------------*
INTERFACE lif_dupl.
  CONSTANTS version TYPE string VALUE `0.4.0`.

  TYPES ty_rule TYPE c LENGTH 10.
  TYPES ty_decision_code TYPE c LENGTH 1.
  TYPES ty_finding TYPE c LENGTH 14.

  " Rules: each one gives evidence that two partners are the same
  CONSTANTS:
    BEGIN OF rule,
      tax_id  TYPE ty_rule VALUE 'TAX_ID',
      iban    TYPE ty_rule VALUE 'IBAN',
      name    TYPE ty_rule VALUE 'NAME',
      address TYPE ty_rule VALUE 'ADDRESS',
      phone   TYPE ty_rule VALUE 'PHONE',
      email   TYPE ty_rule VALUE 'EMAIL',
    END OF rule.

  CONSTANTS:
    BEGIN OF decision,
      duplicate     TYPE ty_decision_code VALUE 'D',
      not_duplicate TYPE ty_decision_code VALUE 'N',
    END OF decision.

  CONSTANTS:
    BEGIN OF finding,
      duplicate      TYPE ty_finding VALUE 'DUPLICATE',
      invalid_tax_id TYPE ty_finding VALUE 'INVALID_TAX_ID',
    END OF finding.

  TYPES ty_strings TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_address,
      country   TYPE land1,
      post_code TYPE string,
      city      TYPE string,
      street    TYPE string,
      house_no  TYPE string,
    END OF ty_address,
    ty_addresses TYPE STANDARD TABLE OF ty_address WITH DEFAULT KEY.

  " One partner as the source delivers it, before normalization
  TYPES:
    BEGIN OF ty_partner,
      partner   TYPE bu_partner,
      name      TYPE string,
      tax_ids   TYPE ty_strings,
      ibans     TYPE ty_strings,
      addresses TYPE ty_addresses,
      phones    TYPE ty_strings,
      emails    TYPE ty_strings,
    END OF ty_partner,
    ty_partners TYPE STANDARD TABLE OF ty_partner WITH DEFAULT KEY.

  " WEIGHT: how sure this rule alone makes us (0 to 100, 0 = rule off)
  " MIN_SIMILARITY: only for NAME, the lowest similarity that counts
  TYPES:
    BEGIN OF ty_rule_setting,
      rule           TYPE ty_rule,
      weight         TYPE i,
      min_similarity TYPE i,
    END OF ty_rule_setting,
    ty_rule_settings TYPE SORTED TABLE OF ty_rule_setting WITH UNIQUE KEY rule.

  " Everything from the selection screen
  TYPES:
    BEGIN OF ty_settings,
      tax_type   TYPE bptaxtype,
      bp_role    TYPE bu_partnerrole,
      bp_group   TYPE bu_group,
      country    TYPE land1,
      key_date   TYPE d,
      tax_check  TYPE abap_bool,
      rules      TYPE ty_rule_settings,
      threshold  TYPE i,
      max_block  TYPE i,
      stop_words TYPE ty_strings,
      unmask     TYPE abap_bool,
    END OF ty_settings.

  " One result line: a likely duplicate pair, or a partner with an invalid tax number
  TYPES:
    BEGIN OF ty_line,
      finding  TYPE ty_finding,
      score    TYPE i,
      partner1 TYPE bu_partner,
      name1    TYPE string,
      partner2 TYPE bu_partner,
      name2    TYPE string,
      reasons  TYPE string,
      decision TYPE ty_decision_code,
    END OF ty_line,
    ty_lines TYPE STANDARD TABLE OF ty_line WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_result,
      lines          TYPE ty_lines,
      partners       TYPE i,
      skipped_blocks TYPE ty_strings,
      hidden_pairs   TYPE i,
    END OF ty_result.

  " A recorded decision; PARTNER1 is the smaller number
  TYPES:
    BEGIN OF ty_decision,
      partner1   TYPE bu_partner,
      partner2   TYPE bu_partner,
      decision   TYPE ty_decision_code,
      changed_by TYPE syuname,
      changed_at TYPE timestamp,
    END OF ty_decision,
    ty_decisions TYPE SORTED TABLE OF ty_decision WITH UNIQUE KEY partner1 partner2.
ENDINTERFACE.

DATA gs_settings TYPE lif_dupl=>ty_settings.


*----------------------------------------------------------------------*
* Error: the text says what is wrong and who can fix it
*----------------------------------------------------------------------*
CLASS lcx_error DEFINITION INHERITING FROM cx_static_check FINAL.
  PUBLIC SECTION.
    DATA text TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING
        text     TYPE string OPTIONAL
        previous TYPE REF TO cx_root OPTIONAL.

    METHODS if_message~get_text REDEFINITION.
ENDCLASS.


CLASS lcx_error IMPLEMENTATION.

  METHOD constructor.
    super->constructor( previous = previous ).
    me->text = text.
  ENDMETHOD.


  METHOD if_message~get_text.
    result = text.
    IF result IS INITIAL.
      result = super->if_message~get_text( ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* Texts for the screen and the list: Turkish when the user is logged on
* in Turkish, English otherwise. The program needs no text elements.
*----------------------------------------------------------------------*
CLASS lcl_text DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS get
      IMPORTING
        iv_en          TYPE csequence
        iv_tr          TYPE csequence
      RETURNING
        value(rv_text) TYPE string.

    "! A number as text, without blanks or thousands separators
    CLASS-METHODS num
      IMPORTING
        iv_number      TYPE i
      RETURNING
        value(rv_text) TYPE string.

    CLASS-METHODS set_selection_texts.

  PRIVATE SECTION.
    CLASS-METHODS add
      IMPORTING
        iv_name  TYPE csequence
        iv_kind  TYPE c
        iv_en    TYPE csequence
        iv_tr    TYPE csequence
      CHANGING
        ct_texts TYPE STANDARD TABLE.
ENDCLASS.


CLASS lcl_text IMPLEMENTATION.

  METHOD get.
    IF sy-langu = 'T'.
      rv_text = iv_tr.
    ELSE.
      rv_text = iv_en.
    ENDIF.
  ENDMETHOD.


  METHOD num.
    DATA lv_text TYPE c LENGTH 12.
    WRITE iv_number TO lv_text LEFT-JUSTIFIED NO-GROUPING.
    rv_text = lv_text.
  ENDMETHOD.


  METHOD add.
    DATA ls_text TYPE rsseltexts.
    ls_text-name = iv_name.
    ls_text-kind = iv_kind.
    ls_text-text = get( iv_en = iv_en iv_tr = iv_tr ).
    APPEND ls_text TO ct_texts.
  ENDMETHOD.


  METHOD set_selection_texts.
    " The function module needs exactly this table type (default key)
    DATA lt_texts TYPE STANDARD TABLE OF rsseltexts WITH DEFAULT KEY.

    t_read = get( iv_en = 'Which partners' iv_tr = 'Hangi cariler' ).
    t_rule = get( iv_en = 'Rules' iv_tr = 'Kurallar' ).
    t_out = get( iv_en = 'Output' iv_tr = 'Çıktı' ).
    t_hint = get( iv_en = 'Weight 0-100: how sure one rule alone makes a pair. 0 = rule off.'
                  iv_tr = 'Ağırlık 0-100: kural tek başına çifti ne kadar kesinleştirir. 0 = kapalı.' ).

    " Texts longer than 30 characters are cut on the screen
    add( EXPORTING iv_name = 'P_ROLE'   iv_kind = 'P' iv_en = 'BP role (empty = all)'
                   iv_tr = 'İş ortağı rolü (boş = tümü)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_GROUP'  iv_kind = 'P' iv_en = 'BP grouping (empty = all)'
                   iv_tr = 'Gruplama (boş = tümü)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_CNTRY'  iv_kind = 'P' iv_en = 'Country (empty = all)'
                   iv_tr = 'Ülke (boş = tümü)' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_TAXTY'  iv_kind = 'P' iv_en = 'Tax number category'
                   iv_tr = 'Vergi numarası kategorisi' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_KEYDT' iv_kind = 'P' iv_en = 'Master-data reference date'
                   iv_tr = 'Ana veri referans tarihi' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_TAXCHK' iv_kind = 'P' iv_en = 'Check Turkish VKN/TCKN'
                   iv_tr = 'Türk VKN/TCKN kontrolü' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_WTAX'   iv_kind = 'P' iv_en = 'Weight: same tax number'
                   iv_tr = 'Ağırlık: aynı vergi no' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_WIBAN'  iv_kind = 'P' iv_en = 'Weight: same IBAN'
                   iv_tr = 'Ağırlık: aynı IBAN' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_WNAME'  iv_kind = 'P' iv_en = 'Weight: similar name'
                   iv_tr = 'Ağırlık: benzer isim' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_MINSIM' iv_kind = 'P' iv_en = 'Name similar at least (%)'
                   iv_tr = 'İsim en az % kaç benzer' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_WADDR'  iv_kind = 'P' iv_en = 'Weight: same address'
                   iv_tr = 'Ağırlık: aynı adres' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_WPHONE' iv_kind = 'P' iv_en = 'Weight: same phone'
                   iv_tr = 'Ağırlık: aynı telefon' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_WMAIL'  iv_kind = 'P' iv_en = 'Weight: same e-mail'
                   iv_tr = 'Ağırlık: aynı e-posta' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_THRESH' iv_kind = 'P' iv_en = 'Show pairs from score'
                   iv_tr = 'Gösterilecek en düşük puan' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_MAXBLK' iv_kind = 'P' iv_en = 'Max. partners per key'
                   iv_tr = 'Anahtar başına en çok cari' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_UNMASK' iv_kind = 'P' iv_en = 'Show full tax numbers'
                   iv_tr = 'Vergi no ve IBAN tam görünsün' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'P_DECID'  iv_kind = 'P' iv_en = 'Show decided pairs'
                   iv_tr = 'Karar verilmiş çiftleri göster' CHANGING ct_texts = lt_texts ).
    add( EXPORTING iv_name = 'S_STOP'   iv_kind = 'S' iv_en = 'Extra words to ignore'
                   iv_tr = 'Yok sayılacak ek kelimeler' CHANGING ct_texts = lt_texts ).

    CALL FUNCTION 'SELECTION_TEXTS_MODIFY'
      EXPORTING
        program                     = sy-repid
      TABLES
        seltexts                    = lt_texts
      EXCEPTIONS
        program_not_found           = 1
        program_cannot_be_generated = 2
        OTHERS                      = 3.
    IF sy-subrc <> 0.                                       "#EC NEEDED
      " Without texts the screen still works; it shows the field names
    ENDIF.
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* Turkish tax numbers (VKN, TCKN). VKN has 10 digits (companies), TCKN
* 11 digits (persons, also sole proprietors). Only the check digits are
* calculated; nothing is looked up.
*----------------------------------------------------------------------*
CLASS lcl_tax_id DEFINITION FINAL.
  PUBLIC SECTION.
    "! Empty if valid, otherwise why not
    CLASS-METHODS check
      IMPORTING
        iv_tax_id         TYPE csequence
      RETURNING
        value(rv_problem) TYPE string.

    CLASS-METHODS is_valid_vkn
      IMPORTING
        iv_vkn          TYPE csequence
      RETURNING
        value(rv_valid) TYPE abap_bool.

    CLASS-METHODS is_valid_tckn
      IMPORTING
        iv_tckn         TYPE csequence
      RETURNING
        value(rv_valid) TYPE abap_bool.

    "! 12345678901 -> 123******01; a TCKN is personal data
    CLASS-METHODS mask
      IMPORTING
        iv_tax_id        TYPE csequence
      RETURNING
        value(rv_masked) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS digit
      IMPORTING
        iv_text         TYPE csequence
        iv_position     TYPE i
      RETURNING
        value(rv_digit) TYPE i.
ENDCLASS.


CLASS lcl_tax_id IMPLEMENTATION.

  METHOD check.
    DATA lv_id TYPE string.
    DATA lv_masked TYPE string.
    DATA lv_len TYPE i.
    DATA lv_count TYPE string.

    lv_id = iv_tax_id.
    CONDENSE lv_id.
    lv_masked = mask( lv_id ).
    lv_len = strlen( lv_id ).
    IF lv_id CN '0123456789'.
      CONCATENATE `Tax number ` lv_masked ` contains other characters than digits` INTO rv_problem.
    ELSEIF lv_len = 10.
      IF is_valid_vkn( lv_id ) = abap_false.
        CONCATENATE `Tax number (VKN) ` lv_masked `: check digit is wrong` INTO rv_problem.
      ENDIF.
    ELSEIF lv_len = 11.
      IF is_valid_tckn( lv_id ) = abap_false.
        CONCATENATE `Identity number (TCKN) ` lv_masked `: check digits are wrong` INTO rv_problem.
      ENDIF.
    ELSE.
      lv_count = lcl_text=>num( lv_len ).
      CONCATENATE `Tax number ` lv_masked ` has ` lv_count ` digits; VKN has 10, TCKN 11` INTO rv_problem.
    ENDIF.
  ENDMETHOD.


  METHOD is_valid_vkn.
    " For digit i (0 to 8): v = (d + 9 - i) mod 10, p = v * 2^(9 - i) mod 9,
    " p = 9 when v <> 0 and p = 0; the 10th digit is (10 - sum mod 10) mod 10
    DATA lv_sum TYPE i.
    DATA lv_power TYPE i VALUE 1024.
    DATA lv_i TYPE i.
    DATA lv_v TYPE i.
    DATA lv_p TYPE i.
    DATA lv_check TYPE i.

    rv_valid = abap_false.
    IF strlen( iv_vkn ) <> 10 OR iv_vkn CN '0123456789'.
      RETURN.
    ENDIF.
    DO 9 TIMES.
      lv_i = sy-index - 1.
      lv_power = lv_power DIV 2.
      lv_v = ( digit( iv_text = iv_vkn iv_position = lv_i ) + 9 - lv_i ) MOD 10.
      lv_p = ( lv_v * lv_power ) MOD 9.
      IF lv_v <> 0 AND lv_p = 0.
        lv_p = 9.
      ENDIF.
      lv_sum = lv_sum + lv_p.
    ENDDO.
    lv_check = ( 10 - lv_sum MOD 10 ) MOD 10.
    IF lv_check = digit( iv_text = iv_vkn iv_position = 9 ).
      rv_valid = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD is_valid_tckn.
    " First digit not 0; 10th = (7 * (d1+d3+d5+d7+d9) - (d2+d4+d6+d8)) mod 10;
    " 11th = (d1 + ... + d10) mod 10
    DATA lv_odd TYPE i.
    DATA lv_even TYPE i.
    DATA lv_position TYPE i.
    DATA lv_10th TYPE i.
    DATA lv_11th TYPE i.

    rv_valid = abap_false.
    IF strlen( iv_tckn ) <> 11 OR iv_tckn CN '0123456789' OR iv_tckn(1) = '0'.
      RETURN.
    ENDIF.
    DO 9 TIMES.
      lv_position = sy-index - 1.
      IF sy-index MOD 2 = 1.
        lv_odd = lv_odd + digit( iv_text = iv_tckn iv_position = lv_position ).
      ELSE.
        lv_even = lv_even + digit( iv_text = iv_tckn iv_position = lv_position ).
      ENDIF.
    ENDDO.
    " MOD in ABAP is never negative
    lv_10th = ( 7 * lv_odd - lv_even ) MOD 10.
    lv_11th = ( lv_odd + lv_even + lv_10th ) MOD 10.
    IF lv_10th = digit( iv_text = iv_tckn iv_position = 9 )
        AND lv_11th = digit( iv_text = iv_tckn iv_position = 10 ).
      rv_valid = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD mask.
    DATA lv_text TYPE string.
    DATA lv_len TYPE i.
    DATA lv_stars TYPE i.
    DATA lv_last TYPE i.

    lv_text = iv_tax_id.
    lv_len = strlen( lv_text ).
    IF lv_len <= 5.
      lv_stars = lv_len.
    ELSE.
      rv_masked = lv_text(3).
      lv_stars = lv_len - 5.
    ENDIF.
    DO lv_stars TIMES.
      CONCATENATE rv_masked '*' INTO rv_masked.
    ENDDO.
    IF lv_len > 5.
      lv_last = lv_len - 2.
      CONCATENATE rv_masked lv_text+lv_last(2) INTO rv_masked.
    ENDIF.
  ENDMETHOD.


  METHOD digit.
    DATA lv_text TYPE string.
    lv_text = iv_text.
    rv_digit = lv_text+iv_position(1).
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* Normalizes names, phones, e-mails and addresses. Case conversion of
* i/I depends on the language (Turkish has i/İ and ı/I), so Turkish
* letters are folded to A-Z with an own table first and the result does
* not depend on the logon language.
*----------------------------------------------------------------------*
CLASS lcl_normalizer DEFINITION FINAL.
  PUBLIC SECTION.
    "! Legal forms and generic trade words, always ignored in names
    CLASS-METHODS default_words
      RETURNING
        value(rt_words) TYPE lif_dupl=>ty_strings.

    "! Free mail providers: the same domain says nothing about the company
    CLASS-METHODS free_mail_domains
      RETURNING
        value(rt_domains) TYPE lif_dupl=>ty_strings.

    "! IT_EXTRA_WORDS are ignored in names in addition to the default words
    METHODS constructor
      IMPORTING
        it_extra_words TYPE lif_dupl=>ty_strings OPTIONAL.

    "! Upper case A-Z and 0-9 only, Turkish letters folded, single spaces
    METHODS simplify
      IMPORTING
        iv_text        TYPE csequence
      RETURNING
        value(rv_text) TYPE string.

    "! Meaningful words of a name, sorted, without legal forms and one-letter words
    METHODS name_tokens
      IMPORTING
        iv_name          TYPE csequence
      RETURNING
        value(rt_tokens) TYPE lif_dupl=>ty_strings.

    METHODS digits
      IMPORTING
        iv_text          TYPE csequence
      RETURNING
        value(rv_digits) TYPE string.

    "! Last 10 digits, so 0212..., +90 212... and 212... are equal; empty below 7 digits
    METHODS phone_key
      IMPORTING
        iv_phone      TYPE csequence
      RETURNING
        value(rv_key) TYPE string.

    METHODS email_key
      IMPORTING
        iv_email      TYPE csequence
      RETURNING
        value(rv_key) TYPE string.

    "! Domain of a company address; empty for free mail providers
    METHODS email_domain
      IMPORTING
        iv_email         TYPE csequence
      RETURNING
        value(rv_domain) TYPE string.

    METHODS tax_key
      IMPORTING
        iv_tax_id     TYPE csequence
      RETURNING
        value(rv_key) TYPE string.

    METHODS iban_key
      IMPORTING
        iv_iban       TYPE csequence
      RETURNING
        value(rv_key) TYPE string.

    "! Country, post code (or city) and street with house number; empty without street
    METHODS address_key
      IMPORTING
        is_address    TYPE lif_dupl=>ty_address
      RETURNING
        value(rv_key) TYPE string.

  PRIVATE SECTION.
    CONSTANTS turkish_letters TYPE string VALUE `çCÇCğGĞGıIiIİIöOÖOşSŞSüUÜUâAÂAîIÎIûUÛUéEÉE`.
    DATA mt_stop_words TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.
ENDCLASS.


CLASS lcl_normalizer IMPLEMENTATION.

  METHOD constructor.
    DATA lt_words TYPE lif_dupl=>ty_strings.
    DATA lt_parts TYPE lif_dupl=>ty_strings.
    DATA lv_word TYPE string.
    DATA lv_part TYPE string.

    lt_words = default_words( ).
    APPEND LINES OF it_extra_words TO lt_words.
    LOOP AT lt_words INTO lv_word.
      lv_word = simplify( lv_word ).
      SPLIT lv_word AT space INTO TABLE lt_parts.
      LOOP AT lt_parts INTO lv_part WHERE table_line IS NOT INITIAL.
        INSERT lv_part INTO TABLE mt_stop_words.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD simplify.
    " Long enough for any name or address line; longer input is cut
    DATA lv_buffer TYPE c LENGTH 1000.
    DATA lv_text TYPE string.
    DATA lv_len TYPE i.
    DATA lv_offset TYPE i.

    lv_text = iv_text.
    TRANSLATE lv_text USING turkish_letters.
    TRANSLATE lv_text TO UPPER CASE.
    lv_buffer = lv_text.
    lv_len = strlen( lv_buffer ).
    DO lv_len TIMES.
      lv_offset = sy-index - 1.
      IF lv_buffer+lv_offset(1) CN sy-abcde AND lv_buffer+lv_offset(1) CN '0123456789'.
        lv_buffer+lv_offset(1) = space.
      ENDIF.
    ENDDO.
    CONDENSE lv_buffer.
    rv_text = lv_buffer.
  ENDMETHOD.


  METHOD name_tokens.
    DATA lt_words TYPE lif_dupl=>ty_strings.
    DATA lv_word TYPE string.
    DATA lv_simple TYPE string.

    lv_simple = simplify( iv_name ).
    SPLIT lv_simple AT space INTO TABLE lt_words.
    LOOP AT lt_words INTO lv_word.
      IF strlen( lv_word ) > 1.
        READ TABLE mt_stop_words WITH TABLE KEY table_line = lv_word TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND lv_word TO rt_tokens.
        ENDIF.
      ENDIF.
    ENDLOOP.
    SORT rt_tokens BY table_line.
    DELETE ADJACENT DUPLICATES FROM rt_tokens COMPARING ALL FIELDS.
  ENDMETHOD.


  METHOD default_words.
    DATA lv_words TYPE string.
    CONCATENATE `AS ANONIM SIRKETI SIRKET LTD STI LIMITED SAN SANAYI TIC TICARET VE ITH IHR`
                ` ITHALAT IHRACAT PAZ PAZARLAMA INS INSAAT TAAH TAAHHUT KOLL KOM KOMANDIT`
                ` KOOP KOOPERATIFI DIS IC INC CORP CO COMPANY LLC PLC GMBH AG SA`
           INTO lv_words.
    SPLIT lv_words AT space INTO TABLE rt_words.
  ENDMETHOD.


  METHOD free_mail_domains.
    DATA lv_domains TYPE string.
    CONCATENATE `gmail.com hotmail.com hotmail.com.tr outlook.com outlook.com.tr live.com msn.com`
                ` yahoo.com yahoo.com.tr yandex.com yandex.com.tr icloud.com me.com mynet.com`
                ` windowslive.com gmx.de web.de proton.me protonmail.com`
           INTO lv_domains.
    SPLIT lv_domains AT space INTO TABLE rt_domains.
  ENDMETHOD.


  METHOD digits.
    DATA lv_text TYPE string.
    DATA lv_len TYPE i.
    DATA lv_offset TYPE i.

    lv_text = iv_text.
    lv_len = strlen( lv_text ).
    DO lv_len TIMES.
      lv_offset = sy-index - 1.
      IF lv_text+lv_offset(1) CO '0123456789'.
        CONCATENATE rv_digits lv_text+lv_offset(1) INTO rv_digits.
      ENDIF.
    ENDDO.
  ENDMETHOD.


  METHOD phone_key.
    DATA lv_digits TYPE string.
    DATA lv_len TYPE i.
    DATA lv_offset TYPE i.

    lv_digits = digits( iv_phone ).
    lv_len = strlen( lv_digits ).
    IF lv_len < 7.
      RETURN.
    ENDIF.
    IF lv_len > 10.
      lv_offset = lv_len - 10.
      rv_key = lv_digits+lv_offset.
    ELSE.
      rv_key = lv_digits.
    ENDIF.
  ENDMETHOD.


  METHOD email_key.
    rv_key = iv_email.
    CONDENSE rv_key.
    TRANSLATE rv_key TO LOWER CASE.
    IF rv_key NS '@'.
      CLEAR rv_key.
    ENDIF.
  ENDMETHOD.


  METHOD email_domain.
    DATA lv_email TYPE string.
    DATA lv_local TYPE string.
    DATA lt_public TYPE lif_dupl=>ty_strings.

    lv_email = email_key( iv_email ).
    IF lv_email IS INITIAL.
      RETURN.
    ENDIF.
    SPLIT lv_email AT '@' INTO lv_local rv_domain.
    IF rv_domain IS INITIAL.
      RETURN.
    ENDIF.
    lt_public = free_mail_domains( ).
    READ TABLE lt_public WITH KEY table_line = rv_domain TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      CLEAR rv_domain.
    ENDIF.
  ENDMETHOD.


  METHOD iban_key.
    rv_key = iv_iban.
    CONDENSE rv_key NO-GAPS.
    TRANSLATE rv_key TO UPPER CASE.
  ENDMETHOD.


  METHOD address_key.
    " CADDESI, CADDE, CAD and CD are the same street word; so are SOKAK/SOKAGI/SOK/SK, ...
    DATA lt_words TYPE lif_dupl=>ty_strings.
    DATA lv_word TYPE string.
    DATA lv_street TYPE string.
    DATA lv_street_input TYPE string.
    DATA lv_place TYPE string.
    DATA lv_text TYPE string.

    lv_street_input = simplify( is_address-street ).
    IF lv_street_input IS INITIAL.
      RETURN.
    ENDIF.
    CONCATENATE is_address-street is_address-house_no INTO lv_text SEPARATED BY space.
    lv_text = simplify( lv_text ).
    SPLIT lv_text AT space INTO TABLE lt_words.
    LOOP AT lt_words INTO lv_word.
      CASE lv_word.
        WHEN `CADDESI` OR `CADDE` OR `CAD`.
          lv_word = `CD`.
        WHEN `SOKAK` OR `SOKAGI` OR `SOK`.
          lv_word = `SK`.
        WHEN `MAHALLESI` OR `MAHALLE` OR `MAH`.
          lv_word = `MH`.
        WHEN `BULVARI` OR `BULVAR` OR `BUL`.
          lv_word = `BLV`.
        WHEN `NO` OR `NUMARA`.
          CLEAR lv_word.
      ENDCASE.
      IF lv_word IS INITIAL.
        CONTINUE.
      ENDIF.
      IF lv_street IS INITIAL.
        lv_street = lv_word.
      ELSE.
        CONCATENATE lv_street lv_word INTO lv_street SEPARATED BY space.
      ENDIF.
    ENDLOOP.
    IF lv_street IS INITIAL.
      RETURN.
    ENDIF.
    lv_place = simplify( is_address-post_code ).
    IF lv_place IS INITIAL.
      lv_place = simplify( is_address-city ).
    ENDIF.
    CONCATENATE is_address-country '/' lv_place '/' lv_street INTO rv_key.
  ENDMETHOD.

  METHOD tax_key.
    rv_key = simplify( iv_tax_id ).
    CONDENSE rv_key NO-GAPS.
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* Finds and scores likely duplicate pairs. No database access, so
* everything here is covered by unit tests.
*
* Each rule that fires gives evidence c (0 to 100); evidence is combined
* as score = 100 * (1 - (1 - c1/100) * (1 - c2/100) * ...), so two weak
* signals together count more than one, and the score never exceeds 100.
*
* Only partners that share a key are compared ("blocking"): tax number,
* IBAN, address, phone, e-mail, e-mail domain, the first three letters of
* the first name word and the longest name word. A key shared by more than
* MAX_BLOCK partners is skipped and reported, so one common word cannot
* make the run compare everybody with everybody.
*----------------------------------------------------------------------*
CLASS ltc_matcher DEFINITION DEFERRED.
CLASS lcl_matcher DEFINITION FINAL FRIENDS ltc_matcher.
  PUBLIC SECTION.
    CONSTANTS default_threshold TYPE i VALUE 60.
    CONSTANTS default_max_block TYPE i VALUE 200.

    CLASS-METHODS default_rules
      RETURNING
        value(rt_rules) TYPE lif_dupl=>ty_rule_settings.

    "! Edit distance (Levenshtein): fewest single-letter changes from one text to the other
    CLASS-METHODS edit_distance
      IMPORTING
        iv_text1           TYPE string
        iv_text2           TYPE string
      RETURNING
        value(rv_distance) TYPE i.

    "! IT_RULES overrides the defaults rule by rule
    METHODS constructor
      IMPORTING
        it_rules      TYPE lif_dupl=>ty_rule_settings OPTIONAL
        io_normalizer TYPE REF TO lcl_normalizer OPTIONAL
        iv_threshold  TYPE i DEFAULT default_threshold
        iv_max_block  TYPE i DEFAULT default_max_block
        iv_unmask     TYPE abap_bool DEFAULT abap_false.

    METHODS find
      IMPORTING
        it_partners      TYPE lif_dupl=>ty_partners
      RETURNING
        value(rs_result) TYPE lif_dupl=>ty_result.

    "! 0 to 100; the better of edit distance and shared words
    METHODS similarity
      IMPORTING
        it_tokens1        TYPE lif_dupl=>ty_strings
        it_tokens2        TYPE lif_dupl=>ty_strings
      RETURNING
        value(rv_percent) TYPE i.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_prepared,
        partner   TYPE bu_partner,
        name      TYPE string,
        tokens    TYPE lif_dupl=>ty_strings,
        tax_ids   TYPE lif_dupl=>ty_strings,
        ibans     TYPE lif_dupl=>ty_strings,
        addresses TYPE lif_dupl=>ty_strings,
        phones    TYPE lif_dupl=>ty_strings,
        emails    TYPE lif_dupl=>ty_strings,
        domains   TYPE lif_dupl=>ty_strings,
      END OF ty_prepared,
      ty_prepared_tab TYPE STANDARD TABLE OF ty_prepared WITH DEFAULT KEY.

    TYPES ty_indexes TYPE STANDARD TABLE OF i WITH DEFAULT KEY.
    TYPES:
      BEGIN OF ty_block,
        key     TYPE string,
        members      TYPE ty_indexes,
        member_count TYPE i,
        last_index   TYPE i,
      END OF ty_block,
      ty_blocks TYPE HASHED TABLE OF ty_block WITH UNIQUE KEY key.

    TYPES:
      BEGIN OF ty_candidate,
        index1 TYPE i,
        index2 TYPE i,
      END OF ty_candidate,
      ty_candidates TYPE HASHED TABLE OF ty_candidate WITH UNIQUE KEY index1 index2.

    DATA mt_rules TYPE lif_dupl=>ty_rule_settings.
    DATA mo_normalizer TYPE REF TO lcl_normalizer.
    DATA mv_threshold TYPE i.
    DATA mv_max_block TYPE i.
    DATA mv_unmask TYPE abap_bool.

    METHODS prepare
      IMPORTING
        is_partner         TYPE lif_dupl=>ty_partner
      RETURNING
        value(rs_prepared) TYPE ty_prepared.

    METHODS add_keys
      IMPORTING
        is_prepared TYPE ty_prepared
        iv_index    TYPE i
      CHANGING
        ct_blocks   TYPE ty_blocks.

    METHODS add_key
      IMPORTING
        iv_prefix TYPE c
        iv_value  TYPE string
        iv_index  TYPE i
      CHANGING
        ct_blocks TYPE ty_blocks.

    METHODS score
      IMPORTING
        is_one         TYPE ty_prepared
        is_other       TYPE ty_prepared
      RETURNING
        value(rs_line) TYPE lif_dupl=>ty_line.

    METHODS weight
      IMPORTING
        iv_rule          TYPE lif_dupl=>ty_rule
      RETURNING
        value(rv_weight) TYPE i.

    METHODS common
      IMPORTING
        it_values       TYPE lif_dupl=>ty_strings
        it_others       TYPE lif_dupl=>ty_strings
      RETURNING
        value(rv_value) TYPE string.

    METHODS show
      IMPORTING
        iv_value       TYPE string
      RETURNING
        value(rv_text) TYPE string.

    METHODS describe_key
      IMPORTING
        iv_key         TYPE string
        iv_count       TYPE i
      RETURNING
        value(rv_text) TYPE string.
ENDCLASS.


CLASS lcl_matcher IMPLEMENTATION.

  METHOD default_rules.
    DATA ls_rule TYPE lif_dupl=>ty_rule_setting.

    ls_rule-rule = lif_dupl=>rule-tax_id.
    ls_rule-weight = 95.
    INSERT ls_rule INTO TABLE rt_rules.
    ls_rule-rule = lif_dupl=>rule-iban.
    ls_rule-weight = 90.
    INSERT ls_rule INTO TABLE rt_rules.
    ls_rule-rule = lif_dupl=>rule-name.
    ls_rule-weight = 70.
    ls_rule-min_similarity = 85.
    INSERT ls_rule INTO TABLE rt_rules.
    CLEAR ls_rule-min_similarity.
    ls_rule-rule = lif_dupl=>rule-address.
    ls_rule-weight = 50.
    INSERT ls_rule INTO TABLE rt_rules.
    ls_rule-rule = lif_dupl=>rule-phone.
    ls_rule-weight = 40.
    INSERT ls_rule INTO TABLE rt_rules.
    ls_rule-rule = lif_dupl=>rule-email.
    ls_rule-weight = 40.
    INSERT ls_rule INTO TABLE rt_rules.
  ENDMETHOD.


  METHOD edit_distance.
    " Two rows of the classic table: the previous and the current letter of text 1
    DATA lt_previous TYPE STANDARD TABLE OF i WITH DEFAULT KEY.
    DATA lt_current TYPE STANDARD TABLE OF i WITH DEFAULT KEY.
    DATA lv_len1 TYPE i.
    DATA lv_len2 TYPE i.
    DATA lv_i TYPE i.
    DATA lv_j TYPE i.
    DATA lv_offset1 TYPE i.
    DATA lv_offset2 TYPE i.
    DATA lv_cost TYPE i.
    DATA lv_value TYPE i.
    DATA lv_best TYPE i.
    DATA lv_left TYPE i.
    DATA lv_up TYPE i.
    DATA lv_diagonal TYPE i.
    DATA lv_columns TYPE i.
    DATA lv_up_index TYPE i.

    lv_len1 = strlen( iv_text1 ).
    lv_len2 = strlen( iv_text2 ).
    IF lv_len1 = 0.
      rv_distance = lv_len2.
      RETURN.
    ENDIF.
    IF lv_len2 = 0.
      rv_distance = lv_len1.
      RETURN.
    ENDIF.

    " Row 0: turning nothing into the first j letters of text 2 takes j steps
    lv_columns = lv_len2 + 1.
    DO lv_columns TIMES.
      lv_value = sy-index - 1.
      APPEND lv_value TO lt_previous.
    ENDDO.

    lv_i = 0.
    WHILE lv_i < lv_len1.
      lv_i = lv_i + 1.
      lv_offset1 = lv_i - 1.
      CLEAR lt_current.
      APPEND lv_i TO lt_current.
      lv_j = 0.
      WHILE lv_j < lv_len2.
        lv_j = lv_j + 1.
        lv_offset2 = lv_j - 1.
        IF iv_text1+lv_offset1(1) = iv_text2+lv_offset2(1).
          lv_cost = 0.
        ELSE.
          lv_cost = 1.
        ENDIF.
        " Table index = column + 1
        lv_up_index = lv_j + 1.
        READ TABLE lt_current INDEX lv_j INTO lv_left.
        READ TABLE lt_previous INDEX lv_up_index INTO lv_up.
        READ TABLE lt_previous INDEX lv_j INTO lv_diagonal.
        lv_best = lv_left + 1.
        IF lv_up + 1 < lv_best.
          lv_best = lv_up + 1.
        ENDIF.
        IF lv_diagonal + lv_cost < lv_best.
          lv_best = lv_diagonal + lv_cost.
        ENDIF.
        APPEND lv_best TO lt_current.
      ENDWHILE.
      lt_previous = lt_current.
    ENDWHILE.
    READ TABLE lt_previous INDEX lv_columns INTO rv_distance.
  ENDMETHOD.


  METHOD constructor.
    DATA ls_rule TYPE lif_dupl=>ty_rule_setting.

    mt_rules = default_rules( ).
    LOOP AT it_rules INTO ls_rule.
      MODIFY TABLE mt_rules FROM ls_rule.
      IF sy-subrc <> 0.
        INSERT ls_rule INTO TABLE mt_rules.
      ENDIF.
    ENDLOOP.
    IF io_normalizer IS BOUND.
      mo_normalizer = io_normalizer.
    ELSE.
      CREATE OBJECT mo_normalizer.
    ENDIF.
    mv_threshold = iv_threshold.
    mv_max_block = iv_max_block.
    mv_unmask = iv_unmask.
  ENDMETHOD.


  METHOD find.
    DATA lt_prepared TYPE ty_prepared_tab.
    DATA ls_prepared TYPE ty_prepared.
    DATA ls_other TYPE ty_prepared.
    DATA lt_blocks TYPE ty_blocks.
    DATA ls_block TYPE ty_block.
    DATA lt_candidates TYPE ty_candidates.
    DATA ls_candidate TYPE ty_candidate.
    DATA ls_partner TYPE lif_dupl=>ty_partner.
    DATA ls_line TYPE lif_dupl=>ty_line.
    DATA lv_index TYPE i.
    DATA lv_index1 TYPE i.
    DATA lv_index2 TYPE i.
    DATA lv_count TYPE i.
    DATA lv_from TYPE i.
    DATA lv_text TYPE string.

    rs_result-partners = lines( it_partners ).
    LOOP AT it_partners INTO ls_partner.
      ls_prepared = prepare( ls_partner ).
      APPEND ls_prepared TO lt_prepared.
      lv_index = sy-tabix.
      add_keys( EXPORTING is_prepared = ls_prepared iv_index = lv_index
                CHANGING  ct_blocks   = lt_blocks ).
    ENDLOOP.

    LOOP AT lt_blocks INTO ls_block.
      lv_count = ls_block-member_count.
      IF lv_count < 2.
        CONTINUE.
      ENDIF.
      IF lv_count > mv_max_block.
        lv_text = describe_key( iv_key = ls_block-key iv_count = lv_count ).
        APPEND lv_text TO rs_result-skipped_blocks.
        CONTINUE.
      ENDIF.
      LOOP AT ls_block-members INTO lv_index1.
        lv_from = sy-tabix + 1.
        LOOP AT ls_block-members INTO lv_index2 FROM lv_from.
          IF lv_index1 < lv_index2.
            ls_candidate-index1 = lv_index1.
            ls_candidate-index2 = lv_index2.
          ELSE.
            ls_candidate-index1 = lv_index2.
            ls_candidate-index2 = lv_index1.
          ENDIF.
          INSERT ls_candidate INTO TABLE lt_candidates.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.

    LOOP AT lt_candidates INTO ls_candidate.
      READ TABLE lt_prepared INDEX ls_candidate-index1 INTO ls_prepared.
      READ TABLE lt_prepared INDEX ls_candidate-index2 INTO ls_other.
      ls_line = score( is_one = ls_prepared is_other = ls_other ).
      IF ls_line-score >= mv_threshold AND ls_line-score > 0.
        APPEND ls_line TO rs_result-lines.
      ENDIF.
    ENDLOOP.
    SORT rs_result-lines BY score DESCENDING partner1 partner2.
    SORT rs_result-skipped_blocks BY table_line.
  ENDMETHOD.


  METHOD similarity.
    DATA lv_text1 TYPE string.
    DATA lv_text2 TYPE string.
    DATA lv_longer TYPE i.
    DATA lv_by_edits TYPE i.
    DATA lv_distance TYPE i.
    DATA lv_by_words TYPE i.
    DATA lv_shared TYPE i.
    DATA lv_all TYPE i.
    DATA lv_token TYPE string.

    IF it_tokens1 IS INITIAL OR it_tokens2 IS INITIAL.
      RETURN.
    ENDIF.
    CONCATENATE LINES OF it_tokens1 INTO lv_text1 SEPARATED BY space.
    CONCATENATE LINES OF it_tokens2 INTO lv_text2 SEPARATED BY space.
    IF lv_text1 = lv_text2.
      rv_percent = 100.
      RETURN.
    ENDIF.

    lv_longer = strlen( lv_text1 ).
    IF strlen( lv_text2 ) > lv_longer.
      lv_longer = strlen( lv_text2 ).
    ENDIF.
    lv_distance = edit_distance( iv_text1 = lv_text1 iv_text2 = lv_text2 ).
    lv_by_edits = 100 - 100 * lv_distance / lv_longer.

    LOOP AT it_tokens1 INTO lv_token WHERE table_line IS NOT INITIAL.
      READ TABLE it_tokens2 WITH KEY table_line = lv_token TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_shared = lv_shared + 1.
      ENDIF.
    ENDLOOP.
    lv_all = lines( it_tokens1 ) + lines( it_tokens2 ) - lv_shared.
    lv_by_words = 100 * lv_shared / lv_all.

    rv_percent = lv_by_edits.
    IF lv_by_words > rv_percent.
      rv_percent = lv_by_words.
    ENDIF.
    " Different names must not reach 100 by rounding
    IF rv_percent >= 100.
      rv_percent = 99.
    ENDIF.
  ENDMETHOD.


  METHOD prepare.
    DATA lv_value TYPE string.
    DATA lv_key TYPE string.
    DATA ls_address TYPE lif_dupl=>ty_address.

    rs_prepared-partner = is_partner-partner.
    rs_prepared-name = is_partner-name.
    rs_prepared-tokens = mo_normalizer->name_tokens( is_partner-name ).

    LOOP AT is_partner-tax_ids INTO lv_value.
      lv_key = mo_normalizer->tax_key( lv_value ).
      IF lv_key IS NOT INITIAL.
        APPEND lv_key TO rs_prepared-tax_ids.
      ENDIF.
    ENDLOOP.
    LOOP AT is_partner-ibans INTO lv_value.
      lv_key = mo_normalizer->iban_key( lv_value ).
      IF lv_key IS NOT INITIAL.
        APPEND lv_key TO rs_prepared-ibans.
      ENDIF.
    ENDLOOP.
    LOOP AT is_partner-addresses INTO ls_address.
      lv_key = mo_normalizer->address_key( ls_address ).
      IF lv_key IS NOT INITIAL.
        APPEND lv_key TO rs_prepared-addresses.
      ENDIF.
    ENDLOOP.
    LOOP AT is_partner-phones INTO lv_value.
      lv_key = mo_normalizer->phone_key( lv_value ).
      IF lv_key IS NOT INITIAL.
        APPEND lv_key TO rs_prepared-phones.
      ENDIF.
    ENDLOOP.
    LOOP AT is_partner-emails INTO lv_value.
      lv_key = mo_normalizer->email_key( lv_value ).
      IF lv_key IS NOT INITIAL.
        APPEND lv_key TO rs_prepared-emails.
        lv_key = mo_normalizer->email_domain( lv_value ).
        IF lv_key IS NOT INITIAL.
          APPEND lv_key TO rs_prepared-domains.
        ENDIF.
      ENDIF.
    ENDLOOP.
    SORT: rs_prepared-tax_ids BY table_line, rs_prepared-ibans BY table_line,
          rs_prepared-addresses BY table_line, rs_prepared-phones BY table_line,
          rs_prepared-emails BY table_line, rs_prepared-domains BY table_line.
    DELETE ADJACENT DUPLICATES FROM: rs_prepared-tax_ids COMPARING ALL FIELDS,
                                     rs_prepared-ibans COMPARING ALL FIELDS,
                                     rs_prepared-addresses COMPARING ALL FIELDS,
                                     rs_prepared-phones COMPARING ALL FIELDS,
                                     rs_prepared-emails COMPARING ALL FIELDS,
                                     rs_prepared-domains COMPARING ALL FIELDS.
  ENDMETHOD.


  METHOD add_keys.
    DATA lv_value TYPE string.
    DATA lv_first TYPE string.
    DATA lv_longest TYPE string.

    IF weight( lif_dupl=>rule-tax_id ) > 0.
      LOOP AT is_prepared-tax_ids INTO lv_value.
        add_key( EXPORTING iv_prefix = 'T' iv_value = lv_value iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( lif_dupl=>rule-iban ) > 0.
      LOOP AT is_prepared-ibans INTO lv_value.
        add_key( EXPORTING iv_prefix = 'I' iv_value = lv_value iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( lif_dupl=>rule-address ) > 0.
      LOOP AT is_prepared-addresses INTO lv_value.
        add_key( EXPORTING iv_prefix = 'A' iv_value = lv_value iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( lif_dupl=>rule-phone ) > 0.
      LOOP AT is_prepared-phones INTO lv_value.
        add_key( EXPORTING iv_prefix = 'P' iv_value = lv_value iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( lif_dupl=>rule-email ) > 0.
      LOOP AT is_prepared-emails INTO lv_value.
        add_key( EXPORTING iv_prefix = 'E' iv_value = lv_value iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
      LOOP AT is_prepared-domains INTO lv_value.
        add_key( EXPORTING iv_prefix = 'D' iv_value = lv_value iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( lif_dupl=>rule-name ) > 0 AND is_prepared-tokens IS NOT INITIAL.
      READ TABLE is_prepared-tokens INDEX 1 INTO lv_first.
      IF strlen( lv_first ) > 3.
        lv_value = lv_first(3).
      ELSE.
        lv_value = lv_first.
      ENDIF.
      add_key( EXPORTING iv_prefix = 'N' iv_value = lv_value iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      lv_longest = lv_first.
      LOOP AT is_prepared-tokens INTO lv_value.
        IF strlen( lv_value ) > strlen( lv_longest ).
          lv_longest = lv_value.
        ENDIF.
      ENDLOOP.
      add_key( EXPORTING iv_prefix = 'W' iv_value = lv_longest iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
    ENDIF.
  ENDMETHOD.


  METHOD add_key.
    DATA lv_key TYPE string.
    DATA ls_block TYPE ty_block.
    FIELD-SYMBOLS <ls_block> TYPE ty_block.

    CONCATENATE iv_prefix ':' iv_value INTO lv_key.
    READ TABLE ct_blocks WITH TABLE KEY key = lv_key ASSIGNING <ls_block>.
    IF sy-subrc <> 0.
      ls_block-key = lv_key.
      INSERT ls_block INTO TABLE ct_blocks ASSIGNING <ls_block>.
    ENDIF.
    " FIND visits one partner at a time, so repeated keys for one index are consecutive.
    IF <ls_block>-last_index = iv_index.
      RETURN.
    ENDIF.
    <ls_block>-last_index = iv_index.
    <ls_block>-member_count = <ls_block>-member_count + 1.
    IF <ls_block>-member_count - 1 <= mv_max_block.
      APPEND iv_index TO <ls_block>-members.
    ENDIF.
  ENDMETHOD.


  METHOD score.
    DATA lt_reasons TYPE lif_dupl=>ty_strings.
    DATA lv_rest TYPE p LENGTH 16 DECIMALS 10 VALUE 1.
    DATA lv_value TYPE string.
    DATA lv_reason TYPE string.
    DATA lv_shown TYPE string.
    DATA lv_weight TYPE i.
    DATA lv_similarity TYPE i.
    DATA lv_minimum TYPE i.
    DATA lv_percent TYPE string.
    DATA ls_rule TYPE lif_dupl=>ty_rule_setting.

    lv_weight = weight( lif_dupl=>rule-tax_id ).
    lv_value = common( it_values = is_one-tax_ids it_others = is_other-tax_ids ).
    IF lv_value IS NOT INITIAL AND lv_weight > 0.
      lv_rest = lv_rest * ( 100 - lv_weight ) / 100.
      lv_shown = show( lv_value ).
      CONCATENATE `Same tax number ` lv_shown INTO lv_reason.
      APPEND lv_reason TO lt_reasons.
    ENDIF.

    lv_weight = weight( lif_dupl=>rule-iban ).
    lv_value = common( it_values = is_one-ibans it_others = is_other-ibans ).
    IF lv_value IS NOT INITIAL AND lv_weight > 0.
      lv_rest = lv_rest * ( 100 - lv_weight ) / 100.
      lv_shown = show( lv_value ).
      CONCATENATE `Same IBAN ` lv_shown INTO lv_reason.
      APPEND lv_reason TO lt_reasons.
    ENDIF.

    lv_weight = weight( lif_dupl=>rule-name ).
    IF lv_weight > 0.
      lv_similarity = similarity( it_tokens1 = is_one-tokens it_tokens2 = is_other-tokens ).
      READ TABLE mt_rules WITH TABLE KEY rule = lif_dupl=>rule-name INTO ls_rule.
      lv_minimum = ls_rule-min_similarity.
      IF lv_similarity > 0 AND lv_similarity >= lv_minimum.
        lv_rest = lv_rest * ( 100 - lv_weight * lv_similarity / 100 ) / 100.
        IF lv_similarity = 100.
          lv_reason = `Same name`.
        ELSE.
          lv_percent = lcl_text=>num( lv_similarity ).
          CONCATENATE `Name ` lv_percent `% similar` INTO lv_reason.
        ENDIF.
        APPEND lv_reason TO lt_reasons.
      ENDIF.
    ENDIF.

    lv_weight = weight( lif_dupl=>rule-address ).
    lv_value = common( it_values = is_one-addresses it_others = is_other-addresses ).
    IF lv_value IS NOT INITIAL AND lv_weight > 0.
      lv_rest = lv_rest * ( 100 - lv_weight ) / 100.
      APPEND `Same address` TO lt_reasons.
    ENDIF.

    lv_weight = weight( lif_dupl=>rule-phone ).
    lv_value = common( it_values = is_one-phones it_others = is_other-phones ).
    IF lv_value IS NOT INITIAL AND lv_weight > 0.
      lv_rest = lv_rest * ( 100 - lv_weight ) / 100.
      APPEND `Same phone` TO lt_reasons.
    ENDIF.

    lv_weight = weight( lif_dupl=>rule-email ).
    IF lv_weight > 0.
      lv_value = common( it_values = is_one-emails it_others = is_other-emails ).
      IF lv_value IS NOT INITIAL.
        lv_rest = lv_rest * ( 100 - lv_weight ) / 100.
        APPEND `Same e-mail` TO lt_reasons.
      ELSE.
        lv_value = common( it_values = is_one-domains it_others = is_other-domains ).
        IF lv_value IS NOT INITIAL.
          " A shared company domain is weaker than the same address
          lv_rest = lv_rest * ( 100 - lv_weight / 2 ) / 100.
          CONCATENATE `Same e-mail domain ` lv_value INTO lv_reason.
          APPEND lv_reason TO lt_reasons.
        ENDIF.
      ENDIF.
    ENDIF.

    rs_line-finding = lif_dupl=>finding-duplicate.
    " Assigning a packed number to an integer rounds it
    rs_line-score = 100 * ( 1 - lv_rest ).
    CONCATENATE LINES OF lt_reasons INTO rs_line-reasons SEPARATED BY `; `.
    IF is_one-partner <= is_other-partner.
      rs_line-partner1 = is_one-partner.
      rs_line-name1 = is_one-name.
      rs_line-partner2 = is_other-partner.
      rs_line-name2 = is_other-name.
    ELSE.
      rs_line-partner1 = is_other-partner.
      rs_line-name1 = is_other-name.
      rs_line-partner2 = is_one-partner.
      rs_line-name2 = is_one-name.
    ENDIF.
  ENDMETHOD.


  METHOD weight.
    DATA ls_rule TYPE lif_dupl=>ty_rule_setting.
    READ TABLE mt_rules WITH TABLE KEY rule = iv_rule INTO ls_rule.
    IF sy-subrc = 0.
      rv_weight = ls_rule-weight.
    ENDIF.
  ENDMETHOD.


  METHOD common.
    LOOP AT it_values INTO rv_value.
      READ TABLE it_others WITH KEY table_line = rv_value TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        RETURN.
      ENDIF.
    ENDLOOP.
    CLEAR rv_value.
  ENDMETHOD.


  METHOD show.
    IF mv_unmask = abap_true.
      rv_text = iv_value.
    ELSE.
      rv_text = lcl_tax_id=>mask( iv_value ).
    ENDIF.
  ENDMETHOD.


  METHOD describe_key.
    DATA lv_value TYPE string.
    DATA lv_count TYPE string.

    lv_value = iv_key+2.
    CASE iv_key(1).
      WHEN 'T'.
        lv_value = show( lv_value ).
        CONCATENATE `Tax number ` lv_value INTO rv_text.
      WHEN 'I'.
        lv_value = show( lv_value ).
        CONCATENATE `IBAN ` lv_value INTO rv_text.
      WHEN 'A'.
        CONCATENATE `Address ` lv_value INTO rv_text.
      WHEN 'P'.
        CONCATENATE `Phone ` lv_value INTO rv_text.
      WHEN 'E'.
        CONCATENATE `E-mail ` lv_value INTO rv_text.
      WHEN 'D'.
        CONCATENATE `E-mail domain ` lv_value INTO rv_text.
      WHEN 'N'.
        CONCATENATE `Names starting with ` lv_value INTO rv_text.
      WHEN 'W'.
        CONCATENATE `Names with the word ` lv_value INTO rv_text.
      WHEN OTHERS.
        rv_text = lv_value.
    ENDCASE.
    lv_count = lcl_text=>num( iv_count ).
    CONCATENATE rv_text ` (` lv_count ` partners, not compared)` INTO rv_text.
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* Reads SAP business partners: BUT000 (names), BUT020/ADRC/ADR2/ADR6
* (addresses, phones, e-mails), DFKKBPTAXNUM (tax numbers of the chosen
* category) and BUT0BK (IBAN). Partners marked for deletion
* (BUT000-XDELE) are left out.
* For another source, change this class; it only has to fill
* LIF_DUPL=>TY_PARTNERS.
*----------------------------------------------------------------------*
CLASS lcl_authorization DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS require_run
      IMPORTING iv_unmask TYPE abap_bool
      RAISING lcx_error.
    CLASS-METHODS can_read_group
      IMPORTING iv_group TYPE but000-augrp
      RETURNING value(rv_allowed) TYPE abap_bool.
    CLASS-METHODS can_decide
      RETURNING value(rv_allowed) TYPE abap_bool.
    CLASS-METHODS require_decision
      IMPORTING iv_partner1 TYPE bu_partner
                iv_partner2 TYPE bu_partner
      RAISING lcx_error.
ENDCLASS.

CLASS lcl_authorization IMPLEMENTATION.
  METHOD require_run.
    AUTHORITY-CHECK OBJECT 'ZCHE_DUPL' ID 'ACTVT' FIELD '03'.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE lcx_error
        EXPORTING text = `Not authorized to run duplicate search (ZCHE_DUPL, activity 03).`.
    ENDIF.
    IF iv_unmask = abap_true.
      AUTHORITY-CHECK OBJECT 'ZCHE_DUPL' ID 'ACTVT' FIELD '16'.
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE lcx_error
          EXPORTING text = `Not authorized to display full tax numbers or IBANs (ZCHE_DUPL, activity 16).`.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD can_read_group.
    AUTHORITY-CHECK OBJECT 'B_BUPA_GRP'
      ID 'ACTVT' FIELD '03'
      ID 'BEGRU' FIELD iv_group.
    IF sy-subrc = 0.
      rv_allowed = abap_true.
    ELSE.
      rv_allowed = abap_false.
    ENDIF.
  ENDMETHOD.

  METHOD can_decide.
    AUTHORITY-CHECK OBJECT 'ZCHE_DUPL' ID 'ACTVT' FIELD '02'.
    IF sy-subrc = 0.
      rv_allowed = abap_true.
    ELSE.
      rv_allowed = abap_false.
    ENDIF.
  ENDMETHOD.

  METHOD require_decision.
    DATA lv_allowed TYPE abap_bool.
    DATA lt_partners TYPE STANDARD TABLE OF bu_partner WITH DEFAULT KEY.
    DATA lv_partner TYPE bu_partner.
    DATA lv_group TYPE but000-augrp.

    require_run( abap_false ).
    lv_allowed = can_decide( ).
    IF lv_allowed = abap_false.
      RAISE EXCEPTION TYPE lcx_error
        EXPORTING text = `Not authorized to save decisions (ZCHE_DUPL, activity 02).`.
    ENDIF.
    IF iv_partner1 IS INITIAL OR iv_partner2 IS INITIAL OR iv_partner1 = iv_partner2.
      RAISE EXCEPTION TYPE lcx_error
        EXPORTING text = `A decision requires two different existing business partners.`.
    ENDIF.
    APPEND iv_partner1 TO lt_partners.
    APPEND iv_partner2 TO lt_partners.
    LOOP AT lt_partners INTO lv_partner.
      CLEAR lv_group.
      SELECT SINGLE augrp FROM but000 INTO lv_group
        WHERE partner = lv_partner AND xdele = space.
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE lcx_error
          EXPORTING text = `Both business partners must exist and be authorized for display.`.
      ENDIF.
      lv_allowed = can_read_group( lv_group ).
      IF lv_allowed = abap_false.
        RAISE EXCEPTION TYPE lcx_error
          EXPORTING text = `Both business partners must exist and be authorized for display.`.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

CLASS lcl_source_bp DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS read
      IMPORTING is_settings TYPE lif_dupl=>ty_settings
      RETURNING value(rt_partners) TYPE lif_dupl=>ty_partners
      RAISING lcx_error.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_key,
        partner TYPE bu_partner,
      END OF ty_key,
      ty_keys TYPE SORTED TABLE OF ty_key WITH UNIQUE KEY partner,
      BEGIN OF ty_candidate,
        partner TYPE bu_partner,
        augrp TYPE but000-augrp,
      END OF ty_candidate,
      ty_candidates TYPE STANDARD TABLE OF ty_candidate WITH DEFAULT KEY,
      BEGIN OF ty_bp,
        partner TYPE but000-partner,
        type TYPE but000-type,
        name_org1 TYPE but000-name_org1,
        name_org2 TYPE but000-name_org2,
        name_org3 TYPE but000-name_org3,
        name_org4 TYPE but000-name_org4,
        name_first TYPE but000-name_first,
        name_last TYPE but000-name_last,
        name_grp1 TYPE but000-name_grp1,
        name_grp2 TYPE but000-name_grp2,
      END OF ty_bp,
      ty_bps TYPE STANDARD TABLE OF ty_bp WITH DEFAULT KEY,
      BEGIN OF ty_address,
        partner TYPE but020-partner,
        addrnumber TYPE adrc-addrnumber,
        country TYPE adrc-country,
        post_code1 TYPE adrc-post_code1,
        city1 TYPE adrc-city1,
        street TYPE adrc-street,
        house_num1 TYPE adrc-house_num1,
      END OF ty_address,
      ty_addresses TYPE SORTED TABLE OF ty_address WITH NON-UNIQUE KEY partner,
      BEGIN OF ty_phone,
        addrnumber TYPE adr2-addrnumber,
        tel_number TYPE adr2-tel_number,
      END OF ty_phone,
      ty_phones TYPE SORTED TABLE OF ty_phone WITH NON-UNIQUE KEY addrnumber,
      BEGIN OF ty_email,
        addrnumber TYPE adr6-addrnumber,
        smtp_addr TYPE adr6-smtp_addr,
      END OF ty_email,
      ty_emails TYPE SORTED TABLE OF ty_email WITH NON-UNIQUE KEY addrnumber,
      BEGIN OF ty_tax,
        partner TYPE dfkkbptaxnum-partner,
        taxnum TYPE dfkkbptaxnum-taxnum,
        taxnumxl TYPE dfkkbptaxnum-taxnumxl,
      END OF ty_tax,
      ty_taxes TYPE SORTED TABLE OF ty_tax WITH NON-UNIQUE KEY partner,
      BEGIN OF ty_bank,
        partner TYPE but0bk-partner,
        iban TYPE but0bk-iban,
      END OF ty_bank,
      ty_banks TYPE SORTED TABLE OF ty_bank WITH NON-UNIQUE KEY partner.
ENDCLASS.

CLASS lcl_source_bp IMPLEMENTATION.
  METHOD read.
    DATA lv_key_timestamp TYPE timestamp.
    DATA lv_timestamp_text TYPE n LENGTH 14.
    DATA lr_groups TYPE RANGE OF bu_group.
    DATA ls_group LIKE LINE OF lr_groups.
    DATA lt_candidates TYPE ty_candidates.
    DATA ls_candidate TYPE ty_candidate.
    DATA lt_keys TYPE ty_keys.
    DATA lt_country_keys TYPE ty_keys.
    DATA lt_selected_keys TYPE ty_keys.
    DATA ls_key TYPE ty_key.
    DATA lv_allowed TYPE abap_bool.
    DATA lt_bps TYPE ty_bps.
    DATA ls_bp TYPE ty_bp.
    DATA lt_addresses TYPE ty_addresses.
    DATA ls_address TYPE ty_address.
    DATA lt_phones TYPE ty_phones.
    DATA ls_phone TYPE ty_phone.
    DATA lt_emails TYPE ty_emails.
    DATA ls_email TYPE ty_email.
    DATA lt_taxes TYPE ty_taxes.
    DATA ls_tax TYPE ty_tax.
    DATA lt_banks TYPE ty_banks.
    DATA ls_bank TYPE ty_bank.
    DATA ls_partner TYPE lif_dupl=>ty_partner.
    DATA ls_partner_address TYPE lif_dupl=>ty_address.
    DATA lv_text TYPE string.

    lcl_authorization=>require_run( is_settings-unmask ).
    CONVERT DATE is_settings-key_date TIME '000000'
      INTO TIME STAMP lv_key_timestamp TIME ZONE 'UTC'.
    IF sy-subrc <> 0 OR lv_key_timestamp IS INITIAL.
      RAISE EXCEPTION TYPE lcx_error
        EXPORTING text = `Enter a valid reference date; validity is evaluated at 00:00 UTC.`.
    ENDIF.
    lv_timestamp_text = lv_key_timestamp.
    IF is_settings-bp_group IS NOT INITIAL.
      ls_group-sign = 'I'.
      ls_group-option = 'EQ'.
      ls_group-low = is_settings-bp_group.
      APPEND ls_group TO lr_groups.
    ENDIF.

    " Read only IDs and authorization groups before eligibility checks.
    IF is_settings-bp_role IS INITIAL.
      SELECT partner augrp FROM but000 INTO TABLE lt_candidates
        WHERE bu_group IN lr_groups AND xdele = space
        ORDER BY partner.
    ELSE.
      SELECT partner augrp FROM but000 INTO TABLE lt_candidates
        WHERE bu_group IN lr_groups AND xdele = space
          AND partner IN ( SELECT partner FROM but100
            WHERE rltyp = is_settings-bp_role
              AND ( valid_from = 0 OR valid_from <= lv_key_timestamp )
              AND ( valid_to = 0 OR valid_to >= lv_key_timestamp ) )
        ORDER BY partner.
    ENDIF.
    LOOP AT lt_candidates INTO ls_candidate.
      lv_allowed = lcl_authorization=>can_read_group( ls_candidate-augrp ).
      IF lv_allowed = abap_true.
        ls_key-partner = ls_candidate-partner.
        INSERT ls_key INTO TABLE lt_keys.
      ENDIF.
    ENDLOOP.
    IF lt_keys IS INITIAL.
      IF lt_candidates IS NOT INITIAL.
        RAISE EXCEPTION TYPE lcx_error
          EXPORTING text = `No selected business partners are authorized for display (B_BUPA_GRP, activity 03).`.
      ENDIF.
      RETURN.
    ENDIF.

    " Country eligibility is established using IDs only, before detail reads.
    IF is_settings-country IS NOT INITIAL.
      SELECT b~partner FROM but020 AS b
        INNER JOIN adrc AS a ON a~addrnumber = b~addrnumber
        INTO TABLE lt_country_keys
        FOR ALL ENTRIES IN lt_keys
        WHERE b~partner = lt_keys-partner
          AND a~country = is_settings-country AND a~nation = space
          AND ( b~addr_valid_from = 0 OR b~addr_valid_from <= lv_key_timestamp )
          AND ( b~addr_valid_to = 0 OR b~addr_valid_to >= lv_key_timestamp )
          AND ( a~date_from = '00000000' OR a~date_from <= is_settings-key_date )
          AND ( a~date_to = '00000000' OR a~date_to >= is_settings-key_date ).
      LOOP AT lt_keys INTO ls_key.
        READ TABLE lt_country_keys TRANSPORTING NO FIELDS
          WITH TABLE KEY partner = ls_key-partner.
        IF sy-subrc = 0.
          INSERT ls_key INTO TABLE lt_selected_keys.
        ENDIF.
      ENDLOOP.
      lt_keys = lt_selected_keys.
      IF lt_keys IS INITIAL.
        RETURN.
      ENDIF.
    ENDIF.

    SELECT partner type name_org1 name_org2 name_org3 name_org4
           name_first name_last name_grp1 name_grp2
      FROM but000 INTO TABLE lt_bps
      FOR ALL ENTRIES IN lt_keys
      WHERE partner = lt_keys-partner.
    SORT lt_bps BY partner.
    SELECT b~partner a~addrnumber a~country a~post_code1 a~city1 a~street a~house_num1
      FROM but020 AS b
      INNER JOIN adrc AS a ON a~addrnumber = b~addrnumber
      INTO TABLE lt_addresses
      FOR ALL ENTRIES IN lt_keys
      WHERE b~partner = lt_keys-partner AND a~nation = space
        AND ( b~addr_valid_from = 0 OR b~addr_valid_from <= lv_key_timestamp )
        AND ( b~addr_valid_to = 0 OR b~addr_valid_to >= lv_key_timestamp )
        AND ( a~date_from = '00000000' OR a~date_from <= is_settings-key_date )
        AND ( a~date_to = '00000000' OR a~date_to >= is_settings-key_date ).
    IF lt_addresses IS NOT INITIAL.
      SELECT addrnumber tel_number FROM adr2 INTO TABLE lt_phones
        FOR ALL ENTRIES IN lt_addresses
        WHERE addrnumber = lt_addresses-addrnumber AND persnumber = space AND flg_nouse = space
          AND ( date_from = '00000000' OR date_from <= is_settings-key_date )
          AND ( valid_from = space OR valid_from = '00000000000000' OR valid_from <= lv_timestamp_text )
          AND ( valid_to = space OR valid_to = '00000000000000' OR valid_to >= lv_timestamp_text ).
      SELECT addrnumber smtp_addr FROM adr6 INTO TABLE lt_emails
        FOR ALL ENTRIES IN lt_addresses
        WHERE addrnumber = lt_addresses-addrnumber AND persnumber = space AND flg_nouse = space
          AND ( date_from = '00000000' OR date_from <= is_settings-key_date )
          AND ( valid_from = space OR valid_from = '00000000000000' OR valid_from <= lv_timestamp_text )
          AND ( valid_to = space OR valid_to = '00000000000000' OR valid_to >= lv_timestamp_text ).
    ENDIF.
    IF is_settings-tax_type IS NOT INITIAL.
      SELECT partner taxnum taxnumxl FROM dfkkbptaxnum INTO TABLE lt_taxes
        FOR ALL ENTRIES IN lt_keys
        WHERE partner = lt_keys-partner AND taxtype = is_settings-tax_type.
    ENDIF.
    SELECT partner iban FROM but0bk INTO TABLE lt_banks
      FOR ALL ENTRIES IN lt_keys
      WHERE partner = lt_keys-partner AND iban <> space
        AND ( bk_valid_from = 0 OR bk_valid_from <= lv_key_timestamp )
        AND ( bk_valid_to = 0 OR bk_valid_to >= lv_key_timestamp ).

    LOOP AT lt_bps INTO ls_bp.
      CLEAR ls_partner.
      ls_partner-partner = ls_bp-partner.
      CASE ls_bp-type.
        WHEN '1'.
          CONCATENATE ls_bp-name_first ls_bp-name_last INTO lv_text SEPARATED BY space.
        WHEN '3'.
          CONCATENATE ls_bp-name_grp1 ls_bp-name_grp2 INTO lv_text SEPARATED BY space.
        WHEN OTHERS.
          CONCATENATE ls_bp-name_org1 ls_bp-name_org2 ls_bp-name_org3 ls_bp-name_org4
            INTO lv_text SEPARATED BY space.
      ENDCASE.
      CONDENSE lv_text.
      ls_partner-name = lv_text.
      LOOP AT lt_addresses INTO ls_address WHERE partner = ls_bp-partner.
        ls_partner_address-country = ls_address-country.
        ls_partner_address-post_code = ls_address-post_code1.
        ls_partner_address-city = ls_address-city1.
        ls_partner_address-street = ls_address-street.
        ls_partner_address-house_no = ls_address-house_num1.
        APPEND ls_partner_address TO ls_partner-addresses.
        LOOP AT lt_phones INTO ls_phone WHERE addrnumber = ls_address-addrnumber.
          lv_text = ls_phone-tel_number.
          APPEND lv_text TO ls_partner-phones.
        ENDLOOP.
        LOOP AT lt_emails INTO ls_email WHERE addrnumber = ls_address-addrnumber.
          lv_text = ls_email-smtp_addr.
          APPEND lv_text TO ls_partner-emails.
        ENDLOOP.
      ENDLOOP.
      LOOP AT lt_taxes INTO ls_tax WHERE partner = ls_bp-partner.
        IF ls_tax-taxnumxl IS NOT INITIAL.
          lv_text = ls_tax-taxnumxl.
        ELSE.
          lv_text = ls_tax-taxnum.
        ENDIF.
        APPEND lv_text TO ls_partner-tax_ids.
      ENDLOOP.
      LOOP AT lt_banks INTO ls_bank WHERE partner = ls_bp-partner.
        lv_text = ls_bank-iban.
        APPEND lv_text TO ls_partner-ibans.
      ENDLOOP.
      APPEND ls_partner TO rt_partners.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.


*----------------------------------------------------------------------*
* Decisions per pair, kept in the standard cluster table INDX, so the
* program needs no own table. Area ZC, ID ZCHE_DUPL_DECISIONS, one entry
* per client.
*----------------------------------------------------------------------*
CLASS lcl_decisions DEFINITION FINAL.
  PUBLIC SECTION.
    CONSTANTS c_id TYPE indx-srtfd VALUE 'ZCHE_DUPL_DECISIONS'.
    CLASS-METHODS load
      RETURNING value(rt_decisions) TYPE lif_dupl=>ty_decisions
      RAISING lcx_error.
    CLASS-METHODS save
      IMPORTING iv_partner1 TYPE bu_partner
                iv_partner2 TYPE bu_partner
                iv_decision TYPE lif_dupl=>ty_decision_code
      RAISING lcx_error.
  PRIVATE SECTION.
    CLASS-METHODS release_lock
      IMPORTING iv_key TYPE rstable-varkey.
ENDCLASS.

CLASS lcl_decisions IMPLEMENTATION.
  METHOD load.
    DATA lx_error TYPE REF TO cx_root.
    DATA lv_text TYPE string.
    DATA lv_error_text TYPE string.

    lcl_authorization=>require_run( abap_false ).
    TRY.
        IMPORT decisions = rt_decisions FROM DATABASE indx(zc) ID c_id.
        IF sy-subrc <> 0.
          CLEAR rt_decisions.
        ENDIF.
      CATCH cx_sy_import_mismatch_error cx_sy_import_format_error cx_sy_open_sql_db INTO lx_error.
        lv_error_text = lx_error->get_text( ).
        CONCATENATE `Cannot read saved duplicate decisions: ` lv_error_text INTO lv_text.
        RAISE EXCEPTION TYPE lcx_error EXPORTING text = lv_text.
    ENDTRY.
  ENDMETHOD.

  METHOD save.
    DATA lv_lock_key TYPE rstable-varkey.
    DATA lv_text TYPE string.
    DATA lv_error_text TYPE string.
    DATA lt_decisions TYPE lif_dupl=>ty_decisions.
    DATA ls_decision TYPE lif_dupl=>ty_decision.
    DATA ls_indx TYPE indx.
    DATA lx_decision TYPE REF TO lcx_error.
    DATA lx_database TYPE REF TO cx_sy_open_sql_db.

    lcl_authorization=>require_decision( iv_partner1 = iv_partner1 iv_partner2 = iv_partner2 ).
    IF iv_decision <> lif_dupl=>decision-duplicate AND iv_decision <> lif_dupl=>decision-not_duplicate.
      RAISE EXCEPTION TYPE lcx_error EXPORTING text = `Choose Duplicate or Not a duplicate.`.
    ENDIF.
    CONCATENATE sy-mandt 'ZC' c_id INTO lv_lock_key.
    CALL FUNCTION 'ENQUEUE_E_TABLE'
      EXPORTING tabname = 'INDX' varkey = lv_lock_key _wait = abap_true
      EXCEPTIONS foreign_lock = 1 system_failure = 2 OTHERS = 3.
    IF sy-subrc <> 0.
      CONCATENATE `Cannot lock saved decisions (` sy-msgv1 `); try again.` INTO lv_text.
      RAISE EXCEPTION TYPE lcx_error EXPORTING text = lv_text.
    ENDIF.

    TRY.
        " Reload under the shared lock so different pairs are not lost.
        lt_decisions = load( ).
        IF iv_partner1 <= iv_partner2.
          ls_decision-partner1 = iv_partner1.
          ls_decision-partner2 = iv_partner2.
        ELSE.
          ls_decision-partner1 = iv_partner2.
          ls_decision-partner2 = iv_partner1.
        ENDIF.
        ls_decision-decision = iv_decision.
        ls_decision-changed_by = sy-uname.
        GET TIME STAMP FIELD ls_decision-changed_at.
        MODIFY TABLE lt_decisions FROM ls_decision.
        IF sy-subrc <> 0.
          INSERT ls_decision INTO TABLE lt_decisions.
        ENDIF.
        ls_indx-aedat = sy-datum.
        ls_indx-usera = sy-uname.
        ls_indx-pgmid = sy-repid.
        EXPORT decisions = lt_decisions TO DATABASE indx(zc) FROM ls_indx ID c_id.
        IF sy-subrc <> 0.
          RAISE EXCEPTION TYPE lcx_error EXPORTING text = `Saving the duplicate decision failed.`.
        ENDIF.
        COMMIT WORK AND WAIT.
        IF sy-subrc <> 0.
          RAISE EXCEPTION TYPE lcx_error EXPORTING text = `Committing the duplicate decision failed.`.
        ENDIF.
      CATCH lcx_error INTO lx_decision.
        ROLLBACK WORK.
        release_lock( lv_lock_key ).
        RAISE EXCEPTION lx_decision.
      CATCH cx_sy_open_sql_db INTO lx_database.
        ROLLBACK WORK.
        release_lock( lv_lock_key ).
        lv_error_text = lx_database->get_text( ).
        CONCATENATE `Cannot save duplicate decision: ` lv_error_text INTO lv_text.
        RAISE EXCEPTION TYPE lcx_error EXPORTING text = lv_text.
    ENDTRY.
    release_lock( lv_lock_key ).
  ENDMETHOD.

  METHOD release_lock.
    CALL FUNCTION 'DEQUEUE_E_TABLE'
      EXPORTING tabname = 'INDX' varkey = iv_key.
  ENDMETHOD.
ENDCLASS.


*----------------------------------------------------------------------*
* Runs a search: source, matcher, decisions, tax number check
*----------------------------------------------------------------------*
CLASS lcl_finder DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING
        is_settings TYPE lif_dupl=>ty_settings.

    METHODS run
      IMPORTING
        iv_show_decided  TYPE abap_bool DEFAULT abap_false
      RETURNING
        value(rs_result) TYPE lif_dupl=>ty_result
      RAISING lcx_error.

    "! Fills the decision of each pair; hides "not a duplicate" pairs unless asked
    CLASS-METHODS apply_decisions
      IMPORTING
        it_decisions    TYPE lif_dupl=>ty_decisions
        iv_show_decided TYPE abap_bool
      CHANGING
        cs_result       TYPE lif_dupl=>ty_result.

    CLASS-METHODS add_tax_id_findings
      IMPORTING
        it_partners TYPE lif_dupl=>ty_partners
        iv_unmask   TYPE abap_bool
        iv_check    TYPE abap_bool DEFAULT abap_false
      CHANGING
        cs_result   TYPE lif_dupl=>ty_result.

  PRIVATE SECTION.
    DATA ms_settings TYPE lif_dupl=>ty_settings.
    DATA mo_matcher TYPE REF TO lcl_matcher.
ENDCLASS.


CLASS lcl_finder IMPLEMENTATION.

  METHOD constructor.
    DATA lo_normalizer TYPE REF TO lcl_normalizer.

    ms_settings = is_settings.
    CREATE OBJECT lo_normalizer
      EXPORTING
        it_extra_words = is_settings-stop_words.
    CREATE OBJECT mo_matcher
      EXPORTING
        it_rules      = is_settings-rules
        io_normalizer = lo_normalizer
        iv_threshold  = is_settings-threshold
        iv_max_block  = is_settings-max_block
        iv_unmask     = is_settings-unmask.
  ENDMETHOD.


  METHOD run.
    DATA lo_source TYPE REF TO lcl_source_bp.
    DATA lt_partners TYPE lif_dupl=>ty_partners.
    DATA lt_decisions TYPE lif_dupl=>ty_decisions.

    lcl_authorization=>require_run( ms_settings-unmask ).
    CREATE OBJECT lo_source.
    lt_partners = lo_source->read( ms_settings ).
    rs_result = mo_matcher->find( lt_partners ).
    lt_decisions = lcl_decisions=>load( ).
    apply_decisions( EXPORTING it_decisions    = lt_decisions
                               iv_show_decided = iv_show_decided
                     CHANGING  cs_result       = rs_result ).
    add_tax_id_findings( EXPORTING it_partners = lt_partners
                                   iv_unmask   = ms_settings-unmask
                                   iv_check    = ms_settings-tax_check
                         CHANGING  cs_result   = rs_result ).
  ENDMETHOD.


  METHOD apply_decisions.
    DATA ls_decision TYPE lif_dupl=>ty_decision.
    DATA lv_before TYPE i.
    FIELD-SYMBOLS <ls_line> TYPE lif_dupl=>ty_line.

    LOOP AT cs_result-lines ASSIGNING <ls_line>.
      READ TABLE it_decisions INTO ls_decision
        WITH TABLE KEY partner1 = <ls_line>-partner1 partner2 = <ls_line>-partner2.
      IF sy-subrc = 0.
        <ls_line>-decision = ls_decision-decision.
      ENDIF.
    ENDLOOP.

    IF iv_show_decided = abap_false.
      lv_before = lines( cs_result-lines ).
      DELETE cs_result-lines WHERE decision = lif_dupl=>decision-not_duplicate.
      cs_result-hidden_pairs = lv_before - lines( cs_result-lines ).
    ENDIF.
  ENDMETHOD.


  METHOD add_tax_id_findings.
    DATA ls_partner TYPE lif_dupl=>ty_partner.
    DATA ls_line TYPE lif_dupl=>ty_line.
    DATA lv_tax_id TYPE string.
    DATA lv_problem TYPE string.
    DATA lv_masked TYPE string.

    IF iv_check = abap_false.
      RETURN.
    ENDIF.
    LOOP AT it_partners INTO ls_partner.
      LOOP AT ls_partner-tax_ids INTO lv_tax_id.
        lv_problem = lcl_tax_id=>check( lv_tax_id ).
        IF lv_problem IS INITIAL.
          CONTINUE.
        ENDIF.
        IF iv_unmask = abap_true.
          CONDENSE lv_tax_id.
          lv_masked = lcl_tax_id=>mask( lv_tax_id ).
          REPLACE lv_masked IN lv_problem WITH lv_tax_id.
        ENDIF.
        CLEAR ls_line.
        ls_line-finding = lif_dupl=>finding-invalid_tax_id.
        ls_line-partner1 = ls_partner-partner.
        ls_line-name1 = ls_partner-name.
        ls_line-reasons = lv_problem.
        APPEND ls_line TO cs_result-lines.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* Selection screen in, ALV list out
*----------------------------------------------------------------------*
CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_row,
        finding  TYPE lif_dupl=>ty_finding,
        score    TYPE i,
        partner1 TYPE bu_partner,
        name1    TYPE c LENGTH 80,
        partner2 TYPE bu_partner,
        name2    TYPE c LENGTH 80,
        reasons  TYPE c LENGTH 255,
        decision TYPE lif_dupl=>ty_decision_code,
        mark_dup TYPE icon_d,
        mark_not TYPE icon_d,
      END OF ty_row,
      ty_rows TYPE STANDARD TABLE OF ty_row WITH DEFAULT KEY.

    "! Checks the screen; returns an error text or nothing
    CLASS-METHODS check_settings
      IMPORTING
        is_settings       TYPE lif_dupl=>ty_settings
      RETURNING
        value(rv_problem) TYPE string.

    CLASS-METHODS run
      IMPORTING
        is_settings     TYPE lif_dupl=>ty_settings
        iv_show_decided TYPE abap_bool.

  PRIVATE SECTION.
    CLASS-DATA gt_rows TYPE ty_rows.
    CLASS-DATA go_alv TYPE REF TO cl_salv_table.

    CLASS-METHODS show.

    CLASS-METHODS on_link_click
      FOR EVENT link_click OF cl_salv_events_table
      IMPORTING
        row
        column.

    CLASS-METHODS text
      IMPORTING
        io_columns TYPE REF TO cl_salv_columns_table
        iv_column  TYPE lvc_fname
        iv_en      TYPE csequence
        iv_tr      TYPE csequence
        iv_long_en TYPE csequence
        iv_long_tr TYPE csequence
      RAISING
        cx_salv_not_found.

    CLASS-METHODS hotspot
      IMPORTING
        io_columns TYPE REF TO cl_salv_columns_table
        iv_column  TYPE lvc_fname
      RAISING
        cx_salv_not_found.
ENDCLASS.


CLASS lcl_app IMPLEMENTATION.

  METHOD check_settings.
    DATA ls_rule TYPE lif_dupl=>ty_rule_setting.

    IF is_settings-key_date IS INITIAL.
      rv_problem = lcl_text=>get( iv_en = 'Enter a master-data reference date.'
                                  iv_tr = 'Ana veri referans tarihini girin.' ).
      RETURN.
    ENDIF.
    IF is_settings-tax_check = abap_true AND is_settings-country IS NOT INITIAL AND is_settings-country <> 'TR'.
      rv_problem = lcl_text=>get( iv_en = 'Turkish checksum validation cannot be used with another country.'
                                  iv_tr = 'Türk vergi numarası kontrolü başka bir ülkeyle kullanılamaz.' ).
      RETURN.
    ENDIF.

    LOOP AT is_settings-rules INTO ls_rule.
      IF ls_rule-weight NOT BETWEEN 0 AND 100 OR ls_rule-min_similarity NOT BETWEEN 0 AND 100.
        rv_problem = lcl_text=>get( iv_en = 'Weights and the name similarity must be between 0 and 100.'
                                    iv_tr = 'Ağırlıklar ve isim benzerliği 0 ile 100 arasında olmalı.' ).
        RETURN.
      ENDIF.
    ENDLOOP.
    IF is_settings-threshold NOT BETWEEN 1 AND 100.
      rv_problem = lcl_text=>get( iv_en = 'The lowest score shown must be between 1 and 100.'
                                  iv_tr = 'Gösterilecek en düşük puan 1 ile 100 arasında olmalı.' ).
      RETURN.
    ENDIF.
    IF is_settings-max_block < 2.
      rv_problem = lcl_text=>get( iv_en = 'Max. partners per key must be at least 2.'
                                  iv_tr = 'Anahtar başına en çok cari en az 2 olmalı.' ).
      RETURN.
    ENDIF.
    CLEAR ls_rule.
    READ TABLE is_settings-rules WITH TABLE KEY rule = lif_dupl=>rule-tax_id INTO ls_rule.
    IF is_settings-tax_type IS INITIAL AND ( ls_rule-weight > 0 OR is_settings-tax_check = abap_true ).
      rv_problem = lcl_text=>get( iv_en = 'Enter a tax category, or disable tax matching and Turkish checksum validation.'
                                  iv_tr = 'Vergi kategorisini girin ya da vergi eşleştirmesini ve Türk numarası kontrolünü kapatın.' ).
    ENDIF.
  ENDMETHOD.


  METHOD run.
    DATA lo_finder TYPE REF TO lcl_finder.
    DATA ls_result TYPE lif_dupl=>ty_result.
    DATA ls_line TYPE lif_dupl=>ty_line.
    DATA ls_row TYPE ty_row.
    DATA lv_pairs TYPE i.
    DATA lv_invalid TYPE i.
    DATA lv_en TYPE string.
    DATA lv_tr TYPE string.
    DATA lv_summary TYPE string.
    DATA lv_skipped TYPE string.
    DATA lv_partners TYPE string.
    DATA lv_pairs_text TYPE string.
    DATA lv_invalid_text TYPE string.
    DATA lv_hidden_text TYPE string.
    DATA lx_error TYPE REF TO lcx_error.
    DATA lv_error TYPE string.
    DATA lv_can_decide TYPE abap_bool.
    DATA lv_key_date TYPE c LENGTH 10.

    CLEAR gt_rows.
    TRY.
        CREATE OBJECT lo_finder
          EXPORTING
            is_settings = is_settings.
        ls_result = lo_finder->run( iv_show_decided ).
      CATCH lcx_error INTO lx_error.
        lv_error = lx_error->get_text( ).
        IF sy-batch = abap_true.
          MESSAGE lv_error TYPE 'E'.
        ELSE.
          MESSAGE lv_error TYPE 'I' DISPLAY LIKE 'E'.
        ENDIF.
        RETURN.
    ENDTRY.
    lv_can_decide = lcl_authorization=>can_decide( ).

    LOOP AT ls_result-lines INTO ls_line.
      CLEAR ls_row.
      MOVE-CORRESPONDING ls_line TO ls_row.
      IF ls_line-finding = lif_dupl=>finding-duplicate.
        IF lv_can_decide = abap_true.
          ls_row-mark_dup = icon_okay.
          ls_row-mark_not = icon_cancel.
        ENDIF.
        lv_pairs = lv_pairs + 1.
      ENDIF.
      APPEND ls_row TO gt_rows.
    ENDLOOP.
    lv_invalid = lines( gt_rows ) - lv_pairs.

    lv_partners = lcl_text=>num( ls_result-partners ).
    lv_pairs_text = lcl_text=>num( lv_pairs ).
    lv_invalid_text = lcl_text=>num( lv_invalid ).
    CONCATENATE lv_partners ` partners read: ` lv_pairs_text ` likely duplicate pairs, `
                lv_invalid_text ` invalid tax numbers` INTO lv_en.
    CONCATENATE lv_partners ` cari okundu: ` lv_pairs_text ` olası mükerrer çift, `
                lv_invalid_text ` hatalı vergi numarası` INTO lv_tr.
    IF ls_result-hidden_pairs > 0.
      lv_hidden_text = lcl_text=>num( ls_result-hidden_pairs ).
      CONCATENATE lv_en `, ` lv_hidden_text ` pairs hidden (marked not duplicate)` INTO lv_en.
      CONCATENATE lv_tr `, ` lv_hidden_text ` çift gizlendi (mükerrer değil)` INTO lv_tr.
    ENDIF.
    lv_summary = lcl_text=>get( iv_en = lv_en iv_tr = lv_tr ).
    MESSAGE lv_summary TYPE 'S'.
    CONCATENATE is_settings-key_date(4) '-' is_settings-key_date+4(2) '-' is_settings-key_date+6(2) INTO lv_key_date.
    CONCATENATE 'Reference date:' lv_key_date '00:00 UTC; version' lif_dupl=>version INTO lv_summary SEPARATED BY space.
    MESSAGE lv_summary TYPE 'S'.

    LOOP AT ls_result-skipped_blocks INTO lv_skipped.
      lv_summary = lcl_text=>get( iv_en = 'Not compared' iv_tr = 'Karşılaştırılmadı' ).
      CONCATENATE lv_summary `: ` lv_skipped INTO lv_summary.
      MESSAGE lv_summary TYPE 'S' DISPLAY LIKE 'W'.
    ENDLOOP.

    show( ).
  ENDMETHOD.


  METHOD show.
    DATA lx_salv TYPE REF TO cx_salv_msg.
    DATA lo_functions TYPE REF TO cl_salv_functions_list.
    DATA lo_columns TYPE REF TO cl_salv_columns_table.
    DATA lo_events TYPE REF TO cl_salv_events_table.
    DATA lv_text TYPE string.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = go_alv
                                CHANGING  t_table      = gt_rows ).
      CATCH cx_salv_msg INTO lx_salv.
        lv_text = lx_salv->get_text( ).
        MESSAGE lv_text TYPE 'I' DISPLAY LIKE 'E'.
        RETURN.
    ENDTRY.

    lo_functions = go_alv->get_functions( ).
    lo_functions->set_all( abap_true ).
    lo_columns = go_alv->get_columns( ).
    lo_columns->set_optimize( abap_true ).
    TRY.
        text( io_columns = lo_columns iv_column = 'FINDING'
              iv_en = 'Finding' iv_tr = 'Bulgu' iv_long_en = 'Finding' iv_long_tr = 'Bulgu' ).
        text( io_columns = lo_columns iv_column = 'SCORE'
              iv_en = 'Score' iv_tr = 'Puan' iv_long_en = 'Score (0-100)' iv_long_tr = 'Puan (0-100)' ).
        text( io_columns = lo_columns iv_column = 'PARTNER1'
              iv_en = 'Partner' iv_tr = 'Cari' iv_long_en = 'Partner' iv_long_tr = 'Cari' ).
        text( io_columns = lo_columns iv_column = 'NAME1'
              iv_en = 'Name' iv_tr = 'Ad' iv_long_en = 'Name' iv_long_tr = 'Ad' ).
        text( io_columns = lo_columns iv_column = 'PARTNER2'
              iv_en = 'Partner 2' iv_tr = 'Cari 2' iv_long_en = 'Second partner' iv_long_tr = 'İkinci cari' ).
        text( io_columns = lo_columns iv_column = 'NAME2'
              iv_en = 'Name 2' iv_tr = 'Ad 2' iv_long_en = 'Name of second partner' iv_long_tr = 'İkinci carinin adı' ).
        text( io_columns = lo_columns iv_column = 'REASONS'
              iv_en = 'Reasons' iv_tr = 'Nedenler' iv_long_en = 'Reasons' iv_long_tr = 'Nedenler' ).
        text( io_columns = lo_columns iv_column = 'DECISION'
              iv_en = 'Decision' iv_tr = 'Karar'
              iv_long_en = 'Decision (D duplicate, N not)' iv_long_tr = 'Karar (D mükerrer, N değil)' ).
        text( io_columns = lo_columns iv_column = 'MARK_DUP'
              iv_en = 'Duplicate' iv_tr = 'Mükerrer' iv_long_en = 'Mark as duplicate' iv_long_tr = 'Mükerrer olarak işaretle' ).
        text( io_columns = lo_columns iv_column = 'MARK_NOT'
              iv_en = 'Not dup.' iv_tr = 'Değil' iv_long_en = 'Mark as not a duplicate' iv_long_tr = 'Mükerrer değil olarak işaretle' ).
        hotspot( io_columns = lo_columns iv_column = 'MARK_DUP' ).
        hotspot( io_columns = lo_columns iv_column = 'MARK_NOT' ).
      CATCH cx_salv_not_found.                          "#EC NO_HANDLER
    ENDTRY.
    lo_events = go_alv->get_event( ).
    SET HANDLER on_link_click FOR lo_events.
    go_alv->display( ).
  ENDMETHOD.


  METHOD on_link_click.
    DATA lv_decision TYPE lif_dupl=>ty_decision_code.
    DATA lx_error TYPE REF TO lcx_error.
    DATA lv_text TYPE string.
    FIELD-SYMBOLS <ls_row> TYPE ty_row.

    READ TABLE gt_rows INDEX row ASSIGNING <ls_row>.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    IF <ls_row>-finding <> lif_dupl=>finding-duplicate.
      RETURN.
    ENDIF.
    CASE column.
      WHEN 'MARK_DUP'.
        lv_decision = lif_dupl=>decision-duplicate.
      WHEN 'MARK_NOT'.
        lv_decision = lif_dupl=>decision-not_duplicate.
      WHEN OTHERS.
        RETURN.
    ENDCASE.
    TRY.
        lcl_decisions=>save( iv_partner1 = <ls_row>-partner1
                             iv_partner2 = <ls_row>-partner2
                             iv_decision = lv_decision ).
      CATCH lcx_error INTO lx_error.
        lv_text = lx_error->get_text( ).
        MESSAGE lv_text TYPE 'I' DISPLAY LIKE 'E'.
        RETURN.
    ENDTRY.
    <ls_row>-decision = lv_decision.
    lv_text = lcl_text=>get( iv_en = 'Saved' iv_tr = 'Kaydedildi' ).
    CONCATENATE lv_text `: ` <ls_row>-partner1 ` / ` <ls_row>-partner2 ` = ` lv_decision INTO lv_text.
    MESSAGE lv_text TYPE 'S'.
    go_alv->refresh( ).
  ENDMETHOD.


  METHOD text.
    DATA lo_column TYPE REF TO cl_salv_column.
    DATA lv_short TYPE scrtext_s.
    DATA lv_medium TYPE scrtext_m.
    DATA lv_long TYPE scrtext_l.

    lo_column = io_columns->get_column( iv_column ).
    lv_short = lcl_text=>get( iv_en = iv_en iv_tr = iv_tr ).
    lv_medium = lcl_text=>get( iv_en = iv_en iv_tr = iv_tr ).
    lv_long = lcl_text=>get( iv_en = iv_long_en iv_tr = iv_long_tr ).
    lo_column->set_short_text( lv_short ).
    lo_column->set_medium_text( lv_medium ).
    lo_column->set_long_text( lv_long ).
  ENDMETHOD.


  METHOD hotspot.
    DATA lo_column TYPE REF TO cl_salv_column_table.
    lo_column ?= io_columns->get_column( iv_column ).
    lo_column->set_cell_type( if_salv_c_cell_type=>hotspot ).
    lo_column->set_icon( abap_true ).
  ENDMETHOD.

ENDCLASS.


*----------------------------------------------------------------------*
* Reads the selection screen
*----------------------------------------------------------------------*
CLASS lcl_screen DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS settings
      RETURNING
        value(rs_settings) TYPE lif_dupl=>ty_settings.

  PRIVATE SECTION.
    CLASS-METHODS add_rule
      IMPORTING
        iv_rule           TYPE lif_dupl=>ty_rule
        iv_weight         TYPE i
        iv_min_similarity TYPE i DEFAULT 0
      CHANGING
        ct_rules          TYPE lif_dupl=>ty_rule_settings.
ENDCLASS.


CLASS lcl_screen IMPLEMENTATION.

  METHOD settings.
    DATA lv_word TYPE string.
    DATA ls_stop LIKE LINE OF s_stop.

    rs_settings-tax_type = p_taxty.
    rs_settings-bp_role = p_role.
    rs_settings-bp_group = p_group.
    rs_settings-country = p_cntry.
    rs_settings-key_date = p_keydt.
    rs_settings-tax_check = p_taxchk.
    rs_settings-threshold = p_thresh.
    rs_settings-max_block = p_maxblk.
    rs_settings-unmask = p_unmask.
    add_rule( EXPORTING iv_rule = lif_dupl=>rule-tax_id  iv_weight = p_wtax   CHANGING ct_rules = rs_settings-rules ).
    add_rule( EXPORTING iv_rule = lif_dupl=>rule-iban    iv_weight = p_wiban  CHANGING ct_rules = rs_settings-rules ).
    add_rule( EXPORTING iv_rule = lif_dupl=>rule-name    iv_weight = p_wname  iv_min_similarity = p_minsim
              CHANGING ct_rules = rs_settings-rules ).
    add_rule( EXPORTING iv_rule = lif_dupl=>rule-address iv_weight = p_waddr  CHANGING ct_rules = rs_settings-rules ).
    add_rule( EXPORTING iv_rule = lif_dupl=>rule-phone   iv_weight = p_wphone CHANGING ct_rules = rs_settings-rules ).
    add_rule( EXPORTING iv_rule = lif_dupl=>rule-email   iv_weight = p_wmail  CHANGING ct_rules = rs_settings-rules ).
    LOOP AT s_stop INTO ls_stop WHERE sign = 'I' AND option = 'EQ'.
      lv_word = ls_stop-low.
      APPEND lv_word TO rs_settings-stop_words.
    ENDLOOP.
  ENDMETHOD.


  METHOD add_rule.
    DATA ls_rule TYPE lif_dupl=>ty_rule_setting.
    ls_rule-rule = iv_rule.
    ls_rule-weight = iv_weight.
    ls_rule-min_similarity = iv_min_similarity.
    INSERT ls_rule INTO TABLE ct_rules.
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Unit tests (in ADT: Ctrl+Shift+F10; in SE38: Program > Execute >
*& Unit Tests). All names, numbers and addresses are made up; check
*& digits of the test numbers were calculated separately.
*& Written for ABAP 7.00: risk level and duration are pseudo comments,
*& and every result is put into a variable before it is checked.
*&---------------------------------------------------------------------*
CLASS ltc_tax_id DEFINITION FINAL FOR TESTING.
  "#AU Risk_Level Harmless
  "#AU Duration Short
  PRIVATE SECTION.
    METHODS vkn_valid FOR TESTING.
    METHODS vkn_wrong_check_digit FOR TESTING.
    METHODS tckn_valid FOR TESTING.
    METHODS tckn_wrong FOR TESTING.
    METHODS check_texts FOR TESTING.
    METHODS mask FOR TESTING.

    METHODS vkn
      IMPORTING
        iv_number TYPE string
        iv_valid  TYPE abap_bool.

    METHODS tckn
      IMPORTING
        iv_number TYPE string
        iv_valid  TYPE abap_bool.

    METHODS problem
      IMPORTING
        iv_number  TYPE string
        iv_problem TYPE string.
ENDCLASS.


CLASS ltc_tax_id IMPLEMENTATION.

  METHOD vkn.
    DATA lv_valid TYPE abap_bool.
    lv_valid = lcl_tax_id=>is_valid_vkn( iv_number ).
    cl_aunit_assert=>assert_equals( act = lv_valid exp = iv_valid msg = iv_number ).
  ENDMETHOD.


  METHOD tckn.
    DATA lv_valid TYPE abap_bool.
    lv_valid = lcl_tax_id=>is_valid_tckn( iv_number ).
    cl_aunit_assert=>assert_equals( act = lv_valid exp = iv_valid msg = iv_number ).
  ENDMETHOD.


  METHOD problem.
    DATA lv_problem TYPE string.
    lv_problem = lcl_tax_id=>check( iv_number ).
    cl_aunit_assert=>assert_equals( act = lv_problem exp = iv_problem msg = iv_number ).
  ENDMETHOD.


  METHOD vkn_valid.
    vkn( iv_number = `1234567890` iv_valid = abap_true ).
    vkn( iv_number = `9876543217` iv_valid = abap_true ).
    vkn( iv_number = `5550001112` iv_valid = abap_true ).
  ENDMETHOD.


  METHOD vkn_wrong_check_digit.
    vkn( iv_number = `1234567891` iv_valid = abap_false ).
    vkn( iv_number = `123456789` iv_valid = abap_false ).
    vkn( iv_number = `12345678A0` iv_valid = abap_false ).
  ENDMETHOD.


  METHOD tckn_valid.
    tckn( iv_number = `10000000146` iv_valid = abap_true ).
    tckn( iv_number = `12345678950` iv_valid = abap_true ).
  ENDMETHOD.


  METHOD tckn_wrong.
    tckn( iv_number = `10000000147` iv_valid = abap_false ).
    tckn( iv_number = `01234567890` iv_valid = abap_false ).
  ENDMETHOD.


  METHOD check_texts.
    problem( iv_number = `1234567890` iv_problem = `` ).
    problem( iv_number = ` 10000000146 ` iv_problem = `` ).
    problem( iv_number = `1234567891` iv_problem = `Tax number (VKN) 123*****91: check digit is wrong` ).
    problem( iv_number = `12345` iv_problem = `Tax number ***** has 5 digits; VKN has 10, TCKN 11` ).
  ENDMETHOD.


  METHOD mask.
    DATA lv_masked TYPE string.
    lv_masked = lcl_tax_id=>mask( '10000000146' ).
    cl_aunit_assert=>assert_equals( act = lv_masked exp = `100******46` ).
  ENDMETHOD.

ENDCLASS.


CLASS ltc_normalizer DEFINITION FINAL FOR TESTING.
  "#AU Risk_Level Harmless
  "#AU Duration Short
  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO lcl_normalizer.

    METHODS setup.
    METHODS turkish_letters FOR TESTING.
    METHODS punctuation FOR TESTING.
    METHODS legal_forms_removed FOR TESTING.
    METHODS word_order_ignored FOR TESTING.
    METHODS extra_stop_words FOR TESTING.
    METHODS phone FOR TESTING.
    METHODS email FOR TESTING.
    METHODS address FOR TESTING.
    METHODS address_requires_street FOR TESTING.
    METHODS tax_id_keeps_letters FOR TESTING.

    METHODS simple
      IMPORTING
        iv_text     TYPE string
        iv_expected TYPE string.

    "! Checks the name words; IV_EXPECTED is the words separated by spaces
    METHODS tokens
      IMPORTING
        iv_name     TYPE string
        iv_expected TYPE string.

    METHODS address_key
      IMPORTING
        iv_post_code  TYPE string OPTIONAL
        iv_city       TYPE string OPTIONAL
        iv_street     TYPE string OPTIONAL
        iv_house_no   TYPE string OPTIONAL
      RETURNING
        value(rv_key) TYPE string.
ENDCLASS.


CLASS ltc_normalizer IMPLEMENTATION.

  METHOD setup.
    CREATE OBJECT mo_cut.
  ENDMETHOD.


  METHOD simple.
    DATA lv_text TYPE string.
    lv_text = mo_cut->simplify( iv_text ).
    cl_aunit_assert=>assert_equals( act = lv_text exp = iv_expected ).
  ENDMETHOD.


  METHOD tokens.
    DATA lt_tokens TYPE lif_dupl=>ty_strings.
    DATA lv_tokens TYPE string.
    lt_tokens = mo_cut->name_tokens( iv_name ).
    CONCATENATE LINES OF lt_tokens INTO lv_tokens SEPARATED BY space.
    cl_aunit_assert=>assert_equals( act = lv_tokens exp = iv_expected msg = iv_name ).
  ENDMETHOD.


  METHOD address_key.
    DATA ls_address TYPE lif_dupl=>ty_address.
    ls_address-country = 'TR'.
    ls_address-post_code = iv_post_code.
    ls_address-city = iv_city.
    ls_address-street = iv_street.
    ls_address-house_no = iv_house_no.
    rv_key = mo_cut->address_key( ls_address ).
  ENDMETHOD.


  METHOD turkish_letters.
    simple( iv_text = `İzmir ığdır ÇİĞDEM şükrü Öz` iv_expected = `IZMIR IGDIR CIGDEM SUKRU OZ` ).
    " Lower case i must not become a dotted capital in any logon language
    simple( iv_text = `existing` iv_expected = `EXISTING` ).
  ENDMETHOD.


  METHOD punctuation.
    simple( iv_text = `  A.B.C.  Tekstil-San.,Tic. ` iv_expected = `A B C TEKSTIL SAN TIC` ).
  ENDMETHOD.


  METHOD legal_forms_removed.
    tokens( iv_name = `Derya Tekstil San. ve Tic. A.Ş.` iv_expected = `DERYA TEKSTIL` ).
    tokens( iv_name = `DERYA TEKSTİL SANAYİ TİCARET ANONİM ŞİRKETİ` iv_expected = `DERYA TEKSTIL` ).
    tokens( iv_name = `Derya Tekstil Ltd. Şti.` iv_expected = `DERYA TEKSTIL` ).
  ENDMETHOD.


  METHOD word_order_ignored.
    tokens( iv_name = `Tekstil Derya` iv_expected = `DERYA TEKSTIL` ).
  ENDMETHOD.


  METHOD extra_stop_words.
    " Extra words are ignored together with the built-in ones
    DATA lt_extra TYPE lif_dupl=>ty_strings.
    APPEND `Holding` TO lt_extra.
    CREATE OBJECT mo_cut
      EXPORTING
        it_extra_words = lt_extra.
    tokens( iv_name = `Derya Holding Ltd.` iv_expected = `DERYA` ).
  ENDMETHOD.


  METHOD phone.
    DATA lv_key TYPE string.
    lv_key = mo_cut->phone_key( '+90 (212) 555 01 02' ).
    cl_aunit_assert=>assert_equals( act = lv_key exp = `2125550102` ).
    lv_key = mo_cut->phone_key( '0212 555 0102' ).
    cl_aunit_assert=>assert_equals( act = lv_key exp = `2125550102` ).
    lv_key = mo_cut->phone_key( '1234' ).
    cl_aunit_assert=>assert_initial( lv_key ).
  ENDMETHOD.


  METHOD email.
    DATA lv_key TYPE string.
    lv_key = mo_cut->email_key( ` Info@Derya.com.tr ` ).
    cl_aunit_assert=>assert_equals( act = lv_key exp = `info@derya.com.tr` ).
    lv_key = mo_cut->email_domain( 'satis@derya.com.tr' ).
    cl_aunit_assert=>assert_equals( act = lv_key exp = `derya.com.tr` ).
    lv_key = mo_cut->email_domain( 'derya.tekstil@gmail.com' ).
    cl_aunit_assert=>assert_initial( lv_key ).
    lv_key = mo_cut->email_key( 'no address' ).
    cl_aunit_assert=>assert_initial( lv_key ).
  ENDMETHOD.


  METHOD address.
    DATA lv_key TYPE string.
    DATA lv_other TYPE string.

    lv_key = address_key( iv_post_code = `34000` iv_city = `İstanbul` iv_street = `Atatürk Cad.` iv_house_no = `12/3` ).
    cl_aunit_assert=>assert_equals( act = lv_key exp = `TR/34000/ATATURK CD 12 3` ).
    " Street words written out or abbreviated give the same key
    lv_other = address_key( iv_post_code = `34000` iv_street = `ATATURK CADDESI No: 12/3` ).
    cl_aunit_assert=>assert_equals( act = lv_other exp = lv_key ).
    lv_key = address_key( iv_post_code = `06000` iv_street = `Lale Sok.` iv_house_no = `7` ).
    lv_other = address_key( iv_post_code = `06000` iv_street = `Lale Sokağı` iv_house_no = `7` ).
    cl_aunit_assert=>assert_equals( act = lv_other exp = lv_key ).
    lv_key = address_key( iv_city = `İzmir` iv_street = `Kordon` ).
    cl_aunit_assert=>assert_equals( act = lv_key exp = `TR/IZMIR/KORDON` ).
    lv_key = address_key( iv_city = `İzmir` ).
    cl_aunit_assert=>assert_initial( lv_key ).
  ENDMETHOD.

  METHOD address_requires_street.
    DATA lv_key TYPE string.

    lv_key = address_key( iv_post_code = `34000` iv_house_no = `12` ).
    cl_aunit_assert=>assert_initial( lv_key ).
    lv_key = address_key( iv_post_code = `34000` iv_street = `...` iv_house_no = `12` ).
    cl_aunit_assert=>assert_initial( lv_key ).
  ENDMETHOD.

  METHOD tax_id_keeps_letters.
    DATA lv_key TYPE string.

    lv_key = mo_cut->tax_key( `ab-123` ).
    cl_aunit_assert=>assert_equals( act = lv_key exp = `AB123` ).
    lv_key = mo_cut->tax_key( `XY 123` ).
    cl_aunit_assert=>assert_equals( act = lv_key exp = `XY123` ).
  ENDMETHOD.

ENDCLASS.


CLASS ltc_matcher DEFINITION FINAL FOR TESTING.
  "#AU Risk_Level Harmless
  "#AU Duration Short
  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO lcl_matcher.
    DATA mt_partners TYPE lif_dupl=>ty_partners.
    DATA ms_result TYPE lif_dupl=>ty_result.
    DATA ms_line TYPE lif_dupl=>ty_line.
    DATA mv_lines TYPE i.

    METHODS setup.
    METHODS same_tax_number FOR TESTING.
    METHODS tax_number_masked FOR TESTING.
    METHODS spelling_variants FOR TESTING.
    METHODS typo_in_name FOR TESTING.
    METHODS different_companies FOR TESTING.
    METHODS weak_signals_add_up FOR TESTING.
    METHODS public_mail_domain_ignored FOR TESTING.
    METHODS rule_switched_off FOR TESTING.
    METHODS crowded_block_skipped FOR TESTING.
    METHODS pair_order FOR TESTING.
    METHODS similarity_values FOR TESTING.
    METHODS edit_distance FOR TESTING.
    METHODS block_members_bounded FOR TESTING.
    METHODS missing_street_not_evidence FOR TESTING.
    METHODS tax_id_letters_distinguish FOR TESTING.
    METHODS formatted_tax_id_matches FOR TESTING.

    "! Adds a made-up partner to MT_PARTNERS
    METHODS partner
      IMPORTING
        iv_id     TYPE bu_partner
        iv_name   TYPE string
        iv_tax    TYPE string OPTIONAL
        iv_iban   TYPE string OPTIONAL
        iv_street TYPE string OPTIONAL
        iv_phone  TYPE string OPTIONAL
        iv_email  TYPE string OPTIONAL.

    "! Runs the matcher on MT_PARTNERS; fills MS_RESULT, MS_LINE (first line) and MV_LINES
    METHODS find.

    "! IV_WORDS1 and IV_WORDS2 are words separated by spaces
    METHODS similarity
      IMPORTING
        iv_words1   TYPE string
        iv_words2   TYPE string
        iv_expected TYPE i.

    METHODS distance
      IMPORTING
        iv_text1    TYPE string
        iv_text2    TYPE string
        iv_expected TYPE i.
ENDCLASS.


CLASS ltc_matcher IMPLEMENTATION.

  METHOD setup.
    CREATE OBJECT mo_cut
      EXPORTING
        iv_unmask = abap_true.
    CLEAR mt_partners.
  ENDMETHOD.


  METHOD partner.
    DATA ls_partner TYPE lif_dupl=>ty_partner.
    DATA ls_address TYPE lif_dupl=>ty_address.

    ls_partner-partner = iv_id.
    ls_partner-name = iv_name.
    IF iv_tax IS NOT INITIAL.
      APPEND iv_tax TO ls_partner-tax_ids.
    ENDIF.
    IF iv_iban IS NOT INITIAL.
      APPEND iv_iban TO ls_partner-ibans.
    ENDIF.
    IF iv_street IS NOT INITIAL.
      ls_address-country = 'TR'.
      ls_address-post_code = `34000`.
      ls_address-city = `Istanbul`.
      ls_address-street = iv_street.
      APPEND ls_address TO ls_partner-addresses.
    ENDIF.
    IF iv_phone IS NOT INITIAL.
      APPEND iv_phone TO ls_partner-phones.
    ENDIF.
    IF iv_email IS NOT INITIAL.
      APPEND iv_email TO ls_partner-emails.
    ENDIF.
    APPEND ls_partner TO mt_partners.
  ENDMETHOD.


  METHOD find.
    ms_result = mo_cut->find( mt_partners ).
    mv_lines = lines( ms_result-lines ).
    CLEAR ms_line.
    READ TABLE ms_result-lines INDEX 1 INTO ms_line.
  ENDMETHOD.


  METHOD similarity.
    DATA lt_tokens1 TYPE lif_dupl=>ty_strings.
    DATA lt_tokens2 TYPE lif_dupl=>ty_strings.
    DATA lv_percent TYPE i.

    IF iv_words1 IS NOT INITIAL.
      SPLIT iv_words1 AT space INTO TABLE lt_tokens1.
    ENDIF.
    IF iv_words2 IS NOT INITIAL.
      SPLIT iv_words2 AT space INTO TABLE lt_tokens2.
    ENDIF.
    lv_percent = mo_cut->similarity( it_tokens1 = lt_tokens1 it_tokens2 = lt_tokens2 ).
    cl_aunit_assert=>assert_equals( act = lv_percent exp = iv_expected ).
  ENDMETHOD.


  METHOD distance.
    DATA lv_distance TYPE i.
    lv_distance = lcl_matcher=>edit_distance( iv_text1 = iv_text1 iv_text2 = iv_text2 ).
    cl_aunit_assert=>assert_equals( act = lv_distance exp = iv_expected ).
  ENDMETHOD.


  METHOD same_tax_number.
    partner( iv_id = '1' iv_name = `Derya Tekstil A.Ş.` iv_tax = `1234567890` ).
    partner( iv_id = '2' iv_name = `Mavi Gıda Ltd.` iv_tax = `1234567890` ).
    find( ).
    cl_aunit_assert=>assert_equals( act = mv_lines exp = 1 ).
    cl_aunit_assert=>assert_equals( act = ms_line-score exp = 95 ).
    cl_aunit_assert=>assert_equals( act = ms_line-reasons exp = `Same tax number 1234567890` ).
  ENDMETHOD.


  METHOD tax_number_masked.
    CREATE OBJECT mo_cut.
    partner( iv_id = '1' iv_name = `Ali Veli` iv_tax = `10000000146` ).
    partner( iv_id = '2' iv_name = `Ayşe Kaya` iv_tax = `10000000146` ).
    find( ).
    cl_aunit_assert=>assert_equals( act = ms_line-reasons exp = `Same tax number 100******46` ).
  ENDMETHOD.


  METHOD spelling_variants.
    partner( iv_id = '1' iv_name = `Derya Tekstil San. ve Tic. A.Ş.` ).
    partner( iv_id = '2' iv_name = `DERYA TEKSTİL SANAYİ TİCARET ANONİM ŞİRKETİ` ).
    find( ).
    cl_aunit_assert=>assert_equals( act = ms_line-score exp = 70 ).
    cl_aunit_assert=>assert_equals( act = ms_line-reasons exp = `Same name` ).
  ENDMETHOD.


  METHOD typo_in_name.
    partner( iv_id = '1' iv_name = `Derya Tekstil A.Ş.` ).
    partner( iv_id = '2' iv_name = `Deria Tekstil AŞ` ).
    find( ).
    cl_aunit_assert=>assert_equals( act = mv_lines exp = 1 ).
    cl_aunit_assert=>assert_equals( act = ms_line-reasons exp = `Name 92% similar` ).
    cl_aunit_assert=>assert_equals( act = ms_line-score exp = 64 ).
  ENDMETHOD.


  METHOD different_companies.
    partner( iv_id = '1' iv_name = `Derya Tekstil A.Ş.` iv_tax = `1234567890` ).
    partner( iv_id = '2' iv_name = `Derya Gıda A.Ş.` iv_tax = `9876543217` ).
    find( ).
    cl_aunit_assert=>assert_equals( act = mv_lines exp = 0 ).
  ENDMETHOD.


  METHOD weak_signals_add_up.
    " Address 50 and phone 40: 1 - 0.5 * 0.6 = 70
    partner( iv_id = '1' iv_name = `Kuzey Lojistik` iv_street = `Atatürk Cad. 12` iv_phone = `0212 555 01 02` ).
    partner( iv_id = '2' iv_name = `Güney Nakliyat` iv_street = `ATATURK CAD 12` iv_phone = `+90 212 5550102` ).
    find( ).
    cl_aunit_assert=>assert_equals( act = ms_line-score exp = 70 ).
    cl_aunit_assert=>assert_equals( act = ms_line-reasons exp = `Same address; Same phone` ).
  ENDMETHOD.


  METHOD public_mail_domain_ignored.
    CREATE OBJECT mo_cut
      EXPORTING
        iv_threshold = 1.
    partner( iv_id = '1' iv_name = `Kuzey Lojistik` iv_email = `kuzey@gmail.com` ).
    partner( iv_id = '2' iv_name = `Güney Nakliyat` iv_email = `guney@gmail.com` ).
    partner( iv_id = '3' iv_name = `Batı Ticaret` iv_email = `satis@bati.com.tr` ).
    partner( iv_id = '4' iv_name = `Doğu Pazarlama` iv_email = `info@bati.com.tr` ).
    find( ).
    cl_aunit_assert=>assert_equals( act = mv_lines exp = 1 ).
    cl_aunit_assert=>assert_equals( act = ms_line-partner1 exp = '3' ).
    cl_aunit_assert=>assert_equals( act = ms_line-reasons exp = `Same e-mail domain bati.com.tr` ).
    cl_aunit_assert=>assert_equals( act = ms_line-score exp = 20 ).
  ENDMETHOD.


  METHOD rule_switched_off.
    DATA lt_rules TYPE lif_dupl=>ty_rule_settings.
    DATA ls_rule TYPE lif_dupl=>ty_rule_setting.

    ls_rule-rule = lif_dupl=>rule-tax_id.
    ls_rule-weight = 0.
    INSERT ls_rule INTO TABLE lt_rules.
    CREATE OBJECT mo_cut
      EXPORTING
        it_rules = lt_rules.
    partner( iv_id = '1' iv_name = `Derya Tekstil` iv_tax = `1234567890` ).
    partner( iv_id = '2' iv_name = `Mavi Gıda` iv_tax = `1234567890` ).
    find( ).
    cl_aunit_assert=>assert_equals( act = mv_lines exp = 0 ).
  ENDMETHOD.


  METHOD crowded_block_skipped.
    DATA lv_skipped TYPE string.
    DATA lv_count TYPE i.

    CREATE OBJECT mo_cut
      EXPORTING
        iv_max_block = 2
        iv_unmask    = abap_true.
    partner( iv_id = '1' iv_name = `Alfa` iv_tax = `1234567890` ).
    partner( iv_id = '2' iv_name = `Beta` iv_tax = `1234567890` ).
    partner( iv_id = '3' iv_name = `Gama` iv_tax = `1234567890` ).
    find( ).
    cl_aunit_assert=>assert_equals( act = mv_lines exp = 0 ).
    lv_count = lines( ms_result-skipped_blocks ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 1 ).
    READ TABLE ms_result-skipped_blocks INDEX 1 INTO lv_skipped.
    cl_aunit_assert=>assert_equals( act = lv_skipped exp = `Tax number 1234567890 (3 partners, not compared)` ).
  ENDMETHOD.


  METHOD pair_order.
    partner( iv_id = '9' iv_name = `Zeta` iv_iban = `TR33 0006 1005 1978 6457 8413 26` ).
    partner( iv_id = '4' iv_name = `Eta` iv_iban = `TR330006100519786457841326` ).
    find( ).
    cl_aunit_assert=>assert_equals( act = ms_line-partner1 exp = '4' ).
    cl_aunit_assert=>assert_equals( act = ms_line-partner2 exp = '9' ).
    cl_aunit_assert=>assert_equals( act = ms_line-score exp = 90 ).
  ENDMETHOD.


  METHOD similarity_values.
    similarity( iv_words1 = `DERYA TEKSTIL` iv_words2 = `DERYA TEKSTIL` iv_expected = 100 ).
    similarity( iv_words1 = `DERYA` iv_words2 = `` iv_expected = 0 ).
    " 7 edits in 13 letters (46) beat one shared word of three (33)
    similarity( iv_words1 = `DERYA TEKSTIL` iv_words2 = `DERYA GIDA` iv_expected = 46 ).
  ENDMETHOD.


  METHOD edit_distance.
    distance( iv_text1 = `KITTEN` iv_text2 = `SITTING` iv_expected = 3 ).
    distance( iv_text1 = `DERYA` iv_text2 = `DERIA` iv_expected = 1 ).
    distance( iv_text1 = `` iv_text2 = `ABC` iv_expected = 3 ).
    distance( iv_text1 = `ABC` iv_text2 = `ABC` iv_expected = 0 ).
  ENDMETHOD.

  METHOD block_members_bounded.
    DATA lt_blocks TYPE lcl_matcher=>ty_blocks.
    DATA ls_block TYPE lcl_matcher=>ty_block.
    DATA lv_index TYPE i.
    DATA lv_count TYPE i.
    DATA lv_member TYPE i.
    DATA lv_subrc TYPE sysubrc.

    CREATE OBJECT mo_cut EXPORTING iv_max_block = 2.
    DO 1000 TIMES.
      lv_index = sy-index.
      mo_cut->add_key( EXPORTING iv_prefix = 'W' iv_value = `TEKSTIL` iv_index = lv_index
                       CHANGING ct_blocks = lt_blocks ).
      mo_cut->add_key( EXPORTING iv_prefix = 'W' iv_value = `TEKSTIL` iv_index = lv_index
                       CHANGING ct_blocks = lt_blocks ).
    ENDDO.
    READ TABLE lt_blocks WITH TABLE KEY key = `W:TEKSTIL` INTO ls_block.
    lv_subrc = sy-subrc.
    cl_aunit_assert=>assert_equals( act = lv_subrc exp = 0 ).
    cl_aunit_assert=>assert_equals( act = ls_block-member_count exp = 1000 ).
    lv_count = lines( ls_block-members ).
    cl_aunit_assert=>assert_equals( act = lv_count exp = 3 ).
    READ TABLE ls_block-members INDEX 3 INTO lv_member.
    cl_aunit_assert=>assert_equals( act = lv_member exp = 3 ).
    cl_aunit_assert=>assert_equals( act = ls_block-last_index exp = 1000 ).
  ENDMETHOD.

  METHOD missing_street_not_evidence.
    DATA ls_address TYPE lif_dupl=>ty_address.
    DATA ls_partner TYPE lif_dupl=>ty_partner.

    ls_address-country = 'TR'.
    ls_address-post_code = `34000`.
    ls_address-house_no = `12`.
    ls_partner-partner = '1'.
    ls_partner-name = `Kuzey Lojistik`.
    APPEND ls_address TO ls_partner-addresses.
    APPEND `0212 555 01 02` TO ls_partner-phones.
    APPEND ls_partner TO mt_partners.
    CLEAR ls_partner.
    ls_partner-partner = '2'.
    ls_partner-name = `Guney Nakliyat`.
    APPEND ls_address TO ls_partner-addresses.
    APPEND `+90 212 5550102` TO ls_partner-phones.
    APPEND ls_partner TO mt_partners.
    find( ).
    cl_aunit_assert=>assert_initial( ms_result-lines ).
  ENDMETHOD.

  METHOD tax_id_letters_distinguish.
    partner( iv_id = '1' iv_name = `Alfa` iv_tax = `AB123` ).
    partner( iv_id = '2' iv_name = `Beta` iv_tax = `XY123` ).
    find( ).
    cl_aunit_assert=>assert_initial( ms_result-lines ).
  ENDMETHOD.

  METHOD formatted_tax_id_matches.
    partner( iv_id = '1' iv_name = `Alfa` iv_tax = `AB-123` ).
    partner( iv_id = '2' iv_name = `Beta` iv_tax = `AB 123` ).
    find( ).
    cl_aunit_assert=>assert_equals( act = mv_lines exp = 1 ).
    cl_aunit_assert=>assert_equals( act = ms_line-score exp = 95 ).
  ENDMETHOD.

ENDCLASS.


CLASS ltc_finder DEFINITION FINAL FOR TESTING.
  "#AU Risk_Level Harmless
  "#AU Duration Short
  PRIVATE SECTION.
    METHODS not_duplicate_hidden FOR TESTING.
    METHODS decided_pairs_shown FOR TESTING.
    METHODS invalid_tax_ids FOR TESTING.
    METHODS settings_checked FOR TESTING.
    METHODS tax_check_is_opt_in FOR TESTING.
    METHODS foreign_country_checked FOR TESTING.
    METHODS reference_date_required FOR TESTING.

    METHODS result
      RETURNING
        value(rs_result) TYPE lif_dupl=>ty_result.

    METHODS decisions
      RETURNING
        value(rt_decisions) TYPE lif_dupl=>ty_decisions.

    "! Asserts whether the settings are refused
    METHODS refused
      IMPORTING
        is_settings TYPE lif_dupl=>ty_settings
        iv_refused  TYPE abap_bool.
ENDCLASS.


CLASS ltc_finder IMPLEMENTATION.

  METHOD result.
    DATA ls_line TYPE lif_dupl=>ty_line.

    ls_line-finding = lif_dupl=>finding-duplicate.
    ls_line-score = 99.
    ls_line-partner1 = '1'.
    ls_line-partner2 = '2'.
    APPEND ls_line TO rs_result-lines.
    ls_line-score = 70.
    ls_line-partner1 = '3'.
    ls_line-partner2 = '4'.
    APPEND ls_line TO rs_result-lines.
    ls_line-score = 64.
    ls_line-partner1 = '1'.
    ls_line-partner2 = '5'.
    APPEND ls_line TO rs_result-lines.
  ENDMETHOD.


  METHOD decisions.
    DATA ls_decision TYPE lif_dupl=>ty_decision.

    ls_decision-partner1 = '1'.
    ls_decision-partner2 = '2'.
    ls_decision-decision = lif_dupl=>decision-duplicate.
    INSERT ls_decision INTO TABLE rt_decisions.
    ls_decision-partner1 = '3'.
    ls_decision-partner2 = '4'.
    ls_decision-decision = lif_dupl=>decision-not_duplicate.
    INSERT ls_decision INTO TABLE rt_decisions.
  ENDMETHOD.


  METHOD refused.
    DATA lv_problem TYPE string.
    DATA lv_refused TYPE abap_bool.

    lv_problem = lcl_app=>check_settings( is_settings ).
    IF lv_problem IS NOT INITIAL.
      lv_refused = abap_true.
    ENDIF.
    cl_aunit_assert=>assert_equals( act = lv_refused exp = iv_refused msg = lv_problem ).
  ENDMETHOD.


  METHOD not_duplicate_hidden.
    DATA ls_result TYPE lif_dupl=>ty_result.
    DATA lt_decisions TYPE lif_dupl=>ty_decisions.
    DATA ls_line TYPE lif_dupl=>ty_line.
    DATA lv_lines TYPE i.

    ls_result = result( ).
    lt_decisions = decisions( ).
    lcl_finder=>apply_decisions( EXPORTING it_decisions = lt_decisions iv_show_decided = abap_false
                                 CHANGING  cs_result    = ls_result ).
    lv_lines = lines( ls_result-lines ).
    cl_aunit_assert=>assert_equals( act = lv_lines exp = 2 ).
    cl_aunit_assert=>assert_equals( act = ls_result-hidden_pairs exp = 1 ).
    READ TABLE ls_result-lines INDEX 1 INTO ls_line.
    cl_aunit_assert=>assert_equals( act = ls_line-decision exp = lif_dupl=>decision-duplicate ).
    READ TABLE ls_result-lines INDEX 2 INTO ls_line.
    cl_aunit_assert=>assert_initial( ls_line-decision ).
  ENDMETHOD.


  METHOD decided_pairs_shown.
    DATA ls_result TYPE lif_dupl=>ty_result.
    DATA lt_decisions TYPE lif_dupl=>ty_decisions.
    DATA ls_line TYPE lif_dupl=>ty_line.
    DATA lv_lines TYPE i.

    ls_result = result( ).
    lt_decisions = decisions( ).
    lcl_finder=>apply_decisions( EXPORTING it_decisions = lt_decisions iv_show_decided = abap_true
                                 CHANGING  cs_result    = ls_result ).
    lv_lines = lines( ls_result-lines ).
    cl_aunit_assert=>assert_equals( act = lv_lines exp = 3 ).
    READ TABLE ls_result-lines INDEX 2 INTO ls_line.
    cl_aunit_assert=>assert_equals( act = ls_line-decision exp = lif_dupl=>decision-not_duplicate ).
    cl_aunit_assert=>assert_initial( ls_result-hidden_pairs ).
  ENDMETHOD.


  METHOD invalid_tax_ids.
    DATA ls_result TYPE lif_dupl=>ty_result.
    DATA ls_line TYPE lif_dupl=>ty_line.
    DATA lt_partners TYPE lif_dupl=>ty_partners.
    DATA ls_partner TYPE lif_dupl=>ty_partner.
    DATA lv_lines TYPE i.

    ls_partner-partner = '1'.
    ls_partner-name = `Ege Mermer`.
    APPEND `1234567891` TO ls_partner-tax_ids.
    APPEND ls_partner TO lt_partners.
    CLEAR ls_partner.
    ls_partner-partner = '2'.
    ls_partner-name = `Derya Tekstil`.
    APPEND `1234567890` TO ls_partner-tax_ids.
    APPEND ls_partner TO lt_partners.

    lcl_finder=>add_tax_id_findings( EXPORTING it_partners = lt_partners iv_unmask = abap_false iv_check = abap_true
                                     CHANGING  cs_result   = ls_result ).
    lv_lines = lines( ls_result-lines ).
    cl_aunit_assert=>assert_equals( act = lv_lines exp = 1 ).
    READ TABLE ls_result-lines INDEX 1 INTO ls_line.
    cl_aunit_assert=>assert_equals( act = ls_line-finding exp = lif_dupl=>finding-invalid_tax_id ).
    cl_aunit_assert=>assert_equals( act = ls_line-reasons
                                    exp = `Tax number (VKN) 123*****91: check digit is wrong` ).
    CLEAR ls_result.
    lcl_finder=>add_tax_id_findings( EXPORTING it_partners = lt_partners iv_unmask = abap_true iv_check = abap_true
                                     CHANGING  cs_result   = ls_result ).
    READ TABLE ls_result-lines INDEX 1 INTO ls_line.
    cl_aunit_assert=>assert_equals( act = ls_line-reasons
                                    exp = `Tax number (VKN) 1234567891: check digit is wrong` ).
  ENDMETHOD.


  METHOD settings_checked.
    DATA ls_settings TYPE lif_dupl=>ty_settings.
    FIELD-SYMBOLS <ls_rule> TYPE lif_dupl=>ty_rule_setting.

    ls_settings-tax_type = 'TR2'.
    ls_settings-key_date = '20261102'.
    ls_settings-threshold = 60.
    ls_settings-max_block = 200.
    ls_settings-rules = lcl_matcher=>default_rules( ).
    refused( is_settings = ls_settings iv_refused = abap_false ).
    ls_settings-threshold = 0.
    refused( is_settings = ls_settings iv_refused = abap_true ).
    ls_settings-threshold = 60.
    READ TABLE ls_settings-rules WITH TABLE KEY rule = lif_dupl=>rule-phone ASSIGNING <ls_rule>.
    <ls_rule>-weight = 101.
    refused( is_settings = ls_settings iv_refused = abap_true ).
    ls_settings-rules = lcl_matcher=>default_rules( ).
    CLEAR ls_settings-tax_type.
    refused( is_settings = ls_settings iv_refused = abap_true ).
  ENDMETHOD.

  METHOD tax_check_is_opt_in.
    DATA lt_partners TYPE lif_dupl=>ty_partners.
    DATA ls_partner TYPE lif_dupl=>ty_partner.
    DATA ls_result TYPE lif_dupl=>ty_result.
    DATA lv_lines TYPE i.

    ls_partner-partner = '1'.
    ls_partner-name = 'Foreign partner'.
    APPEND `123456789` TO ls_partner-tax_ids.
    APPEND ls_partner TO lt_partners.
    lcl_finder=>add_tax_id_findings( EXPORTING it_partners = lt_partners iv_unmask = abap_false
                                    CHANGING cs_result = ls_result ).
    cl_aunit_assert=>assert_initial( ls_result-lines ).
    lcl_finder=>add_tax_id_findings( EXPORTING it_partners = lt_partners iv_unmask = abap_false iv_check = abap_true
                                    CHANGING cs_result = ls_result ).
    lv_lines = lines( ls_result-lines ).
    cl_aunit_assert=>assert_equals( act = lv_lines exp = 1 ).
  ENDMETHOD.

  METHOD foreign_country_checked.
    DATA ls_settings TYPE lif_dupl=>ty_settings.
    FIELD-SYMBOLS <ls_rule> TYPE lif_dupl=>ty_rule_setting.

    ls_settings-key_date = '20261102'.
    ls_settings-tax_type = 'US1'.
    ls_settings-country = 'US'.
    ls_settings-tax_check = abap_true.
    ls_settings-threshold = 60.
    ls_settings-max_block = 200.
    ls_settings-rules = lcl_matcher=>default_rules( ).
    refused( is_settings = ls_settings iv_refused = abap_true ).
    ls_settings-tax_check = abap_false.
    refused( is_settings = ls_settings iv_refused = abap_false ).
    ls_settings-country = 'TR'.
    ls_settings-tax_check = abap_true.
    CLEAR ls_settings-tax_type.
    READ TABLE ls_settings-rules WITH TABLE KEY rule = lif_dupl=>rule-tax_id ASSIGNING <ls_rule>.
    <ls_rule>-weight = 0.
    refused( is_settings = ls_settings iv_refused = abap_true ).
  ENDMETHOD.

  METHOD reference_date_required.
    DATA ls_settings TYPE lif_dupl=>ty_settings.

    ls_settings-tax_type = 'TR2'.
    ls_settings-threshold = 60.
    ls_settings-max_block = 200.
    ls_settings-rules = lcl_matcher=>default_rules( ).
    refused( is_settings = ls_settings iv_refused = abap_true ).
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Events
*&---------------------------------------------------------------------*
INITIALIZATION.
  lcl_text=>set_selection_texts( ).

AT SELECTION-SCREEN.
  LOOP AT s_stop INTO gs_stop.
    IF gs_stop-sign <> 'I' OR gs_stop-option <> 'EQ'.
      gv_problem = lcl_text=>get( iv_en = 'Extra ignored words must be inclusive, exact values.'
                                  iv_tr = 'Ek yok sayılacak kelimeler dahil edilen tam değerler olmalı.' ).
      MESSAGE gv_problem TYPE 'E'.
    ENDIF.
  ENDLOOP.
  gs_settings = lcl_screen=>settings( ).
  gv_problem = lcl_app=>check_settings( gs_settings ).
  IF gv_problem IS NOT INITIAL.
    MESSAGE gv_problem TYPE 'E'.
  ENDIF.

START-OF-SELECTION.
  gs_settings = lcl_screen=>settings( ).
  lcl_app=>run( is_settings = gs_settings iv_show_decided = p_decid ).
