-- Outstanding Loan Snapshot

DROP PROCEDURE IF EXISTS proc_outstanding_loans_as_of;
DROP PROCEDURE IF EXISTS proc_outstanding_loans_as_of_v2;
DROP PROCEDURE IF EXISTS proc_outstanding_loan_snapshot;
DROP PROCEDURE IF EXISTS proc_outstanding_loan_snapshot_v2;
DROP PROCEDURE IF EXISTS proc_count_outstanding_loan_snapshot_v2;
DROP PROCEDURE IF EXISTS proc_prepare_outstanding_loan_snapshot;
DROP PROCEDURE IF EXISTS proc_build_outstanding_loan_snapshot_tmp;
DELIMITER $$
CREATE PROCEDURE proc_prepare_outstanding_loan_snapshot(
    IN p_report_date        DATE,
    IN p_search_term        VARCHAR(255),
    IN p_filter_product     INT,
    IN p_product_ref_ids    JSON,
    IN p_filter_branch      INT,
    IN p_branch_ref_ids     JSON,
    IN p_filter_org         INT,
    IN p_org_ref_ids        JSON,
    IN p_filter_sales_rep   INT,
    IN p_sales_rep_ref_ids  JSON,
    IN p_loan_ref_id        VARCHAR(45),
    IN p_customer_ref_id    VARCHAR(45),
    IN p_mature_only        BOOLEAN,
    IN p_in_arrears_only    BOOLEAN,
    IN p_min_dpd            INT,
    IN p_max_dpd            INT
)
BEGIN
    DECLARE v_report_date      DATE;
    DECLARE v_next_date        DATE;
    DECLARE v_search_term      VARCHAR(255);
    DECLARE v_filter_product   INT;
    DECLARE v_filter_branch    INT;
    DECLARE v_filter_org       INT;
    DECLARE v_filter_sales_rep INT;
    DECLARE v_mature_only      BOOLEAN;
    DECLARE v_in_arrears_only  BOOLEAN;
    SET v_report_date      = COALESCE(p_report_date, CURRENT_DATE());
    SET v_next_date        = DATE_ADD(v_report_date, INTERVAL 1 DAY);
    SET v_search_term      = NULLIF(TRIM(p_search_term), '');
    SET v_filter_product   = COALESCE(p_filter_product,   0);
    SET v_filter_branch    = COALESCE(p_filter_branch,    0);
    SET v_filter_org       = COALESCE(p_filter_org,       0);
    SET v_filter_sales_rep = COALESCE(p_filter_sales_rep, 0);
    SET v_mature_only      = COALESCE(p_mature_only,      FALSE);
    SET v_in_arrears_only  = COALESCE(p_in_arrears_only,  FALSE);

    DROP TEMPORARY TABLE IF EXISTS tmp_outstanding_loan_snapshot;
    DROP TEMPORARY TABLE IF EXISTS tmp_fl;
    DROP TEMPORARY TABLE IF EXISTS tmp_prd;
    DROP TEMPORARY TABLE IF EXISTS tmp_pa;
    DROP TEMPORARY TABLE IF EXISTS tmp_lpa;
    DROP TEMPORARY TABLE IF EXISTS tmp_spa;
    DROP TEMPORARY TABLE IF EXISTS tmp_gl_movements;
    DROP TEMPORARY TABLE IF EXISTS tmp_jm;
    DROP TEMPORARY TABLE IF EXISTS tmp_swr;
    DROP TEMPORARY TABLE IF EXISTS tmp_dpd;
    DROP TEMPORARY TABLE IF EXISTS tmp_pit_base;
    DROP TEMPORARY TABLE IF EXISTS tmp_jb;
    DROP TEMPORARY TABLE IF EXISTS tmp_ps;
    CREATE TEMPORARY TABLE tmp_fl (
        id                      BIGINT         NOT NULL,
        loanRefId               VARCHAR(45),
        loanProductId           BIGINT,
        userId                  BIGINT,
        disbursementDate        DATE,
        maturityDate            DATE,
        requestedAmount         DECIMAL(19,2),
        disbursementAmount      DECIMAL(19,2),
        writeOffAmount          DECIMAL(19,2),
        isDefaulted             TINYINT(1),
        loanStatus              VARCHAR(45),
        installments            INT,
        interestRate            DECIMAL(10,5),
        productId               BIGINT,
        productRefId            VARCHAR(45),
        productName             VARCHAR(255),
        customerRefId           VARCHAR(45),
        fullName                VARCHAR(255),
        phoneNumber             VARCHAR(45),
        idNumber                VARCHAR(45),
        branchRefId             VARCHAR(45),
        branchName              VARCHAR(255),
        salesRefId              VARCHAR(45),
        salesPersonName         VARCHAR(255),
        organizationRefIds      TEXT,
        organizationNames       TEXT,
        PRIMARY KEY (id)
    );
    INSERT INTO tmp_fl
    WITH product_filter AS (
        SELECT jt.refId
        FROM JSON_TABLE(
            COALESCE(p_product_ref_ids, JSON_ARRAY()),
            '$[*]' COLUMNS (refId VARCHAR(45) PATH '$')
        ) jt
    ),
    branch_filter AS (
        SELECT jt.refId
        FROM JSON_TABLE(
            COALESCE(p_branch_ref_ids, JSON_ARRAY()),
            '$[*]' COLUMNS (refId VARCHAR(45) PATH '$')
        ) jt
    ),
    org_filter AS (
        SELECT jt.refId
        FROM JSON_TABLE(
            COALESCE(p_org_ref_ids, JSON_ARRAY()),
            '$[*]' COLUMNS (refId VARCHAR(45) PATH '$')
        ) jt
    ),
    sales_filter AS (
        SELECT jt.refId
        FROM JSON_TABLE(
            COALESCE(p_sales_rep_ref_ids, JSON_ARRAY()),
            '$[*]' COLUMNS (refId VARCHAR(45) PATH '$')
        ) jt
    ),
    user_org_membership AS (
        SELECT DISTINCT
            ca.userid,
            bo.refId AS organizationRefId,
            bo.name  AS organizationName
        FROM b_user_category_assignment ca
        INNER JOIN b_user_category buc ON buc.id  = ca.categoryid
        INNER JOIN b_org           bo  ON bo.id   = buc.orgid
    ),
    user_orgs AS (
        SELECT
            uom.userid,
            GROUP_CONCAT(DISTINCT uom.organizationRefId ORDER BY uom.organizationRefId SEPARATOR ',') AS organizationRefIds,
            GROUP_CONCAT(DISTINCT uom.organizationName  ORDER BY uom.organizationName  SEPARATOR ',') AS organizationNames
        FROM user_org_membership uom
        GROUP BY uom.userid
    )
    SELECT
        la.id,
        la.refId,
        la.loanProductId,
        la.userId,
        DATE(la.disbursementDate),
        DATE(la.dueDate),
        COALESCE(la.requestedAmount,  0),
        COALESCE(la.disbursementAmount, 0),
        COALESCE(la.writeOffAmount, 0),
        COALESCE(la.isDefaulted, 0),
        CASE
            WHEN la.applicationStatus = 'COMPLETED'
             AND la.repaymentStatus   = 'PAID'
            THEN 'CLOSED'
            ELSE 'OPEN'
        END,
        la.repaymentPeriod,
        la.interestRate,
        p.id,
        p.refId,
        p.name,
        u.refId,
        u.fullName,
        u.phoneNumber,
        u.idNumber,
        branch.refId,
        branch.name,
        COALESCE(bsr.refId, ''),
        COALESCE(bsr.fullName, ''),
        COALESCE(uo.organizationRefIds, ''),
        COALESCE(uo.organizationNames, '')
    FROM c_loanapplication la
    INNER JOIN u_loan_product         p      ON p.id      = la.loanProductId
    INNER JOIN b_user                 u      ON u.id      = la.userId
    LEFT  JOIN b_branch               branch ON branch.id = u.branchid
    LEFT  JOIN b_sales_representative bsr    ON bsr.id   = u.salesRepresentativeId
    LEFT  JOIN user_orgs              uo     ON uo.userid = u.id
    WHERE la.isActive = 1
      AND (la.approvalStatus = 'APPROVED' OR la.approvalstatus IS NULL)
      AND la.applicationStatus = 'COMPLETED'
      AND la.disbursementStatus = 'DISBURSED'
      AND la.loanStatus = 'OPEN'
      AND la.accountingStatus = 'ACCOUNTED'
      AND la.disbursementDate < v_next_date
      AND (p_loan_ref_id     IS NULL OR p_loan_ref_id     = '' OR la.refId = p_loan_ref_id)
      AND (p_customer_ref_id IS NULL OR p_customer_ref_id = '' OR u.refId  = p_customer_ref_id)
      AND (v_filter_product   = 0 OR EXISTS (SELECT 1 FROM product_filter pf WHERE pf.refId = p.refId))
      AND (v_filter_branch    = 0 OR EXISTS (SELECT 1 FROM branch_filter  bf WHERE bf.refId = branch.refId))
      AND (v_filter_sales_rep = 0 OR EXISTS (SELECT 1 FROM sales_filter   sf WHERE sf.refId = bsr.refId))
      AND (v_filter_org       = 0 OR EXISTS (
              SELECT 1 FROM user_org_membership uom
              INNER JOIN org_filter ofl ON ofl.refId = uom.organizationRefId
              WHERE uom.userid = u.id
      ))
      AND (v_mature_only = FALSE OR DATE(la.dueDate) <= v_report_date)
      AND (
            v_search_term IS NULL
            OR LOWER(la.refId)                       LIKE CONCAT('%', LOWER(v_search_term), '%')
            OR LOWER(p.name)                         LIKE CONCAT('%', LOWER(v_search_term), '%')
            OR LOWER(COALESCE(u.fullName,    ''))    LIKE CONCAT('%', LOWER(v_search_term), '%')
            OR LOWER(COALESCE(u.phoneNumber, ''))    LIKE CONCAT('%', LOWER(v_search_term), '%')
            OR LOWER(COALESCE(u.idNumber,    ''))    LIKE CONCAT('%', LOWER(v_search_term), '%')
            OR LOWER(COALESCE(branch.name,   ''))    LIKE CONCAT('%', LOWER(v_search_term), '%')
            OR LOWER(COALESCE(bsr.fullName,  ''))    LIKE CONCAT('%', LOWER(v_search_term), '%')
            OR CAST(la.id AS CHAR(20))               LIKE CONCAT('%', v_search_term, '%')
      );
    CREATE TEMPORARY TABLE tmp_prd (
        penaltyExecutionRefId VARCHAR(45) NOT NULL,
        reversalPostingDate   DATE,
        PRIMARY KEY (penaltyExecutionRefId)
    );
    INSERT INTO tmp_prd
    SELECT
        penalty.refId,
        DATE(MAX(journal.postingDate))
    FROM c_penaltyexecution penalty
    INNER JOIN gl_journal journal
           ON journal.transactionId = penalty.reversalTransactionId
          AND journal.isActive      = 1
    WHERE penalty.isActive                 = 1
      AND penalty.reversalTransactionId IS NOT NULL
    GROUP BY penalty.refId;
    DROP TEMPORARY TABLE IF EXISTS tmp_pa;
    CREATE TEMPORARY TABLE tmp_pa AS
    SELECT
        p.loanid,
        ROUND(SUM(CASE
            WHEN p.paymentDate < v_next_date
             AND (COALESCE(p.principalAllocation,0) + COALESCE(p.interestAllocation,0) + COALESCE(p.penaltiesAllocation,0)) > 0
            THEN p.amount - COALESCE(p.balanceAfterAllocations, 0) ELSE 0
        END), 2) AS totalPaidToDate,
        ROUND(SUM(CASE
            WHEN p.paymentDate < v_next_date
             AND (COALESCE(p.principalAllocation,0) + COALESCE(p.interestAllocation,0) + COALESCE(p.penaltiesAllocation,0)) > 0
            THEN p.amount ELSE 0
        END), 2) AS totalSchedulePaidToDate,
        MAX(CASE
            WHEN p.paymentDate < v_next_date
             AND (COALESCE(p.principalAllocation,0) + COALESCE(p.interestAllocation,0) + COALESCE(p.penaltiesAllocation,0)) > 0
            THEN DATE(p.paymentDate) ELSE NULL
        END) AS lastPaymentDate
    FROM c_loan_payment p
    INNER JOIN tmp_fl fl ON fl.id = p.loanid
    WHERE p.isActive         = 1
      AND p.accountingStatus = 'ACCOUNTED'
      AND (p.reversalPostingDate IS NULL OR p.reversalPostingDate >= v_next_date)
    GROUP BY p.loanid;
    ALTER TABLE tmp_pa ADD PRIMARY KEY (loanid);
    DROP TEMPORARY TABLE IF EXISTS tmp_lpa;
    CREATE TEMPORARY TABLE tmp_lpa AS
    SELECT
        pa.loanid,
        ROUND(SUM(p.amount), 2) AS lastPaymentAmount
    FROM tmp_pa pa
    INNER JOIN c_loan_payment p
           ON p.loanid           = pa.loanid
          AND DATE(p.paymentDate) = pa.lastPaymentDate
    WHERE pa.lastPaymentDate IS NOT NULL
      AND p.isActive         = 1
      AND p.accountingStatus = 'ACCOUNTED'
      AND (p.reversalPostingDate IS NULL OR p.reversalPostingDate >= v_next_date)
      AND (COALESCE(p.principalAllocation,0) + COALESCE(p.interestAllocation,0) + COALESCE(p.penaltiesAllocation,0)) > 0
    GROUP BY pa.loanid;
    ALTER TABLE tmp_lpa ADD PRIMARY KEY (loanid);

    DROP TEMPORARY TABLE IF EXISTS tmp_spa;
    CREATE TEMPORARY TABLE tmp_spa AS
    SELECT
        e.loanscheduleId AS scheduleId,
        ROUND(SUM(CASE
            WHEN DATE(e.scheduledDate) >  v_report_date
             AND prd.reversalPostingDate IS NULL
            THEN e.amount ELSE 0
        END), 2) AS penaltiesChargedAfter,
        ROUND(SUM(CASE
            WHEN DATE(e.scheduledDate) <= v_report_date
             AND prd.reversalPostingDate >  v_report_date
            THEN e.amount ELSE 0
        END), 2) AS penaltiesChargedBeforeReversedAfter
    FROM c_penaltyexecution e
    INNER JOIN tmp_fl  fl  ON fl.id = e.loanid
    LEFT  JOIN tmp_prd prd ON prd.penaltyExecutionRefId = e.refId
    WHERE e.isActive = 1
      AND e.accountingStatus = 'ACCOUNTED'
      AND e.penaltyStatus    IN ('EXECUTED', 'REVERSED')
      AND e.loanscheduleId   IS NOT NULL
    GROUP BY e.loanscheduleId;
    ALTER TABLE tmp_spa ADD PRIMARY KEY (scheduleId);
    DROP TEMPORARY TABLE IF EXISTS tmp_gl_movements;
    CREATE TEMPORARY TABLE tmp_gl_movements (
        loanid          BIGINT        NOT NULL,
        feeId           BIGINT,
        signedAmount    DECIMAL(19,2),
        deductionRule   VARCHAR(45),
        feeclass        VARCHAR(45),
        receivableAccNo VARCHAR(45),
        lineAccountNo   VARCHAR(45),
        transactionType VARCHAR(45),
        INDEX idx_loan (loanid),
        INDEX idx_fee  (feeId)
    );
    -- PRIMARY SOURCE
    INSERT INTO tmp_gl_movements
    SELECT
        j.loanid,
        gjf.feeId,
        gjf.signedAmount,
        COALESCE(gjf.deductionRule, fee.deductionRule, 'DO_NOT_DEDUCT') AS deductionRule,
        fee.feeclass,
        fee.receivableAccountNumber AS receivableAccNo,
        jl.accountNo AS lineAccountNo,
        j.transactionType
    FROM gl_journal      j
    INNER JOIN gl_journal_line jl  ON jl.journalId     = j.id   AND jl.isActive  = 1
    INNER JOIN gl_journal_fee  gjf ON gjf.journallineid = jl.id  AND gjf.isActive = 1
    INNER JOIN u_fee_config    fee ON fee.id            = gjf.feeId
    INNER JOIN tmp_fl          fl  ON fl.id             = j.loanid
    WHERE j.isActive         = 1
      AND j.postingDate      < v_next_date
      AND NOT (j.accountingEvent = 'ACCREVERSAL' AND j.transactionType NOT IN ('FEE_ACCRUAL', 'ACCRUAL'));
    -- SUPPLEMENTAL SOURCE
    INSERT INTO tmp_gl_movements
    SELECT
        fa.loanid,
        fa.feeId,
        fa.signedamount                                                  AS signedAmount,
        COALESCE(fa.deductionRule, fee.deductionRule, 'DO_NOT_DEDUCT')  AS deductionRule,
        fee.feeclass,
        fee.receivableAccountNumber                                      AS receivableAccNo,
        CAST(fa.gl_coa_id AS CHAR)                                       AS lineAccountNo,
        fa.activityType                                                  AS transactionType
    FROM gl_factacc   fa
    INNER JOIN u_fee_config fee ON fee.id  = fa.feeId
    INNER JOIN tmp_fl        fl  ON fl.id  = fa.loanid
    WHERE fa.isActive  = 1
      AND fa.feeId IS NOT NULL
      AND DATE(fa.postingdate) < v_next_date
      AND NOT EXISTS (
          SELECT 1
          FROM gl_journal j2
          INNER JOIN gl_journal_line jl2  ON jl2.journalId     = j2.id   AND jl2.isActive  = 1
          INNER JOIN gl_journal_fee  gjf2 ON gjf2.journallineid = jl2.id  AND gjf2.isActive = 1
          WHERE j2.loanid = fa.loanid
            AND j2.transactionId = fa.transactionId
            AND j2.isActive = 1
            AND j2.accountingEvent = 'ACCPOST'
            AND gjf2.feeId         = fa.feeId
            AND SIGN(gjf2.signedAmount) = SIGN(fa.signedamount)
      )
      AND NOT EXISTS (
          SELECT 1
          FROM c_loan_payment lp
          WHERE lp.loanid = fa.loanid
            AND lp.transactionId = fa.transactionId
            AND lp.isActive = 0
            AND lp.reversalTransactionId IS NOT NULL
      );
    DROP TEMPORARY TABLE IF EXISTS tmp_jm;
    CREATE TEMPORARY TABLE tmp_jm AS
    SELECT
        fl.id AS loanid,
        fl.writeOffAmount,
        fl.isDefaulted,
        ROUND(SUM(CASE
            WHEN mv.feeId = 1000000
             AND mv.lineAccountNo = mv.receivableAccNo
             AND NOT (mv.signedAmount < 0 AND mv.transactionType = 'LOAN_DISBURSEMENT')
            THEN mv.signedAmount ELSE 0
        END), 2) AS principalBalanceMovement,
        ROUND(SUM(CASE
            WHEN mv.feeId = 1000001
             AND mv.lineAccountNo = mv.receivableAccNo
             AND NOT (mv.signedAmount < 0 AND mv.transactionType = 'LOAN_DISBURSEMENT')
            THEN mv.signedAmount ELSE 0
        END), 2) AS interestBalanceMovement,
        ROUND(SUM(CASE
            WHEN mv.feeclass = 'LOAN_FEE'
             AND mv.feeId NOT IN (1000000, 1000001)
             AND mv.lineAccountNo = mv.receivableAccNo
             AND mv.deductionRule NOT IN ('UPFRONT_FEES','DEDUCT_FROM_DISBURSEMENT','DEPOSIT','ADD_TO_PRINCIPAL')
            THEN mv.signedAmount ELSE 0
        END), 2) AS feesBalanceMovement,
        ROUND(SUM(CASE
            WHEN mv.feeclass = 'PENALTY'
             AND mv.lineAccountNo = mv.receivableAccNo
             AND NOT (mv.signedAmount < 0 AND mv.transactionType = 'LOAN_DISBURSEMENT')
            THEN mv.signedAmount ELSE 0
        END), 2) AS penaltiesBalanceMovement,
        ROUND(SUM(CASE
            WHEN mv.feeclass = 'LOAN_FEE'
             AND mv.feeId NOT IN (1000000, 1000001)
             AND mv.lineAccountNo = mv.receivableAccNo
             AND mv.deductionRule NOT IN ('UPFRONT_FEES','DEDUCT_FROM_DISBURSEMENT','DEPOSIT','ADD_TO_PRINCIPAL')
             AND mv.transactionType = 'FEE_ACCRUAL'
            THEN mv.signedAmount ELSE 0
        END), 2) AS totalFeesChargeMovement,
        ROUND(SUM(CASE
            WHEN mv.feeclass = 'PENALTY'
             AND mv.lineAccountNo = mv.receivableAccNo
             AND mv.transactionType IN ('FEE_ACCRUAL', 'ACCRUAL')
            THEN mv.signedAmount ELSE 0
        END), 2) AS totalPenaltiesChargeMovement
    FROM tmp_fl fl
    LEFT JOIN tmp_gl_movements mv ON mv.loanid = fl.id
    GROUP BY fl.id, fl.writeOffAmount, fl.isDefaulted;
    ALTER TABLE tmp_jm ADD PRIMARY KEY (loanid);

    DROP TEMPORARY TABLE IF EXISTS tmp_jb;
    CREATE TEMPORARY TABLE tmp_jb AS
    SELECT
        m.loanid,
        m.writeOffAmount,
        m.isDefaulted,
        -- GL movement path
        ROUND(GREATEST(0, m.principalBalanceMovement), 2)   AS principalBalanceAsOfDate,
        ROUND(GREATEST(0, m.interestBalanceMovement), 2)    AS interestBalanceAsOfDate,
        ROUND(GREATEST(0, m.feesBalanceMovement), 2)        AS feesBalanceAsOfDate,
        ROUND(GREATEST(0, m.penaltiesBalanceMovement), 2)   AS penaltiesBalanceAsOfDate,
        ROUND(GREATEST(0,
            GREATEST(0, m.principalBalanceMovement)
            + GREATEST(0, m.interestBalanceMovement)
            + GREATEST(0, m.feesBalanceMovement)
            + GREATEST(0, m.penaltiesBalanceMovement)
            + CASE WHEN m.isDefaulted = 1 THEN COALESCE(m.writeOffAmount, 0) ELSE 0 END
        ), 2) AS loanBalanceAsOfDate,
        ROUND(GREATEST(0, m.totalFeesChargeMovement), 2)    AS totalFeesAsOfDate,
        ROUND(GREATEST(0, m.totalPenaltiesChargeMovement), 2) AS totalPenaltiesAsOfDate
    FROM tmp_jm m;
    ALTER TABLE tmp_jb ADD PRIMARY KEY (loanid);
    DROP TEMPORARY TABLE IF EXISTS tmp_swr;
    CREATE TEMPORARY TABLE tmp_swr AS
    SELECT
        s.id,
        s.loanid,
        DATE(s.scheduledDate) AS scheduledDate,
        s.amount,
        COALESCE(
            SUM(s.amount) OVER (
                PARTITION BY s.loanid
                ORDER BY DATE(s.scheduledDate), s.id
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ), 0
        ) AS priorCumAmount
    FROM c_loanpaymentschedule s
    INNER JOIN tmp_fl fl ON fl.id = s.loanid
    WHERE s.isActive = 1;
    ALTER TABLE tmp_swr ADD INDEX idx_loan (loanid), ADD INDEX idx_id (id);
    DROP TEMPORARY TABLE IF EXISTS tmp_ps;
    CREATE TEMPORARY TABLE tmp_ps AS
    SELECT
        swr.loanid,
        swr.scheduledDate,
        GREATEST(0, ROUND(
            swr.amount
            - LEAST(swr.amount, GREATEST(0,
                  COALESCE(pa.totalSchedulePaidToDate, 0) - swr.priorCumAmount
              ))
            - COALESCE(spa.penaltiesChargedAfter,              0)
            + COALESCE(spa.penaltiesChargedBeforeReversedAfter, 0)
        , 2)) AS pitBalance
    FROM tmp_swr swr
    LEFT JOIN tmp_pa  pa  ON pa.loanid      = swr.loanid
    LEFT JOIN tmp_spa spa ON spa.scheduleId = swr.id;
    ALTER TABLE tmp_ps ADD INDEX idx_loan (loanid), ADD INDEX idx_date (scheduledDate);
    DROP TEMPORARY TABLE IF EXISTS tmp_dpd;
    CREATE TEMPORARY TABLE tmp_dpd AS
    SELECT
        fl.id AS loanid,
        GREATEST(COALESCE(
            DATEDIFF(
                v_report_date,
                (SELECT MIN(DATE(s.scheduleddate))
                 FROM   c_loanpaymentschedule s
                 WHERE  s.loanid    = fl.id
                   AND  s.isActive  = 1
                   AND  DATE(s.scheduleddate) <= v_report_date
                   AND  s.paymentstatus NOT IN ('PAID','WRITEOFF','BRIDGED')
                   AND  s.outstandingBalance > 0)
            ), 0), 0) AS currentDPD,
        GREATEST(COALESCE((
            SELECT MAX(COALESCE(DATEDIFF(
                CASE
                    WHEN s.outstandingBalance > 0
                     AND s.paymentstatus NOT IN ('PAID','WRITEOFF','BRIDGED')
                    THEN v_report_date
                    ELSE LEAST(COALESCE(
                            (SELECT DATE(MAX(p.paymentDate))
                             FROM   c_loan_payment p
                             WHERE  p.loanid           = s.loanid
                               AND  p.isactive         = 1
                               AND  p.accountingStatus = 'ACCOUNTED'),
                            v_report_date), v_report_date)
                END,
                DATE(s.scheduleddate)
            ), 0))
            FROM   c_loanpaymentschedule s
            WHERE  s.loanid  = fl.id
              AND  s.isActive = 1
              AND  DATE(s.scheduleddate)  <= v_report_date
              AND  (s.outstandingBalance  > 0 OR s.accruedPenalties > 0)
        ), 0), 0) AS maxDPD,
        ROUND(COALESCE((
            SELECT AVG(DATEDIFF(v_report_date, DATE(s.scheduleddate)))
            FROM   c_loanpaymentschedule s
            WHERE  s.loanid   = fl.id
              AND  s.isActive  = 1
              AND  DATE(s.scheduleddate) <= v_report_date
              AND  s.paymentstatus NOT IN ('PAID','WRITEOFF','BRIDGED')
              AND  s.outstandingBalance  > 0
        ), 0), 0) AS avgDPD
    FROM tmp_fl fl;
    ALTER TABLE tmp_dpd ADD PRIMARY KEY (loanid);
    DROP TEMPORARY TABLE IF EXISTS tmp_pit_base;
    CREATE TEMPORARY TABLE tmp_pit_base AS
    SELECT
        fl.id              AS loanId,
        fl.loanRefId,
        fl.productId,
        fl.productRefId,
        fl.productName,
        fl.userId,
        fl.customerRefId,
        fl.fullName,
        fl.phoneNumber,
        fl.idNumber,
        fl.branchRefId,
        fl.branchName,
        fl.salesRefId,
        fl.salesPersonName,
        fl.organizationRefIds,
        fl.organizationNames,
        fl.disbursementDate,
        fl.maturityDate,
        fl.requestedAmount,
        fl.disbursementAmount,
        fl.writeOffAmount,
        fl.isDefaulted,
        fl.loanStatus,
        fl.installments,
        fl.interestRate
    FROM tmp_fl fl;
    ALTER TABLE tmp_pit_base ADD PRIMARY KEY (loanId);

    CREATE TEMPORARY TABLE tmp_outstanding_loan_snapshot (
        reportDate              DATE,
        loanId                  BIGINT,
        loanRefId               VARCHAR(45),
        loanStatus              VARCHAR(45),
        productId               BIGINT,
        productRefId            VARCHAR(45),
        productName             VARCHAR(255),
        installments            VARCHAR(10),
        customerId              BIGINT,
        customerRefId           VARCHAR(45),
        fullName                VARCHAR(255),
        phoneNumber             VARCHAR(45),
        idNumber                VARCHAR(45),
        branchRefId             VARCHAR(45),
        branchName              VARCHAR(255),
        salesRefId              VARCHAR(45),
        salesPersonName         VARCHAR(255),
        organizationRefIds      TEXT,
        organizationNames       TEXT,
        disbursementDate        DATE,
        maturityDate            DATE,
        isMaturedAsOfDate       VARCHAR(3),
        repaymentStatus         VARCHAR(45),
        writeOffAmount          VARCHAR(25),
        requestedAmount         VARCHAR(25),
        disbursementAmount      VARCHAR(25),
        principalBalance        VARCHAR(25),
        interestBalance         VARCHAR(25),
        interestRate            DECIMAL(10,5),
        totalFees               VARCHAR(25),
        feesBalance             VARCHAR(25),
        totalPenalties          VARCHAR(25),
        penaltiesBalance        VARCHAR(25),
        loanBalance             VARCHAR(25),
        totalPayment            VARCHAR(25),
        lastPaymentDate         VARCHAR(10),
        lastPaymentAmount       VARCHAR(25),
        arrearsBalance          VARCHAR(25),
        firstArrearsDate        VARCHAR(10),
        lastArrearsDate         VARCHAR(10),
        arrearsInstallmentCount VARCHAR(10),
        isInArrears             VARCHAR(3),
        currentDPD              VARCHAR(10),
        maxDPD                  VARCHAR(10),
        avgDPD                  VARCHAR(10)
    );

    INSERT INTO tmp_outstanding_loan_snapshot
    WITH
    payment_aggregates AS (SELECT * FROM tmp_pa),
    last_payment_amount AS (SELECT * FROM tmp_lpa),
    schedule_penalty_adjustments AS (SELECT * FROM tmp_spa),
    journal_movements_to_date AS (SELECT * FROM tmp_jm),
    journal_balances_to_date AS (SELECT * FROM tmp_jb),
    schedule_with_running AS (SELECT * FROM tmp_swr),
    pit_schedule AS (SELECT * FROM tmp_ps),
    arrears AS (
        SELECT
            ps.loanid,
            MIN(ps.scheduledDate)        AS firstArrearsDate,
            MAX(ps.scheduledDate)        AS lastArrearsDate,
            COUNT(*)                     AS arrearsInstallmentCount,
            ROUND(SUM(ps.pitBalance), 2) AS arrearsBalance
        FROM pit_schedule ps
        WHERE ps.scheduledDate <= v_report_date
          AND ps.pitBalance     > 0
        GROUP BY ps.loanid
    ),
    pit_loans_base AS (
        SELECT
            fl.loanId,
            fl.loanRefId,
            fl.productId,
            fl.productRefId,
            fl.productName,
            fl.userId,
            fl.customerRefId,
            fl.fullName,
            fl.phoneNumber,
            fl.idNumber,
            fl.branchRefId,
            fl.branchName,
            fl.salesRefId,
            fl.salesPersonName,
            fl.organizationRefIds,
            fl.organizationNames,
            fl.disbursementDate,
            fl.maturityDate,
            fl.requestedAmount,
            fl.disbursementAmount,
            fl.writeOffAmount,
            fl.isDefaulted,
            fl.loanStatus,
            COALESCE(CAST(jb.principalBalanceAsOfDate AS CHAR), '0.00') AS principalBalanceAsOfDate,
            COALESCE(CAST(jb.interestBalanceAsOfDate  AS CHAR), '0.00') AS interestBalanceAsOfDate,
            COALESCE(CAST(jb.totalFeesAsOfDate        AS CHAR), '0.00') AS totalFeesAsOfDate,
            COALESCE(CAST(jb.feesBalanceAsOfDate      AS CHAR), '0.00') AS feesBalanceAsOfDate,
            COALESCE(CAST(jb.totalPenaltiesAsOfDate   AS CHAR), '0.00') AS totalPenaltiesAsOfDate,
            COALESCE(CAST(jb.penaltiesBalanceAsOfDate AS CHAR), '0.00') AS penaltiesBalanceAsOfDate,
            COALESCE(CAST(jb.loanBalanceAsOfDate      AS CHAR), '0.00') AS loanBalanceAsOfDate,
            ROUND(COALESCE(pa.totalPaidToDate, 0), 2)         AS totalPaymentAsOfDate,
            COALESCE(pa.totalSchedulePaidToDate, 0)           AS totalSchedulePaidToDate,
            IFNULL(pa.lastPaymentDate, '')                    AS lastPaymentDate,
            IFNULL(lpa.lastPaymentAmount, '')                 AS lastPaymentAmount,
            COALESCE(NULLIF(ar.arrearsBalance,           0), '') AS arrearsBalance,
            IFNULL(ar.firstArrearsDate, '')                   AS firstArrearsDate,
            IFNULL(ar.lastArrearsDate, '')                    AS lastArrearsDate,
            COALESCE(NULLIF(ar.arrearsInstallmentCount,  0), '') AS arrearsInstallmentCount,
            COALESCE(NULLIF(dpd.currentDPD, 0), '')           AS currentDPD,
            COALESCE(NULLIF(dpd.maxDPD,     0), '')           AS maxDPD,
            COALESCE(NULLIF(dpd.avgDPD,     0), '')           AS avgDPD,
            CASE WHEN ar.firstArrearsDate IS NULL 
                 THEN 'NO' 
                 ELSE 'YES' 
            END AS isInArrears,
            fl.installments,
            fl.interestRate
        FROM tmp_pit_base fl
        LEFT JOIN payment_aggregates       pa  ON pa.loanid  = fl.loanId
        LEFT JOIN last_payment_amount      lpa ON lpa.loanid = fl.loanId
        LEFT JOIN arrears                  ar  ON ar.loanid  = fl.loanId
        LEFT JOIN journal_balances_to_date jb  ON jb.loanid  = fl.loanId
        LEFT JOIN tmp_dpd                  dpd ON dpd.loanid = fl.loanId
    ),
    pit_loans AS (
        SELECT plb.*,
            CASE
                WHEN plb.isDefaulted = 1 THEN 'WRITEOFF'
                WHEN plb.loanBalanceAsOfDate = ''
                  OR CAST(NULLIF(plb.loanBalanceAsOfDate,'') AS DECIMAL(19,2)) <= 0
                THEN 'PAID'
                WHEN plb.totalSchedulePaidToDate > 0 OR plb.totalPaymentAsOfDate > 0
                THEN 'PARTIALLYPAID'
                ELSE 'NOTPAID'
            END AS repaymentStatusAsOfDate
        FROM pit_loans_base plb
    )
    SELECT
        v_report_date,
        pl.loanId,
        pl.loanRefId,
        pl.loanStatus,
        pl.productId,
        pl.productRefId,
        pl.productName,
        pl.installments,
        pl.userId  AS customerId,
        pl.customerRefId,
        pl.fullName,
        pl.phoneNumber,
        pl.idNumber,
        pl.branchRefId,
        pl.branchName,
        pl.salesRefId,
        pl.salesPersonName,
        pl.organizationRefIds,
        pl.organizationNames,
        pl.disbursementDate,
        pl.maturityDate,
        CASE WHEN pl.maturityDate <= v_report_date
             THEN 'YES'
             ELSE 'NO'
        END AS isMaturedAsOfDate,
        pl.repaymentStatusAsOfDate  AS repaymentStatus,
        CASE WHEN pl.isDefaulted = 1
             THEN CAST(pl.writeOffAmount AS CHAR)
             ELSE ''
        END AS writeOffAmount,
        pl.requestedAmount,
        pl.disbursementAmount,
        pl.principalBalanceAsOfDate AS principalBalance,
        pl.interestBalanceAsOfDate  AS interestBalance,
        pl.interestRate,
        pl.totalFeesAsOfDate        AS totalFees,
        pl.feesBalanceAsOfDate      AS feesBalance,
        pl.totalPenaltiesAsOfDate   AS totalPenalties,
        pl.penaltiesBalanceAsOfDate AS penaltiesBalance,
        pl.loanBalanceAsOfDate      AS loanBalance,
        pl.totalPaymentAsOfDate     AS totalPayment,
        pl.lastPaymentDate,
        pl.lastPaymentAmount,
        pl.arrearsBalance,
        pl.firstArrearsDate,
        pl.lastArrearsDate,
        pl.arrearsInstallmentCount,
        pl.isInArrears,
        pl.currentDPD,
        pl.maxDPD,
        pl.avgDPD
    FROM pit_loans pl
    WHERE (CAST(NULLIF(pl.loanBalanceAsOfDate, '') AS DECIMAL(19,2)) > 0
            OR (CAST(NULLIF(pl.loanBalanceAsOfDate, '') AS DECIMAL(19,2)) <= 0
                AND pl.lastPaymentDate = DATE_FORMAT(v_report_date, '%Y-%m-%d')))
      AND (v_in_arrears_only = FALSE OR pl.isInArrears = 'YES')
      AND (p_min_dpd IS NULL OR CAST(NULLIF(pl.maxDPD, '') AS SIGNED) >= p_min_dpd)
      AND (p_max_dpd IS NULL OR CAST(NULLIF(pl.maxDPD, '') AS SIGNED) <= p_max_dpd);

    DROP TEMPORARY TABLE IF EXISTS tmp_pa;
    DROP TEMPORARY TABLE IF EXISTS tmp_lpa;
    DROP TEMPORARY TABLE IF EXISTS tmp_spa;
    DROP TEMPORARY TABLE IF EXISTS tmp_gl_movements;
    DROP TEMPORARY TABLE IF EXISTS tmp_jm;
    DROP TEMPORARY TABLE IF EXISTS tmp_swr;
    DROP TEMPORARY TABLE IF EXISTS tmp_dpd;
    DROP TEMPORARY TABLE IF EXISTS tmp_pit_base;
    DROP TEMPORARY TABLE IF EXISTS tmp_fl;
    DROP TEMPORARY TABLE IF EXISTS tmp_prd;
    DROP TEMPORARY TABLE IF EXISTS tmp_jb;
    DROP TEMPORARY TABLE IF EXISTS tmp_ps;
