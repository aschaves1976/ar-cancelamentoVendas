--------------------------------------------------------
--  Arquivo criado - Sexta-feira-Julho-10-2020   
--------------------------------------------------------
--------------------------------------------------------
--  DDL for Package Body XXVEN_AR_SALES_CANC_PKG
--------------------------------------------------------

CREATE OR REPLACE PACKAGE BODY      XXVEN_AR_SALES_CANC_PKG AS
  /* $Header: XXVEN_AR_SALES_CANC_PKG.pkb  1.1 2020/05/05 00:00:00 appldev ship $ */
  --
  -- +=================================================================+
  -- |            Drogaria Venancio, RIO DE JANEIRO, BRASIL            |
  -- |                       ALL RIGHTS RESERVED.                      |
  -- +=================================================================+
  -- | FILENAME                                                        |
  -- |  XXVEN_AR_SALES_CANC_PKG.pkb                                    |
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


  PROCEDURE processa_cancelamento_p
    ( 
        errbuf              OUT VARCHAR2
      , retcode             OUT VARCHAR2
      , p_origem            IN  VARCHAR2
      , p_pedido_programare IN  VARCHAR2 DEFAULT NULL
      , p_customer_trx_id   IN  NUMBER   DEFAULT NULL
     )
  IS
   --
   CURSOR c_leg_prog IS
     SELECT
               prog.id_sequencial
             , prog.pedido_venda_programare
             , rcta.customer_trx_id
             , rcta.trx_number
             , rcta.printing_last_printed
       FROM
               tb_prog_ebs_ped_venda_cab@intprd prog
             , ra_customer_trx_all              rcta
      WHERE 1=1
        AND NVL( rcta.reason_code,'X' )                     <> 'CANCELLATION'
        AND (  (  NVL(  rcta.interface_header_context, 'X'  )  = 'PROGRAMARE' AND
                TO_NUMBER(  SUBSTR(  rcta.ct_reference, 2, LENGTH(  rcta.ct_reference  )  )  ) = TO_NUMBER(  prog.pedido_venda_programare  ) 
               ) OR (  rcta.ct_reference = prog.pedido_venda_programare  ) 
             )
        AND prog.pedido_venda_programare IS NOT NULL
        AND prog.motivo_canc_devol       IS NOT NULL
        AND prog.status_integracao       IS NULL
        AND prog.organizacao_venda       IN 
          ( 
            SELECT organization_code
              FROM org_organization_definitions
            WHERE 1=1
              AND operating_unit = g_org_id
           )
        AND EXISTS 
          ( 
            SELECT  1
              FROM  tb_prog_ebs_ped_venda_cab@INTPRD prog2
            WHERE 1=1
              AND prog2.codigo_pedido_oracle          = rcta.customer_trx_id
              AND TRIM( prog2.pedido_venda_programare ) = TRIM( prog.pedido_venda_programare )
              AND prog2.codigo_pedido_oracle          IS NOT NULL
              AND prog2.motivo_canc_devol             IS NULL
           )
        AND rcta.customer_trx_id         = NVL (  p_customer_trx_id, rcta.customer_trx_id  )
        AND prog.pedido_venda_programare = NVL (  p_pedido_programare, pedido_venda_programare  )
        AND ROWNUM < 11 -- O concurrent só executará 10 cancelamentos por vez, a pedido da área funcional.
     ORDER BY id_sequencial
   ;
   --
   l_return_status             VARCHAR2( 1 );
   l_msg_error                 VARCHAR2( 1000 );
   --
   l_tab_transactions          tab_transactions;
   l_count                     NUMBER;
   l_count_analisa             NUMBER;
   l_count_programare          NUMBER;   
   l_customer_trx_id           ra_customer_trx_all.customer_trx_id%TYPE;
   l_trx_number                ra_customer_trx_all.trx_number%TYPE;
   l_printing_last_printed     ra_customer_trx_all.printing_last_printed%TYPE;
   l_pedido                    VARCHAR2( 200 );
   l_processados_sucesso       NUMBER;
   --

   PROCEDURE debug_log( p_message IN VARCHAR2 ) IS
   BEGIN
      --
      IF g_conc_request_id <> -1 THEN
         --
         fnd_file.put_line( fnd_file.log, p_message );
         dbms_output.put_line ( p_message );
         --
      END IF;
      --
   END debug_log;

   FUNCTION func_verifica_linha
     (  p_customer_trx_id IN NUMBER
      , p_trx_number      IN ra_customer_trx_all.trx_number%TYPE
     )
   RETURN VARCHAR2 IS
      --
      l_dummy        VARCHAR2(1);
      l_quant        NUMBER;
      l_mens_erro    VARCHAR2(1000);
      l_falta_saldo  CONSTANT VARCHAR2(500) := ' Nota fiscal (trx_number = ' || p_trx_number || ' / ' || 'customer_trx_id= ' || p_customer_trx_id || ') nao sera processada. Nao ha saldo remanescente.';
      --
   BEGIN
     --
     SELECT COUNT(1)
       INTO l_quant
       FROM ar_payment_schedules_v
     WHERE 1=1
       AND customer_trx_id = p_customer_trx_id
     ; 
     --
     IF l_quant = 0 THEN
       --
       l_mens_erro := NULL;
       --
     ELSE
       --
       SELECT SUM(amount_due_remaining)
         INTO l_quant
         FROM ar_payment_schedules_v
       WHERE 1=1
         AND status          = 'OP'
         AND customer_trx_id = p_customer_trx_id
       ;
       --
       IF NVL(l_quant, 0) > 0 THEN
         --
         l_mens_erro := NULL;
         --
       ELSIF NVL(l_quant, 0) < 0 THEN
         --
         l_mens_erro := l_falta_saldo;
         --
       ELSE
         --
         BEGIN
           --
           SELECT 1
           INTO l_dummy
           FROM dual
           WHERE EXISTS
             (
               SELECT 'Exist'
                 FROM
                       ar_app_adj_v           aa
                      , ar_payment_schedules_v ap
               WHERE 1=1
                 AND aa.payment_schedule_id = ap.payment_schedule_id
                 AND UPPER(aa.class)        IN ('PAGAMENTO', 'PAYMENT')
                 AND ap.status              = 'CL'
                 AND ap.customer_trx_id     = p_customer_trx_id
             )
           ;
           --
           l_mens_erro := NULL;
           --
         EXCEPTION WHEN NO_DATA_FOUND THEN
           --
           l_mens_erro := l_falta_saldo;
           --
         END;
       END IF;
       --
     END IF;
     --
     --
     IF l_mens_erro IS NULL THEN
       --
       BEGIN
         SELECT 1
           INTO l_dummy
           FROM dual
         WHERE EXISTS
           (
             SELECT
                      bs_batch_source_name
                    , ctt_type_name
                    , trx_number
                    , ct_reference
               FROM   ra_customer_trx_partial_v
             WHERE 1=1
               AND bs_batch_source_name NOT IN ( 'CANCEL_CAR_GL', 'CANCEL_CAR_SEM_GL', 'CANC_SEM_CAR_COM_GL', 'CANC_SEM_CAR_SEM_GL' )
               AND (
                     ctt_type_name NOT LIKE '1202%' AND
                     ctt_type_name NOT LIKE '2202%'
                   )
               AND customer_trx_id = p_customer_trx_id
           )
         ;
         --
         l_mens_erro := NULL;
         --
       EXCEPTION WHEN NO_DATA_FOUND THEN
         --
         l_mens_erro := ' Nota fiscal (trx_number=' || p_trx_number || '/' || 'customer_trx_id=' || p_customer_trx_id || ') nao sera processada. Origem ou tipo da nota invalido.';
         --
       END;
     END IF;
     --
     RETURN (l_mens_erro);
     --
   EXCEPTION WHEN OTHERS THEN
      --
      l_mens_erro := 'Erro inesperado na funcao func_verifica_linha. Nota nao sera processada (p_customer_trx_id): ' || p_customer_trx_id || '. ' || SUBSTR(SQLERRM, 1, 150);
      debug_log(l_mens_erro);
      RETURN (l_mens_erro);
      --
   END func_verifica_linha;


   PROCEDURE atualiza_cab_lin_status
     (   p_atualiza_status         IN NUMBER
       , p_id_sequencial           IN NUMBER
       , p_pedido_venda_programare IN VARCHAR2
       , p_message                 IN VARCHAR2
       , p_retcode                 OUT VARCHAR2
     )
   IS
      --
      l_mens_erro  VARCHAR2(200);
      l_quant_proc NUMBER := 0;
      --
   BEGIN
     --
     l_mens_erro :='ERRO: AO ALTERAR TABELA TB_PROG_EBS_PED_VENDA_CAB';
   UPDATE tb_prog_ebs_ped_venda_cab@intprd
      SET
          -- status_integracao = DECODE(p_atualiza_status, 40, 41, p_atualiza_status)
              status_integracao    = p_atualiza_status
            , data_integracao   = SYSDATE
            , envio_erro        = TRIM( p_message )
            , codigo_pedido_oracle = p_pedido_venda_programare
     WHERE 1=1
       AND id_sequencial           = p_id_sequencial
       AND pedido_venda_programare = p_pedido_venda_programare
       AND status_integracao IS NULL
     ;
     l_quant_proc := SQL%ROWCOUNT;
     --
     l_mens_erro :='ERRO: AO ALTERAR TABELA TB_PROG_EBS_PED_VENDA_LIN';
     UPDATE   tb_prog_ebs_ped_venda_lin@intprd
       SET 
              status_integracao = p_atualiza_status
            , data_integracao   = SYSDATE
            , envio_erro        = TRIM( p_message )
     WHERE 1=1
       AND id_seq_pai              = p_id_sequencial
       AND pedido_venda_programare = p_pedido_venda_programare
       AND status_integracao IS NULL
     ;
     l_quant_proc := SQL%ROWCOUNT;
     --
     l_mens_erro :='ERRO: AO ALTERAR TABELA TB_PROG_EBS_PED_VENDA_PAGAM';
     UPDATE tb_prog_ebs_ped_venda_pagam@intprd
       SET
              status_integracao = p_atualiza_status
            , data_integracao   = SYSDATE
            , envio_erro        = TRIM(p_message)
     WHERE 1=1
       AND id_seq_pai              = p_id_sequencial
       AND pedido_venda_programare = p_pedido_venda_programare
       AND status_integracao IS NULL
     ;
     l_quant_proc := SQL%ROWCOUNT;
     --
     l_mens_erro :='ERRO: AO ALTERAR TABELA TB_PROG_EBS_PED_VENDA_TRANSP';
     UPDATE tb_prog_ebs_ped_venda_transp@intprd
     SET
       status_integracao = p_atualiza_status
     , data_integracao   = SYSDATE
     , envio_erro        = TRIM(p_message)
     WHERE 1=1
       AND id_seq_pai              = p_id_sequencial
       AND pedido_venda_programare = p_pedido_venda_programare
       AND status_integracao IS NULL
     ;
     l_quant_proc := SQL%ROWCOUNT;
     --
     l_mens_erro :='ERRO: AO ALTERAR TABELA TB_PROG_EBS_PED_VENDA_AJUSTE';
     UPDATE tb_prog_ebs_ped_venda_ajuste@intprd
       SET
              status_integracao = p_atualiza_status
            , data_integracao   = SYSDATE
            , envio_erro        = TRIM(p_message)
     WHERE 1=1
       AND id_seq_pai              = p_id_sequencial
       AND pedido_venda_programare = p_pedido_venda_programare
       AND status_integracao IS NULL
     ;
     l_quant_proc := SQL%ROWCOUNT;
     --
     p_retcode := NULL;
     COMMIT;
     --
   EXCEPTION WHEN OTHERS THEN
      --
      FND_FILE.PUT_LINE(FND_FILE.LOG,l_mens_erro || '. ' || SUBSTR(SQLERRM, 1, 150));
      p_retcode := 2;
      ROLLBACK;
      --
   END atualiza_cab_lin_status;

   PROCEDURE create_credit_memo
     (
         p_id_sequencial           IN NUMBER
       , p_customer_trx_id         IN NUMBER
       , p_pedido_venda_programare IN VARCHAR2
       , x_new_customer_trx_id     OUT NOCOPY NUMBER
       , x_new_trx_number          OUT NOCOPY VARCHAR2
       , x_return_status           OUT NOCOPY VARCHAR2
       , x_msg_error               OUT NOCOPY VARCHAR2
     )
   IS
      --
      l_return_status                 VARCHAR2(1);
      l_msg_error                     VARCHAR2(1000);
      l_erro_api                      NUMBER;
      l_msg_count                     NUMBER;
      l_msg_data                      VARCHAR2(2000);
      l_request_id                    NUMBER;
      l_context                       VARCHAR2(2);
      l_cm_lines_tbl                  arw_cmreq_cover.cm_line_tbl_type_cover;
      l_interface_header_rec          arw_cmreq_cover.pq_interface_rec_type;
      l_customer_trx_id               NUMBER;
      l_customer_trx_line_id          NUMBER;
      l_ind                           NUMBER;
      l_batch_name                    VARCHAR2(240);
      l_origin_meaning                fnd_lookup_values_vl.meaning%TYPE;
      l_origin_code                   fnd_lookup_values_vl.lookup_code%TYPE;
      l_origin_desc                   fnd_lookup_values_vl.description%TYPE;
      --
      l_quantity_invoiced             NUMBER;
      l_unit_selling_price            NUMBER;
      l_ct_reference                  ra_customer_trx_all.ct_reference%TYPE;
      l_interface_header_context      ra_customer_trx_all.interface_header_context%TYPE;
      l_cust_trx_line_id_frete        NUMBER;
      l_cust_trx_line_id_ajuste       NUMBER;
      l_trx_number                     ra_customer_trx_all.trx_number%TYPE;
      lv_line_credit_flag             VARCHAR2(1) := 'N';  -- Doc ID 844939.1
      --
      e_error                     EXCEPTION;
      --
      CURSOR c_inv(pc_id_sequencial            NUMBER
                 , pc_pedido_venda_programare  NUMBER) IS
         SELECT 1 ord
              , 'ITEM'              tipo_linha
              , id_sequencial
              , linha_venda_programare
              , organizacao_venda
              , numero_linha
              , quantidade
              , valor_item
              , codigo_item
              , TRIM(UPPER(num_lote))  num_lote
              , NVL(valor_frete, 0)    valor_frete
           FROM TB_PROG_EBS_PED_VENDA_LIN@intprd
          WHERE pedido_venda_programare = pc_pedido_venda_programare
            AND id_seq_pai              = pc_id_sequencial
            AND status_integracao IS NULL
         UNION
         SELECT  2
               , 'AJUSTE'
               , tpepva.id_sequencial
               , tpepvl.linha_venda_programare
               , tpepvl.organizacao_venda
               , tpepvl.numero_linha
               , tpepvl.quantidade
               , (NVL(tpepva.valor_desconto,0) * -1) valor_total
               , tpepvl.codigo_item
               , TRIM(UPPER(tpepvl.num_lote))        num_lote
               , 0                                   valor_frete
           FROM TB_PROG_EBS_PED_VENDA_LIN@intprd TPEPVL
                --
             , (SELECT *
                  FROM TB_PROG_EBS_PED_VENDA_AJUSTE@intprd 
                 WHERE status_integracao IS NULL
                   AND NVL(valor_desconto, 0)  > 0
                   AND pedido_venda_programare = pc_pedido_venda_programare
                   AND id_seq_pai              = pc_id_sequencial) tpepva
                --
          WHERE tpepvl.linha_venda_programare  = tpepva.linha_venda_programare
            AND tpepvl.organizacao_venda       = tpepva.organizacao_venda
            AND tpepvl.pedido_venda_programare = pc_pedido_venda_programare
            AND tpepvl.id_seq_pai              = pc_id_sequencial
            AND tpepvl.status_integracao       IS NULL
       ORDER BY linha_venda_programare
              , ord ;
      --
   BEGIN
     --
     BEGIN
       fnd_global.apps_initialize(fnd_global.user_id, fnd_global.resp_id, 222,0);
       mo_global.init('AR');
       mo_global.set_policy_context('S', fnd_global.org_id);
     END;
     --
     l_msg_error     := NULL;
     x_return_status := fnd_api.g_ret_sts_success;
     debug_log(' ');
     debug_log('  create_credit_memo:');
     debug_log('    Parametros');
     debug_log('    Id Seq Pai:      ' || p_id_sequencial);
     debug_log('    Customer Trx Id: ' || p_customer_trx_id);
     debug_log('    Org Id:          ' || g_org_id);
     debug_log(' ');
     --
     l_cm_lines_tbl.DELETE;
     l_customer_trx_id := p_customer_trx_id;
     l_ind             := 0;
     --
     SELECT ct_reference
          , interface_header_context
       INTO l_ct_reference
          , l_interface_header_context
       FROM ra_customer_trx_all
      WHERE customer_trx_id = p_customer_trx_id;
     --
     FOR lc_inv IN c_inv
       (  p_id_sequencial
        , p_pedido_venda_programare
       )
     LOOP
       --
       IF l_interface_header_context = 'PROGRAMARE' THEN
         --
         BEGIN
           --
           l_msg_error := '  Erro ao selecionar item para cancelamento no AR (context "PROGRAMARE"). Venda Pedido Programare: ' || p_pedido_venda_programare || ', Org. Venda: ' || lc_inv.organizacao_venda ||
                          ', Cod. Item: ' || lc_inv.codigo_item || ', Num. Lote: ' || lc_inv.num_lote || ', Tipo Linha: ' || lc_inv.tipo_linha || ', Customer Trx Id: ' || p_customer_trx_id;
           --
           SELECT
                    customer_trx_line_id
                  , unit_selling_price
                  , customer_trx_line_id_frete
                  , trx_number
             INTO
                    l_customer_trx_line_id
                  , l_unit_selling_price
                  , l_cust_trx_line_id_frete
                  , l_trx_number
             FROM
                  (
                    SELECT
                             rctla.customer_trx_id
                           , rctla.customer_trx_line_id
                           , rctla.unit_selling_price
                           , rctla.interface_line_attribute4
                           , rctla.interface_line_attribute5
                           , rctla.interface_line_attribute7
                           , TRIM( UPPER( rctla.attribute11 ) )  num_lote  -- = num_lote da linha do barramento
                           --
                           , ( SELECT msi.segment1
                                FROM mtl_system_items_b msi
                               WHERE msi.inventory_item_id = rctla.inventory_item_id
                                 AND msi.organization_id   = rctla.warehouse_id ) segment1
                           --
                           , ( SELECT mp.organization_code
                                FROM mtl_parameters mp
                                WHERE mp.organization_id = rctla.warehouse_id )   organization_code
                           -- Achando frete
                           , ( SELECT frete.customer_trx_line_id
                                FROM ra_customer_trx_lines_all frete
                                WHERE frete.interface_line_attribute6 = rctla.interface_line_attribute2
                                  AND frete.customer_trx_id           = rctla.customer_trx_id
                                  AND frete.interface_line_attribute7 = 'FRETE'
                                  AND frete.line_type                 = 'LINE' ) customer_trx_line_id_frete
                           -- Achando frete
                           , ( SELECT trx_number
                                FROM ra_customer_trx_all
                               WHERE customer_trx_id = rctla.customer_trx_id )   trx_number
                           --
                      FROM   ra_customer_trx_lines_all rctla
                    WHERE 1=1
                      AND rctla.line_type = 'LINE'
                  )   prg
           WHERE 1=1
             AND prg.organization_code            = lc_inv.organizacao_venda
             AND prg.interface_line_attribute7    = lc_inv.tipo_linha
             AND prg.segment1                     = lc_inv.codigo_item
             AND ( ( lc_inv.tipo_linha            = 'ITEM' 
                    AND  NVL( prg.num_lote, '0' ) = NVL( lc_inv.num_lote, '0' )
                   )
                   OR  ( lc_inv.tipo_linha        <> 'ITEM' ) 
                 )
             AND prg.customer_trx_id              = l_customer_trx_id
           ;
           --
           l_ind := l_ind + 1;
           --
           l_cm_lines_tbl(l_ind).customer_trx_line_id := l_customer_trx_line_id;
           l_cm_lines_tbl(l_ind).quantity_credited    := lc_inv.quantidade * -1;
           l_cm_lines_tbl(l_ind).price                := l_unit_selling_price;
           l_cm_lines_tbl(l_ind).extended_amount      := ROUND((lc_inv.quantidade * l_unit_selling_price * -1), 2);
           --
           IF lc_inv.valor_frete > 0 THEN
             --
             IF l_cust_trx_line_id_frete IS NULL THEN
               --
               l_msg_error := 'Erro ao realizar cancelamento para frete referente ao item: ' || lc_inv.codigo_item || ', Venda Pedido Programare: ' || p_pedido_venda_programare ||
                              '. Ha frete associado ao item na linha do barramento porem o frete nao foi identificado na nota fiscal: ' || l_trx_number || '. Customer_Trx_Id: ' || l_customer_trx_id;
               RAISE e_error;                  
               --
             ELSE
               --
               l_ind := l_ind + 1;
               l_cm_lines_tbl(l_ind).customer_trx_line_id := l_cust_trx_line_id_frete;
               l_cm_lines_tbl(l_ind).quantity_credited    := -1;
               l_cm_lines_tbl(l_ind).price                := ROUND((lc_inv.quantidade * lc_inv.valor_frete), 2);
               lv_line_credit_flag := 'Y';
               --
             END IF;
             --
           END IF;
           --
         EXCEPTION
           WHEN OTHERS THEN
             l_msg_error := l_msg_error || '. ' || SUBSTR(SQLERRM,1,200);
             RAISE e_error;
         END;
         --
       END IF;
       --
     END LOOP;
     --
     --
     IF l_cm_lines_tbl.COUNT = 0 THEN
       --
       l_msg_error := '  Nao ha linha(s) a processar nas tabelas do barramento para o pedido venda programare: ' || p_pedido_venda_programare;
       RAISE e_error;
       --
     ELSE
       --
       BEGIN
         --
         SELECT
                  meaning
                , lookup_code
                , description
           INTO
                  l_origin_meaning
                , l_origin_code
                , l_origin_desc
           FROM   fnd_lookup_values_vl
         WHERE 1=1
           AND lookup_type = 'XXVEN_ORIGEM_DEVOL_AC'
           AND lookup_code = 'ORIGEM'
         ;
         --
       EXCEPTION
         WHEN OTHERS THEN
           l_msg_error := ' Erro ao selecionar informacao na lookup "XXVEN - ORIGEM DEVOL - AC": ' || SUBSTR(SQLERRM,1,200);
           RAISE e_error;
         --
       END;
       --
       BEGIN
         --
         SELECT   name
           INTO   l_batch_name
           FROM   ra_batch_sources_all bs
         WHERE 1=1
           AND name   = l_origin_desc
           AND org_id = g_org_id
         ;
         --
       EXCEPTION WHEN OTHERS THEN
          l_msg_error := ' Erro ao selecionar informacao origem da nota: ' || l_origin_desc || ' - ' || SUBSTR(SQLERRM,1,200);
          RAISE e_error;
       END;
       --
       debug_log(' ');
       debug_log('  Call API ar_credit_memo_api_pub.create_request');
       --
       BEGIN
         --
         ar_credit_memo_api_pub.create_request
           (   -- standard api parameters
               p_api_version                  => 1.0
             , p_init_msg_list                => fnd_api.g_true
             , p_commit                       => fnd_api.g_false
               -- credit memo request parameters
             , p_customer_trx_id              => l_customer_trx_id
             , p_line_credit_flag             => 'Y'
             , p_cm_line_tbl                  => l_cm_lines_tbl
             , p_cm_reason_code               => 'CANCELLATION' -- 'RETURN'
             , p_skip_workflow_flag           => 'Y' --lv_line_credit_flag
             , p_batch_source_name            => l_batch_name   -- 'DV_MANUAL'
             , p_interface_attribute_rec      => NULL
             , p_credit_method_installments   => NULL
             , p_credit_method_rules          => NULL -- 'UNIT' --NULL
             , x_return_status                => l_return_status
             , x_msg_count                    => l_msg_count
             , x_msg_data                     => l_msg_data
             , x_request_id                   => l_request_id
           )
         ;
         --
         l_msg_count := NVL(l_msg_count, 0);
         debug_log('  Message count: ' || l_msg_count);
         debug_log('  Return Status: ' || l_return_status);
         debug_log('  Message Data:  ' || l_msg_data);
         --
       END;
       --
       IF l_msg_count = 1 THEN
         l_msg_error := SUBSTR('  ' || l_msg_data,1,900);
         RAISE e_error;
       ELSIF l_msg_count > 1 THEN
         --
         l_erro_api  := 0;
         LOOP
           l_erro_api  := l_erro_api  + 1;
           l_msg_data := fnd_msg_pub.get(fnd_msg_pub.g_next, fnd_api.g_false);
           --
           IF l_msg_data IS NULL THEN
             exit;
           END IF;
           --
           debug_log('  Message ' || l_erro_api  || ' - ' || l_msg_data);
           l_msg_error := l_msg_error || SUBSTR(('  Message ' || l_erro_api  || ' - ' || l_msg_data), 1, 250);
           --
         END LOOP;
         --
         l_msg_error := TRIM(l_msg_error);
         --
         RAISE e_error;
         --
       END IF;
       --
       IF l_return_status <> 'S' THEN
         l_msg_error :='  Falha executando API ar_credit_memo_api_pub.create_request';
         RAISE e_error;
       ELSE
         debug_log('  API ar_credit_memo_api_pub.create_request Request_ID:      ' || l_request_id);
         SELECT cm_customer_trx_id
           INTO x_new_customer_trx_id
           FROM ra_cm_requests_all
         WHERE 1=1
           AND request_id = l_request_id
         ;
         --
         debug_log('  Novo Aviso Credito. Cm Cust Trx ID AR (customer_trx_id):   ' || x_new_customer_trx_id);
         -- You can issue a COMMIT; at this point IF you want to save the created credit memo to the database
         -- commit;
         BEGIN
           SELECT trx_number
             INTO x_new_trx_number
             FROM ra_customer_trx_all rct
           WHERE 1=1
             AND rct.customer_trx_id = x_new_customer_trx_id
           ;
           --
           debug_log('  Novo Aviso Credito. CM Trx Number AR (trx_number):         ' || x_new_trx_number);
           --
         EXCEPTION WHEN OTHERS THEN
           NULL;
         END;
         --
       END IF;
       --
     END IF;
     --
   EXCEPTION
      WHEN e_error THEN
         x_msg_error     := l_msg_error;
         x_return_status := fnd_api.g_ret_sts_error;
         debug_log(x_msg_error);
         ROLLBACK;
      WHEN OTHERS THEN
         x_msg_error     := 'Erro processando API ar_credit_memo_api_pub.create_request: ' || SUBSTR(SQLERRM,1,200);
         x_return_status := fnd_api.g_ret_sts_error;
         debug_log(x_msg_error);
         ROLLBACK;
   END create_credit_memo;

   PROCEDURE print_output (p_tab_transactions    IN tab_transactions
                          ,x_return_status       OUT NOCOPY VARCHAR2
                          ,x_msg_error           OUT NOCOPY VARCHAR2
                          ) IS
      --
      l_flag_a  VARCHAR2(10) := '0';
      l_flag_p  VARCHAR2(10) := '0';
      --
   BEGIN
      x_return_status := fnd_api.g_ret_sts_success;
      debug_log('Process print_output');
      fnd_file.put_line(fnd_file.output,'+---------------------------------------------------------------------------+');
      fnd_file.put_line(fnd_file.output,'                                   Venancio                                  ');
      fnd_file.put_line(fnd_file.output,'+---------------------------------------------------------------------------+');
      fnd_file.put_line(fnd_file.output,'                                                                            ' );
      --
      IF g_count = 0 THEN
         fnd_file.put_line(fnd_file.output,'  Nenhuma transacao encontrada para processar');
      ELSE
         fnd_file.put_line(fnd_file.output,'  Total de transacoes encontradas para processar: ' || g_count);
      END IF;
      --
      IF p_tab_transactions.count > 0 THEN
         --
         FOR i IN p_tab_transactions.first..p_tab_transactions.last
         LOOP
           --
           IF p_tab_transactions(i).origen = 'PROGRAMARE' AND p_tab_transactions(i).status = 'E' THEN
             IF l_flag_p = '0' THEN
               fnd_file.put_line(fnd_file.output,'            ' );
               fnd_file.put_line(fnd_file.output,' Programare: ');
               l_flag_p := '1';
             END IF;
             fnd_file.put_line(fnd_file.output,' ' || p_tab_transactions(i).msg_error);
           END IF;
           --
         END LOOP;
         --
      END IF; --p_tab_transactions.count > 0
      --
      fnd_file.put_line(fnd_file.output,'   '                                                                          );
      fnd_file.put_line(fnd_file.output,'+---------------------------------------------------------------------------+');
      fnd_file.put_line(fnd_file.output, '                            End of out messages'                             );
      fnd_file.put_line(fnd_file.output,'+---------------------------------------------------------------------------+');
      --
   EXCEPTION WHEN OTHERS THEN
      x_return_status := fnd_api.g_ret_sts_error;
      x_msg_error     := 'Error IN print_output: Description Error: ' || SUBSTR(SQLERRM,1,200);
      debug_log(x_msg_error);
   END print_output;


  BEGIN

     mo_global.set_policy_context( 'S', g_org_id  ); -- g_org_id:= 83;  --g_org_id );

     debug_log( '  ' );
     debug_log( '  ' );
     debug_log( '***********************************************************' );
     debug_log( '  Concurrent Program: "XXVEN - AR Cancelamento de Vendas"  ' );
     debug_log( '    Parametros' );
     debug_log( '      Origem                 : ' || p_origem );
     debug_log( '      Num. Pedido Programare : ' || p_pedido_programare );
     debug_log( '      Request Id             : ' || g_conc_request_id );
     debug_log( '      Operating Unit         : ' || g_org_id );
     debug_log( '***********************************************************' );
     debug_log( '  ' );
     --
     l_tab_transactions.DELETE;
     l_processados_sucesso := 0;
     l_count               := 0;
     --
     -- Selecionando os dados do Cursor
     IF p_origem = 'PROGRAMARE' OR
        p_origem IS NULL
     THEN
       --
       debug_log( ' ' );
       debug_log( 'INICIO pedidos selecionados - PROGRAMARE' );
       l_count_programare := 0;
       --
       FOR r_leg_prog IN c_leg_prog
       LOOP
          g_count := g_count+1;
          debug_log( ' ' );
          debug_log( '    Cabecalho Id Sequencial: ' || r_leg_prog.id_sequencial );
          debug_log( '    Pedido Venda Programare: ' || r_leg_prog.pedido_venda_programare );
          debug_log( ' ' );
          --
          l_pedido := r_leg_prog.pedido_venda_programare;
          l_count  := l_count + 1;
          --
          BEGIN
             --
             l_tab_transactions( l_count ).id_sequencial         := r_leg_prog.id_sequencial;
             l_tab_transactions( l_count ).numero_cancelamento   := r_leg_prog.pedido_venda_programare;
             l_tab_transactions( l_count ).origen                := 'PROGRAMARE';
             l_tab_transactions( l_count ).customer_trx_id       := r_leg_prog.customer_trx_id;
             l_tab_transactions( l_count ).trx_number            := r_leg_prog.trx_number;
             l_tab_transactions( l_count ).printing_last_printed := r_leg_prog.printing_last_printed;
             l_tab_transactions( l_count ).status                := NULL;
             l_tab_transactions( l_count ).msg_error             := NULL;
             --
             IF l_tab_transactions( l_count ).printing_last_printed >= SYSDATE -1 AND
                l_tab_transactions( l_count ).printing_last_printed <= SYSDATE    THEN
                l_tab_transactions( l_count ).cancel_devol := 'CANCELAMENTO';
             END IF;
             --
             debug_log( ' Origem                        : ' || l_tab_transactions( l_count ).origen );
             debug_log( ' Trx Id  AR ( customer_trx_id ): ' || l_tab_transactions( l_count ).customer_trx_id );
             debug_log( ' Trx Num AR ( trx_number )     : ' || l_tab_transactions( l_count ).trx_number );
             debug_log( ' Type    AR                    : ' || l_tab_transactions( l_count ).cancel_devol );
             debug_log( ' ' );
             --
          EXCEPTION
             WHEN NO_DATA_FOUND THEN
                l_msg_error := 'Erro ao seleccionar pedido venda programare no AR: ' || r_leg_prog.pedido_venda_programare || '. ' || SUBSTR( SQLERRM, 1, 200 );
                debug_log( l_msg_error );
                --
                l_tab_transactions( l_count ).id_sequencial         := r_leg_prog.id_sequencial;
                l_tab_transactions( l_count ).numero_cancelamento      := r_leg_prog.pedido_venda_programare;
                l_tab_transactions( l_count ).origen                := 'PROGRAMARE';
                l_tab_transactions( l_count ).customer_trx_id       := NULL;
                l_tab_transactions( l_count ).trx_number            := NULL;
                l_tab_transactions( l_count ).printing_last_printed := NULL;
                l_tab_transactions( l_count ).status                := 'E';
                l_tab_transactions( l_count ).msg_error             := l_msg_error;
                --
                atualiza_cab_lin_status( p_atualiza_status         => 30
                                      , p_id_sequencial           => r_leg_prog.id_sequencial
                                      , p_pedido_venda_programare => r_leg_prog.pedido_venda_programare
                                      , p_message                 => l_msg_error
                                      , p_retcode                 => retcode );
                --
             WHEN OTHERS THEN
                l_msg_error := 'Erro inesperado ao selecionar pedido venda programare no AR: ' || r_leg_prog.pedido_venda_programare || '. ' || SUBSTR( SQLERRM,1,200 );
                debug_log( l_msg_error );
                --
                l_tab_transactions( l_count ).id_sequencial         := r_leg_prog.id_sequencial;
                l_tab_transactions( l_count ).numero_cancelamento      := r_leg_prog.pedido_venda_programare;
                l_tab_transactions( l_count ).origen                := 'PROGRAMARE';
                l_tab_transactions( l_count ).customer_trx_id       := NULL;
                l_tab_transactions( l_count ).trx_number            := NULL;
                l_tab_transactions( l_count ).printing_last_printed := NULL;
                l_tab_transactions( l_count ).status                := 'E';
                l_tab_transactions( l_count ).msg_error             := l_msg_error;
                --
                atualiza_cab_lin_status( p_atualiza_status         => 30
                                      , p_id_sequencial           => r_leg_prog.id_sequencial
                                      , p_pedido_venda_programare => r_leg_prog.pedido_venda_programare
                                      , p_message                 => l_msg_error
                                      , p_retcode                 => retcode );
                --
          END;
          --
       END LOOP;
       --
       debug_log( '  ' );
       debug_log( 'FIM pedidos selecionados - PROGRAMARE' );
       --
     END IF; -- IF Programare
     --
     --
     debug_log( '  ' );
     debug_log( 'INICIO LOOP execucao processo Cancelamento de Vendas' );
     debug_log( 'Quantidade de pedidos a serem processados : ' || l_count );
     --
     IF l_tab_transactions.count > 0 THEN
       --
       FOR i IN l_tab_transactions.FIRST..l_tab_transactions.LAST
       LOOP
         --
         IF l_tab_transactions( i ).status IS NULL THEN
           --
           IF l_tab_transactions( i ).cancel_devol = 'CANCELAMENTO' THEN
             debug_log( '  Cancelamento' );
             debug_log( '  ID -> '||l_tab_transactions( i ).customer_trx_id );
             debug_log( '  Nota Fiscal Origem -> '||l_tab_transactions( i ).numero_cancelamento );
             -- 1 cancel invoice
             -- 2 generate aviso credito
             --
             l_msg_error := func_verifica_linha
               (   p_customer_trx_id => l_tab_transactions( i ).customer_trx_id
                 , p_trx_number      => l_tab_transactions( i ).trx_number
               )
             ;
             IF l_msg_error IS NOT NULL THEN
               --
               debug_log( '  ' );
               debug_log( l_msg_error );
               --
               atualiza_cab_lin_status
                 (   p_atualiza_status         => 30
                   , p_id_sequencial           => l_tab_transactions( i ).id_sequencial
                   , p_pedido_venda_programare => l_tab_transactions( i ).numero_cancelamento
                   , p_message                 => l_msg_error
                   , p_retcode                 => retcode
                 )
               ;
               --
               CONTINUE;
               --
             END IF;
             --
             BEGIN
               --
               debug_log( ' Step 1 -> INICIO execucao procedimento "create_credit_memo"' );
               create_credit_memo
                 (   p_id_sequencial           => l_tab_transactions( i ).id_sequencial
                   , p_customer_trx_id         => l_tab_transactions( i ).customer_trx_id
                   , p_pedido_venda_programare => l_tab_transactions( i ).numero_cancelamento
                   , x_new_customer_trx_id     => l_tab_transactions( i ).cr_new_customer_trx_id
                   , x_new_trx_number          => l_tab_transactions( i ).cr_new_trx_number
                   , x_return_status           => l_return_status
                   , x_msg_error               => l_msg_error
                 )
               ;
               --
               IF l_return_status <> fnd_api.g_ret_sts_success OR
                  l_msg_error IS NOT NULL
               THEN
                 --
                 IF p_origem = 'PROGRAMARE' OR p_origem IS NULL THEN
                   --
                   atualiza_cab_lin_status
                     (   p_atualiza_status         => 30
                       , p_id_sequencial           => l_tab_transactions( i ).id_sequencial
                       , p_pedido_venda_programare => l_tab_transactions( i ).numero_cancelamento
                       , p_message                 => l_msg_error
                       , p_retcode                 => retcode
                     )
                   ;
                   --
                 END IF;
                 --
                 debug_log( '  ' );
                 debug_log( ' Step 1 -> FIM execucao procedimento "create_credit_memo" com erros.' );
                 --
                 CONTINUE;
                 --
               END IF;
               --
             END;
             --
             debug_log( ' Step 1 -> FIM execucao procedimento "create_credit_memo"' );
             debug_log( '  ' );
             --
             IF p_origem = 'PROGRAMARE' OR p_origem IS NULL THEN
               --
               atualiza_cab_lin_status( p_atualiza_status         => 40
                                     , p_id_sequencial           => l_tab_transactions( i ).id_sequencial
                                     , p_pedido_venda_programare => l_tab_transactions( i ).numero_cancelamento
                                     , p_message                 => NULL
                                     , p_retcode                 => retcode );
               --
               IF retcode IS NULL THEN
                  l_processados_sucesso := l_processados_sucesso + 1;
               END IF;
               --
             END IF;
             --
           END IF;
           --
         END IF;
         --
       END LOOP;
        --
     END IF; -- l_tab_transactions.count > 0
     --
     debug_log( 'FIM LOOP execucao processo cancelamento de vendas PROGRAMARE' );
     --
     COMMIT;
     --
     IF retcode IS NULL THEN
        --
        IF l_count_programare <> l_processados_sucesso OR l_processados_sucesso = 0 THEN
           --
           retcode := 1;
           --
        END IF;
        --
     END IF;
     --
     debug_log( '  ' );
     debug_log( '  ' );
     debug_log( '  ' );
     debug_log( '************************************************************' );
     debug_log( 'Total de pedidos processados com sucesso : ' || l_processados_sucesso );
     debug_log( '************************************************************' );
     debug_log( '  ' );
     debug_log( '  ' );
     debug_log( 'FIM execucao procedimento processa_cancelamento_p' );
     debug_log( '  ' );
     --
     BEGIN
       --
       print_output
         (
            p_tab_transactions => l_tab_transactions -- IN tab_transactions
          , x_return_status    => l_return_status    -- OUT NOCOPY VARCHAR2
          , x_msg_error        => l_msg_error        -- OUT NOCOPY VARCHAR2
         )
       ;
       --
     END;
     --
  EXCEPTION
     WHEN OTHERS THEN
        errbuf  := 'Erro executando a procedure processa_cancelamento_p. ' || SUBSTR( SQLERRM,1,200 );
        retcode := '2';
        debug_log( ' ' );
        debug_log( errbuf );
        ROLLBACK;
     --
  END processa_cancelamento_p;

END XXVEN_AR_SALES_CANC_PKG;
/