"! <p class="shorttext synchronized">Partner duplicates: where the partners come from</p>
"! Implement it to read partners from somewhere else (for example LFA1/KNA1)
"! and enter the class in ZCHE_DUPL_PROF-SOURCE_CLASS.
INTERFACE zif_che_dupl_source
  PUBLIC.

  METHODS read
    IMPORTING
      is_profile         TYPE zif_che_dupl=>ty_profile
    RETURNING
      VALUE(rt_partners) TYPE zif_che_dupl=>ty_partners
    RAISING
      zcx_che_dupl.

ENDINTERFACE.
