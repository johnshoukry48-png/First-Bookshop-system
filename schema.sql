-- =====================================================================
--  نظام محاسبة المكتبة (First - Bookshop) — مخطط قاعدة بيانات Supabase
--  شغّل هذا الملف كاملاً مرة واحدة من: Supabase ▸ SQL Editor ▸ New query
-- =====================================================================

-- ---------- 1) المستخدمون والأدوار ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  full_name   text default '',
  role        text not null default 'staff' check (role in ('admin','staff','viewer')),
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'admin' and active from public.profiles where id = auth.uid()), false);
$$;

-- حساب القراءة فقط (viewer): يقرأ كل شيء ولا يكتب أي شيء
create or replace function public.can_read_all() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role in ('admin','viewer') and active from public.profiles where id = auth.uid()), false);
$$;
create or replace function public.is_writer() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role in ('admin','staff') and active from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.is_active_user() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select active from public.profiles where id = auth.uid()), false);
$$;

-- إنشاء ملف تعريف تلقائياً لكل مستخدم جديد (الدور الافتراضي: موظف)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', ''))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ترقية للنسخ القديمة: السماح بدور viewer
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('admin','staff','viewer'));

-- ---------- 2) القوائم الأساسية ----------
create table if not exists public.customers (
  id           bigint generated always as identity primary key,
  name         text not null unique,
  type         text not null default 'اجل' check (type in ('اجل','نقدى')),
  credit_limit numeric(14,2),                       -- الحد الائتماني (ورقة ارصدة العملاء ▸ Credit)
  show_in_balances boolean not null default true,   -- false = مخفي في الجدول المحوري بملف Excel
  created_at   timestamptz not null default now()
);
create table if not exists public.publishers (
  id         bigint generated always as identity primary key,
  name       text not null unique,
  show_in_balances boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------- 3) الحركات ----------
-- المبيعات  (جداول July / Aug / ... في ورقتي مبيعات_1 و مبيعات_2 + جدول DS للأرصدة الافتتاحية)
create table if not exists public.sales (
  id            bigint generated always as identity primary key,
  invoice_no    text not null default '',
  customer_id   bigint not null references public.customers(id),
  invoice_value numeric(14,2) not null default 0,   -- قيمة الفاتورة
  commission    numeric(14,2) not null default 0,   -- العمولة
  credit        numeric(14,2) not null default 0,   -- الاجل  (= قيمة الفاتورة − العمولة للعميل الآجل)
  payments      numeric(14,2) not null default 0,   -- الدفعات
  sale_date     date not null default current_date,
  term          text not null default 'الاول' check (term in ('الاول','الثانى')),
  period        text,                               -- الشهر المحاسبي YYYY-MM
  source        text default 'app',
  created_by    uuid default auth.uid() references auth.users(id),
  created_at    timestamptz not null default now()
);
-- المشتريات (جداول JulP / AugP / ... + جدول DP)
create table if not exists public.purchases (
  id               bigint generated always as identity primary key,
  publisher_id     bigint not null references public.publishers(id),
  cash_purchases   numeric(14,2) not null default 0, -- مشتريات نقدى
  credit_purchases numeric(14,2) not null default 0, -- مشتريات اجل (= المسحوبات)
  payments         numeric(14,2) not null default 0, -- دفعات ناشرين
  purchase_date    date not null default current_date,
  term             text not null default 'الاول' check (term in ('الاول','الثانى')),
  period           text,
  source           text default 'app',
  created_by       uuid default auth.uid() references auth.users(id),
  created_at       timestamptz not null default now()
);
-- المصروفات (جداول الخزنة: البند / المبلغ / بيان / التاريخ)
create table if not exists public.expenses (
  id           bigint generated always as identity primary key,
  category     text not null default 'أخرى',
  amount       numeric(14,2) not null default 0,
  description  text default '',
  expense_date date not null default current_date,
  period       text,
  created_by   uuid default auth.uid() references auth.users(id),
  created_at   timestamptz not null default now()
);
-- مرتجعات العملاء / الناشرين
create table if not exists public.customer_returns (
  id          bigint generated always as identity primary key,
  customer_id bigint not null references public.customers(id),
  term        text not null default 'الاول' check (term in ('الاول','الثانى')),
  amount      numeric(14,2) not null default 0,
  return_date date not null default current_date,
  note        text default '',
  created_by  uuid default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now()
);
create table if not exists public.publisher_returns (
  id           bigint generated always as identity primary key,
  publisher_id bigint not null references public.publishers(id),
  term         text not null default 'الاول' check (term in ('الاول','الثانى')),
  amount       numeric(14,2) not null default 0,
  return_date  date not null default current_date,
  note         text default '',
  created_by   uuid default auth.uid() references auth.users(id),
  created_at   timestamptz not null default now()
);

