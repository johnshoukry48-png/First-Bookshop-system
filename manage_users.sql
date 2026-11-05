-- =====================================================================
--  إدارة المستخدمين والأدوار — شغّله في Supabase ▸ SQL Editor
--  الأدوار: admin = مدير/مالك | staff = موظف إدخال | viewer = قراءة فقط
-- =====================================================================

-- (1) إنشاء المستخدم: من Supabase ▸ Authentication ▸ Users ▸ Add user (بريد + كلمة مرور)
--     ثم فعّل "Auto Confirm User" ليدخل مباشرة. يظهر تلقائياً بدور staff.

-- (2) تحديد الدور وتفعيل الحساب (غيّر البريد والدور):
update public.profiles
   set role = 'viewer',            -- admin | staff | viewer
       active = true,
       full_name = 'اسم الشخص'
 where email = 'someone@example.com';

-- (3) إيقاف حساب دون حذفه (يُمنع من الدخول فوراً):
-- update public.profiles set active = false where email = 'someone@example.com';

-- (4) إعادة تفعيله:
-- update public.profiles set active = true where email = 'someone@example.com';

-- (5) تعيين أكثر من شخص دفعة واحدة:
-- update public.profiles set role = 'staff',  active = true where email in ('a@x.com','b@x.com');
-- update public.profiles set role = 'viewer', active = true where email in ('c@x.com');

-- (6) عرض كل المستخدمين وأدوارهم:
select email, full_name, role, active, created_at from public.profiles order by created_at;

-- (7) حذف مستخدم نهائياً (لا تحذف من له حركات؛ الأفضل إيقافه): من Authentication ▸ Users ▸ Delete.

-- (8) إنشاء مستخدم بالكامل من SQL دون لوحة Supabase (اختياري):
-- insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change, email_change_token_new)
-- values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated', 'new@example.com', crypt('كلمة_مرور_قوية', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');
-- ثم شغّل (2) لتحديد دوره.
