INTERFACE if_message PUBLIC.
  METHODS get_text RETURNING value(result) TYPE string.
  METHODS get_longtext IMPORTING preserve_newlines TYPE abap_bool OPTIONAL RETURNING value(result) TYPE string.
ENDINTERFACE.
