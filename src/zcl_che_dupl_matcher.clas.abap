"! <p class="shorttext synchronized">Partner duplicates: finds and scores likely duplicate pairs</p>
"! No database access, so everything here is covered by unit tests.
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
CLASS zcl_che_dupl_matcher DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS default_rules
      RETURNING
        VALUE(rt_rules) TYPE zif_che_dupl=>ty_rule_settings.

    "! IT_RULES overrides the defaults rule by rule
    METHODS constructor
      IMPORTING
        it_rules      TYPE zif_che_dupl=>ty_rule_settings OPTIONAL
        io_normalizer TYPE REF TO zcl_che_dupl_normalizer OPTIONAL
        iv_threshold  TYPE i DEFAULT zif_che_dupl=>default_threshold
        iv_max_block  TYPE i DEFAULT zif_che_dupl=>default_max_block
        iv_unmask     TYPE abap_bool DEFAULT abap_false.

    METHODS find
      IMPORTING
        it_partners      TYPE zif_che_dupl=>ty_partners
      RETURNING
        VALUE(rs_result) TYPE zif_che_dupl=>ty_result.

    "! 0 to 100; the better of edit distance and shared words
    METHODS similarity
      IMPORTING
        it_tokens1        TYPE zif_che_dupl=>ty_strings
        it_tokens2        TYPE zif_che_dupl=>ty_strings
      RETURNING
        VALUE(rv_percent) TYPE i.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_prepared,
        partner   TYPE bu_partner,
        name      TYPE string,
        tokens    TYPE zif_che_dupl=>ty_strings,
        tax_ids   TYPE zif_che_dupl=>ty_strings,
        ibans     TYPE zif_che_dupl=>ty_strings,
        addresses TYPE zif_che_dupl=>ty_strings,
        phones    TYPE zif_che_dupl=>ty_strings,
        emails    TYPE zif_che_dupl=>ty_strings,
        domains   TYPE zif_che_dupl=>ty_strings,
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

    DATA mt_rules TYPE zif_che_dupl=>ty_rule_settings.
    DATA mo_normalizer TYPE REF TO zcl_che_dupl_normalizer.
    DATA mv_threshold TYPE i.
    DATA mv_max_block TYPE i.
    DATA mv_unmask TYPE abap_bool.

    METHODS prepare
      IMPORTING
        is_partner         TYPE zif_che_dupl=>ty_partner
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
        VALUE(rs_line) TYPE zif_che_dupl=>ty_line.

    METHODS weight
      IMPORTING
        iv_rule          TYPE zche_dupl_rule
      RETURNING
        VALUE(rv_weight) TYPE i.

    METHODS common
      IMPORTING
        it_values       TYPE zif_che_dupl=>ty_strings
        it_others       TYPE zif_che_dupl=>ty_strings
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



