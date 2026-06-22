# \# Outstanding Loan Snapshot Report

# 

# \## Overview

# 

# The Outstanding Loan Snapshot Report provides a point-in-time view of the loan portfolio as of a specified reporting date. It reconstructs the financial position of every active loan using loan master data, repayment schedules, payment transactions, penalty events, and accounting ledger movements to produce an accurate outstanding balance and delinquency snapshot.

# 

# \## Business Purpose

# 

# This report supports portfolio monitoring, credit risk management, collections operations, finance reconciliation, and regulatory reporting by presenting the exact outstanding position of loans on a selected date.

# 

# The report enables stakeholders to:

# 

# \* Measure total outstanding portfolio exposure.

# \* Monitor principal, interest, fee, and penalty receivables.

# \* Identify loans in arrears and delinquent accounts.

# \* Track Days Past Due (DPD) metrics.

# \* Analyze repayment performance and maturity status.

# \* Assess write-offs and defaulted loan exposure.

# \* Support provisioning, collections, and portfolio quality reporting.

# 

# 

# \## Technical Architecture

# 

# The report is implemented through a series of MySQL stored procedures that construct a temporary point-in-time dataset using staged calculations and aggregations.

# 

# \### Core Procedures

# 

# | Procedure                                 | Purpose                                                                          |

# | ----------------------------------------- | -------------------------------------------------------------------------------- |

# | `proc\_prepare\_outstanding\_loan\_snapshot`  | Builds the snapshot dataset and calculates all balances and delinquency metrics. |

# | `proc\_outstanding\_loan\_snapshot\_v2`       | Returns paginated report results.                                                |

# | `proc\_count\_outstanding\_loan\_snapshot\_v2` | Returns total record count for pagination.                                       |

# | `proc\_outstanding\_loan\_snapshot`          | Wrapper procedure with default parameters.                                       |

# | `proc\_outstanding\_loans\_as\_of\_v2`         | Alias procedure for as-of-date reporting.                                        |

# | `proc\_outstanding\_loans\_as\_of`            | Legacy wrapper procedure.                                                        |

# 

# 

# 

# \## Data Sources

# 

# The report derives information from:

# 

# \### Loan Origination

# 

# \* `c\_loanapplication`

# \* `u\_loan\_product`

# 

# \### Customer \& Organizational Structure

# 

# \* `b\_user`

# \* `b\_branch`

# \* `b\_sales\_representative`

# \* `b\_org`

# \* `b\_user\_category\_assignment`

# 

# \### Payments \& Schedules

# 

# \* `c\_loan\_payment`

# \* `c\_loanpaymentschedule`

# 

# \### Penalties

# 

# \* `c\_penaltyexecution`

# 

# \### Accounting \& General Ledger

# 

# \* `gl\_journal`

# \* `gl\_journal\_line`

# \* `gl\_journal\_fee`

# \* `gl\_factacc`

# 

# 

# \## Financial Calculations

# 

# \### Outstanding Principal

# 

# Calculated from accounting receivable movements associated with the principal receivable account.

# 

# \### Outstanding Interest

# 

# Calculated from interest-related receivable ledger movements posted up to the reporting date.

# 

# \### Outstanding Fees

# 

# Represents accrued and unpaid loan fees excluding upfront, deducted, deposit, and capitalized fees.

# 

# \### Outstanding Penalties

# 

# Represents accrued and unpaid penalty charges after applying reversal adjustments.

# 

# \### Total Loan Balance

# 

# Loan Balance = Principal + Interest + Fees + Penalties + Write-Off Exposure

# 

# The balance is reconstructed directly from accounting movements to ensure financial accuracy.

# 

# \### Payments

# 

# The report calculates:

# 

# \* Total payments received to date.

# \* Scheduled repayments received.

# \* Last payment date.

# \* Last payment amount.

# 

# Only accounted and non-reversed transactions are considered.

# 

# 

# \## Delinquency \& Arrears Analysis

# 

# \### Arrears Balance

# 

# Calculated using repayment schedules and payment allocations to determine overdue unpaid installments as of the reporting date.

# 

# \### Days Past Due (DPD)

# 

# The report computes:

# 

# | Metric      | Description                                      |

# | ----------- | ------------------------------------------------ |

# | Current DPD | Days since earliest unpaid overdue installment.  |

# | Maximum DPD | Highest delinquency experienced by the loan.     |

# | Average DPD | Average overdue days across unpaid installments. |

# 

# \### Arrears Indicators

# 

# \* First arrears date

# \* Last arrears date

# \* Number of overdue installments

# \* Arrears balance

# \* In-arrears flag (YES/NO)

# 

# 

# \## Loan Classification Logic

# 

# \### Repayment Status

# 

# | Status        | Condition                                      |

# | ------------- | ---------------------------------------------- |

# | PAID          | Outstanding balance ≤ 0                        |

# | PARTIALLYPAID | Payments exist but balance remains outstanding |

# | NOTPAID       | No repayments recorded                         |

# | WRITEOFF      | Loan marked as defaulted/write-off             |

# 

# \### Maturity Status

# 

# | Status | Condition                      |

# | ------ | ------------------------------ |

# | YES    | Maturity date ≤ reporting date |

# | NO     | Maturity date > reporting date |

# 

# 

# \## Supported Filters

# 

# The report supports dynamic filtering by:

# 

# \* Reporting Date

# \* Loan Reference

# \* Customer Reference

# \* Product

# \* Branch

# \* Organization

# \* Sales Representative

# \* Search Term

# \* Matured Loans Only

# \* Loans in Arrears Only

# \* Minimum DPD

# \* Maximum DPD

# 

# 

# \## Output Metrics

# 

# The report produces the following key portfolio indicators:

# 

# \### Exposure Metrics

# 

# \* Requested Amount

# \* Disbursed Amount

# \* Outstanding Principal

# \* Outstanding Interest

# \* Outstanding Fees

# \* Outstanding Penalties

# \* Total Outstanding Loan Balance

# \* Write-Off Amount

# 

# \### Repayment Metrics

# 

# \* Total Payments

# \* Last Payment Date

# \* Last Payment Amount

# 

# \### Credit Risk Metrics

# 

# \* Current DPD

# \* Maximum DPD

# \* Average DPD

# \* Arrears Balance

# \* Arrears Installment Count

# \* Repayment Status

# \* Maturity Status

# 

# \### Portfolio Segmentation

# 

# \* Product

# \* Branch

# \* Organization

# \* Sales Representative

# \* Customer

# 

# 

# \## Key Financial Characteristics

# 

# \* Point-in-time portfolio reconstruction.

# \* Ledger-driven balance calculations.

# \* Supports historical as-of-date reporting.

# \* Includes reversals and accounting adjustments.

# \* Captures delinquency and arrears exposure.

# \* Suitable for portfolio analytics, collections management, finance reconciliation, and regulatory reporting.



