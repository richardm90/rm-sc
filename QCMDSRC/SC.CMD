/******************************************************************************/
/* SC         - Service Commander                                             */
/*                                                                            */
/* 29/08/2026 - RM - created                                                  */
/******************************************************************************/

             CMD        PROMPT('Service Commander')

             PARM       KWD(OPTION) +
                        TYPE(*CHAR) +
                        LEN(12) +
                        RSTD(*YES) +
                        MIN(1) +
                        VALUES(*CHECK *START *STOP *KILL *RESTART +
                               *INFO *FILE *LIST *GROUPS *JOBINFO +
                               *LOGINFO *PERFINFO *SCRUNATTRS) +
                        PROMPT('Operation')

             PARM       KWD(SERVICE) +
                        TYPE(*CHAR) +
                        LEN(256) +
                        DFT(*NONE) +
                        SPCVAL((*NONE)) +
                        CASE(*MIXED) +
                        PROMPT('Service, group: or all')

             PARM       KWD(COLOURS) +
                        TYPE(*CHAR) +
                        LEN(4) +
                        RSTD(*YES) +
                        DFT(*NO) +
                        VALUES(*NO *YES) +
                        PROMPT('Colour output')

             PARM       KWD(ALL) +
                        TYPE(*CHAR) +
                        LEN(4) +
                        RSTD(*YES) +
                        DFT(*NO) +
                        VALUES(*NO *YES) +
                        PROMPT('Include ignored groups')

             PARM       KWD(IGNGRP) +
                        TYPE(*CHAR) +
                        LEN(64) +
                        DFT(*DFT) +
                        SPCVAL((*DFT)) +
                        CASE(*MIXED) +
                        PROMPT('Groups to ignore')
