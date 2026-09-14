-- Resolve a PL/pgSQL variable/SQL alias ambiguity in multi-line IG receipts.

create or replace function public.create_ig_exam_payment_batch(
  p_account_id uuid,
  p_transaction_date date,
  p_idempotency_key text,
  p_lines jsonb,
  p_tenders jsonb,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = 'public', 'private', 'pg_temp'
as $function$
declare
  b uuid;
  x jsonb;
  clean jsonb := '[]'::jsonb;
  entry public.ig_exam_entries%rowtype;
  paid bigint;
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'At least one IG subject is required';
  end if;
  if jsonb_array_length(p_lines) <> (
    select count(distinct line_item.value ->> 'ig_exam_entry_id')
    from jsonb_array_elements(p_lines) as line_item(value)
  ) then
    raise exception 'Duplicate IG subject line';
  end if;
  for x in select value from jsonb_array_elements(p_lines) as line_item(value) loop
    select * into entry
    from public.ig_exam_entries
    where id = (x ->> 'ig_exam_entry_id')::uuid
      and account_id = p_account_id
      and status = 'POSTED';
    if not found then raise exception 'Approved IG entry not found'; end if;
    paid := (x ->> 'paid_now_piasters')::bigint;
    if paid <= 0 or paid > entry.fee_piasters - coalesce((
      select sum(l.paid_now_piasters)
      from public.student_payment_lines l
      where l.ig_exam_entry_id = entry.id and l.status = 'POSTED'
    ), 0) then
      raise exception 'IG payment exceeds outstanding fee';
    end if;
    clean := clean || jsonb_build_array(jsonb_build_object(
      'category', 'EXAMS',
      'description', x ->> 'description',
      'due_piasters', entry.fee_piasters,
      'paid_now_piasters', paid,
      'cost_center_id', public.ig_cost_center_id()
    ));
  end loop;
  b := public.create_student_payment_batch(
    p_account_id, p_transaction_date, p_idempotency_key, clean, p_tenders, p_notes
  );
  for x in select value from jsonb_array_elements(p_lines) as line_item(value) loop
    update public.student_payment_lines
    set ig_exam_entry_id = (x ->> 'ig_exam_entry_id')::uuid
    where id = (
      select l.id
      from public.student_payment_lines l
      where l.batch_id = b
        and l.ig_exam_entry_id is null
        and l.description = x ->> 'description'
        and l.paid_now_piasters = (x ->> 'paid_now_piasters')::bigint
      limit 1
    );
    if not found then raise exception 'Unable to link IG subject line'; end if;
  end loop;
  return b;
end
$function$;

revoke all on function public.create_ig_exam_payment_batch(uuid,date,text,jsonb,jsonb,text)
  from public, anon;
grant execute on function public.create_ig_exam_payment_batch(uuid,date,text,jsonb,jsonb,text)
  to authenticated;