END $$
CREATE PROCEDURE proc_outstanding_loan_snapshot_v2(
    IN p_report_date        DATE,
    IN p_search_term        VARCHAR(255),
    IN p_filter_product     INT,
    IN p_product_ref_ids    JSON,
    IN p_filter_branch      INT,
    IN p_branch_ref_ids     JSON,
    IN p_filter_org         INT,
    IN p_org_ref_ids        JSON,
    IN p_filter_sales_rep   INT,
    IN p_sales_rep_ref_ids  JSON,
    IN p_loan_ref_id        VARCHAR(45),
    IN p_customer_ref_id    VARCHAR(45),
    IN p_mature_only        BOOLEAN,
    IN p_in_arrears_only    BOOLEAN,
    IN p_min_dpd            INT,
    IN p_max_dpd            INT,
    IN p_offset             INT,
    IN p_limit              INT
)
BEGIN
    DECLARE v_offset INT;
    DECLARE v_limit  INT;
    SET v_offset = CASE WHEN p_offset IS NULL OR p_offset < 0 THEN 0          ELSE p_offset END;
    SET v_limit  = CASE WHEN p_limit  IS NULL OR p_limit  < 1 THEN 2147483647 ELSE p_limit  END;
    CALL proc_prepare_outstanding_loan_snapshot(
        p_report_date, p_search_term,
        p_filter_product,   p_product_ref_ids,
        p_filter_branch,    p_branch_ref_ids,
        p_filter_org,       p_org_ref_ids,
        p_filter_sales_rep, p_sales_rep_ref_ids,
        p_loan_ref_id, p_customer_ref_id,
        p_mature_only, p_in_arrears_only,
        p_min_dpd, p_max_dpd
    );
    SELECT * FROM tmp_outstanding_loan_snapshot
    ORDER BY disbursementDate DESC, loanId DESC
    LIMIT v_offset, v_limit;
