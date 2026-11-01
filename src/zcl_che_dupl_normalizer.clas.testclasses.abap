CLASS ltc_normalizer DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO zcl_che_dupl_normalizer.

    METHODS setup.
    METHODS turkish_letters FOR TESTING.
    METHODS punctuation FOR TESTING.
    METHODS legal_forms_removed FOR TESTING.
    METHODS word_order_ignored FOR TESTING.
    METHODS own_stop_words FOR TESTING.
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
    DATA(lt_exp) = VALUE zif_che_dupl=>ty_strings( ( `DERYA` ) ( `TEKSTIL` ) ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->name_tokens( `Derya Tekstil San. ve Tic. A.Ş.` ) exp = lt_exp ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->name_tokens( `DERYA TEKSTİL SANAYİ TİCARET ANONİM ŞİRKETİ` ) exp = lt_exp ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->name_tokens( `Derya Tekstil Ltd. Şti.` ) exp = lt_exp ).
  ENDMETHOD.


  METHOD word_order_ignored.
    cl_abap_unit_assert=>assert_equals( act = mo_cut->name_tokens( `Tekstil Derya` )
                                        exp = mo_cut->name_tokens( `Derya Tekstil` ) ).
  ENDMETHOD.


  METHOD own_stop_words.
    " Own words replace the defaults, so LTD counts again
    mo_cut = NEW #( VALUE #( ( `Holding` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->name_tokens( `Derya Holding Ltd.` )
                                        exp = VALUE zif_che_dupl=>ty_strings( ( `DERYA` ) ( `LTD` ) ) ).
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