CLASS zcl_che_dupl_matcher IMPLEMENTATION.

  METHOD default_rules.
    rt_rules = VALUE #(
      ( rule = zif_che_dupl=>rule-tax_id  weight = 95 )
      ( rule = zif_che_dupl=>rule-iban    weight = 90 )
      ( rule = zif_che_dupl=>rule-name    weight = 70 min_similarity = 85 )
      ( rule = zif_che_dupl=>rule-address weight = 50 )
      ( rule = zif_che_dupl=>rule-phone   weight = 40 )
      ( rule = zif_che_dupl=>rule-email   weight = 40 ) ).
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
    IF weight( zif_che_dupl=>rule-tax_id ) > 0.
      LOOP AT is_prepared-tax_ids INTO DATA(lv_value).
        add_key( EXPORTING iv_key = |T:{ lv_value }| iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( zif_che_dupl=>rule-iban ) > 0.
      LOOP AT is_prepared-ibans INTO lv_value.
        add_key( EXPORTING iv_key = |I:{ lv_value }| iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( zif_che_dupl=>rule-address ) > 0.
      LOOP AT is_prepared-addresses INTO lv_value.
        add_key( EXPORTING iv_key = |A:{ lv_value }| iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( zif_che_dupl=>rule-phone ) > 0.
      LOOP AT is_prepared-phones INTO lv_value.
        add_key( EXPORTING iv_key = |P:{ lv_value }| iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( zif_che_dupl=>rule-email ) > 0.
      LOOP AT is_prepared-emails INTO lv_value.
        add_key( EXPORTING iv_key = |E:{ lv_value }| iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
      LOOP AT is_prepared-domains INTO lv_value.
        add_key( EXPORTING iv_key = |D:{ lv_value }| iv_index = iv_index CHANGING ct_blocks = ct_blocks ).
      ENDLOOP.
    ENDIF.
    IF weight( zif_che_dupl=>rule-name ) > 0 AND is_prepared-tokens IS NOT INITIAL.
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
    DATA lt_reasons TYPE zif_che_dupl=>ty_strings.
    DATA lv_rest TYPE decfloat34 VALUE 1.

    DATA(lv_value) = common( it_values = is_one-tax_ids it_others = is_other-tax_ids ).
    IF lv_value IS NOT INITIAL AND weight( zif_che_dupl=>rule-tax_id ) > 0.
      lv_rest = lv_rest * ( 100 - weight( zif_che_dupl=>rule-tax_id ) ) / 100.
      APPEND |Same tax number { show( lv_value ) }| TO lt_reasons.
    ENDIF.

    lv_value = common( it_values = is_one-ibans it_others = is_other-ibans ).
    IF lv_value IS NOT INITIAL AND weight( zif_che_dupl=>rule-iban ) > 0.
      lv_rest = lv_rest * ( 100 - weight( zif_che_dupl=>rule-iban ) ) / 100.
      APPEND |Same IBAN { show( lv_value ) }| TO lt_reasons.
    ENDIF.

    IF weight( zif_che_dupl=>rule-name ) > 0.
      DATA(lv_similarity) = similarity( it_tokens1 = is_one-tokens it_tokens2 = is_other-tokens ).
      DATA(lv_minimum) = mt_rules[ rule = zif_che_dupl=>rule-name ]-min_similarity.
      IF lv_similarity > 0 AND lv_similarity >= lv_minimum.
        lv_rest = lv_rest * ( 100 - weight( zif_che_dupl=>rule-name ) * lv_similarity / 100 ) / 100.
        APPEND COND string( WHEN lv_similarity = 100 THEN `Same name`
                            ELSE |Name { lv_similarity }% similar| ) TO lt_reasons.
      ENDIF.
    ENDIF.

    lv_value = common( it_values = is_one-addresses it_others = is_other-addresses ).
    IF lv_value IS NOT INITIAL AND weight( zif_che_dupl=>rule-address ) > 0.
      lv_rest = lv_rest * ( 100 - weight( zif_che_dupl=>rule-address ) ) / 100.
      APPEND `Same address` TO lt_reasons.
    ENDIF.

    lv_value = common( it_values = is_one-phones it_others = is_other-phones ).
    IF lv_value IS NOT INITIAL AND weight( zif_che_dupl=>rule-phone ) > 0.
      lv_rest = lv_rest * ( 100 - weight( zif_che_dupl=>rule-phone ) ) / 100.
      APPEND `Same phone` TO lt_reasons.
    ENDIF.

    IF weight( zif_che_dupl=>rule-email ) > 0.
      lv_value = common( it_values = is_one-emails it_others = is_other-emails ).
      IF lv_value IS NOT INITIAL.
        lv_rest = lv_rest * ( 100 - weight( zif_che_dupl=>rule-email ) ) / 100.
        APPEND `Same e-mail` TO lt_reasons.
      ELSE.
        lv_value = common( it_values = is_one-domains it_others = is_other-domains ).
        IF lv_value IS NOT INITIAL.
          " A shared company domain is weaker than the same address
          lv_rest = lv_rest * ( 100 - weight( zif_che_dupl=>rule-email ) / 2 ) / 100.
          APPEND |Same e-mail domain { lv_value }| TO lt_reasons.
        ENDIF.
      ENDIF.
    ENDIF.

    rs_line-finding = zif_che_dupl=>finding-duplicate.
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
    rv_text = COND #( WHEN mv_unmask = abap_true THEN iv_value ELSE zcl_che_dupl_tax_id=>mask( iv_value ) ).
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

