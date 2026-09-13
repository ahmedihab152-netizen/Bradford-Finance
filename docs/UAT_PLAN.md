# Isolated UAT plan

The UAT screen writes only to `uat_runs` and `uat_steps`. These tables are not referenced by dashboards, ledgers, student balances, expenses, or reports.

Required role evidence: OWNER access/oversight, ACCOUNTANT draft creation, FINANCE_MANAGER submission/review, IG ACCOUNTANT cost-center isolation, and the configured Dr Amany approval authority. The last two are capabilities checked from the existing cost-center/approval-authority model rather than new values in `finance_role`.

Scenario: create isolated run; verify payment and expense DRAFT; advance both to SUBMITTED; confirm they still do not affect official totals; verify configured Dr Amany authority; advance the simulation to POSTED; print the simulated payment receipt and expense voucher; record PASS/FAIL evidence. This does not impersonate users and does not create real financial records.
