"! <p class="shorttext synchronized">Partner duplicates: reads SAP business partners</p>
"! BUT000 (names), BUT020/ADRC/ADR2/ADR6 (addresses, phones, e-mails),
"! DFKKBPTAXNUM (tax numbers of the profile's tax type) and BUT0BK (IBAN).
"! Partners marked for deletion (BUT000-XDELE) are left out.
CLASS zcl_che_dupl_source_bp DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_che_dupl_source.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_key,
        partner TYPE bu_partner,
      END OF ty_key,
      ty_keys TYPE SORTED TABLE OF ty_key WITH UNIQUE KEY partner.
ENDCLASS.



CLASS zcl_che_dupl_source_bp IMPLEMENTATION.

  METHOD zif_che_dupl_source~read.
    DATA lt_keys TYPE ty_keys.
    DATA lr_group TYPE RANGE OF bu_group.
    DATA lr_role TYPE RANGE OF bu_partnerrole.

    IF is_profile-bp_group IS NOT INITIAL.
      lr_group = VALUE #( ( sign = 'I' option = 'EQ' low = is_profile-bp_group ) ).
    ENDIF.

    IF is_profile-bp_role IS INITIAL.
      SELECT partner, type, name_org1, name_org2, name_org3, name_org4,
             name_first, name_last, name_grp1, name_grp2
        FROM but000
        WHERE bu_group IN @lr_group
          AND xdele = @abap_false
        ORDER BY partner
        INTO TABLE @DATA(lt_but000).
    ELSE.
      lr_role = VALUE #( ( sign = 'I' option = 'EQ' low = is_profile-bp_role ) ).
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

    DATA(lv_tax_type) = COND bptaxtype( WHEN is_profile-tax_type IS INITIAL
                                        THEN zif_che_dupl=>default_tax_type
                                        ELSE is_profile-tax_type ).
    SELECT partner, taxnum, taxnumxl
      FROM dfkkbptaxnum
      FOR ALL ENTRIES IN @lt_keys
      WHERE partner = @lt_keys-partner
        AND taxtype = @lv_tax_type
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
      DATA(ls_partner) = VALUE zif_che_dupl=>ty_partner( partner = ls_bp-partner ).
      ls_partner-name = condense( SWITCH string( ls_bp-type
        WHEN '1' THEN |{ ls_bp-name_first } { ls_bp-name_last }|
        WHEN '3' THEN |{ ls_bp-name_grp1 } { ls_bp-name_grp2 }|
        ELSE |{ ls_bp-name_org1 } { ls_bp-name_org2 } { ls_bp-name_org3 } { ls_bp-name_org4 }| ) ).

      DATA(lv_country_ok) = xsdbool( is_profile-country IS INITIAL ).
      READ TABLE lt_addresses TRANSPORTING NO FIELDS WITH KEY partner = ls_bp-partner BINARY SEARCH.
      LOOP AT lt_addresses INTO DATA(ls_address) FROM sy-tabix.
        IF ls_address-partner <> ls_bp-partner.
          EXIT.
        ENDIF.
        IF ls_address-country = is_profile-country.
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

