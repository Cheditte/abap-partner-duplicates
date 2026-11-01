" Test numbers are made up; their check digits were calculated separately
CLASS ltc_tax_id DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS vkn_valid FOR TESTING.
    METHODS vkn_wrong_check_digit FOR TESTING.
    METHODS tckn_valid FOR TESTING.
    METHODS tckn_wrong FOR TESTING.
    METHODS check_texts FOR TESTING.
    METHODS mask FOR TESTING.
ENDCLASS.


CLASS ltc_tax_id IMPLEMENTATION.

  METHOD vkn_valid.
    cl_abap_unit_assert=>assert_true( zcl_che_dupl_tax_id=>is_valid_vkn( `1234567890` ) ).
    cl_abap_unit_assert=>assert_true( zcl_che_dupl_tax_id=>is_valid_vkn( `9876543217` ) ).
    cl_abap_unit_assert=>assert_true( zcl_che_dupl_tax_id=>is_valid_vkn( `5550001112` ) ).
  ENDMETHOD.


  METHOD vkn_wrong_check_digit.
    cl_abap_unit_assert=>assert_false( zcl_che_dupl_tax_id=>is_valid_vkn( `1234567891` ) ).
    cl_abap_unit_assert=>assert_false( zcl_che_dupl_tax_id=>is_valid_vkn( `123456789` ) ).
    cl_abap_unit_assert=>assert_false( zcl_che_dupl_tax_id=>is_valid_vkn( `12345678A0` ) ).
  ENDMETHOD.


  METHOD tckn_valid.
    cl_abap_unit_assert=>assert_true( zcl_che_dupl_tax_id=>is_valid_tckn( `10000000146` ) ).
    cl_abap_unit_assert=>assert_true( zcl_che_dupl_tax_id=>is_valid_tckn( `12345678950` ) ).
  ENDMETHOD.


  METHOD tckn_wrong.
    cl_abap_unit_assert=>assert_false( zcl_che_dupl_tax_id=>is_valid_tckn( `10000000147` ) ).
    cl_abap_unit_assert=>assert_false( zcl_che_dupl_tax_id=>is_valid_tckn( `01234567890` ) ).
  ENDMETHOD.


  METHOD check_texts.
    cl_abap_unit_assert=>assert_initial( zcl_che_dupl_tax_id=>check( `1234567890` ) ).
    cl_abap_unit_assert=>assert_initial( zcl_che_dupl_tax_id=>check( ` 10000000146 ` ) ).
    cl_abap_unit_assert=>assert_equals( act = zcl_che_dupl_tax_id=>check( `1234567891` )
                                        exp = `Tax number (VKN) 123*****91: check digit is wrong` ).
    cl_abap_unit_assert=>assert_equals( act = zcl_che_dupl_tax_id=>check( `12345` )
                                        exp = `Tax number ***** has 5 digits; VKN has 10, TCKN 11` ).
  ENDMETHOD.


  METHOD mask.
    cl_abap_unit_assert=>assert_equals( act = zcl_che_dupl_tax_id=>mask( `10000000146` ) exp = `100******46` ).
  ENDMETHOD.

ENDCLASS.
