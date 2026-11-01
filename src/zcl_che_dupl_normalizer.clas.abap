"! <p class="shorttext synchronized">Partner duplicates: normalizes names, phones and e-mails</p>
"! Case conversion of i/I depends on the language (Turkish has i/İ and ı/I),
"! so Turkish letters are folded to A-Z with an own table first and the
"! result does not depend on the logon language.
CLASS zcl_che_dupl_normalizer DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Legal forms and generic trade words; used when ZCHE_DUPL_STOP is empty
    CLASS-METHODS default_words
      RETURNING
        VALUE(rt_words) TYPE zif_che_dupl=>ty_strings.

    "! Free mail providers: the same domain says nothing about the company
    CLASS-METHODS free_mail_domains
      RETURNING
        VALUE(rt_domains) TYPE zif_che_dupl=>ty_strings.

    METHODS constructor
      IMPORTING
        it_stop_words TYPE zif_che_dupl=>ty_strings OPTIONAL.

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
        VALUE(rt_tokens) TYPE zif_che_dupl=>ty_strings.

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
        is_address    TYPE zif_che_dupl=>ty_address
      RETURNING
        VALUE(rv_key) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS turkish_letters TYPE string VALUE `çCÇCğGĞGıIiIİIöOÖOşSŞSüUÜUâAÂAîIÎIûUÛUéEÉE`.
    DATA mt_stop_words TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.
ENDCLASS.



CLASS zcl_che_dupl_normalizer IMPLEMENTATION.

  METHOD constructor.
    DATA(lt_words) = it_stop_words.
    IF lt_words IS INITIAL.
      lt_words = default_words( ).
    ENDIF.
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

