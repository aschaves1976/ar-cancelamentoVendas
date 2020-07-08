**

## AR Cancelamento de Vendas (Programare)
Este desenvolvimento visa atender demandas pontuais no cliente.
Cancelar as notas de Vendas realizadas pelo Programare no AR.

## Concurrent

| Program Name | Short Name | Description | | | | | | |
|--|--|--|--|--|--|--|--|--|
|  XXVEN - AR Cancelamento de Vendas (Programare) | XXVEN_AR_SALESCANC | Cancelamento de Vendas (Programare) |
| **EXECUTABLE** | **SHORT NAME** | **DESCRIPTION** | **EXECUTION FILE NAME**|
| XXVEN_AR_SALESCANC | XXVEN_AR_SALESCANC | Cancelamento de Vendas (Programare) | XXVEN_AR_SALES_CANC_PKG.PROCESSA_CANCELAMENTO_P |
| **PARAMETER** |  |  |  | |
| **SEQUENCE** | **PARAMETER** | **DESCRIPTION** | **VALUE SET**| **DEFAULT TYPE**| **DEFAULT VALUE** | **DISPLAY SIZE** | **CONCAT DESCRITPION** | **PROMPT** |
| 1| p_origem| Origem | 10 Characters | Constant | PROGRAMARE | 10 | 25 | Origem: |
| 2| p_pedido_programare| Pedido| 15 Characters | NULL| NULL| 15 | 25 | Pedido Programare: |

## Responsibility

| Concurrent |Responsibility|  Request Group| Application |
|--|--|--|--|
| XXVEN - AR Cancelamento de Vendas (Programare) | DV AR SUPER USUARIO | JLBR + AR Reports | Latin America Localizations |

## File

 - XXVEN_AR_SALES_CANC_PKG.pks
 - XXVEN_AR_SALES_CANC_PKG.pkb