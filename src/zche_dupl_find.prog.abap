*&---------------------------------------------------------------------*
*& ZCHE_DUPL_FIND: find likely duplicate business partners
*& abap-partner-duplicates 0.2.0, https://github.com/Cheditte/abap-partner-duplicates
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Install: SE38, create executable program ZCHE_DUPL_FIND, paste this
*& source, activate. Nothing else is needed: no tables, no text elements.
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

DATA gv_word TYPE c LENGTH 40.

SELECTION-SCREEN BEGIN OF BLOCK b_read WITH FRAME TITLE t_read.
  PARAMETERS p_role TYPE bu_partnerrole.
  PARAMETERS p_group TYPE bu_group.
  PARAMETERS p_cntry TYPE land1.
  PARAMETERS p_taxty TYPE bptaxtype DEFAULT 'TR2'.
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


INTERFACE lif_dupl.
  CONSTANTS version TYPE string VALUE `0.2.0`.

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

  TYPES ty_strings TYPE STANDARD TABLE OF string WITH EMPTY KEY.

  TYPES:
    BEGIN OF ty_address,
      country   TYPE land1,
      post_code TYPE string,
      city      TYPE string,
      street    TYPE string,
      house_no  TYPE string,
    END OF ty_address,
    ty_addresses TYPE STANDARD TABLE OF ty_address WITH EMPTY KEY.

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
    ty_partners TYPE STANDARD TABLE OF ty_partner WITH EMPTY KEY.

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
    ty_lines TYPE STANDARD TABLE OF ty_line WITH EMPTY KEY.

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


"! The text says what is wrong and who can fix it
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

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
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


"! Texts for the screen and the list: Turkish when the user is logged on
"! in Turkish, English otherwise. The program needs no text elements.
CLASS lcl_text DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS get
      IMPORTING
        iv_en          TYPE csequence
        iv_tr          TYPE csequence
      RETURNING
        VALUE(rv_text) TYPE string.

    CLASS-METHODS set_selection_texts.
ENDCLASS.


CLASS lcl_text IMPLEMENTATION.

  METHOD get.
    rv_text = COND #( WHEN sy-langu = 'T' THEN iv_tr ELSE iv_en ).
  ENDMETHOD.


  METHOD set_selection_texts.
    " The function module needs exactly this table type (default key)
    DATA lt_texts TYPE STANDARD TABLE OF rsseltexts WITH DEFAULT KEY.

    t_read = get( iv_en = `Which partners` iv_tr = `Hangi cariler` ).
    t_rule = get( iv_en = `Rules` iv_tr = `Kurallar` ).
    t_out = get( iv_en = `Output` iv_tr = `Çıktı` ).
    t_hint = get( iv_en = `Weight 0-100: how sure one rule alone makes a pair. 0 = rule off.`
                  iv_tr = `Ağırlık 0-100: kural tek başına çifti ne kadar kesinleştirir. 0 = kapalı.` ).

    " Texts longer than 30 characters are cut on the screen
    lt_texts = VALUE #( kind = 'P'
      ( name = 'P_ROLE'   text = get( iv_en = `BP role (empty = all)`      iv_tr = `İş ortağı rolü (boş = tümü)` ) )
      ( name = 'P_GROUP'  text = get( iv_en = `BP grouping (empty = all)`  iv_tr = `Gruplama (boş = tümü)` ) )
      ( name = 'P_CNTRY'  text = get( iv_en = `Country (empty = all)`      iv_tr = `Ülke (boş = tümü)` ) )
      ( name = 'P_TAXTY'  text = get( iv_en = `Tax number category`        iv_tr = `Vergi numarası kategorisi` ) )
      ( name = 'P_WTAX'   text = get( iv_en = `Weight: same tax number`    iv_tr = `Ağırlık: aynı vergi no` ) )
      ( name = 'P_WIBAN'  text = get( iv_en = `Weight: same IBAN`          iv_tr = `Ağırlık: aynı IBAN` ) )
      ( name = 'P_WNAME'  text = get( iv_en = `Weight: similar name`       iv_tr = `Ağırlık: benzer isim` ) )
      ( name = 'P_MINSIM' text = get( iv_en = `Name similar at least (%)`  iv_tr = `İsim en az % kaç benzer` ) )
      ( name = 'P_WADDR'  text = get( iv_en = `Weight: same address`       iv_tr = `Ağırlık: aynı adres` ) )
      ( name = 'P_WPHONE' text = get( iv_en = `Weight: same phone`         iv_tr = `Ağırlık: aynı telefon` ) )
      ( name = 'P_WMAIL'  text = get( iv_en = `Weight: same e-mail`        iv_tr = `Ağırlık: aynı e-posta` ) )
      ( name = 'P_THRESH' text = get( iv_en = `Show pairs from score`      iv_tr = `Gösterilecek en düşük puan` ) )
      ( name = 'P_MAXBLK' text = get( iv_en = `Max. partners per key`      iv_tr = `Anahtar başına en çok cari` ) )
      ( name = 'P_UNMASK' text = get( iv_en = `Show full tax numbers`      iv_tr = `Vergi no ve IBAN tam görünsün` ) )
      ( name = 'P_DECID'  text = get( iv_en = `Show decided pairs`         iv_tr = `Karar verilmiş çiftleri göster` ) ) ).
    APPEND VALUE #( name = 'S_STOP' kind = 'S'
                    text = get( iv_en = `Extra words to ignore` iv_tr = `Yok sayılacak ek kelimeler` ) ) TO lt_texts.

    CALL FUNCTION 'SELECTION_TEXTS_MODIFY'
      EXPORTING
        program                     = sy-repid
      TABLES
        seltexts                    = lt_texts
      EXCEPTIONS
        program_not_found           = 1
        program_cannot_be_generated = 2
        OTHERS                      = 3.
    IF sy-subrc <> 0 ##NEEDED.
      " Without texts the screen still works; it shows the field names
    ENDIF.
  ENDMETHOD.

ENDCLASS.


"! Turkish tax numbers (VKN, TCKN). VKN has 10 digits (companies), TCKN
"! 11 digits (persons, also sole proprietors). Only the check digits are
"! calculated; nothing is looked up.
CLASS lcl_tax_id DEFINITION FINAL.
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

  PRIVATE SECTION.
    CLASS-METHODS digit
      IMPORTING
        iv_text         TYPE csequence
        iv_position     TYPE i
      RETURNING
        VALUE(rv_digit) TYPE i.
ENDCLASS.


CLASS lcl_tax_id IMPLEMENTATION.

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


"! Normalizes names, phones, e-mails and addresses. Case conversion of
"! i/I depends on the language (Turkish has i/İ and ı/I), so Turkish
"! letters are folded to A-Z with an own table first and the result does
"! not depend on the logon language.
CLASS lcl_normalizer DEFINITION FINAL.
  PUBLIC SECTION.
    "! Legal forms and generic trade words, always ignored in names
    CLASS-METHODS default_words
      RETURNING
        VALUE(rt_words) TYPE lif_dupl=>ty_strings.

    "! Free mail providers: the same domain says nothing about the company
    CLASS-METHODS free_mail_domains
      RETURNING
        VALUE(rt_domains) TYPE lif_dupl=>ty_strings.

    "! IT_EXTRA_WORDS are ignored in names in addition to the default words
    METHODS constructor
      IMPORTING
        it_extra_words TYPE lif_dupl=>ty_strings OPTIONAL.

    "! Upper case A-Z and 0-9 only, Turkish letters folded, single spaces
    METHODS simplify
      IMPORTING
        iv_text        TYPE csequence
      RETURNING
        VALUE(rv_text) TYPE string.

    "! Meaningful words of a name, sorted, without legal forms and one-letter words
    METHODS name_tokens
      IMPORTING
        iv_name          TYPE csequence
      RETURNING
        VALUE(rt_tokens) TYPE lif_dupl=>ty_strings.

    METHODS digits
      IMPORTING
        iv_text          TYPE csequence
      RETURNING
        VALUE(rv_digits) TYPE string.

    "! Last 10 digits, so 0212..., +90 212... and 212... are equal; empty below 7 digits
    METHODS phone_key
      IMPORTING
        iv_phone      TYPE csequence
      RETURNING
        VALUE(rv_key) TYPE string.

    METHODS email_key
      IMPORTING
        iv_email      TYPE csequence
      RETURNING
        VALUE(rv_key) TYPE string.

    "! Domain of a company address; empty for free mail providers
    METHODS email_domain
      IMPORTING
        iv_email         TYPE csequence
      RETURNING
        VALUE(rv_domain) TYPE string.

    METHODS iban_key
      IMPORTING
        iv_iban       TYPE csequence
      RETURNING
        VALUE(rv_key) TYPE string.

    "! Country, post code (or city) and street with house number; empty without street
    METHODS address_key
      IMPORTING
        is_address    TYPE lif_dupl=>ty_address
      RETURNING
        VALUE(rv_key) TYPE string.

  PRIVATE SECTION.
    CONSTANTS turkish_letters TYPE string VALUE `çCÇCğGĞGıIiIİIöOÖOşSŞSüUÜUâAÂAîIÎIûUÛUéEÉE`.
    DATA mt_stop_words TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.
