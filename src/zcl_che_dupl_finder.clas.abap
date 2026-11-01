"! <p class="shorttext synchronized">Partner duplicates: reads the profile and runs a search</p>
"! Settings: ZCHE_DUPL_PROF (profile), ZCHE_DUPL_RULES (rule weights,
"! optional), ZCHE_DUPL_STOP (words to ignore in names, optional).
"! Decisions in ZCHE_DUPL_DECI: a pair marked "not a duplicate" is hidden
"! in later runs.
CLASS zcl_che_dupl_finder DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING
        iv_profile TYPE zche_dupl_profile
      RAISING
        zcx_che_dupl.

    METHODS run
      IMPORTING
        iv_show_decided  TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(rs_result) TYPE zif_che_dupl=>ty_result
      RAISING
        zcx_che_dupl.

    METHODS get_profile
      RETURNING
        VALUE(rs_profile) TYPE zif_che_dupl=>ty_profile.

    "! Saves a decision for a pair; the caller commits
    CLASS-METHODS save_decision
      IMPORTING
        iv_partner1 TYPE bu_partner
        iv_partner2 TYPE bu_partner
        iv_decision TYPE zche_dupl_decision
        iv_note     TYPE csequence OPTIONAL.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA ms_profile TYPE zif_che_dupl=>ty_profile.
    DATA mo_source TYPE REF TO zif_che_dupl_source.
    DATA mo_matcher TYPE REF TO zcl_che_dupl_matcher.

    METHODS apply_decisions
      IMPORTING
        iv_show_decided TYPE abap_bool
      CHANGING
        cs_result       TYPE zif_che_dupl=>ty_result.

    METHODS add_tax_id_findings
      IMPORTING
        it_partners TYPE zif_che_dupl=>ty_partners
      CHANGING
        cs_result   TYPE zif_che_dupl=>ty_result.
ENDCLASS.



CLASS zcl_che_dupl_finder IMPLEMENTATION.

  METHOD constructor.
    SELECT SINGLE * FROM zche_dupl_prof WHERE profile = @iv_profile INTO @ms_profile.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_che_dupl
        EXPORTING text = |Profile { iv_profile } does not exist. Create it in table ZCHE_DUPL_PROF (SM30).|.
    ENDIF.

    DATA(lv_class) = COND seoclsname( WHEN ms_profile-source_class IS INITIAL
                                      THEN zif_che_dupl=>default_source_class
                                      ELSE ms_profile-source_class ).
    TRY.
        CREATE OBJECT mo_source TYPE (lv_class).
      CATCH cx_sy_create_object_error cx_sy_move_cast_error INTO DATA(lx_create).
        RAISE EXCEPTION TYPE zcx_che_dupl
          EXPORTING text     = |Source class { lv_class } cannot be used: it must exist and implement ZIF_CHE_DUPL_SOURCE.|
                    previous = lx_create.
    ENDTRY.

    SELECT rule_id, weight, min_similarity
      FROM zche_dupl_rules
      WHERE profile = @iv_profile
      INTO TABLE @DATA(lt_rule_rows).
    DATA(lt_rules) = VALUE zif_che_dupl=>ty_rule_settings(
      FOR ls_row IN lt_rule_rows ( rule = ls_row-rule_id weight = ls_row-weight min_similarity = ls_row-min_similarity ) ).

    SELECT word FROM zche_dupl_stop INTO TABLE @DATA(lt_word_rows).
    DATA(lt_words) = VALUE zif_che_dupl=>ty_strings( FOR ls_word IN lt_word_rows ( CONV #( ls_word-word ) ) ).

    mo_matcher = NEW #( it_rules      = lt_rules
                        io_normalizer = NEW zcl_che_dupl_normalizer( lt_words )
                        iv_threshold  = COND #( WHEN ms_profile-threshold IS INITIAL
                                                THEN zif_che_dupl=>default_threshold
                                                ELSE CONV i( ms_profile-threshold ) )
                        iv_max_block  = COND #( WHEN ms_profile-max_block IS INITIAL
                                                THEN zif_che_dupl=>default_max_block
                                                ELSE ms_profile-max_block )
                        iv_unmask     = ms_profile-unmask ).
  ENDMETHOD.


  METHOD run.
    DATA(lt_partners) = mo_source->read( ms_profile ).
    rs_result = mo_matcher->find( lt_partners ).
    apply_decisions( EXPORTING iv_show_decided = iv_show_decided CHANGING cs_result = rs_result ).
    add_tax_id_findings( EXPORTING it_partners = lt_partners CHANGING cs_result = rs_result ).
  ENDMETHOD.


  METHOD get_profile.
    rs_profile = ms_profile.
  ENDMETHOD.


  METHOD save_decision.
    DATA ls_decision TYPE zche_dupl_deci.
    " Same order as in the result lines: the smaller number first
    ls_decision-partner1 = COND #( WHEN iv_partner1 <= iv_partner2 THEN iv_partner1 ELSE iv_partner2 ).
    ls_decision-partner2 = COND #( WHEN iv_partner1 <= iv_partner2 THEN iv_partner2 ELSE iv_partner1 ).
    ls_decision-decision = iv_decision.
    ls_decision-note = iv_note.
    ls_decision-changed_by = sy-uname.
    GET TIME STAMP FIELD ls_decision-changed_at.
    MODIFY zche_dupl_deci FROM @ls_decision.
  ENDMETHOD.


  METHOD apply_decisions.
    IF cs_result-lines IS INITIAL.
      RETURN.
    ENDIF.
    SELECT partner1, partner2, decision
      FROM zche_dupl_deci
      FOR ALL ENTRIES IN @cs_result-lines
      WHERE partner1 = @cs_result-lines-partner1
        AND partner2 = @cs_result-lines-partner2
      INTO TABLE @DATA(lt_decisions).
    SORT lt_decisions BY partner1 partner2.

    LOOP AT cs_result-lines ASSIGNING FIELD-SYMBOL(<ls_line>).
      READ TABLE lt_decisions INTO DATA(ls_decision)
        WITH KEY partner1 = <ls_line>-partner1 partner2 = <ls_line>-partner2 BINARY SEARCH.
      IF sy-subrc = 0.
        <ls_line>-decision = ls_decision-decision.
      ENDIF.
    ENDLOOP.

    IF iv_show_decided = abap_false.
      DATA(lv_before) = lines( cs_result-lines ).
      DELETE cs_result-lines WHERE decision = zif_che_dupl=>decision-not_duplicate.
      cs_result-hidden_pairs = lv_before - lines( cs_result-lines ).
    ENDIF.
  ENDMETHOD.


  METHOD add_tax_id_findings.
    LOOP AT it_partners INTO DATA(ls_partner).
      LOOP AT ls_partner-tax_ids INTO DATA(lv_tax_id).
        DATA(lv_problem) = zcl_che_dupl_tax_id=>check( lv_tax_id ).
        IF lv_problem IS NOT INITIAL.
          IF ms_profile-unmask = abap_true.
            REPLACE zcl_che_dupl_tax_id=>mask( condense( val = lv_tax_id del = ` ` ) )
              IN lv_problem WITH condense( val = lv_tax_id del = ` ` ).
          ENDIF.
          APPEND VALUE #( finding  = zif_che_dupl=>finding-invalid_tax_id
                          partner1 = ls_partner-partner
                          name1    = ls_partner-name
                          reasons  = lv_problem ) TO cs_result-lines.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

