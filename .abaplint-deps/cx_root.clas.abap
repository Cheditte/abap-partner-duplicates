CLASS cx_root DEFINITION PUBLIC ABSTRACT CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_message.
    ALIASES get_text FOR if_message~get_text.
    DATA previous TYPE REF TO cx_root READ-ONLY.
    METHODS constructor IMPORTING textid LIKE textid OPTIONAL previous TYPE REF TO cx_root OPTIONAL.
    DATA textid TYPE c LENGTH 32.
ENDCLASS.
CLASS cx_root IMPLEMENTATION.
  METHOD constructor.
  ENDMETHOD.
  METHOD if_message~get_text.
  ENDMETHOD.
  METHOD if_message~get_longtext.
  ENDMETHOD.
ENDCLASS.
