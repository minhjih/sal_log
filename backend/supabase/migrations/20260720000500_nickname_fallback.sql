-- ═══════════════════════════════════════════════════════════
-- 닉네임 폴백 개선
--
-- 소셜(Google/Apple/Kakao) 가입은 raw_user_meta_data에 'nickname'이
-- 없어 빈 닉네임으로 생성되던 문제 수정:
--   nickname → full_name → name → 이메일 로컬파트 순으로 폴백.
-- 기존에 빈 닉네임으로 만들어진 계정도 백필한다.
-- ═══════════════════════════════════════════════════════════

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_nickname text;
begin
  v_nickname := coalesce(
    nullif(left(new.raw_user_meta_data ->> 'nickname', 12), ''),
    nullif(left(new.raw_user_meta_data ->> 'full_name', 12), ''),
    nullif(left(new.raw_user_meta_data ->> 'name', 12), ''),
    nullif(left(split_part(coalesce(new.email, ''), '@', 1), 12), ''),
    ''
  );

  insert into public.users (id, nickname, avatar_url)
  values (new.id, v_nickname, new.raw_user_meta_data ->> 'avatar_url')
  on conflict (id) do nothing;

  insert into public.profiles (user_id) values (new.id)
  on conflict (user_id) do nothing;

  return new;
end $$;

-- 이미 빈 닉네임으로 생성된 계정 백필
update public.users u
   set nickname = coalesce(
     nullif(left(au.raw_user_meta_data ->> 'full_name', 12), ''),
     nullif(left(au.raw_user_meta_data ->> 'name', 12), ''),
     nullif(left(split_part(coalesce(au.email, ''), '@', 1), 12), ''),
     u.nickname
   )
  from auth.users au
 where au.id = u.id
   and u.nickname = '';
