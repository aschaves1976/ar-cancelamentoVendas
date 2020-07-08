CREATE OR REPLACE PACKAGE APPS.XXVEN_AR_SALES_CANC_PKG AUTHID CURRENT_USER AS
  /* $Header: XXVEN_AR_SALES_CANC_PKG.pks  1.1 2020/05/05 00:00:00 appldev ship $ */
  --
  -- +=================================================================+
  -- |            Drogaria Venancio, RIO DE JANEIRO, BRASIL            |
  -- |                       ALL RIGHTS RESERVED.                      |
  -- +=================================================================+
  -- | FILENAME                                                        |
  -- |  XXVEN_AR_SALES_CANC_PKG.pks                                    |
  -- |                                                                 |
  -- | PURPOSE                                                         |
  -- |  Package Desenvolvida para Atender ao Cancelamento de Vendas    |
  -- |   Identificados no Legado( Programare ).                        |
  -- |  O Concurrent XXVEN - AR Cancelamento de Vendas faz a chamada   | 
  -- |   da Procedure processa_cancelamento_p.                         |
  -- |                                                                 |
  -- | DESCRIPTION                                                     |
  -- |   XXVEN - AR Cancelamento de Vendas                             |
  -- |                                                                 |
  -- | CREATED BY                                                      |
  -- |    ASChaves  ( 2020-05-05 )   v01                               |
  -- |                                                                 |
  -- | UPDATED BY                                                      |
  -- |                                                                 |
  -- +=================================================================+
  
  
  -- Global Variable
  g_resp_id              NUMBER      := TO_NUMBER(  fnd_profile.value(  'RESP_ID'  )  );
  g_conc_request_id      NUMBER      := fnd_global.conc_request_id;
  g_user_id              NUMBER      := fnd_global.user_id;
  g_login_id             NUMBER      := fnd_global.login_id;
  g_conc_program_id      NUMBER      := fnd_global.conc_program_id;
  g_conc_login_id        NUMBER      := fnd_global.conc_login_id;
  g_prog_appl_id         NUMBER      := fnd_global.prog_appl_id;
  g_count                NUMBER      := 0;
  g_org_id               NUMBER ( 15 ) := fnd_global.org_id;
  g_ret_sts_success      VARCHAR2( 1 ) := fnd_api.g_ret_sts_success;
  g_ret_sts_error        VARCHAR2( 1 ) := fnd_api.g_ret_sts_error;
  g_ret_sts_unexp_error  VARCHAR2( 1 ) := fnd_api.g_ret_sts_unexp_error;
  
  TYPE rec_transactions IS RECORD
    ( 
        id_sequencial             NUMBER
      , numero_cancelamento       VARCHAR2( 240 )
      , origen                    VARCHAR2( 240 )
      , customer_trx_id           ra_customer_trx_all.customer_trx_id%TYPE
      , trx_number                ra_customer_trx_all.trx_number%TYPE
      , printing_last_printed     ra_customer_trx_all.printing_last_printed%TYPE
      , cancel_devol              VARCHAR2( 240 )
      , cr_new_customer_trx_id    NUMBER
      , cr_new_trx_number         VARCHAR2( 240 )
      , status                    VARCHAR2( 240 )
      , msg_error                 VARCHAR2( 1000 )
    )
  ;
  TYPE tab_transactions IS TABLE OF rec_transactions INDEX BY BINARY_INTEGER;
  
  PROCEDURE processa_cancelamento_p
    ( 
        errbuf              OUT VARCHAR2
      , retcode             OUT VARCHAR2
      , p_origem            IN  VARCHAR2
      , p_pedido_programare IN  VARCHAR2 DEFAULT NULL
      , p_customer_trx_id   IN  NUMBER   DEFAULT NULL
     )
  ;

END XXVEN_AR_SALES_CANC_PKG;
/