-- ---------- 4) الخزنة الشهرية ----------
create table if not exists public.treasury_months (
  month            text primary key check (month ~ '^\d{4}-\d{2}$'),
  opening_override numeric(14,2),     -- "خزينة قديمة" لأول شهر فقط؛ بقية الأشهر تُرحَّل تلقائياً من إغلاق الشهر السابق
  cash_box         numeric(14,2) not null default 0,  -- خزنة نقدى
  drawer           numeric(14,2) not null default 0,  -- الدرج
  post             numeric(14,2) not null default 0,  -- البريد
  bank             numeric(14,2) not null default 0   -- البنك
);
create table if not exists public.pending_items (       -- المعلق: فواتير نقدى لم تسدد / سلف (تُحتسب كمبلغ موجود)
  id            bigint generated always as identity primary key,
  month         text not null references public.treasury_months(month) on delete cascade,
  label         text not null,
  kind          text not null default 'أخرى',   -- فاتورة نقدى لم تسدد | سلفة | أخرى
  amount        numeric(14,2) not null default 0,   -- يُدخل موجباً: يقلّل العجز / يزيد الجرد
  carry         boolean not null default true,      -- يُرحَّل للأشهر التالية حتى السداد
  settled       boolean not null default false,
  settled_month text                                -- شهر السداد (لا يُحتسب فيه ولا بعده)
);

-- ---------- 4.5) طريقة الدفع + تسويات الحساب (v4) ----------
alter table public.sales     add column if not exists pay_method text default '';
alter table public.purchases add column if not exists pay_method text default '';
alter table public.expenses  add column if not exists pay_method text not null default 'نقدى';
-- طريقة الدفع تبقى فارغة للفاتورة الآجلة التي لا دفعة فيها
alter table public.sales     alter column pay_method drop not null; alter table public.sales     alter column pay_method set default '';
alter table public.purchases alter column pay_method drop not null; alter table public.purchases alter column pay_method set default '';
alter table public.sales     drop constraint if exists sales_pay_method_check;
alter table public.sales     add constraint sales_pay_method_check check (pay_method in ('','نقدى','بنك','بريد'));
alter table public.purchases drop constraint if exists purchases_pay_method_check;
alter table public.purchases add constraint purchases_pay_method_check check (pay_method in ('','نقدى','بنك','بريد'));
alter table public.expenses  drop constraint if exists expenses_pay_method_check;
alter table public.expenses  add constraint expenses_pay_method_check check (pay_method in ('نقدى','بنك','بريد'));
-- نوع الفاتورة (اجل / نقدى) + فاتورة معلقة
do $$ begin
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='sales' and column_name='inv_type') then
    alter table public.sales add column inv_type text not null default 'اجل' check (inv_type in ('اجل','نقدى'));
    update public.sales set inv_type = 'نقدى' where credit = 0 and invoice_value <> 0;   -- ترقية البيانات القديمة
    update public.sales set pay_method = '' where payments = 0 and inv_type = 'اجل';
  end if;
end $$;
alter table public.sales add column if not exists is_pending boolean not null default false;
alter table public.pending_items add column if not exists sale_id bigint references public.sales(id) on delete cascade;
-- تسويات الحساب: عمولة/مبلغ يُضاف على المدفوع أو المسحوب لعميل/ناشر — تؤثر على الأرصدة فقط ولا تدخل الخزنة
create table if not exists public.adjustments (
  id           bigint generated always as identity primary key,
  kind         text not null check (kind in ('c','p')),
  customer_id  bigint references public.customers(id),
  publisher_id bigint references public.publishers(id),
  direction    text not null check (direction in ('paid','drawn')),   -- paid = تضاف على المدفوع | drawn = تضاف على المسحوب
  amount       numeric(14,2) not null default 0,
  adj_date     date not null default current_date,
  term         text not null default 'الاول' check (term in ('الاول','الثانى')),
  note         text default '',
  created_by   uuid default auth.uid() references auth.users(id),
  created_at   timestamptz not null default now(),
  check ((kind = 'c' and customer_id is not null and publisher_id is null) or (kind = 'p' and publisher_id is not null and customer_id is null))
);
create index if not exists idx_adj_cust on public.adjustments(customer_id);
create index if not exists idx_adj_pub  on public.adjustments(publisher_id);