END $$
CREATE PROCEDURE proc_count_outstanding_loan_snapshot_v2(
    IN p_report_date        DATE,
    IN p_search_term        VARCHAR(255),
    IN p_filter_product     INT,
    IN p_product_ref_ids    JSON,
    IN p_filter_branch      INT,
    IN p_branch_ref_ids     JSON,
    IN p_filter_org         INT,
    IN p_org_ref_ids        JSON,
    IN p_filter_sales_rep   INT,
    IN p_sales_rep_ref_ids  JSON,
    IN p_loan_ref_id        VARCHAR(45),
    IN p_customer_ref_id    VARCHAR(45),
    IN p_mature_only        BOOLEAN,
    IN p_in_arrears_only    BOOLEAN,
    IN p_min_dpd            INT,
    IN p_max_dpd            INT
)
BEGIN
    CALL proc_prepare_outstanding_loan_snapshot(
        p_report_date, p_search_term,
        p_filter_product,   p_product_ref_ids,
        p_filter_branch,    p_branch_ref_ids,
        p_filter_org,       p_org_ref_ids,
        p_filter_sales_rep, p_sales_rep_ref_ids,
        p_loan_ref_id, p_customer_ref_id,
        p_mature_only, p_in_arrears_only,
        p_min_dpd, p_max_dpd
    );
    SELECT COUNT(*) AS totalCount FROM tmp_outstanding_loan_snapshot;
