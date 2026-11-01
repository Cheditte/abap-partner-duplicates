*&---------------------------------------------------------------------*
*& ZCHE_DUPL_FIND: find likely duplicate business partners
*& abap-partner-duplicates, https://github.com/Cheditte/abap-partner-duplicates
*& MIT License, Copyright (c) 2026 Ali Emre Altuntas
*&---------------------------------------------------------------------*
*& Reads only; nothing is merged, blocked or deleted. In the list, click
*& "Duplicate" or "Not dup." to record a decision; pairs marked "not a
*& duplicate" are hidden in later runs.
*&---------------------------------------------------------------------*
REPORT zche_dupl_find.

PARAMETERS p_prof TYPE zche_dupl_profile OBLIGATORY.
PARAMETERS p_decid AS CHECKBOX DEFAULT abap_false.


CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_row,
        finding   TYPE zif_che_dupl=>ty_finding,
        score     TYPE i,
        partner1  TYPE bu_partner,
        name1     TYPE c LENGTH 80,
        partner2  TYPE bu_partner,
        name2     TYPE c LENGTH 80,
        reasons   TYPE c LENGTH 255,
        decision  TYPE zche_dupl_decision,
        mark_dup  TYPE icon_d,
        mark_not  TYPE icon_d,
      END OF ty_row,
      ty_rows TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    CLASS-METHODS run
      IMPORTING
        iv_profile      TYPE zche_dupl_profile
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
        iv_text    TYPE scrtext_m
        iv_long    TYPE scrtext_l
      RAISING
        cx_salv_not_found.

ENDCLASS.



CLASS lcl_app IMPLEMENTATION.

  METHOD run.
    DATA ls_result TYPE zif_che_dupl=>ty_result.
    TRY.
        ls_result = NEW zcl_che_dupl_finder( iv_profile )->run( iv_show_decided ).
      CATCH zcx_che_dupl INTO DATA(lx_error).
        " In the background an E message ends the job as "Cancelled"
        IF sy-batch = abap_true.
          MESSAGE lx_error->get_text( ) TYPE 'E'.
        ELSE.
          MESSAGE lx_error->get_text( ) TYPE 'I' DISPLAY LIKE 'E'.
        ENDIF.
        RETURN.
    ENDTRY.

    LOOP AT ls_result-lines INTO DATA(ls_line).
      DATA(ls_row) = CORRESPONDING ty_row( ls_line ).
      IF ls_line-finding = zif_che_dupl=>finding-duplicate.
        ls_row-mark_dup = icon_okay.
        ls_row-mark_not = icon_cancel.
      ENDIF.
      APPEND ls_row TO gt_rows.
    ENDLOOP.

    DATA(lv_pairs) = REDUCE i( INIT n = 0 FOR r IN gt_rows WHERE ( finding = zif_che_dupl=>finding-duplicate ) NEXT n = n + 1 ).
    DATA(lv_invalid) = lines( gt_rows ) - lv_pairs.
    MESSAGE |{ ls_result-partners } partners read: { lv_pairs } likely duplicate pairs, { lv_invalid } invalid tax numbers|
         && |{ COND #( WHEN ls_result-hidden_pairs > 0 THEN |, { ls_result-hidden_pairs } pairs hidden (marked not duplicate)| ) }|
      TYPE 'S'.
    LOOP AT ls_result-skipped_blocks INTO DATA(lv_skipped).
      MESSAGE |Not compared: { lv_skipped }| TYPE 'S' DISPLAY LIKE 'W'.
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
        text( io_columns = lo_columns iv_column = 'FINDING'  iv_text = 'Finding'   iv_long = 'Finding' ).
        text( io_columns = lo_columns iv_column = 'SCORE'    iv_text = 'Score'     iv_long = 'Score (0-100)' ).
        text( io_columns = lo_columns iv_column = 'PARTNER1' iv_text = 'Partner'   iv_long = 'Partner' ).
        text( io_columns = lo_columns iv_column = 'NAME1'    iv_text = 'Name'      iv_long = 'Name' ).
        text( io_columns = lo_columns iv_column = 'PARTNER2' iv_text = 'Partner 2' iv_long = 'Second partner' ).
        text( io_columns = lo_columns iv_column = 'NAME2'    iv_text = 'Name 2'    iv_long = 'Name of second partner' ).
        text( io_columns = lo_columns iv_column = 'REASONS'  iv_text = 'Reasons'   iv_long = 'Reasons' ).
        text( io_columns = lo_columns iv_column = 'DECISION' iv_text = 'Decision'  iv_long = 'Decision (D duplicate, N not)' ).
        text( io_columns = lo_columns iv_column = 'MARK_DUP' iv_text = 'Duplicate' iv_long = 'Mark as duplicate' ).
        text( io_columns = lo_columns iv_column = 'MARK_NOT' iv_text = 'Not dup.'  iv_long = 'Mark as not a duplicate' ).
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
    IF sy-subrc <> 0 OR <ls_row>-finding <> zif_che_dupl=>finding-duplicate.
      RETURN.
    ENDIF.
    <ls_row>-decision = SWITCH #( column
      WHEN 'MARK_DUP' THEN zif_che_dupl=>decision-duplicate
      WHEN 'MARK_NOT' THEN zif_che_dupl=>decision-not_duplicate ).
    IF <ls_row>-decision IS INITIAL.
      RETURN.
    ENDIF.
    zcl_che_dupl_finder=>save_decision( iv_partner1 = <ls_row>-partner1
                                        iv_partner2 = <ls_row>-partner2
                                        iv_decision = <ls_row>-decision ).
    COMMIT WORK.
    MESSAGE |Saved: { <ls_row>-partner1 } / { <ls_row>-partner2 } = { <ls_row>-decision }| TYPE 'S'.
    go_alv->refresh( ).
  ENDMETHOD.


  METHOD text.
    DATA(lo_column) = io_columns->get_column( iv_column ).
    lo_column->set_short_text( CONV #( iv_text ) ).
    lo_column->set_medium_text( iv_text ).
    lo_column->set_long_text( iv_long ).
  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.
  lcl_app=>run( iv_profile = p_prof iv_show_decided = p_decid ).