ENDCLASS.


CLASS lcl_normalizer IMPLEMENTATION.

  METHOD constructor.
    DATA(lt_words) = default_words( ).
    APPEND LINES OF it_extra_words TO lt_words.
    LOOP AT lt_words INTO DATA(lv_word).
      SPLIT simplify( lv_word ) AT space INTO TABLE DATA(lt_parts).
      LOOP AT lt_parts INTO DATA(lv_part) WHERE table_line IS NOT INITIAL.
        INSERT lv_part INTO TABLE mt_stop_words.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD simplify.
    DATA lv_char TYPE c LENGTH 1.
    DATA(lv_text) = CONV string( iv_text ).
    TRANSLATE lv_text USING turkish_letters.
    lv_text = to_upper( lv_text ).
    DO strlen( lv_text ) TIMES.
      lv_char = substring( val = lv_text off = sy-index - 1 len = 1 ).
      IF lv_char CA sy-abcde OR lv_char CA '0123456789'.
        rv_text = rv_text && lv_char.
      ELSE.
        rv_text = rv_text && ` `.
      ENDIF.
    ENDDO.
    CONDENSE rv_text.
  ENDMETHOD.


  METHOD name_tokens.
    SPLIT simplify( iv_name ) AT space INTO TABLE DATA(lt_words).
    LOOP AT lt_words INTO DATA(lv_word).
      IF strlen( lv_word ) > 1 AND NOT line_exists( mt_stop_words[ table_line = lv_word ] ).
        APPEND lv_word TO rt_tokens.
      ENDIF.
    ENDLOOP.
    SORT rt_tokens BY table_line.
    DELETE ADJACENT DUPLICATES FROM rt_tokens COMPARING table_line.
  ENDMETHOD.


  METHOD default_words.
    DATA(lv_words) = `AS ANONIM SIRKETI SIRKET LTD STI LIMITED SAN SANAYI TIC TICARET VE ITH IHR`
                  && ` ITHALAT IHRACAT PAZ PAZARLAMA INS INSAAT TAAH TAAHHUT KOLL KOM KOMANDIT`
                  && ` KOOP KOOPERATIFI DIS IC INC CORP CO COMPANY LLC PLC GMBH AG SA`.
    SPLIT lv_words AT space INTO TABLE rt_words.
  ENDMETHOD.


  METHOD free_mail_domains.
    DATA(lv_domains) = `gmail.com hotmail.com hotmail.com.tr outlook.com outlook.com.tr live.com msn.com`
                    && ` yahoo.com yahoo.com.tr yandex.com yandex.com.tr icloud.com me.com mynet.com`
                    && ` windowslive.com gmx.de web.de proton.me protonmail.com`.
    SPLIT lv_domains AT space INTO TABLE rt_domains.
  ENDMETHOD.


  METHOD digits.
    DATA lv_char TYPE c LENGTH 1.
    DATA(lv_text) = CONV string( iv_text ).
    DO strlen( lv_text ) TIMES.
      lv_char = substring( val = lv_text off = sy-index - 1 len = 1 ).
      IF lv_char CA '0123456789'.
        rv_digits = rv_digits && lv_char.
      ENDIF.
    ENDDO.
  ENDMETHOD.


  METHOD phone_key.
    DATA(lv_digits) = digits( iv_phone ).
    DATA(lv_len) = strlen( lv_digits ).
    IF lv_len < 7.
      RETURN.
    ENDIF.
    rv_key = COND #( WHEN lv_len > 10 THEN substring( val = lv_digits off = lv_len - 10 ) ELSE lv_digits ).
  ENDMETHOD.


  METHOD email_key.
    rv_key = to_lower( condense( val = iv_email del = ` ` ) ).
    IF rv_key NS '@'.
      CLEAR rv_key.
    ENDIF.
  ENDMETHOD.


  METHOD email_domain.
    DATA(lv_email) = email_key( iv_email ).
    IF lv_email IS INITIAL.
      RETURN.
    ENDIF.
    SPLIT lv_email AT '@' INTO DATA(lv_local) rv_domain ##NEEDED.
    DATA(lt_public) = free_mail_domains( ).
    IF rv_domain IS INITIAL OR line_exists( lt_public[ table_line = rv_domain ] ).
      CLEAR rv_domain.
    ENDIF.
  ENDMETHOD.


  METHOD iban_key.
    rv_key = to_upper( replace( val = iv_iban sub = ` ` with = `` occ = 0 ) ).
  ENDMETHOD.


  METHOD address_key.
    " CADDESI, CADDE, CAD and CD are the same street word; so are SOKAK/SOKAGI/SOK/SK, ...
    SPLIT simplify( |{ is_address-street } { is_address-house_no }| ) AT space INTO TABLE DATA(lt_words).
    DATA(lv_street) = ``.
    LOOP AT lt_words INTO DATA(lv_word).
      lv_word = SWITCH #( lv_word
        WHEN `CADDESI` OR `CADDE` OR `CAD` THEN `CD`
        WHEN `SOKAK` OR `SOKAGI` OR `SOK` THEN `SK`
        WHEN `MAHALLESI` OR `MAHALLE` OR `MAH` THEN `MH`
        WHEN `BULVARI` OR `BULVAR` OR `BUL` THEN `BLV`
        WHEN `NO` OR `NUMARA` THEN ``
        ELSE lv_word ).
      IF lv_word IS NOT INITIAL.
        lv_street = condense( |{ lv_street } { lv_word }| ).
      ENDIF.
    ENDLOOP.
    IF lv_street IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_place) = simplify( is_address-post_code ).
    IF lv_place IS INITIAL.
      lv_place = simplify( is_address-city ).
    ENDIF.
    rv_key = |{ is_address-country }/{ lv_place }/{ lv_street }|.
  ENDMETHOD.

ENDCLASS.


"! Finds and scores likely duplicate pairs. No database access, so
"! everything here is covered by unit tests.
"!
"! Each rule that fires gives evidence c (0 to 100); evidence is combined
"! as score = 100 * (1 - (1 - c1/100) * (1 - c2/100) * ...), so two weak
"! signals together count more than one, and the score never exceeds 100.
"!
"! Only partners that share a key are compared ("blocking"): tax number,
"! IBAN, address, phone, e-mail, e-mail domain, the first three letters of
"! the first name word and the longest name word. A key shared by more than
"! MAX_BLOCK partners is skipped and reported, so one common word cannot
"! make the run compare everybody with everybody.
CLASS lcl_matcher DEFINITION FINAL.
  PUBLIC SECTION.
    CONSTANTS default_threshold TYPE i VALUE 60.
    CONSTANTS default_max_block TYPE i VALUE 200.

    CLASS-METHODS default_rules
      RETURNING
        VALUE(rt_rules) TYPE lif_dupl=>ty_rule_settings.

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
        VALUE(rs_result) TYPE lif_dupl=>ty_result.

    "! 0 to 100; the better of edit distance and shared words
    METHODS similarity
      IMPORTING
        it_tokens1        TYPE lif_dupl=>ty_strings
        it_tokens2        TYPE lif_dupl=>ty_strings
      RETURNING
        VALUE(rv_percent) TYPE i.

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
      ty_prepared_tab TYPE STANDARD TABLE OF ty_prepared WITH EMPTY KEY.

    TYPES ty_indexes TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_block,
        key     TYPE string,
        members TYPE ty_indexes,
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
        VALUE(rs_prepared) TYPE ty_prepared.

    METHODS add_keys
      IMPORTING
        is_prepared TYPE ty_prepared
        iv_index    TYPE i
      CHANGING
        ct_blocks   TYPE ty_blocks.

    METHODS add_key
      IMPORTING
        iv_key    TYPE string
        iv_index  TYPE i
      CHANGING
        ct_blocks TYPE ty_blocks.

    METHODS score
      IMPORTING
        is_one         TYPE ty_prepared
        is_other       TYPE ty_prepared
      RETURNING
        VALUE(rs_line) TYPE lif_dupl=>ty_line.

    METHODS weight
      IMPORTING
        iv_rule          TYPE lif_dupl=>ty_rule
      RETURNING
        VALUE(rv_weight) TYPE i.

    METHODS common
      IMPORTING
        it_values       TYPE lif_dupl=>ty_strings
        it_others       TYPE lif_dupl=>ty_strings
      RETURNING
        VALUE(rv_value) TYPE string.

    METHODS show
      IMPORTING
        iv_value       TYPE string
      RETURNING
        VALUE(rv_text) TYPE string.

    METHODS describe_key
      IMPORTING
        iv_key         TYPE string
        iv_count       TYPE i
      RETURNING
        VALUE(rv_text) TYPE string.
ENDCLASS.


