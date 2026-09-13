# Transport backend

The four production tables are `transport_routes`, `transport_vehicles`, `transport_staff`, and `transport_enrollments`. The migration enables RLS, removes every browser DELETE/TRUNCATE privilege, and retains only authenticated SELECT plus policy-controlled INSERT/UPDATE. No seed data is included.

Operational finance remains in `student_payments` with `payment_category = TRANSPORT`; only POSTED payments affect official totals. Transport enrollment status does not post money by itself.

Run migrations through the Supabase migration history (`supabase db push`) or the managed migration API. Never paste an untracked schema change into Production.
