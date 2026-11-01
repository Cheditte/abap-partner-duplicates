" All names, numbers and addresses are made up
CLASS ltc_matcher DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO zcl_che_dupl_matcher.

    METHODS setup.
    METHODS same_tax_number FOR TESTING.
    METHODS tax_number_masked FOR TESTING.
    METHODS spelling_variants FOR TESTING.
    METHODS typo_in_name FOR TESTING.
    METHODS different_companies FOR TESTING.
    METHODS weak_signals_add_up FOR TESTING.
    METHODS public_mail_domain_ignored FOR TESTING.
    METHODS rule_switched_off FOR TESTING.
    METHODS crowded_block_skipped FOR TESTING.
    METHODS pair_order FOR TESTING.
    METHODS similarity_values FOR TESTING.

    METHODS partner
      IMPORTING
        iv_id             TYPE bu_partner
        iv_name           TYPE string
        iv_tax            TYPE string OPTIONAL
        iv_iban           TYPE string OPTIONAL
        iv_street         TYPE string OPTIONAL
        iv_phone          TYPE string OPTIONAL
        iv_email          TYPE string OPTIONAL
      RETURNING
        VALUE(rs_partner) TYPE zif_che_dupl=>ty_partner.
ENDCLASS.


CLASS ltc_matcher IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( iv_unmask = abap_true ).
  ENDMETHOD.


  METHOD partner.
    rs_partner-partner = iv_id.
    rs_partner-name = iv_name.
    IF iv_tax IS NOT INITIAL.
      rs_partner-tax_ids = VALUE #( ( iv_tax ) ).
    ENDIF.
    IF iv_iban IS NOT INITIAL.
      rs_partner-ibans = VALUE #( ( iv_iban ) ).
    ENDIF.
    IF iv_street IS NOT INITIAL.
      rs_partner-addresses = VALUE #( ( country = 'TR' post_code = `34000` city = `Istanbul` street = iv_street ) ).
    ENDIF.
    IF iv_phone IS NOT INITIAL.
      rs_partner-phones = VALUE #( ( iv_phone ) ).
    ENDIF.
    IF iv_email IS NOT INITIAL.
      rs_partner-emails = VALUE #( ( iv_email ) ).
    ENDIF.
  ENDMETHOD.


  METHOD same_tax_number.
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Derya Tekstil A.Ş.` iv_tax = `1234567890` ) )
      ( partner( iv_id = '2' iv_name = `Mavi Gıda Ltd.` iv_tax = `1234567890` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-lines ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-score exp = 95 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-reasons exp = `Same tax number 1234567890` ).
  ENDMETHOD.


  METHOD tax_number_masked.
    mo_cut = NEW #( ).
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Ali Veli` iv_tax = `10000000146` ) )
      ( partner( iv_id = '2' iv_name = `Ayşe Kaya` iv_tax = `10000000146` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-reasons exp = `Same tax number 100******46` ).
  ENDMETHOD.


  METHOD spelling_variants.
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Derya Tekstil San. ve Tic. A.Ş.` ) )
      ( partner( iv_id = '2' iv_name = `DERYA TEKSTİL SANAYİ TİCARET ANONİM ŞİRKETİ` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-score exp = 70 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-reasons exp = `Same name` ).
  ENDMETHOD.


  METHOD typo_in_name.
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Derya Tekstil A.Ş.` ) )
      ( partner( iv_id = '2' iv_name = `Deria Tekstil AŞ` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-lines ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-reasons exp = `Name 92% similar` ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-score exp = 64 ).
  ENDMETHOD.


  METHOD different_companies.
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Derya Tekstil A.Ş.` iv_tax = `1234567890` ) )
      ( partner( iv_id = '2' iv_name = `Derya Gıda A.Ş.` iv_tax = `9876543217` ) ) ) ).
    cl_abap_unit_assert=>assert_initial( ls_result-lines ).
  ENDMETHOD.


  METHOD weak_signals_add_up.
    " Address 50 and phone 40: 1 - 0.5 * 0.6 = 70
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Kuzey Lojistik` iv_street = `Atatürk Cad. 12` iv_phone = `0212 555 01 02` ) )
      ( partner( iv_id = '2' iv_name = `Güney Nakliyat` iv_street = `ATATURK CAD 12` iv_phone = `+90 212 5550102` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-score exp = 70 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-reasons exp = `Same address; Same phone` ).
  ENDMETHOD.


  METHOD public_mail_domain_ignored.
    mo_cut = NEW #( iv_threshold = 1 ).
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Kuzey Lojistik` iv_email = `kuzey@gmail.com` ) )
      ( partner( iv_id = '2' iv_name = `Güney Nakliyat` iv_email = `guney@gmail.com` ) )
      ( partner( iv_id = '3' iv_name = `Batı Ticaret` iv_email = `satis@bati.com.tr` ) )
      ( partner( iv_id = '4' iv_name = `Doğu Pazarlama` iv_email = `info@bati.com.tr` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-lines ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-partner1 exp = '3' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-reasons exp = `Same e-mail domain bati.com.tr` ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-score exp = 20 ).
  ENDMETHOD.


  METHOD rule_switched_off.
    mo_cut = NEW #( it_rules = VALUE #( ( rule = zif_che_dupl=>rule-tax_id weight = 0 ) ) ).
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Derya Tekstil` iv_tax = `1234567890` ) )
      ( partner( iv_id = '2' iv_name = `Mavi Gıda` iv_tax = `1234567890` ) ) ) ).
    cl_abap_unit_assert=>assert_initial( ls_result-lines ).
  ENDMETHOD.


  METHOD crowded_block_skipped.
    mo_cut = NEW #( iv_max_block = 2 iv_unmask = abap_true ).
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '1' iv_name = `Alfa` iv_tax = `1234567890` ) )
      ( partner( iv_id = '2' iv_name = `Beta` iv_tax = `1234567890` ) )
      ( partner( iv_id = '3' iv_name = `Gama` iv_tax = `1234567890` ) ) ) ).
    cl_abap_unit_assert=>assert_initial( ls_result-lines ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-skipped_blocks
                                        exp = VALUE zif_che_dupl=>ty_strings(
                                          ( `Tax number 1234567890 (3 partners, not compared)` ) ) ).
  ENDMETHOD.


  METHOD pair_order.
    DATA(ls_result) = mo_cut->find( VALUE #(
      ( partner( iv_id = '9' iv_name = `Zeta` iv_iban = `TR33 0006 1005 1978 6457 8413 26` ) )
      ( partner( iv_id = '4' iv_name = `Eta` iv_iban = `TR330006100519786457841326` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-partner1 exp = '4' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-partner2 exp = '9' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-lines[ 1 ]-score exp = 90 ).
  ENDMETHOD.


  METHOD similarity_values.
    cl_abap_unit_assert=>assert_equals(
      act = mo_cut->similarity( it_tokens1 = VALUE #( ( `DERYA` ) ( `TEKSTIL` ) )
                                it_tokens2 = VALUE #( ( `DERYA` ) ( `TEKSTIL` ) ) )
      exp = 100 ).
    cl_abap_unit_assert=>assert_initial( mo_cut->similarity( it_tokens1 = VALUE #( ( `DERYA` ) )
                                                             it_tokens2 = VALUE #( ) ) ).
    " 7 edits in 13 letters (46) beat one shared word of three (33)
    cl_abap_unit_assert=>assert_equals(
      act = mo_cut->similarity( it_tokens1 = VALUE #( ( `DERYA` ) ( `TEKSTIL` ) )
                                it_tokens2 = VALUE #( ( `DERYA` ) ( `GIDA` ) ) )
      exp = 46 ).
  ENDMETHOD.

ENDCLASS.
