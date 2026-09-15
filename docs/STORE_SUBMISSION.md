# Bradford ERP — Store submission pack

This document contains draft store copy and operational answers. Legal, privacy, and business owners must approve the final declarations before submission.

## Identity

- App name: **Bradford ERP**
- Android application ID / iOS bundle ID: `com.bradforderp.app`
- Version: `1.0.0`
- Category: Business
- Audience: authorized school employees and administrators; not a children’s app and not intended for student use
- Website: `https://app.bradforderp.com`
- Support: `https://app.bradforderp.com/docs/support.html`
- Privacy policy: `https://app.bradforderp.com/docs/privacy.html`
- Account deletion: `https://app.bradforderp.com/docs/account-deletion.html`
- Support email: `support@bradforderp.com`
- Technical contact: `developer@bradforderp.com`

## Arabic listing

### Short description

إدارة الموارد البشرية والحسابات والموافقات المدرسية بأمان من مكان واحد.

### Full description

Bradford ERP هو نظام تشغيلي لموظفي المدرسة المصرح لهم، يجمع الموارد البشرية والحسابات والتحصيلات والموافقات والتقارير في تطبيق واحد.

يشمل النظام ملفات الموظفين، الحضور والانصراف، الإجازات والخصومات والمرتبات، بالإضافة إلى حسابات الطلاب والتحصيلات والخزنة والمصروفات والمخزون والأصول والنقل والتقارير. تعتمد الصلاحيات على دور كل مستخدم، وتُسجل العمليات المهمة في سجل تدقيق.

التطبيق مخصص للاستخدام الإداري الداخلي. يلزم حساب معتمد من إدارة المؤسسة، وقد تتطلب بعض الأدوار تحققًا إضافيًا.

## English listing

### Short description

Secure school HR, finance, approvals, collections, and reports in one app.

### Full description

Bradford ERP is an operational platform for authorized school staff. It brings human resources, finance, student collections, approvals, and reporting into one secure application.

The system covers employee records, attendance, leave, deductions, payroll, student accounts, treasury, expenses, inventory, assets, transport, and operational reports. Access is role-based, and important actions are recorded in an audit trail.

The app is intended for internal administrative use. An approved organizational account is required, and some roles may require additional verification.

## App Review notes

- This is an internal school administration and ERP application, not a consumer banking or student application.
- No digital goods, subscriptions, advertising, or in-app purchases are sold in the app.
- The backend must remain available during review.
- Provide a dedicated reviewer account with non-production demonstration data and the minimum permissions needed to inspect the app.
- If MFA is enabled for the reviewer, include an approved review procedure in the private review notes. Never publish credentials in this repository.
- Explain that financial posting and payroll approval are restricted by role and cannot be demonstrated from a read-only account.

## Privacy questionnaire draft

Confirm every answer with the school’s legal/privacy owner before submission.

| Data group | Expected use | Shared/sold |
|---|---|---|
| Account identifiers, name, email, role | Authentication, authorization, support | Service providers only; not sold |
| Employee and HR records | HR operations and payroll | Authorized school users and processors only |
| Student and guardian records | Accounts, collections, transport, school operations | Authorized school users and processors only |
| Financial records | Accounting, audit, receipts, approvals | Authorized school users and processors only |
| Documents and uploaded files | Evidence, contracts, receipts, HR records | Authorized school users and processors only |
| Attendance and biometric-device identifiers | Attendance calculation and audit | Authorized school users and processors only |
| Audit and security events | Security, fraud prevention, compliance | Processors and authorized administrators only |

Operational declarations:

- Data is encrypted in transit using HTTPS/TLS.
- Data is not sold and is not used for advertising or cross-app tracking.
- Access is restricted by authenticated role and database row-level security.
- A user can initiate an account-deletion request from the app and the published deletion page.
- Some accounting, payroll, and audit records may need to be retained for legal or operational obligations after account access is disabled.

## Assets still required

- Phone screenshots showing login, dashboard, HR, finance, and a non-sensitive report.
- Tablet screenshots if tablet distribution is enabled.
- Final app icon approval by the brand owner.
- Optional promotional graphic for Google Play.
- A reviewer demo account populated only with synthetic demonstration records.
- Legal approval of the privacy policy and retention wording.

Do not use screenshots containing real student, employee, financial, national-ID, biometric, or authentication data.
