import json
import re
import shutil
import sys
from pathlib import Path


def sql_json(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).replace("'", "''")


def sql_text(value):
    return str(value).replace("'", "''")


def chunks(values, size=300):
    for start in range(0, len(values), size):
        yield values[start : start + size]


def write(path, content):
    path.write_text(content.strip() + "\n", encoding="utf-8")


def main():
    payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    output = Path(sys.argv[2])
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    sequence = 0

    def emit(label, sql):
        nonlocal sequence
        sequence += 1
        write(output / f"{sequence:03d}_{label}.sql", sql)

    emit(
        "backup_and_cutover",
        """
        begin;
        create schema if not exists archive;
        create table archive.bf_20261022_students as table public.students;
        create table archive.bf_20261022_student_accounts as table public.student_accounts;
        create table archive.bf_20261022_student_payments as table public.student_payments;
        create table archive.bf_20261022_transport_enrollments as table public.transport_enrollments;
        create table archive.bf_20261022_transport_routes as table public.transport_routes;
        create table archive.bf_20261022_legacy_applications as table public.legacy_applications;
        create table archive.bf_20261022_legacy_treasury_rows as table public.legacy_treasury_rows;
        create table archive.bf_20261022_treasury_transactions as table public.treasury_transactions;
        create table archive.bf_20261022_bank_accounts as table public.bank_accounts;
        create table archive.bf_20261022_bank_transactions as table public.bank_transactions;
        update public.erp_source_files set active=false,status='SUPERSEDED' where active;
        delete from public.transport_enrollments;
        update public.student_accounts set
          source_meta=coalesce(source_meta,'{}'::jsonb)||jsonb_build_object('superseded',true,'superseded_at','2026-10-22'),
          notes=concat_ws(' — ',notes,'تم استبداله بملفات المصدر المعتمدة بتاريخ 2026-10-22'),
          updated_at=now();
        delete from public.legacy_applications;
        delete from public.legacy_treasury_rows;
        update public.transport_routes set status='INACTIVE';
        update public.students set status='INACTIVE',updated_at=now();
        commit;
        """,
    )

    source_files = payload["source_files"]
    for part in chunks(source_files, 50):
        rows = sql_json(part)
        emit(
            "source_files",
            f"""
            insert into public.erp_source_files(file_key,file_name,sha256,category,academic_year,size_bytes,row_count,status,active,metadata)
            select x.file_key,x.file_name,x.sha256,x.category,x.academic_year,x.size_bytes,x.row_count,
              case when x.duplicate_of is null then 'VALIDATED' else 'DUPLICATE' end,
              x.duplicate_of is null,
              jsonb_build_object('duplicate_of_key',x.duplicate_of,'loaded_at','2026-10-22')
            from jsonb_to_recordset('{rows}'::jsonb)
              as x(file_key text,file_name text,sha256 text,category text,academic_year text,size_bytes bigint,row_count integer,duplicate_of text)
            on conflict(file_key) do update set file_name=excluded.file_name,sha256=excluded.sha256,category=excluded.category,
              academic_year=excluded.academic_year,size_bytes=excluded.size_bytes,row_count=excluded.row_count,status=excluded.status,
              active=excluded.active,metadata=excluded.metadata;
            update public.erp_source_files f set duplicate_of=d.id
            from public.erp_source_files d
            where f.metadata->>'duplicate_of_key'=d.file_key and f.duplicate_of is null;
            """,
        )

    for part in chunks(payload["raw_rows"], 350):
        rows = sql_json(part)
        emit(
            "source_rows",
            f"""
            insert into public.erp_source_rows(source_file_id,sheet_name,source_row,record_type,external_key,normalized_data,row_hash,validation_status)
            select f.id,x.sheet_name,x.source_row,x.record_type,x.external_key,x.normalized_data,x.row_hash,
              case when f.status='DUPLICATE' then 'DUPLICATE' else 'VALID' end
            from jsonb_to_recordset('{rows}'::jsonb)
              as x(file_key text,sheet_name text,source_row integer,record_type text,external_key text,normalized_data jsonb,row_hash text)
            join public.erp_source_files f on f.file_key=x.file_key
            on conflict(source_file_id,sheet_name,source_row,record_type,external_key)
            do update set normalized_data=excluded.normalized_data,row_hash=excluded.row_hash,validation_status=excluded.validation_status;
            """,
        )

    for part in chunks(payload["students"], 300):
        rows = sql_json(part)
        emit(
            "students",
            f"""
            insert into public.students(student_code,student_name,grade,status,national_id,joined_year,normalized_grade,grade_sort_order,
              grade_review_required,source_grade,program,program_review_required,updated_at)
            select x.student_code,x.student_name,x.grade,x.status,nullif(x.national_id,''),x.joined_year,x.grade,x.grade_sort_order,
              x.grade_sort_order=999,x.source_grade,null,true,now()
            from jsonb_to_recordset('{rows}'::jsonb)
              as x(student_code text,student_name text,grade text,status text,national_id text,joined_year integer,grade_sort_order integer,source_grade text,source_row integer)
            on conflict(student_code) do update set student_name=excluded.student_name,grade=excluded.grade,status=excluded.status,
              national_id=excluded.national_id,joined_year=excluded.joined_year,normalized_grade=excluded.normalized_grade,
              grade_sort_order=excluded.grade_sort_order,grade_review_required=excluded.grade_review_required,source_grade=excluded.source_grade,
              program=null,program_review_required=true,updated_at=now();
            """,
        )

    for part in chunks(payload["accounts"], 250):
        rows = sql_json(part)
        emit(
            "accounts",
            f"""
            insert into public.student_accounts(student_id,academic_year,tuition_piasters,discount_piasters,books_piasters,activity_piasters,
              transport_piasters,prior_year_balance_piasters,notes,original_tuition_piasters,net_tuition_piasters,other_piasters,
              total_due_piasters,legacy_paid_piasters,legacy_remaining_piasters,discount_percent,discount_type,source_external_id,
              source_meta,opening_paid_piasters,opening_remaining_piasters,opening_due_piasters,updated_at)
            select s.id,x.academic_year,x.net_tuition_piasters,x.discount_piasters,x.books_piasters,x.activity_piasters,
              x.transport_piasters,x.prior_year_balance_piasters,x.notes,x.original_tuition_piasters,x.net_tuition_piasters,
              x.other_piasters,x.total_due_piasters,x.legacy_paid_piasters,x.legacy_remaining_piasters,x.discount_percent,
              x.discount_type,'SRC2526-'||x.student_code,
              jsonb_build_object('source_file','طلبة عام 25-26 (1).xlsx','source_row',x.source_row),
              x.legacy_paid_piasters,x.legacy_remaining_piasters,x.total_due_piasters,now()
            from jsonb_to_recordset('{rows}'::jsonb) as x(
              student_code text,academic_year text,original_tuition_piasters bigint,discount_percent numeric,discount_type text,
              discount_piasters bigint,net_tuition_piasters bigint,activity_piasters bigint,books_piasters bigint,
              transport_piasters bigint,other_piasters bigint,prior_year_balance_piasters bigint,total_due_piasters bigint,
              legacy_paid_piasters bigint,legacy_remaining_piasters bigint,notes text,source_row integer)
            join public.students s on s.student_code=x.student_code
            on conflict(student_id,academic_year) do update set tuition_piasters=excluded.tuition_piasters,
              discount_piasters=excluded.discount_piasters,books_piasters=excluded.books_piasters,activity_piasters=excluded.activity_piasters,
              transport_piasters=excluded.transport_piasters,prior_year_balance_piasters=excluded.prior_year_balance_piasters,
              notes=excluded.notes,original_tuition_piasters=excluded.original_tuition_piasters,net_tuition_piasters=excluded.net_tuition_piasters,
              other_piasters=excluded.other_piasters,total_due_piasters=excluded.total_due_piasters,
              legacy_paid_piasters=excluded.legacy_paid_piasters,legacy_remaining_piasters=excluded.legacy_remaining_piasters,
              discount_percent=excluded.discount_percent,discount_type=excluded.discount_type,source_external_id=excluded.source_external_id,
              source_meta=excluded.source_meta,opening_paid_piasters=excluded.opening_paid_piasters,
              opening_remaining_piasters=excluded.opening_remaining_piasters,opening_due_piasters=excluded.opening_due_piasters,updated_at=now();
            """,
        )

    for part in chunks(payload["payments"], 250):
        rows = sql_json(part)
        emit(
            "payments",
            f"""
            insert into public.student_payments(account_id,transaction_date,amount_piasters,payment_method,receipt_number,bank_reference,
              notes,status,payment_category,category_label,effect_sign)
            select a.id,x.transaction_date::date,x.amount_piasters,
              case when x.payment_method='CASH' then 'CASH'::public.payment_method else 'OTHER'::public.payment_method end,
              'SRC2526-'||x.student_code||'-'||x.source_row||'-'||x.source_col,nullif(x.bank_reference,''),
              concat_ws(' — ','مصدر: طلبة عام 25-26 (1).xlsx صف '||x.source_row||' عمود '||x.source_col,
                case when nullif(x.receipt_number,'') is not null then 'مرجع المصدر: '||x.receipt_number end),
              'POSTED'::public.record_status,'TUITION','مصروفات دراسية',1
            from jsonb_to_recordset('{rows}'::jsonb) as x(
              student_code text,transaction_date text,amount_piasters bigint,receipt_number text,bank_reference text,
              payment_method text,payment_category text,source_row integer,source_col integer)
            join public.students s on s.student_code=x.student_code
            join public.student_accounts a on a.student_id=s.id and a.academic_year='2025-2026';
            """,
        )

    for part in chunks(payload["applications"], 300):
        rows = sql_json(part)
        emit(
            "applications",
            f"""
            insert into public.legacy_applications(source_external_id,status,student_code,student_name,grade,file_due_piasters,
              file_paid_piasters,total_paid_piasters,collector,source_meta)
            select x.source_external_id,x.status,nullif(x.student_code,''),x.student_name,x.grade,x.file_due_piasters,
              x.file_paid_piasters,x.total_paid_piasters,x.collector,
              jsonb_build_object('source_file','طلبة عام 25-26 (1).xlsx','source_row',x.source_row,'phone',x.phone)
            from jsonb_to_recordset('{rows}'::jsonb) as x(
              source_external_id text,status text,student_code text,student_name text,grade text,file_due_piasters bigint,
              file_paid_piasters bigint,total_paid_piasters bigint,collector text,phone text,source_row integer);
            """,
        )

    for part in chunks(payload["treasury"], 300):
        rows = sql_json(part)
        emit(
            "treasury",
            f"""
            with x as (
              select * from jsonb_to_recordset('{rows}'::jsonb) as d(
                source_row integer,transaction_date text,source_balance_piasters bigint,inflow_piasters bigint,outflow_piasters bigint,
                bank_piasters bigint,description text,document_text text,source_code text,payment_method_text text,expense_type text,
                company text,invoice_number text,withholding_piasters bigint,reported_amount_piasters bigint)
            )
            insert into public.legacy_treasury_rows(source_row,transaction_date,source_balance_piasters,inflow_piasters,outflow_piasters,
              bank_piasters,description,document_text,source_code,payment_method_text,expense_type,company,invoice_number,
              withholding_piasters,reported_amount_piasters,source_meta)
            select source_row,nullif(transaction_date,'')::date,source_balance_piasters,inflow_piasters,outflow_piasters,bank_piasters,
              description,document_text,source_code,payment_method_text,expense_type,company,invoice_number,withholding_piasters,
              reported_amount_piasters,jsonb_build_object('source_file','الخزينه (1).xlsx') from x;

            with x as (
              select * from jsonb_to_recordset('{rows}'::jsonb) as d(
                source_row integer,transaction_date text,source_balance_piasters bigint,inflow_piasters bigint,outflow_piasters bigint,
                bank_piasters bigint,description text,document_text text,source_code text,payment_method_text text,expense_type text,
                company text,invoice_number text,withholding_piasters bigint,reported_amount_piasters bigint)
            )
            insert into public.treasury_transactions(voucher_number,transaction_date,direction,amount_piasters,payment_method,
              counterparty,category,description,status,review_note)
            select 'SRC-T-'||source_row,transaction_date::date,
              case when inflow_piasters>0 then 'RECEIPT' else 'PAYMENT' end,
              case when inflow_piasters>0 then inflow_piasters else outflow_piasters end,
              case when lower(coalesce(payment_method_text,'')) like '%كاش%' then 'CASH'::public.payment_method else 'OTHER'::public.payment_method end,
              company,expense_type,description,'POSTED'::public.record_status,
              'مصدر تاريخي: الخزينه (1).xlsx'
            from x where transaction_date is not null and (inflow_piasters>0 or outflow_piasters>0);
            """,
        )

    # Bank accounts are source sheets shared across academic-year workbooks.
    labels = sorted({row["sheet_name"] for row in payload["bank_transactions"]})
    for index, label in enumerate(labels, 1):
        safe = sql_text(label)
        emit(
            "bank_account",
            f"""
            insert into public.bank_accounts(bank_name,account_label,currency,active)
            select case when '{safe}' like '%الاسكندرية%' then 'بنك الإسكندرية' else 'QNB الأهلي' end,
              '{safe}','EGP',true
            where not exists(select 1 from public.bank_accounts where account_label='{safe}');
            """,
        )
    for part in chunks(payload["bank_transactions"], 300):
        rows = sql_json(part)
        emit(
            "bank_transactions",
            f"""
            insert into public.bank_transactions(bank_account_id,transaction_date,debit_piasters,credit_piasters,description,
              bank_reference,scope,reconciliation_status)
            select a.id,x.transaction_date::date,x.debit_piasters,x.credit_piasters,
              concat_ws(' — ',x.description,x.notes,'المصدر '||x.academic_year||' صف '||x.source_row),
              nullif(x.bank_reference,''),'SCHOOL'::public.bank_scope,'NEEDS_REVIEW'::public.reconciliation_status
            from jsonb_to_recordset('{rows}'::jsonb) as x(
              file_key text,academic_year text,sheet_name text,source_row integer,transaction_date text,credit_piasters bigint,
              debit_piasters bigint,description text,bank_reference text,student_code text,notes text)
            join public.bank_accounts a on a.account_label=x.sheet_name
            where x.transaction_date is not null
              and not exists(
                select 1 from public.bank_transactions b
                where b.bank_account_id=a.id and b.transaction_date=x.transaction_date::date
                  and b.debit_piasters=x.debit_piasters and b.credit_piasters=x.credit_piasters
                  and b.description=concat_ws(' — ',x.description,x.notes,'المصدر '||x.academic_year||' صف '||x.source_row)
              );
            """,
        )

    bus = payload["bus"]
    for part in chunks(bus, 250):
        rows = sql_json(part)
        emit(
            "bus_students",
            f"""
            insert into public.students(student_code,student_name,grade,status,normalized_grade,grade_sort_order,grade_review_required,
              source_grade,program,program_review_required,updated_at)
            select 'BUS26-'||lpad(x.source_row::text,4,'0'),x.student_name,x.grade,'ACTIVE',x.grade,x.grade_sort_order,
              x.grade_sort_order=999,x.grade,null,true,now()
            from jsonb_to_recordset('{rows}'::jsonb) as x(
              source_row integer,student_name text,grade text,grade_sort_order integer,route_name text,fee_piasters bigint,academic_year text)
            where not exists(
              select 1 from public.students s
              where regexp_replace(lower(s.student_name),'[^[:alnum:]]','','g')=regexp_replace(lower(x.student_name),'[^[:alnum:]]','','g')
            )
            on conflict(student_code) do update set student_name=excluded.student_name,grade=excluded.grade,status='ACTIVE',
              normalized_grade=excluded.normalized_grade,grade_sort_order=excluded.grade_sort_order,updated_at=now();
            """,
        )

    routes = sorted({row["route_name"] for row in bus})
    for index, route in enumerate(routes, 1):
        route_json = sql_json(route)
        fee = max(row["fee_piasters"] for row in bus if row["route_name"] == route)
        emit(
            "bus_route",
            f"""
            insert into public.transport_routes(route_code,route_name,areas,academic_year,annual_fee_piasters,status,notes)
            values('SRC-BUS-{index:02d}','{route_json}',array['{route_json}'],'2026-2027',{fee},'ACTIVE','مصدر: باص عام 2026-2027.xlsx')
            on conflict(route_code) do update set route_name=excluded.route_name,areas=excluded.areas,
              academic_year=excluded.academic_year,annual_fee_piasters=excluded.annual_fee_piasters,status='ACTIVE',notes=excluded.notes,updated_at=now();
            """,
        )

    route_codes = {route: f"SRC-BUS-{index:02d}" for index, route in enumerate(routes, 1)}
    for part in chunks(bus, 250):
        enriched = [{**row, "route_code": route_codes[row["route_name"]]} for row in part]
        rows = sql_json(enriched)
        emit(
            "bus_enrollments",
            f"""
            insert into public.transport_enrollments(student_id,academic_year,route_id,fee_piasters,status,notes)
            select s.id,x.academic_year,r.id,x.fee_piasters,'ACTIVE','مصدر: باص عام 2026-2027.xlsx صف '||x.source_row
            from jsonb_to_recordset('{rows}'::jsonb) as x(
              source_row integer,student_name text,grade text,grade_sort_order integer,route_name text,route_code text,
              fee_piasters bigint,academic_year text)
            join lateral (
              select candidate.id
              from public.students candidate
              where candidate.student_code='BUS26-'||lpad(x.source_row::text,4,'0')
                 or regexp_replace(lower(candidate.student_name),'[^[:alnum:]]','','g')=regexp_replace(lower(x.student_name),'[^[:alnum:]]','','g')
              order by (candidate.student_code='BUS26-'||lpad(x.source_row::text,4,'0')) desc,
                (candidate.status='ACTIVE') desc,candidate.student_code
              limit 1
            ) s on true
            join public.transport_routes r on r.route_code=x.route_code
            on conflict(student_id,academic_year) do update set route_id=excluded.route_id,fee_piasters=excluded.fee_piasters,
              status='ACTIVE',notes=excluded.notes,updated_at=now();
            """,
        )

    totals = {
        "students": len(payload["students"]),
        "accounts": len(payload["accounts"]),
        "payments": len(payload["payments"]),
        "applications": len(payload["applications"]),
        "treasury": len(payload["treasury"]),
        "amany_treasury": len(payload["amany_treasury"]),
        "bank_transactions": len(payload["bank_transactions"]),
        "bus": len(payload["bus"]),
        "source_rows": len(payload["raw_rows"]),
    }
    totals_json = sql_json(totals)
    emit(
        "finalize",
        f"""
        update public.erp_source_files f set
          imported_count=(select count(*) from public.erp_source_rows r where r.source_file_id=f.id and r.validation_status='VALID'),
          status=case when f.status='DUPLICATE' then 'DUPLICATE' else 'IMPORTED' end,
          imported_at=now();
        insert into public.import_batches(batch_key,source_name,status,row_count,imported_count,duplicate_count,totals,notes,completed_at)
        values('SOURCE-20261022','14 finance workbooks','IMPORTED',
          {len(payload["raw_rows"])},{len(payload["raw_rows"]) - 29},29,'{totals_json}'::jsonb,
          'استبدال المصادر السابقة بعد أرشفتها في schema archive. نسخة تحليل السداد المكررة لم تضاعف الأرقام.',now())
        on conflict(batch_key) do update set status='IMPORTED',row_count=excluded.row_count,imported_count=excluded.imported_count,
          duplicate_count=excluded.duplicate_count,totals=excluded.totals,notes=excluded.notes,completed_at=now();
        """,
    )
    print(json.dumps({"sql_files": sequence, "output": str(output), "totals": totals}, ensure_ascii=False))


if __name__ == "__main__":
    main()