END $$
CREATE PROCEDURE proc_outstanding_loan_snapshot(IN p_report_date DATE)
BEGIN
    CALL proc_outstanding_loan_snapshot_v2(
        p_report_date, NULL,
        0, JSON_ARRAY(), 0, JSON_ARRAY(), 0, JSON_ARRAY(), 0, JSON_ARRAY(),
        NULL, NULL, FALSE, FALSE, NULL, NULL, 0, NULL
    );
END $$
CREATE PROCEDURE proc_outstanding_loans_as_of_v2(
    IN p_report_date        DATE,
    IN p_search_term        VARCHAR(255),
    IN p_filter_product     INT,
    IN p_product_ref_ids    JSON,
    IN p_filter_branch      INT,
    IN p_branch_ref_ids     JSON,
    IN p_filter_org         INT,
    IN p_org_ref_ids        JSON,
    IN p_filter_sales_rep   INT,
    IN p_sales_rep_ref_ids  JSON,
    IN p_loan_ref_id        VARCHAR(45),
    IN p_customer_ref_id    VARCHAR(45),
    IN p_mature_only        BOOLEAN,
    IN p_in_arrears_only    BOOLEAN,
    IN p_min_dpd            INT,
    IN p_max_dpd            INT
)
BEGIN
    CALL proc_outstanding_loan_snapshot_v2(
        p_report_date, p_search_term,
        p_filter_product,   p_product_ref_ids,
        p_filter_branch,    p_branch_ref_ids,
        p_filter_org,       p_org_ref_ids,
        p_filter_sales_rep, p_sales_rep_ref_ids,
        p_loan_ref_id, p_customer_ref_id,
        p_mature_only, p_in_arrears_only,
        p_min_dpd, p_max_dpd, 0, NULL
    );
END $$
CREATE PROCEDURE proc_outstanding_loans_as_of(IN p_report_date DATE)
BEGIN
    CALL proc_outstanding_loan_snapshot(p_report_date);
END $$
DELIMITER ;


-- CALL proc_outstanding_loan_snapshot('2026-06-30');