-- ---------- 5) الإعدادات وسجل التدقيق ----------
create table if not exists public.app_settings (
  key text primary key, value text not null
);
insert into public.app_settings(key, value) values
  ('current_term','الاول'),
  ('credit_alert_ratio','0.9'),
  ('credit_alert_basis','payments')   -- payments = كما في Excel (المدفوعات ≥ 90% من الحد) | balance = الصافي ≥ 90% من الحد
on conflict (key) do nothing;

create table if not exists public.audit_log (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default now(),
  user_id    uuid default auth.uid(),
  table_name text, action text, row_id text, old_data jsonb, new_data jsonb
);
create or replace function public.log_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log(table_name, action, row_id, old_data, new_data)
  values (tg_table_name, tg_op,
          coalesce((case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end)->>'id',''),
          case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

-- الرقم التلقائي للفاتورة: أكبر رقم عددي موجود + 1 (يعمل لكل المستخدمين حتى لو لا يرون فواتير غيرهم)
create or replace function public.next_invoice_no() returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(max(invoice_no::bigint), 0) + 1 from public.sales where invoice_no ~ '^\d{1,9}$';
$$;
create or replace function public.fill_invoice_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.invoice_no, '') = '' and coalesce(new.invoice_value, 0) <> 0 then
    perform pg_advisory_xact_lock(7301);
    new.invoice_no := public.next_invoice_no()::text;
  end if;
  return new;
end $$;
drop trigger if exists trg_invoice_no on public.sales;
create trigger trg_invoice_no before insert on public.sales for each row execute function public.fill_invoice_no();

-- الشهر المحاسبي تلقائياً من التاريخ عند الإدخال إن لم يُحدَّد
create or replace function public.fill_period() returns trigger
language plpgsql as $$
begin
  if tg_table_name = 'sales' and new.period is null then new.period := to_char(new.sale_date,'YYYY-MM'); end if;
  if tg_table_name = 'purchases' and new.period is null then new.period := to_char(new.purchase_date,'YYYY-MM'); end if;
  if tg_table_name = 'expenses' and new.period is null then new.period := to_char(new.expense_date,'YYYY-MM'); end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['sales','purchases','expenses'] loop
    execute format('drop trigger if exists trg_period on public.%I', t);
    execute format('create trigger trg_period before insert or update on public.%I for each row execute function public.fill_period()', t);
  end loop;
  foreach t in array array['sales','purchases','expenses','customer_returns','publisher_returns','customers','publishers','treasury_months','pending_items','adjustments','app_settings'] loop
    execute format('drop trigger if exists trg_audit on public.%I', t);
    execute format('create trigger trg_audit after insert or update or delete on public.%I for each row execute function public.log_change()', t);
  end loop;
end $$;

create index if not exists idx_sales_cust   on public.sales(customer_id);
create index if not exists idx_sales_period on public.sales(period);
create index if not exists idx_purch_pub    on public.purchases(publisher_id);
create index if not exists idx_purch_period on public.purchases(period);
create index if not exists idx_exp_period   on public.expenses(period);

-- ---------- 6) صلاحيات الصفوف (RLS) ----------
alter table public.profiles          enable row level security;
alter table public.customers         enable row level security;
alter table public.publishers        enable row level security;
alter table public.sales             enable row level security;
alter table public.purchases         enable row level security;
alter table public.expenses          enable row level security;
alter table public.customer_returns  enable row level security;
alter table public.publisher_returns enable row level security;
alter table public.treasury_months   enable row level security;
alter table public.pending_items     enable row level security;
alter table public.adjustments       enable row level security;
alter table public.app_settings      enable row level security;
alter table public.audit_log         enable row level security;

-- الملفات الشخصية: كل مستخدم يرى ملفه، والمدير يرى ويعدّل الجميع
drop policy if exists p_prof_sel on public.profiles;
create policy p_prof_sel on public.profiles for select using (id = auth.uid() or public.is_admin());
drop policy if exists p_prof_upd on public.profiles;
create policy p_prof_upd on public.profiles for update using (public.is_admin()) with check (public.is_admin());

