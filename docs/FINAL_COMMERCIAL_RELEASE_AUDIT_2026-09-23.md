# Bradford ERP — Final Commercial Release Audit

Audit date: 2026-09-23 (Africa/Cairo)  
Production commit inspected: `dae808a`  
Production: <https://app.bradforderp.com/>  
GitHub Pages: <https://ahmedihab152-netizen.github.io/Bradford-Finance/>

## Decision

**NOT READY for commercial handover.** The deployed application remains available, but the commercial release gate is closed. No Production financial row was created, changed, approved, posted, reversed, or deleted during this audit.

## Evidence summary

| Gate | Result | Evidence |
|---|---|---|
| Resend SMTP and password recovery | PASS (user-verified) | A recovery request returned successfully; Dr Amany completed password reset and Production Auth records a successful sign-in at `2026-09-23 05:46:57 UTC`. No secret was read or stored. |
| Frontend/JavaScript/static security | PASS | 23/23 automated tests passed; static verification passed; no service-role key, private key, DB credential URL, localhost URL, native `alert()` or duplicate production HTML entry was found. |
| HTTPS production endpoints | PASS | Both production URLs returned HTTP 200 over HTTPS with identical 225,416-byte payloads. |
| RLS coverage | PASS with security warnings | All 193 Production public tables and all 194 Staging public tables have RLS enabled. Supabase Security Advisor still reports 37 Production and 39 Staging authenticated-callable `SECURITY DEFINER` functions requiring explicit allow-list review. |
| Role bindings | PARTIAL | Production contains OWNER, HR_MANAGER, DR_AMANY_APPROVER, PAYROLL_CASHIER, ATTENDANCE_OFFICER and IG_ACCOUNTANT bindings. Only OWNER accounts have signed in for all environments; Dr Amany signed in on Production. Several required role accounts have never completed real browser UAT. |
| Payroll workflow | PASS server-side / FAIL real-role browser UAT | Isolated Staging transaction reached `PAID`, recorded preparer/submitter/approver/cashier, produced four HR audit events and two balanced journals, then rolled back. Residue check was zero. Real named-user browser UAT is incomplete. |
| Approval workflow | PARTIAL | Dr Amany's exclusive role/capability and Production sign-in are verified. Production currently has zero SUBMITTED student payments and zero SUBMITTED expenses, so no real pending approval can be validated without changing live data. |
| Attachments | FAIL release parity | Staging has `operation_attachments`; Production does not. All Storage buckets are private, but both environments currently contain zero objects, so upload/open/delete and off-site object-backup recovery are not evidenced end-to-end. |
| Audit trail | PASS for tested payroll transaction | The rolled-back workflow emitted four expected HR audit events. Production has 13,441 general audit events and 193 HR audit events. Append-only behavior still requires named-role browser testing. |
| Database integrity | PARTIAL | No unbalanced POSTED journals were found. Production counts: 509 students, 909 student payments, 1,642 expenses, zero payroll runs/payments, zero inventory movements. Two student-payment dates are year 2100 or later and require data-owner review without automatic correction. |
| Backup and restore | FAIL | `backup_manifests` and `restore_test_runs` are empty in Production and Staging. No current restore rehearsal or separate Storage-object backup evidence exists. The older dashboard screenshot is not sufficient evidence for the 2026-09-23 release. |
| ZKTeco biometric | FAIL | No device, employee link, or real punch exists in either environment. `biometric_sync_enabled=false` remains correct. Physical connection and one matched real fingerprint are mandatory. |
| Android | PASS debug build / PARTIAL release | `gradlew bundleDebug` completed successfully. Store-signed release AAB, device QA, push delivery and biometric native-login QA are not evidenced. |
| iOS | FAIL | No macOS/Xcode archive, signing, TestFlight upload, device QA, Face ID or push-delivery evidence is available. |
| Staging security posture | FAIL | Leaked Password Protection and sufficient MFA options are still flagged on Staging. Production has no leaked-password warning, but retains the SECURITY DEFINER review warning. |
| Production/Staging schema parity | FAIL | Staging has 194 public tables; Production has 193. The missing Production table is `operation_attachments`. Production deployment is blocked until migration parity is reviewed and rehearsed. |

## Non-destructive Staging UAT

The payroll test used an isolated SQL transaction and temporary Auth/profile/capability/scope/employee/payroll rows. It exercised:

`DRAFT → SUBMITTED → APPROVED → PAID`

Observed before rollback:

- status `PAID`;
- preparer, submitter, approver and cashier timestamps/users populated;
- one payroll payment;
- four HR audit events;
- two balanced journals.

Post-rollback residue:

- temporary Auth users: 0;
- temporary profiles: 0;
- temporary employees: 0;
- temporary payroll runs: 0;
- temporary payroll payments: 0.

## Required closure actions

1. Connect the physical ZKTeco device in Staging, register its serial/IP/integration method, map one real device user to one employee, import one real punch, verify timestamp/timezone/duplicate prevention, and retain signed evidence. Only then consider enabling biometric synchronization.
2. Apply/rehearse the missing attachment migration on Staging, perform a real private-bucket upload/open/download/delete test with a non-financial test file, confirm signed URL expiry and audit attribution, then take a separate encrypted Storage backup.
3. Record a current database backup manifest with SHA-256, restore it to an isolated target, verify schema/counts/RLS/journal balance, and record a PASSED restore test. Never restore over Production.
4. Complete browser UAT by the actual named users without sharing passwords: HR manager, attendance officer, Dr Amany, both payroll cashiers, IG accountant, auditor/accountant/treasury/procurement/storekeeper as applicable.
5. Review and explicitly allow-list or reduce the 37 Production authenticated-callable SECURITY DEFINER functions using the Supabase advisor guidance.
6. Investigate the two payment dates in/after 2100 and document the owner's correction decision. Do not auto-correct.
7. Enable Staging leaked-password protection and appropriate MFA methods, then rerun the advisor.
8. Produce a signed Android release AAB and an iOS Archive/TestFlight build, then run device, push, offline, PDF/share, biometric-login and accessibility tests.

## Deployment decision

No Production migration, merge, push or release rollback was performed because mandatory commercial gates failed. The currently deployed commit remains `dae808a`.

