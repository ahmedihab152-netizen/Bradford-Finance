-- Missing document-number defaults prevented otherwise valid UI drafts.
-- Sequences are additive and the defaults do not rewrite existing rows.
create sequence if not exists public.procurement_rfq_number_seq;
create sequence if not exists public.inventory_count_number_seq;
create sequence if not exists public.purchase_return_number_seq;

alter table public.procurement_rfqs alter column rfq_number set default
 ('RFQ-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.procurement_rfq_number_seq')::text,6,'0'));
alter table public.inventory_counts alter column count_number set default
 ('CNT-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.inventory_count_number_seq')::text,6,'0'));
alter table public.purchase_returns alter column return_number set default
 ('RET-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.purchase_return_number_seq')::text,6,'0'));