-- العملاء والناشرون: الجميع (النشطون) يقرأ ويضيف، والمدير فقط يعدّل ويحذف
do $$
declare t text;
begin
  foreach t in array array['customers','publishers'] loop
    execute format('drop policy if exists p_%1$s_sel on public.%1$s', t);
    execute format('create policy p_%1$s_sel on public.%1$s for select using (public.is_active_user())', t);
    execute format('drop policy if exists p_%1$s_ins on public.%1$s', t);
    execute format('create policy p_%1$s_ins on public.%1$s for insert with check (public.is_writer())', t);
    execute format('drop policy if exists p_%1$s_upd on public.%1$s', t);
    execute format('create policy p_%1$s_upd on public.%1$s for update using (public.is_admin()) with check (public.is_admin())', t);
    execute format('drop policy if exists p_%1$s_del on public.%1$s', t);
    execute format('create policy p_%1$s_del on public.%1$s for delete using (public.is_admin())', t);
  end loop;
  -- الحركات: الموظف يُدخل ويرى حركاته فقط ويعدّل/يحذف حركاته خلال 24 ساعة، والمدير كل شيء
  foreach t in array array['sales','purchases','expenses','customer_returns','publisher_returns'] loop
    execute format('drop policy if exists p_%1$s_sel on public.%1$s', t);
    execute format('create policy p_%1$s_sel on public.%1$s for select using (public.can_read_all() or (public.is_writer() and created_by = auth.uid()))', t);
    execute format('drop policy if exists p_%1$s_ins on public.%1$s', t);
    execute format('create policy p_%1$s_ins on public.%1$s for insert with check (public.is_admin() or (public.is_writer() and created_by = auth.uid()))', t);
    execute format('drop policy if exists p_%1$s_upd on public.%1$s', t);
    execute format('create policy p_%1$s_upd on public.%1$s for update using (public.is_admin() or (public.is_writer() and created_by = auth.uid() and created_at > now() - interval ''24 hours'')) with check (public.is_admin() or created_by = auth.uid())', t);
    execute format('drop policy if exists p_%1$s_del on public.%1$s', t);
    execute format('create policy p_%1$s_del on public.%1$s for delete using (public.is_admin() or (public.is_writer() and created_by = auth.uid() and created_at > now() - interval ''24 hours''))', t);
  end loop;
  -- الخزنة والفواتير المعلقة والإعدادات وسجل التدقيق: للمدير فقط
  foreach t in array array['treasury_months','pending_items'] loop
    execute format('drop policy if exists p_%1$s_all on public.%1$s', t);
    execute format('create policy p_%1$s_all on public.%1$s for all using (public.is_admin()) with check (public.is_admin())', t);
    execute format('drop policy if exists p_%1$s_view on public.%1$s', t);
    execute format('create policy p_%1$s_view on public.%1$s for select using (public.can_read_all())', t);
  end loop;
  -- الموظف يستطيع تسجيل فاتورة نقدى معلقة (إدراج فقط)؛ التعديل والحذف للمدير
  execute 'drop policy if exists p_pending_items_ins on public.pending_items';
  execute 'create policy p_pending_items_ins on public.pending_items for insert with check (public.is_writer())';
  -- تسويات الحساب: المدير يكتب، والمدير وحساب القراءة يقرآن
  execute 'drop policy if exists p_adjustments_all on public.adjustments';
  execute 'create policy p_adjustments_all on public.adjustments for all using (public.is_admin()) with check (public.is_admin())';
  execute 'drop policy if exists p_adjustments_view on public.adjustments';
  execute 'create policy p_adjustments_view on public.adjustments for select using (public.can_read_all())';
end $$;
drop policy if exists p_set_sel on public.app_settings;
create policy p_set_sel on public.app_settings for select using (public.is_active_user());
drop policy if exists p_set_mod on public.app_settings;
create policy p_set_mod on public.app_settings for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists p_audit_sel on public.audit_log;
create policy p_audit_sel on public.audit_log for select using (public.can_read_all());

-- ---------- 7) التحديث اللحظي (Realtime) ----------
do $$
declare t text;
begin
  foreach t in array array['sales','purchases','expenses','customer_returns','publisher_returns','treasury_months','pending_items','adjustments'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ---------- 7.5) أشهر الخزنة الاثنا عشر (يوليو 2026 ← يونيو 2027) فارغة كما في ملف Excel ----------
insert into public.treasury_months(month)
select to_char(d, 'YYYY-MM') from generate_series('2026-07-01'::date, '2027-06-01'::date, interval '1 month') d
on conflict do nothing;

-- ---------- 8) تعيين أول مدير ----------
-- 1) أنشئ حسابك من Authentication ▸ Users ▸ Add user  (بريد + كلمة مرور)
-- 2) ثم شغّل السطر التالي بعد وضع بريدك:
--    update public.profiles set role = 'admin', full_name = 'المالك' where email = 'your@email.com';
