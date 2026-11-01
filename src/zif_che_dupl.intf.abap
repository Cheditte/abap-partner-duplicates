"! <p class="shorttext synchronized">Partner duplicates: types and constants</p>
INTERFACE zif_che_dupl
  PUBLIC.

  CONSTANTS version TYPE string VALUE `0.1.0`.
  CONSTANTS default_source_class TYPE seoclsname VALUE 'ZCL_CHE_DUPL_SOURCE_BP'.
  CONSTANTS default_tax_type TYPE bptaxtype VALUE 'TR2'.
  CONSTANTS default_threshold TYPE i VALUE 60.
  CONSTANTS default_max_block TYPE i VALUE 200.

  " Rules: each one gives evidence that two partners are the same
  CONSTANTS:
    BEGIN OF rule,
      tax_id  TYPE zche_dupl_rule VALUE 'TAX_ID',
      iban    TYPE zche_dupl_rule VALUE 'IBAN',
      name    TYPE zche_dupl_rule VALUE 'NAME',
      address TYPE zche_dupl_rule VALUE 'ADDRESS',
      phone   TYPE zche_dupl_rule VALUE 'PHONE',
      email   TYPE zche_dupl_rule VALUE 'EMAIL',
    END OF rule.

  CONSTANTS:
    BEGIN OF decision,
      duplicate     TYPE zche_dupl_decision VALUE 'D',
      not_duplicate TYPE zche_dupl_decision VALUE 'N',
    END OF decision.

  TYPES ty_finding TYPE c LENGTH 14.
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
      rule           TYPE zche_dupl_rule,
      weight         TYPE i,
      min_similarity TYPE i,
    END OF ty_rule_setting,
    ty_rule_settings TYPE SORTED TABLE OF ty_rule_setting WITH UNIQUE KEY rule.

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
      decision TYPE zche_dupl_decision,
    END OF ty_line,
    ty_lines TYPE STANDARD TABLE OF ty_line WITH EMPTY KEY.

  TYPES:
    BEGIN OF ty_result,
      lines          TYPE ty_lines,
      partners       TYPE i,
      skipped_blocks TYPE ty_strings,
      hidden_pairs   TYPE i,
    END OF ty_result.

  TYPES ty_profile TYPE zche_dupl_prof.

ENDINTERFACE.