CLASS lcl_matcher IMPLEMENTATION.

  METHOD default_rules.
    rt_rules = VALUE #(
      ( rule = lif_dupl=>rule-tax_id  weight = 95 )
      ( rule = lif_dupl=>rule-iban    weight = 90 )
      ( rule = lif_dupl=>rule-name    weight = 70 min_similarity = 85 )
      ( rule = lif_dupl=>rule-address weight = 50 )
      ( rule = lif_dupl=>rule-phone   weight = 40 )
      ( rule = lif_dupl=>rule-email   weight = 40 ) ).
  ENDMETHOD.


  METHOD constructor.
    mt_rules = default_rules( ).
    LOOP AT it_rules INTO DATA(ls_rule).
      MODIFY TABLE mt_rules FROM ls_rule.
      IF sy-subrc <> 0.
        INSERT ls_rule INTO TABLE mt_rules.
      ENDIF.
    ENDLOOP.
    mo_normalizer = COND #( WHEN io_normalizer IS BOUND THEN io_normalizer ELSE NEW #( ) ).
    mv_threshold = iv_threshold.
    mv_max_block = iv_max_block.
    mv_unmask = iv_unmask.
  ENDMETHOD.


  METHOD find.
    DATA lt_prepared TYPE ty_prepared_tab.
    DATA lt_blocks TYPE ty_blocks.
    DATA lt_candidates TYPE ty_candidates.

    rs_result-partners = lines( it_partners ).
    LOOP AT it_partners INTO DATA(ls_partner).
      APPEND prepare( ls_partner ) TO lt_prepared.
      DATA(lv_index) = lines( lt_prepared ).
      add_keys( EXPORTING is_prepared = lt_prepared[ lv_index ] iv_index = lv_index
                CHANGING  ct_blocks   = lt_blocks ).
    ENDLOOP.

    LOOP AT lt_blocks INTO DATA(ls_block) WHERE members IS NOT INITIAL.
      DATA(lv_count) = lines( ls_block-members ).
      IF lv_count < 2.
        CONTINUE.
      ENDIF.
      IF lv_count > mv_max_block.
        APPEND describe_key( iv_key = ls_block-key iv_count = lv_count ) TO rs_result-skipped_blocks.
        CONTINUE.
      ENDIF.
      LOOP AT ls_block-members INTO DATA(lv_index1).
        DATA(lv_from) = sy-tabix + 1.
        LOOP AT ls_block-members INTO DATA(lv_index2) FROM lv_from.
          INSERT VALUE #( index1 = nmin( val1 = lv_index1 val2 = lv_index2 )
                          index2 = nmax( val1 = lv_index1 val2 = lv_index2 ) ) INTO TABLE lt_candidates.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.

    LOOP AT lt_candidates INTO DATA(ls_candidate).
      DATA(ls_line) = score( is_one = lt_prepared[ ls_candidate-index1 ] is_other = lt_prepared[ ls_candidate-index2 ] ).
      IF ls_line-score >= mv_threshold AND ls_line-score > 0.
        APPEND ls_line TO rs_result-lines.
      ENDIF.
    ENDLOOP.
    SORT rs_result-lines BY score DESCENDING partner1 partner2.
    SORT rs_result-skipped_blocks BY table_line.
  ENDMETHOD.


  METHOD similarity.
    IF it_tokens1 IS INITIAL OR it_tokens2 IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_text1) = concat_lines_of( table = it_tokens1 sep = ` ` ).
    DATA(lv_text2) = concat_lines_of( table = it_tokens2 sep = ` ` ).
    IF lv_text1 = lv_text2.
      rv_percent = 100.
      RETURN.
    ENDIF.

    DATA(lv_longer) = nmax( val1 = strlen( lv_text1 ) val2 = strlen( lv_text2 ) ).
    DATA(lv_by_edits) = 100 - 100 * distance( val1 = lv_text1 val2 = lv_text2 ) / lv_longer.

    DATA(lv_shared) = REDUCE i( INIT n = 0
                                FOR lv_token IN it_tokens1 WHERE ( table_line IS NOT INITIAL )
                                NEXT n = n + COND i( WHEN line_exists( it_tokens2[ table_line = lv_token ] ) THEN 1 ) ).
    DATA(lv_all) = lines( it_tokens1 ) + lines( it_tokens2 ) - lv_shared.
    DATA(lv_by_words) = 100 * lv_shared / lv_all.

    rv_percent = nmax( val1 = lv_by_edits val2 = lv_by_words ).
    " Different names must not reach 100 by rounding
    IF rv_percent >= 100.
      rv_percent = 99.
    ENDIF.
  ENDMETHOD.


  METHOD prepare.
    rs_prepared-partner = is_partner-partner.
    rs_prepared-name = is_partner-name.
    rs_prepared-tokens = mo_normalizer->name_tokens( is_partner-name ).

    LOOP AT is_partner-tax_ids INTO DATA(lv_value).
      DATA(lv_key) = mo_normalizer->digits( lv_value ).
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
    LOOP AT is_partner-addresses INTO DATA(ls_address).
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
    DELETE ADJACENT DUPLICATES FROM: rs_prepared-tax_ids COMPARING table_line,
                                     rs_prepared-ibans COMPARING table_line,
                                     rs_prepared-addresses COMPARING table_line,
                                     rs_prepared-phones COMPARING table_line,
                                     rs_prepared-emails COMPARING table_line,
                                     rs_prepared-domains COMPARING table_line.
  ENDMETHOD.


  METHOD add_keys.
    IF weight( lif_dupl=>rule-tax_id ) > 0.
      LOOP AT is_prepared-tax_ids INTO DATA(lv_value).
        add_key( EXPORTING iv_key = |T:{ lv_value }| iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( lif_dupl=>rule-iban ) > 0.
      LOOP AT is_prepared-ibans INTO lv_value.
        add_key( EXPORTING iv_key = |I:{ lv_value }| iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( lif_dupl=>rule-address ) > 0.
      LOOP AT is_prepared-addresses INTO lv_value.
        add_key( EXPORTING iv_key = |A:{ lv_value }| iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( lif_dupl=>rule-phone ) > 0.
      LOOP AT is_prepared-phones INTO lv_value.
        add_key( EXPORTING iv_key = |P:{ lv_value }| iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( lif_dupl=>rule-email ) > 0.
      LOOP AT is_prepared-emails INTO lv_value.
        add_key( EXPORTING iv_key = |E:{ lv_value }| iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
      LOOP AT is_prepared-domains INTO lv_value.
        add_key( EXPORTING iv_key = |D:{ lv_value }| iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( lif_dupl=>rule-name ) > 0 AND is_prepared-tokens IS NOT INITIAL.
      DATA(lv_first) = is_prepared-tokens[ 1 ].
      add_key( EXPORTING iv_key   = |N:{ substring( val = lv_first len = nmin( val1 = 3 val2 = strlen( lv_first ) ) ) }|
                         iv_index = iv_index
               CHANGING  ct_blocks = ct_blocks ).
      DATA(lv_longest) = lv_first.
      LOOP AT is_prepared-tokens INTO lv_value.
        IF strlen( lv_value ) > strlen( lv_longest ).
          lv_longest = lv_value.
        ENDIF.
      ENDLOOP.
      add_key( EXPORTING iv_key = |W:{ lv_longest }| iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
    ENDIF.
  ENDMETHOD.


  METHOD add_key.
    ASSIGN ct_blocks[ key = iv_key ] TO FIELD-SYMBOL(<ls_block>).
    IF sy-subrc <> 0.
      INSERT VALUE #( key = iv_key ) INTO TABLE ct_blocks ASSIGNING <ls_block>.
    ENDIF.
    " A partner can produce the same key twice (two equal addresses)
    IF NOT line_exists( <ls_block>-members[ table_line = iv_index ] ).
      APPEND iv_index TO <ls_block>-members.
    ENDIF.
  ENDMETHOD.


  METHOD score.
    DATA lt_reasons TYPE lif_dupl=>ty_strings.
    DATA lv_rest TYPE decfloat34 VALUE 1.

    DATA(lv_value) = common( it_values = is_one-tax_ids it_others = is_other-tax_ids ).
    IF lv_value IS NOT INITIAL AND weight( lif_dupl=>rule-tax_id ) > 0.
      lv_rest = lv_rest * ( 100 - weight( lif_dupl=>rule-tax_id ) ) / 100.
      APPEND |Same tax number { show( lv_value ) }| TO lt_reasons.
    ENDIF.

    lv_value = common( it_values = is_one-ibans it_others = is_other-ibans ).
    IF lv_value IS NOT INITIAL AND weight( lif_dupl=>rule-iban ) > 0.
      lv_rest = lv_rest * ( 100 - weight( lif_dupl=>rule-iban ) ) / 100.
      APPEND |Same IBAN { show( lv_value ) }| TO lt_reasons.
    ENDIF.

    IF weight( lif_dupl=>rule-name ) > 0.
      DATA(lv_similarity) = similarity( it_tokens1 = is_one-tokens it_tokens2 = is_other-tokens ).
      DATA(lv_minimum) = mt_rules[ rule = lif_dupl=>rule-name ]-min_similarity.
      IF lv_similarity > 0 AND lv_similarity >= lv_minimum.
        lv_rest = lv_rest * ( 100 - weight( lif_dupl=>rule-name ) * lv_similarity / 100 ) / 100.
        APPEND COND string( WHEN lv_similarity = 100 THEN `Same name`
                            ELSE |Name { lv_similarity }% similar| ) TO lt_reasons.
      ENDIF.
    ENDIF.

    lv_value = common( it_values = is_one-addresses it_others = is_other-addresses ).
    IF lv_value IS NOT INITIAL AND weight( lif_dupl=>rule-address ) > 0.
      lv_rest = lv_rest * ( 100 - weight( lif_dupl=>rule-address ) ) / 100.
      APPEND `Same address` TO lt_reasons.
    ENDIF.

    lv_value = common( it_values = is_one-phones it_others = is_other-phones ).
    IF lv_value IS NOT INITIAL AND weight( lif_dupl=>rule-phone ) > 0.
      lv_rest = lv_rest * ( 100 - weight( lif_dupl=>rule-phone ) ) / 100.
      APPEND `Same phone` TO lt_reasons.
    ENDIF.

    IF weight( lif_dupl=>rule-email ) > 0.
      lv_value = common( it_values = is_one-emails it_others = is_other-emails ).
      IF lv_value IS NOT INITIAL.
        lv_rest = lv_rest * ( 100 - weight( lif_dupl=>rule-email ) ) / 100.
        APPEND `Same e-mail` TO lt_reasons.
      ELSE.
        lv_value = common( it_values = is_one-domains it_others = is_other-domains ).
        IF lv_value IS NOT INITIAL.
          " A shared company domain is weaker than the same address
          lv_rest = lv_rest * ( 100 - weight( lif_dupl=>rule-email ) / 2 ) / 100.
          APPEND |Same e-mail domain { lv_value }| TO lt_reasons.
        ENDIF.
      ENDIF.
    ENDIF.

    rs_line-finding = lif_dupl=>finding-duplicate.
    rs_line-score = round( val = 100 * ( 1 - lv_rest ) dec = 0 ).
    rs_line-reasons = concat_lines_of( table = lt_reasons sep = `; ` ).
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
    rv_weight = VALUE #( mt_rules[ rule = iv_rule ]-weight OPTIONAL ).
  ENDMETHOD.


  METHOD common.
    LOOP AT it_values INTO rv_value.
      IF line_exists( it_others[ table_line = rv_value ] ).
        RETURN.
      ENDIF.
    ENDLOOP.
    CLEAR rv_value.
  ENDMETHOD.


  METHOD show.
    rv_text = COND #( WHEN mv_unmask = abap_true THEN iv_value ELSE lcl_tax_id=>mask( iv_value ) ).
  ENDMETHOD.


  METHOD describe_key.
    DATA(lv_value) = substring( val = iv_key off = 2 ).
    rv_text = SWITCH #( iv_key(1)
      WHEN 'T' THEN |Tax number { show( lv_value ) }|
      WHEN 'I' THEN |IBAN { show( lv_value ) }|
      WHEN 'A' THEN |Address { lv_value }|
      WHEN 'P' THEN |Phone { lv_value }|
      WHEN 'E' THEN |E-mail { lv_value }|
      WHEN 'D' THEN |E-mail domain { lv_value }|
      WHEN 'N' THEN |Names starting with { lv_value }|
      WHEN 'W' THEN |Names with the word { lv_value }|
      ELSE lv_value ) && | ({ iv_count } partners, not compared)|.
  ENDMETHOD.

ENDCLASS.


"! Reads SAP business partners: BUT000 (names), BUT020/ADRC/ADR2/ADR6
"! (addresses, phones, e-mails), DFKKBPTAXNUM (tax numbers of the chosen
"! category) and BUT0BK (IBAN). Partners marked for deletion
"! (BUT000-XDELE) are left out.
"! For another source, change this class; it only has to fill
"! LIF_DUPL=>TY_PARTNERS.
CLASS lcl_source_bp DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS read
      IMPORTING
        is_settings        TYPE lif_dupl=>ty_settings
      RETURNING
        VALUE(rt_partners) TYPE lif_dupl=>ty_partners.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_key,
        partner TYPE bu_partner,
      END OF ty_key,
      ty_keys TYPE SORTED TABLE OF ty_key WITH UNIQUE KEY partner.
ENDCLASS.


CLASS lcl_source_bp IMPLEMENTATION.

  METHOD read.
    DATA lt_keys TYPE ty_keys.
    DATA lr_group TYPE RANGE OF bu_group.
    DATA lr_role TYPE RANGE OF bu_partnerrole.

    IF is_settings-bp_group IS NOT INITIAL.
      lr_group = VALUE #( ( sign = 'I' option = 'EQ' low = is_settings-bp_group ) ).
    ENDIF.

    IF is_settings-bp_role IS INITIAL.
      SELECT partner, type, name_org1, name_org2, name_org3, name_org4,
             name_first, name_last, name_grp1, name_grp2
        FROM but000
        WHERE bu_group IN @lr_group
          AND xdele = @abap_false
        ORDER BY partner
        INTO TABLE @DATA(lt_but000).
    ELSE.
      lr_role = VALUE #( ( sign = 'I' option = 'EQ' low = is_settings-bp_role ) ).
      SELECT partner, type, name_org1, name_org2, name_org3, name_org4,
             name_first, name_last, name_grp1, name_grp2
        FROM but000
        WHERE bu_group IN @lr_group
          AND xdele = @abap_false
          AND partner IN ( SELECT partner FROM but100 WHERE rltyp IN @lr_role )
        ORDER BY partner
        INTO TABLE @lt_but000.
    ENDIF.
    IF lt_but000 IS INITIAL.
      RETURN.
    ENDIF.
    lt_keys = CORRESPONDING #( lt_but000 ).

    SELECT b~partner, a~addrnumber, a~country, a~post_code1, a~city1, a~street, a~house_num1
      FROM but020 AS b
      INNER JOIN adrc AS a ON a~addrnumber = b~addrnumber
      FOR ALL ENTRIES IN @lt_keys
      WHERE b~partner = @lt_keys-partner
        AND a~nation = @space
      INTO TABLE @DATA(lt_addresses).
    SORT lt_addresses BY partner.

    IF lt_addresses IS NOT INITIAL.
      SELECT addrnumber, tel_number
        FROM adr2
        FOR ALL ENTRIES IN @lt_addresses
        WHERE addrnumber = @lt_addresses-addrnumber
          AND persnumber = @space
        INTO TABLE @DATA(lt_phones).
      SORT lt_phones BY addrnumber.

      SELECT addrnumber, smtp_addr
        FROM adr6
        FOR ALL ENTRIES IN @lt_addresses
        WHERE addrnumber = @lt_addresses-addrnumber
          AND persnumber = @space
        INTO TABLE @DATA(lt_emails).
      SORT lt_emails BY addrnumber.
    ENDIF.

    SELECT partner, taxnum, taxnumxl
      FROM dfkkbptaxnum
      FOR ALL ENTRIES IN @lt_keys
      WHERE partner = @lt_keys-partner
        AND taxtype = @is_settings-tax_type
      INTO TABLE @DATA(lt_taxes).
    SORT lt_taxes BY partner.

    SELECT partner, iban
      FROM but0bk
      FOR ALL ENTRIES IN @lt_keys
      WHERE partner = @lt_keys-partner
        AND iban <> @space
      INTO TABLE @DATA(lt_banks).
    SORT lt_banks BY partner.

    LOOP AT lt_but000 INTO DATA(ls_bp).
      DATA(ls_partner) = VALUE lif_dupl=>ty_partner( partner = ls_bp-partner ).
      ls_partner-name = condense( SWITCH string( ls_bp-type
        WHEN '1' THEN |{ ls_bp-name_first } { ls_bp-name_last }|
        WHEN '3' THEN |{ ls_bp-name_grp1 } { ls_bp-name_grp2 }|
        ELSE |{ ls_bp-name_org1 } { ls_bp-name_org2 } { ls_bp-name_org3 } { ls_bp-name_org4 }| ) ).

      DATA(lv_country_ok) = xsdbool( is_settings-country IS INITIAL ).
      READ TABLE lt_addresses TRANSPORTING NO FIELDS WITH KEY partner = ls_bp-partner BINARY SEARCH.
      LOOP AT lt_addresses INTO DATA(ls_address) FROM sy-tabix.
        IF ls_address-partner <> ls_bp-partner.
          EXIT.
        ENDIF.
        IF ls_address-country = is_settings-country.
          lv_country_ok = abap_true.
        ENDIF.
        APPEND VALUE #( country   = ls_address-country
                        post_code = ls_address-post_code1
                        city      = ls_address-city1
                        street    = ls_address-street
                        house_no  = ls_address-house_num1 ) TO ls_partner-addresses.
        READ TABLE lt_phones TRANSPORTING NO FIELDS WITH KEY addrnumber = ls_address-addrnumber BINARY SEARCH.
        LOOP AT lt_phones INTO DATA(ls_phone) FROM sy-tabix.
          IF ls_phone-addrnumber <> ls_address-addrnumber.
            EXIT.
          ENDIF.
          APPEND CONV string( ls_phone-tel_number ) TO ls_partner-phones.
        ENDLOOP.
        READ TABLE lt_emails TRANSPORTING NO FIELDS WITH KEY addrnumber = ls_address-addrnumber BINARY SEARCH.
        LOOP AT lt_emails INTO DATA(ls_email) FROM sy-tabix.
          IF ls_email-addrnumber <> ls_address-addrnumber.
            EXIT.
          ENDIF.
          APPEND CONV string( ls_email-smtp_addr ) TO ls_partner-emails.
        ENDLOOP.
      ENDLOOP.
      IF lv_country_ok = abap_false.
        CONTINUE.
      ENDIF.

      READ TABLE lt_taxes TRANSPORTING NO FIELDS WITH KEY partner = ls_bp-partner BINARY SEARCH.
      LOOP AT lt_taxes INTO DATA(ls_tax) FROM sy-tabix.
        IF ls_tax-partner <> ls_bp-partner.
          EXIT.
        ENDIF.
        APPEND COND string( WHEN ls_tax-taxnum IS NOT INITIAL THEN ls_tax-taxnum ELSE ls_tax-taxnumxl )
          TO ls_partner-tax_ids.
      ENDLOOP.

      READ TABLE lt_banks TRANSPORTING NO FIELDS WITH KEY partner = ls_bp-partner BINARY SEARCH.
      LOOP AT lt_banks INTO DATA(ls_bank) FROM sy-tabix.
        IF ls_bank-partner <> ls_bp-partner.
          EXIT.
        ENDIF.
        APPEND CONV string( ls_bank-iban ) TO ls_partner-ibans.
      ENDLOOP.

      APPEND ls_partner TO rt_partners.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.


"! Decisions per pair, kept in the standard cluster table INDX, so the
"! program needs no own table. Area ZC, ID ZCHE_DUPL_DECISIONS, one entry
"! per client.
CLASS lcl_decisions DEFINITION FINAL.
  PUBLIC SECTION.
    CONSTANTS c_id TYPE indx_srtfd VALUE 'ZCHE_DUPL_DECISIONS'.

    CLASS-METHODS load
      RETURNING
        VALUE(rt_decisions) TYPE lif_dupl=>ty_decisions.

    "! Saves a decision and commits
    CLASS-METHODS save
      IMPORTING
        iv_partner1 TYPE bu_partner
        iv_partner2 TYPE bu_partner
        iv_decision TYPE lif_dupl=>ty_decision_code
      RAISING
        lcx_error.
ENDCLASS.


CLASS lcl_decisions IMPLEMENTATION.

  METHOD load.
    IMPORT decisions = rt_decisions FROM DATABASE indx(zc) ID c_id.
    IF sy-subrc <> 0.
      CLEAR rt_decisions.
    ENDIF.
  ENDMETHOD.


  METHOD save.
    DATA lv_varkey TYPE rstable-varkey.

    " Two users deciding at the same time must not overwrite each other
    lv_varkey = |{ sy-mandt }ZC{ c_id }|.
    CALL FUNCTION 'ENQUEUE_E_TABLE'
      EXPORTING
        tabname        = 'INDX'
        varkey         = lv_varkey
        _wait          = abap_true
      EXCEPTIONS
        foreign_lock   = 1
        system_failure = 2
        OTHERS         = 3.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE lcx_error
        EXPORTING text = lcl_text=>get( iv_en = |Decisions are locked by user { sy-msgv1 }. Try again.|
                                        iv_tr = |Kararlar { sy-msgv1 } kullanıcısı tarafından kilitli. Tekrar deneyin.| ).
    ENDIF.

    DATA(lt_decisions) = load( ).
    " Same order as in the result lines: the smaller number first
    DATA(ls_decision) = VALUE lif_dupl=>ty_decision(
      partner1   = COND #( WHEN iv_partner1 <= iv_partner2 THEN iv_partner1 ELSE iv_partner2 )
      partner2   = COND #( WHEN iv_partner1 <= iv_partner2 THEN iv_partner2 ELSE iv_partner1 )
      decision   = iv_decision
      changed_by = sy-uname ).
    GET TIME STAMP FIELD ls_decision-changed_at.
    MODIFY TABLE lt_decisions FROM ls_decision.
    IF sy-subrc <> 0.
      INSERT ls_decision INTO TABLE lt_decisions.
    ENDIF.

    DATA(ls_indx) = VALUE indx( aedat = sy-datum usera = sy-uname pgmid = sy-repid ).
    EXPORT decisions = lt_decisions TO DATABASE indx(zc) FROM ls_indx ID c_id.
    COMMIT WORK.

    CALL FUNCTION 'DEQUEUE_E_TABLE'
      EXPORTING
        tabname = 'INDX'
        varkey  = lv_varkey.
  ENDMETHOD.

ENDCLASS.


"! Runs a search: source, matcher, decisions, tax number check
CLASS lcl_finder DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING
        is_settings TYPE lif_dupl=>ty_settings.

    METHODS run
      IMPORTING
        iv_show_decided  TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(rs_result) TYPE lif_dupl=>ty_result.

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
      CHANGING
        cs_result   TYPE lif_dupl=>ty_result.

  PRIVATE SECTION.
    DATA ms_settings TYPE lif_dupl=>ty_settings.
    DATA mo_matcher TYPE REF TO lcl_matcher.
ENDCLASS.


CLASS lcl_finder IMPLEMENTATION.

  METHOD constructor.
    ms_settings = is_settings.
    mo_matcher = NEW #( it_rules      = is_settings-rules
                        io_normalizer = NEW lcl_normalizer( is_settings-stop_words )
                        iv_threshold  = is_settings-threshold
                        iv_max_block  = is_settings-max_block
                        iv_unmask     = is_settings-unmask ).
  ENDMETHOD.


  METHOD run.
    DATA(lt_partners) = NEW lcl_source_bp( )->read( ms_settings ).
    rs_result = mo_matcher->find( lt_partners ).
    apply_decisions( EXPORTING it_decisions    = lcl_decisions=>load( )
                               iv_show_decided = iv_show_decided
                     CHANGING  cs_result       = rs_result ).
    add_tax_id_findings( EXPORTING it_partners = lt_partners
                                   iv_unmask   = ms_settings-unmask
                         CHANGING  cs_result   = rs_result ).
  ENDMETHOD.


  METHOD apply_decisions.
    LOOP AT cs_result-lines ASSIGNING FIELD-SYMBOL(<ls_line>).
      READ TABLE it_decisions INTO DATA(ls_decision)
        WITH TABLE KEY partner1 = <ls_line>-partner1 partner2 = <ls_line>-partner2.
      IF sy-subrc = 0.
        <ls_line>-decision = ls_decision-decision.
      ENDIF.
    ENDLOOP.

    IF iv_show_decided = abap_false.
      DATA(lv_before) = lines( cs_result-lines ).
      DELETE cs_result-lines WHERE decision = lif_dupl=>decision-not_duplicate.
      cs_result-hidden_pairs = lv_before - lines( cs_result-lines ).
    ENDIF.
  ENDMETHOD.


  METHOD add_tax_id_findings.
    LOOP AT it_partners INTO DATA(ls_partner).
      LOOP AT ls_partner-tax_ids INTO DATA(lv_tax_id).
        DATA(lv_problem) = lcl_tax_id=>check( lv_tax_id ).
        IF lv_problem IS NOT INITIAL.
          IF iv_unmask = abap_true.
            REPLACE lcl_tax_id=>mask( condense( val = lv_tax_id del = ` ` ) )
              IN lv_problem WITH condense( val = lv_tax_id del = ` ` ).
          ENDIF.
          APPEND VALUE #( finding  = lif_dupl=>finding-invalid_tax_id
                          partner1 = ls_partner-partner
                          name1    = ls_partner-name
                          reasons  = lv_problem ) TO cs_result-lines.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.


"! Selection screen in, ALV list out
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
      ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    "! Checks the screen; returns an error text or nothing
    CLASS-METHODS check_settings
      IMPORTING
        is_settings       TYPE lif_dupl=>ty_settings
      RETURNING
        VALUE(rv_problem) TYPE string.

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
        iv_en      TYPE string
        iv_tr      TYPE string
        iv_long_en TYPE string
        iv_long_tr TYPE string
      RAISING
        cx_salv_not_found.
ENDCLASS.


CLASS lcl_app IMPLEMENTATION.

  METHOD check_settings.
    LOOP AT is_settings-rules INTO DATA(ls_rule).
      IF ls_rule-weight NOT BETWEEN 0 AND 100 OR ls_rule-min_similarity NOT BETWEEN 0 AND 100.
        rv_problem = lcl_text=>get( iv_en = `Weights and the name similarity must be between 0 and 100.`
                                    iv_tr = `Ağırlıklar ve isim benzerliği 0 ile 100 arasında olmalı.` ).
        RETURN.
      ENDIF.
    ENDLOOP.
    IF is_settings-threshold NOT BETWEEN 1 AND 100.
      rv_problem = lcl_text=>get( iv_en = `The lowest score shown must be between 1 and 100.`
                                  iv_tr = `Gösterilecek en düşük puan 1 ile 100 arasında olmalı.` ).
    ELSEIF is_settings-max_block < 2.
      rv_problem = lcl_text=>get( iv_en = `Max. partners per key must be at least 2.`
                                  iv_tr = `Anahtar başına en çok cari en az 2 olmalı.` ).
    ELSEIF is_settings-tax_type IS INITIAL AND is_settings-rules[ rule = lif_dupl=>rule-tax_id ]-weight > 0.
      rv_problem = lcl_text=>get( iv_en = `Enter the tax number category (for example TR2), or set its weight to 0.`
                                  iv_tr = `Vergi numarası kategorisini girin (örneğin TR2) ya da ağırlığını 0 yapın.` ).
    ENDIF.
  ENDMETHOD.


  METHOD run.
    DATA(ls_result) = NEW lcl_finder( is_settings )->run( iv_show_decided ).

    LOOP AT ls_result-lines INTO DATA(ls_line).
      DATA(ls_row) = CORRESPONDING ty_row( ls_line ).
      IF ls_line-finding = lif_dupl=>finding-duplicate.
        ls_row-mark_dup = icon_okay.
        ls_row-mark_not = icon_cancel.
      ENDIF.
      APPEND ls_row TO gt_rows.
    ENDLOOP.

    DATA(lv_pairs) = REDUCE i( INIT n = 0 FOR r IN gt_rows WHERE ( finding = lif_dupl=>finding-duplicate ) NEXT n = n + 1 ).
    DATA(lv_invalid) = lines( gt_rows ) - lv_pairs.
    DATA(lv_summary) = lcl_text=>get(
      iv_en = |{ ls_result-partners } partners read: { lv_pairs } likely duplicate pairs, { lv_invalid } invalid tax numbers|
           && |{ COND #( WHEN ls_result-hidden_pairs > 0 THEN |, { ls_result-hidden_pairs } pairs hidden (marked not duplicate)| ) }|
      iv_tr = |{ ls_result-partners } cari okundu: { lv_pairs } olası mükerrer çift, { lv_invalid } hatalı vergi numarası|
           && |{ COND #( WHEN ls_result-hidden_pairs > 0 THEN |, { ls_result-hidden_pairs } çift gizlendi (mükerrer değil)| ) }| ).
    MESSAGE lv_summary TYPE 'S'.
    LOOP AT ls_result-skipped_blocks INTO DATA(lv_skipped).
      MESSAGE |{ lcl_text=>get( iv_en = `Not compared` iv_tr = `Karşılaştırılmadı` ) }: { lv_skipped }| TYPE 'S' DISPLAY LIKE 'W'.
    ENDLOOP.

    show( ).
  ENDMETHOD.


  METHOD show.
    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = go_alv
                                CHANGING  t_table      = gt_rows ).
      CATCH cx_salv_msg INTO DATA(lx_salv).
        MESSAGE lx_salv TYPE 'I' DISPLAY LIKE 'E'.
        RETURN.
    ENDTRY.

    go_alv->get_functions( )->set_all( ).
    DATA(lo_columns) = go_alv->get_columns( ).
    lo_columns->set_optimize( ).
    TRY.
        text( io_columns = lo_columns iv_column = 'FINDING'
              iv_en = `Finding` iv_tr = `Bulgu` iv_long_en = `Finding` iv_long_tr = `Bulgu` ).
        text( io_columns = lo_columns iv_column = 'SCORE'
              iv_en = `Score` iv_tr = `Puan` iv_long_en = `Score (0-100)` iv_long_tr = `Puan (0-100)` ).
        text( io_columns = lo_columns iv_column = 'PARTNER1'
              iv_en = `Partner` iv_tr = `Cari` iv_long_en = `Partner` iv_long_tr = `Cari` ).
        text( io_columns = lo_columns iv_column = 'NAME1'
              iv_en = `Name` iv_tr = `Ad` iv_long_en = `Name` iv_long_tr = `Ad` ).
        text( io_columns = lo_columns iv_column = 'PARTNER2'
              iv_en = `Partner 2` iv_tr = `Cari 2` iv_long_en = `Second partner` iv_long_tr = `İkinci cari` ).
        text( io_columns = lo_columns iv_column = 'NAME2'
              iv_en = `Name 2` iv_tr = `Ad 2` iv_long_en = `Name of second partner` iv_long_tr = `İkinci carinin adı` ).
        text( io_columns = lo_columns iv_column = 'REASONS'
              iv_en = `Reasons` iv_tr = `Nedenler` iv_long_en = `Reasons` iv_long_tr = `Nedenler` ).
        text( io_columns = lo_columns iv_column = 'DECISION'
              iv_en = `Decision` iv_tr = `Karar`
              iv_long_en = `Decision (D duplicate, N not)` iv_long_tr = `Karar (D mükerrer, N değil)` ).
        text( io_columns = lo_columns iv_column = 'MARK_DUP'
              iv_en = `Duplicate` iv_tr = `Mükerrer` iv_long_en = `Mark as duplicate` iv_long_tr = `Mükerrer olarak işaretle` ).
        text( io_columns = lo_columns iv_column = 'MARK_NOT'
              iv_en = `Not dup.` iv_tr = `Değil` iv_long_en = `Mark as not a duplicate` iv_long_tr = `Mükerrer değil olarak işaretle` ).
        CAST cl_salv_column_table( lo_columns->get_column( 'MARK_DUP' ) )->set_cell_type( if_salv_c_cell_type=>hotspot ).
        CAST cl_salv_column_table( lo_columns->get_column( 'MARK_NOT' ) )->set_cell_type( if_salv_c_cell_type=>hotspot ).
        CAST cl_salv_column_table( lo_columns->get_column( 'MARK_DUP' ) )->set_icon( abap_true ).
        CAST cl_salv_column_table( lo_columns->get_column( 'MARK_NOT' ) )->set_icon( abap_true ).
      CATCH cx_salv_not_found ##NO_HANDLER.
    ENDTRY.
    SET HANDLER on_link_click FOR go_alv->get_event( ).
    go_alv->display( ).
  ENDMETHOD.


  METHOD on_link_click.
    ASSIGN gt_rows[ row ] TO FIELD-SYMBOL(<ls_row>).
    IF sy-subrc <> 0 OR <ls_row>-finding <> lif_dupl=>finding-duplicate.
      RETURN.
    ENDIF.
    DATA(lv_decision) = SWITCH lif_dupl=>ty_decision_code( column
      WHEN 'MARK_DUP' THEN lif_dupl=>decision-duplicate
      WHEN 'MARK_NOT' THEN lif_dupl=>decision-not_duplicate ).
    IF lv_decision IS INITIAL.
      RETURN.
    ENDIF.
    TRY.
        lcl_decisions=>save( iv_partner1 = <ls_row>-partner1
                             iv_partner2 = <ls_row>-partner2
                             iv_decision = lv_decision ).
      CATCH lcx_error INTO DATA(lx_error).
        MESSAGE lx_error->get_text( ) TYPE 'I' DISPLAY LIKE 'E'.
        RETURN.
    ENDTRY.
    <ls_row>-decision = lv_decision.
    MESSAGE |{ lcl_text=>get( iv_en = `Saved` iv_tr = `Kaydedildi` ) }: { <ls_row>-partner1 } / { <ls_row>-partner2 } = { lv_decision }|
      TYPE 'S'.
    go_alv->refresh( ).
  ENDMETHOD.


  METHOD text.
    DATA(lo_column) = io_columns->get_column( iv_column ).
    DATA(lv_text) = lcl_text=>get( iv_en = iv_en iv_tr = iv_tr ).
    lo_column->set_short_text( CONV #( lv_text ) ).
    lo_column->set_medium_text( CONV #( lv_text ) ).
    lo_column->set_long_text( CONV #( lcl_text=>get( iv_en = iv_long_en iv_tr = iv_long_tr ) ) ).
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Unit tests (in ADT: Ctrl+Shift+F10; in SE38: Program > Execute >
*& Unit Tests). All names, numbers and addresses are made up; check
*& digits of the test numbers were calculated separately.
*&---------------------------------------------------------------------*
CLASS ltc_tax_id DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS vkn_valid FOR TESTING.
    METHODS vkn_wrong_check_digit FOR TESTING.
    METHODS tckn_valid FOR TESTING.
    METHODS tckn_wrong FOR TESTING.
    METHODS check_texts FOR TESTING.
    METHODS mask FOR TESTING.
ENDCLASS.


CLASS ltc_tax_id IMPLEMENTATION.

  METHOD vkn_valid.
    cl_abap_unit_assert=>assert_true( lcl_tax_id=>is_valid_vkn( `1234567890` ) ).
    cl_abap_unit_assert=>assert_true( lcl_tax_id=>is_valid_vkn( `9876543217` ) ).
    cl_abap_unit_assert=>assert_true( lcl_tax_id=>is_valid_vkn( `5550001112` ) ).
  ENDMETHOD.


  METHOD vkn_wrong_check_digit.
    cl_abap_unit_assert=>assert_false( lcl_tax_id=>is_valid_vkn( `1234567891` ) ).
    cl_abap_unit_assert=>assert_false( lcl_tax_id=>is_valid_vkn( `123456789` ) ).
    cl_abap_unit_assert=>assert_false( lcl_tax_id=>is_valid_vkn( `12345678A0` ) ).
  ENDMETHOD.


  METHOD tckn_valid.
    cl_abap_unit_assert=>assert_true( lcl_tax_id=>is_valid_tckn( `10000000146` ) ).
    cl_abap_unit_assert=>assert_true( lcl_tax_id=>is_valid_tckn( `12345678950` ) ).
  ENDMETHOD.


  METHOD tckn_wrong.
    cl_abap_unit_assert=>assert_false( lcl_tax_id=>is_valid_tckn( `10000000147` ) ).
    cl_abap_unit_assert=>assert_false( lcl_tax_id=>is_valid_tckn( `01234567890` ) ).
  ENDMETHOD.


  METHOD check_texts.
    cl_abap_unit_assert=>assert_initial( lcl_tax_id=>check( `1234567890` ) ).
    cl_abap_unit_assert=>assert_initial( lcl_tax_id=>check( ` 10000000146 ` ) ).
    cl_abap_unit_assert=>assert_equals( act = lcl_tax_id=>check( `1234567891` )
                                        exp = `Tax number (VKN) 123*****91: check digit is wrong` ).
    cl_abap_unit_assert=>assert_equals( act = lcl_tax_id=>check( `12345` )
                                        exp = `Tax number ***** has 5 digits; VKN has 10, TCKN 11` ).
  ENDMETHOD.


  METHOD mask.
    cl_abap_unit_assert=>assert_equals( act = lcl_tax_id=>mask( `10000000146` ) exp = `100******46` ).
  ENDMETHOD.

ENDCLASS.


CLASS ltc_normalizer DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

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
ENDCLASS.


CLASS ltc_normalizer IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( ).
  ENDMETHOD.


  METHOD turkish_letters.
    cl_abap_unit_assert=>assert_equals( act = mo_cut->simplify( `İzmir ığdır ÇİĞDEM şükrü Öz` )
                                        exp = `IZMIR IGDIR CIGDEM SUKRU OZ` ).
    " Lower case i must not become a dotted capital in any logon language
    cl_abap_unit_assert=>assert_equals( act = mo_cut->simplify( `existing` ) exp = `EXISTING` ).
  ENDMETHOD.


  METHOD punctuation.
    cl_abap_unit_assert=>assert_equals( act = mo_cut->simplify( `  A.B.C.  Tekstil-San.,Tic. ` )
                                        exp = `A B C TEKSTIL SAN TIC` ).
  ENDMETHOD.


  METHOD legal_forms_removed.
    DATA(lt_exp) = VALUE lif_dupl=>ty_strings( ( `DERYA` ) ( `TEKSTIL` ) ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->name_tokens( `Derya Tekstil San. ve Tic. A.Ş.` ) exp = lt_exp ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->name_tokens( `DERYA TEKSTİL SANAYİ TİCARET ANONİM ŞİRKETİ` ) exp = lt_exp ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->name_tokens( `Derya Tekstil Ltd. Şti.` ) exp = lt_exp ).
  ENDMETHOD.


  METHOD word_order_ignored.
    cl_abap_unit_assert=>assert_equals( act = mo_cut->name_tokens( `Tekstil Derya` )
                                        exp = mo_cut->name_tokens( `Derya Tekstil` ) ).
  ENDMETHOD.


  METHOD extra_stop_words.
    " Extra words are ignored together with the built-in ones
    mo_cut = NEW #( VALUE #( ( `Holding` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->name_tokens( `Derya Holding Ltd.` )
                                        exp = VALUE lif_dupl=>ty_strings( ( `DERYA` ) ) ).
  ENDMETHOD.


  METHOD phone.
    cl_abap_unit_assert=>assert_equals( act = mo_cut->phone_key( `+90 (212) 555 01 02` ) exp = `2125550102` ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->phone_key( `0212 555 0102` ) exp = `2125550102` ).
    cl_abap_unit_assert=>assert_initial( mo_cut->phone_key( `1234` ) ).
  ENDMETHOD.


  METHOD email.
    cl_abap_unit_assert=>assert_equals( act = mo_cut->email_key( ` Info@Derya.com.tr ` ) exp = `info@derya.com.tr` ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->email_domain( `satis@derya.com.tr` ) exp = `derya.com.tr` ).
    cl_abap_unit_assert=>assert_initial( mo_cut->email_domain( `derya.tekstil@gmail.com` ) ).
    cl_abap_unit_assert=>assert_initial( mo_cut->email_key( `no address` ) ).
  ENDMETHOD.


  METHOD address.
    DATA(lv_key) = mo_cut->address_key( VALUE #( country = 'TR' post_code = `34000` city = `İstanbul`
                                                 street = `Atatürk Cad.` house_no = `12/3` ) ).
    cl_abap_unit_assert=>assert_equals( act = lv_key exp = `TR/34000/ATATURK CD 12 3` ).
    " Street words written out or abbreviated give the same key
    cl_abap_unit_assert=>assert_equals(
      act = mo_cut->address_key( VALUE #( country = 'TR' post_code = `34000` street = `ATATURK CADDESI No: 12/3` ) )
      exp = lv_key ).
    cl_abap_unit_assert=>assert_equals(
      act = mo_cut->address_key( VALUE #( country = 'TR' post_code = `06000` street = `Lale Sok.` house_no = `7` ) )
      exp = mo_cut->address_key( VALUE #( country = 'TR' post_code = `06000` street = `Lale Sokağı` house_no = `7` ) ) ).
    lv_key = mo_cut->address_key( VALUE #( country = 'TR' city = `İzmir` street = `Kordon` ) ).
    cl_abap_unit_assert=>assert_equals( act = lv_key exp = `TR/IZMIR/KORDON` ).
    cl_abap_unit_assert=>assert_initial( mo_cut->address_key( VALUE #( country = 'TR' city = `İzmir` ) ) ).
  ENDMETHOD.

ENDCLASS.


CLASS ltc_matcher DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO lcl_matcher.

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

    METHODS partner
      IMPORTING
        iv_id             TYPE bu_partner
        iv_name           TYPE string
        iv_tax            TYPE string OPTIONAL
        iv_iban           TYPE string OPTIONAL
        iv_street         TYPE string OPTIONAL
        iv_phone          TYPE string OPTIONAL
        iv_email          TYPE string OPTIONAL
      RETURNING
        VALUE(rs_partner) TYPE lif_dupl=>ty_partner.
ENDCLASS.


CLASS ltc_matcher IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( iv_unmask = abap_true ).
  ENDMETHOD.


  METHOD partner.
    rs_partner-partner = iv_id.
    rs_partner-name = iv_name.
    IF iv_tax IS NOT INITIAL.
      rs_partner-tax_ids = VALUE #( ( iv_tax ) ).
    ENDIF.
    IF iv_iban IS NOT INITIAL.
      rs_partner-ibans = VALUE #( ( iv_iban ) ).
    ENDIF.
    IF iv_street IS NOT INITIAL.
      rs_partner-addresses = VALUE #( ( country = 'TR' post_code = `34000` city = `Istanbul` street = iv_street ) ).
    ENDIF.
    IF iv_phone IS NOT INITIAL.
      rs_partner-phones = VALUE #( ( iv_phone ) ).
    ENDIF.
    IF iv_email IS NOT INITIAL.
      rs_partner-emails = VALUE #( ( iv_email ) ).
    ENDIF.
  ENDMETHOD.


  METHOD same_tax_number.
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Derya Tekstil A.Ş.` iv_tax = `1234567890` ) )
      ( partner( iv_id = '2' iv_name = `Mavi Gıda Ltd.` iv_tax = `1234567890` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-lines ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-score exp = 95 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-reasons exp = `Same tax number 1234567890` ).
  ENDMETHOD.


  METHOD tax_number_masked.
    mo_cut = NEW #( ).
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Ali Veli` iv_tax = `10000000146` ) )
      ( partner( iv_id = '2' iv_name = `Ayşe Kaya` iv_tax = `10000000146` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-reasons exp = `Same tax number 100******46` ).
  ENDMETHOD.


  METHOD spelling_variants.
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Derya Tekstil San. ve Tic. A.Ş.` ) )
      ( partner( iv_id = '2' iv_name = `DERYA TEKSTİL SANAYİ TİCARET ANONİM ŞİRKETİ` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-score exp = 70 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-reasons exp = `Same name` ).
  ENDMETHOD.


  METHOD typo_in_name.
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Derya Tekstil A.Ş.` ) )
      ( partner( iv_id = '2' iv_name = `Deria Tekstil AŞ` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-lines ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-reasons exp = `Name 92% similar` ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-score exp = 64 ).
  ENDMETHOD.


  METHOD different_companies.
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Derya Tekstil A.Ş.` iv_tax = `1234567890` ) )
      ( partner( iv_id = '2' iv_name = `Derya Gıda A.Ş.` iv_tax = `9876543217` ) ) ) ).
    cl_abap_unit_assert=>assert_initial( ls_result-lines ).
  ENDMETHOD.


  METHOD weak_signals_add_up.
    " Address 50 and phone 40: 1 - 0.5 * 0.6 = 70
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Kuzey Lojistik` iv_street = `Atatürk Cad. 12` iv_phone = `0212 555 01 02` ) )
      ( partner( iv_id = '2' iv_name = `Güney Nakliyat` iv_street = `ATATURK CAD 12` iv_phone = `+90 212 5550102` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-score exp = 70 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-reasons exp = `Same address; Same phone` ).
  ENDMETHOD.


  METHOD public_mail_domain_ignored.
    mo_cut = NEW #( iv_threshold = 1 ).
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Kuzey Lojistik` iv_email = `kuzey@gmail.com` ) )
      ( partner( iv_id = '2' iv_name = `Güney Nakliyat` iv_email = `guney@gmail.com` ) )
      ( partner( iv_id = '3' iv_name = `Batı Ticaret` iv_email = `satis@bati.com.tr` ) )
      ( partner( iv_id = '4' iv_name = `Doğu Pazarlama` iv_email = `info@bati.com.tr` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-lines ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-partner1 exp = '3' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-reasons exp = `Same e-mail domain bati.com.tr` ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-score exp = 20 ).
  ENDMETHOD.


  METHOD rule_switched_off.
    mo_cut = NEW #( it_rules = VALUE #( ( rule = lif_dupl=>rule-tax_id weight = 0 ) ) ).
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Derya Tekstil` iv_tax = `1234567890` ) )
      ( partner( iv_id = '2' iv_name = `Mavi Gıda` iv_tax = `1234567890` ) ) ) ).
    cl_abap_unit_assert=>assert_initial( ls_result-lines ).
  ENDMETHOD.


  METHOD crowded_block_skipped.
    mo_cut = NEW #( iv_max_block = 2 iv_unmask = abap_true ).
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Alfa` iv_tax = `1234567890` ) )
      ( partner( iv_id = '2' iv_name = `Beta` iv_tax = `1234567890` ) )
      ( partner( iv_id = '3' iv_name = `Gama` iv_tax = `1234567890` ) ) ) ).
    cl_abap_unit_assert=>assert_initial( ls_result-lines ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-skipped_blocks
                                        exp = VALUE lif_dupl=>ty_strings(
                                          ( `Tax number 1234567890 (3 partners, not compared)` ) ) ).
  ENDMETHOD.


  METHOD pair_order.
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '9' iv_name = `Zeta` iv_iban = `TR33 0006 1005 1978 6457 8413 26` ) )
      ( partner( iv_id = '4' iv_name = `Eta` iv_iban = `TR330006100519786457841326` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-partner1 exp = '4' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-partner2 exp = '9' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-score exp = 90 ).
  ENDMETHOD.


  METHOD similarity_values.
    cl_abap_unit_assert=>assert_equals(
      act = mo_cut->similarity( it_tokens1 = VALUE #( ( `DERYA` ) ( `TEKSTIL` ) )
                                it_tokens2 = VALUE #( ( `DERYA` ) ( `TEKSTIL` ) ) )
      exp = 100 ).
    cl_abap_unit_assert=>assert_initial( mo_cut->similarity( it_tokens1 = VALUE #( ( `DERYA` ) )
                                                             it_tokens2 = VALUE #( ) ) ).
    " 7 edits in 13 letters (46) beat one shared word of three (33)
    cl_abap_unit_assert=>assert_equals(
      act = mo_cut->similarity( it_tokens1 = VALUE #( ( `DERYA` ) ( `TEKSTIL` ) )
                                it_tokens2 = VALUE #( ( `DERYA` ) ( `GIDA` ) ) )
      exp = 46 ).
  ENDMETHOD.

ENDCLASS.


CLASS ltc_finder DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS not_duplicate_hidden FOR TESTING.
    METHODS decided_pairs_shown FOR TESTING.
    METHODS invalid_tax_ids FOR TESTING.
    METHODS settings_checked FOR TESTING.

    METHODS result
      RETURNING
        VALUE(rs_result) TYPE lif_dupl=>ty_result.

    METHODS decisions
      RETURNING
        VALUE(rt_decisions) TYPE lif_dupl=>ty_decisions.
ENDCLASS.


CLASS ltc_finder IMPLEMENTATION.

  METHOD result.
    rs_result-lines = VALUE #( finding = lif_dupl=>finding-duplicate
      ( score = 99 partner1 = '1' partner2 = '2' )
      ( score = 70 partner1 = '3' partner2 = '4' )
      ( score = 64 partner1 = '1' partner2 = '5' ) ).
  ENDMETHOD.


  METHOD decisions.
    rt_decisions = VALUE #(
      ( partner1 = '1' partner2 = '2' decision = lif_dupl=>decision-duplicate )
      ( partner1 = '3' partner2 = '4' decision = lif_dupl=>decision-not_duplicate ) ).
  ENDMETHOD.


  METHOD not_duplicate_hidden.
    DATA(ls_result) = result( ).
    lcl_finder=>apply_decisions( EXPORTING it_decisions = decisions( ) iv_show_decided = abap_false
                                 CHANGING  cs_result    = ls_result ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-lines ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-hidden_pairs exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-decision exp = lif_dupl=>decision-duplicate ).
    cl_abap_unit_assert=>assert_initial( ls_result-lines[ 2 ]-decision ).
  ENDMETHOD.


  METHOD decided_pairs_shown.
    DATA(ls_result) = result( ).
    lcl_finder=>apply_decisions( EXPORTING it_decisions = decisions( ) iv_show_decided = abap_true
                                 CHANGING  cs_result    = ls_result ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-lines ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 2 ]-decision exp = lif_dupl=>decision-not_duplicate ).
    cl_abap_unit_assert=>assert_initial( ls_result-hidden_pairs ).
  ENDMETHOD.


  METHOD invalid_tax_ids.
    DATA ls_result TYPE lif_dupl=>ty_result.
    DATA(lt_partners) = VALUE lif_dupl=>ty_partners(
      ( partner = '1' name = `Ege Mermer` tax_ids = VALUE #( ( `1234567891` ) ) )
      ( partner = '2' name = `Derya Tekstil` tax_ids = VALUE #( ( `1234567890` ) ) ) ).
    lcl_finder=>add_tax_id_findings( EXPORTING it_partners = lt_partners iv_unmask = abap_false
                                     CHANGING  cs_result   = ls_result ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-lines ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-finding exp = lif_dupl=>finding-invalid_tax_id ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-reasons
                                        exp = `Tax number (VKN) 123*****91: check digit is wrong` ).
    CLEAR ls_result.
    lcl_finder=>add_tax_id_findings( EXPORTING it_partners = lt_partners iv_unmask = abap_true
                                     CHANGING  cs_result   = ls_result ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-reasons
                                        exp = `Tax number (VKN) 1234567891: check digit is wrong` ).
  ENDMETHOD.


  METHOD settings_checked.
    DATA(ls_settings) = VALUE lif_dupl=>ty_settings( tax_type = 'TR2' threshold = 60 max_block = 200
                                                     rules = lcl_matcher=>default_rules( ) ).
    cl_abap_unit_assert=>assert_initial( lcl_app=>check_settings( ls_settings ) ).
    ls_settings-threshold = 0.
    cl_abap_unit_assert=>assert_not_initial( lcl_app=>check_settings( ls_settings ) ).
    ls_settings-threshold = 60.
    ls_settings-rules[ rule = lif_dupl=>rule-phone ]-weight = 101.
    cl_abap_unit_assert=>assert_not_initial( lcl_app=>check_settings( ls_settings ) ).
    ls_settings-rules = lcl_matcher=>default_rules( ).
    CLEAR ls_settings-tax_type.
    cl_abap_unit_assert=>assert_not_initial( lcl_app=>check_settings( ls_settings ) ).
  ENDMETHOD.

ENDCLASS.


*&---------------------------------------------------------------------*
*& Events
*&---------------------------------------------------------------------*
CLASS lcl_screen DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS settings
      RETURNING
        VALUE(rs_settings) TYPE lif_dupl=>ty_settings.
ENDCLASS.


CLASS lcl_screen IMPLEMENTATION.

  METHOD settings.
    rs_settings = VALUE #(
      tax_type  = p_taxty
      bp_role   = p_role
      bp_group  = p_group
      country   = p_cntry
      threshold = p_thresh
      max_block = p_maxblk
      unmask    = p_unmask
      rules     = VALUE #( ( rule = lif_dupl=>rule-tax_id  weight = p_wtax )
                           ( rule = lif_dupl=>rule-iban    weight = p_wiban )
                           ( rule = lif_dupl=>rule-name    weight = p_wname min_similarity = p_minsim )
                           ( rule = lif_dupl=>rule-address weight = p_waddr )
                           ( rule = lif_dupl=>rule-phone   weight = p_wphone )
                           ( rule = lif_dupl=>rule-email   weight = p_wmail ) ) ).
    LOOP AT s_stop INTO DATA(ls_stop) WHERE sign = 'I' AND option = 'EQ'.
      APPEND CONV string( ls_stop-low ) TO rs_settings-stop_words.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.


INITIALIZATION.
  lcl_text=>set_selection_texts( ).

AT SELECTION-SCREEN.
  DATA(gv_problem) = lcl_app=>check_settings( lcl_screen=>settings( ) ).
  IF gv_problem IS NOT INITIAL.
    MESSAGE gv_problem TYPE 'E'.
  ENDIF.

START-OF-SELECTION.
  lcl_app=>run( is_settings = lcl_screen=>settings( ) iv_show_decided = p_decid ).
