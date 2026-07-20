-- ═══════════════════════════════════════════════════════════
-- sal-log · RPC (security definer)
--
--  · create_group        그룹 생성 + 오너 등록 + 초대 토큰 발급(원문 1회 반환)
--  · create_invite       초대 토큰 재발급 (기존 토큰 폐기 옵션)
--  · preview_invite      토큰으로 그룹 미리보기 (수락 전 확인 화면)
--  · accept_invite       토큰 검증 후 그룹 참여
--  · expand_group        커플 → 친구 그룹 확장 (오너)
--  · leave_group         그룹 탈퇴
--  · get_bootstrap       내 계정/그룹/멤버(공유 동의 반영) 한 번에 로드
-- ═══════════════════════════════════════════════════════════

-- ── 토큰 유틸 ─────────────────────────────────────────────
-- I/L/O/0/1 제외 알파벳+숫자 31자로 'KL-XXXXXX' 생성
create or replace function public.gen_invite_token()
returns text language sql volatile as $$
  select 'KL-' || string_agg(
    substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), ''
  )
  from generate_series(1, 6);
$$;

-- Supabase는 pgcrypto를 extensions 스키마에 설치하므로 digest를 정규화해서 호출
create or replace function public.hash_invite_token(p_token text)
returns text language sql immutable as $$
  select encode(extensions.digest(upper(trim(p_token)), 'sha256'), 'hex');
$$;

-- 멤버 색상 팔레트 (가입 순서대로)
create or replace function public.pick_member_color(p_index int)
returns text language sql immutable as $$
  select (array['#FF7A9E', '#6FC3FF', '#7BE3A0', '#C7A6FF', '#FFD36F', '#87E0D1'])
         [1 + (p_index % 6)];
$$;

-- ── 그룹 생성 ─────────────────────────────────────────────
create or replace function public.create_group(
  p_name text,
  p_type public.group_type default 'couple'
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_group groups%rowtype;
  v_token text;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  insert into groups (name, type, owner_id, max_members)
  values (
    coalesce(nullif(trim(p_name), ''),
             case p_type when 'couple' then '우리의 30일' else '같이 하는 셋로그' end),
    p_type,
    v_uid,
    case p_type when 'couple' then 2 else 12 end
  )
  returning * into v_group;

  insert into group_members (group_id, user_id, role, status, color_hex)
  values (v_group.id, v_uid, 'owner', 'active', pick_member_color(0));

  insert into sharing_preferences (group_id, user_id)
  values (v_group.id, v_uid);

  v_token := _issue_invite(v_group.id, v_uid);

  return jsonb_build_object(
    'group_id', v_group.id,
    'invite_token', v_token,
    'invite_url', 'https://kilog.app/join/' || v_token
  );
end $$;

-- 내부: 유니크 보장 토큰 발급
create or replace function public._issue_invite(p_group_id uuid, p_user_id uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_token text;
  v_try   int := 0;
begin
  loop
    v_token := gen_invite_token();
    begin
      insert into group_invites (group_id, token_hash, invited_by)
      values (p_group_id, hash_invite_token(v_token), p_user_id);
      return v_token;
    exception when unique_violation then
      v_try := v_try + 1;
      if v_try > 5 then raise exception 'INVITE_TOKEN_COLLISION'; end if;
    end;
  end loop;
end $$;

revoke all on function public._issue_invite(uuid, uuid) from public, anon, authenticated;

-- ── 초대 재발급 (기존 활성 토큰 전부 폐기 후 새로 발급) ────
create or replace function public.create_invite(p_group_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_token text;
begin
  if not is_member(p_group_id, v_uid) then
    raise exception 'NOT_A_MEMBER';
  end if;

  update group_invites set revoked_at = now()
   where group_id = p_group_id and revoked_at is null;

  v_token := _issue_invite(p_group_id, v_uid);

  return jsonb_build_object(
    'invite_token', v_token,
    'invite_url', 'https://kilog.app/join/' || v_token
  );
end $$;

-- ── 초대 미리보기 (수락 전 확인 화면용) ────────────────────
create or replace function public.preview_invite(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_invite group_invites%rowtype;
  v_group  groups%rowtype;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select * into v_invite
    from group_invites
   where token_hash = hash_invite_token(p_token) and revoked_at is null;

  if not found then raise exception 'INVITE_NOT_FOUND'; end if;
  if v_invite.expires_at < now() then raise exception 'INVITE_EXPIRED'; end if;
  if v_invite.used_count >= v_invite.max_uses then raise exception 'INVITE_EXHAUSTED'; end if;

  select * into v_group from groups where id = v_invite.group_id;

  return jsonb_build_object(
    'group_id', v_group.id,
    'name', v_group.name,
    'type', v_group.type,
    'max_members', v_group.max_members,
    'member_count', (select count(*) from group_members
                      where group_id = v_group.id and status = 'active'),
    'inviter_nickname', (select nickname from users where id = v_invite.invited_by),
    'expires_at', v_invite.expires_at
  );
end $$;

-- ── 초대 수락 ─────────────────────────────────────────────
create or replace function public.accept_invite(p_token text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_invite group_invites%rowtype;
  v_group  groups%rowtype;
  v_count  int;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select * into v_invite
    from group_invites
   where token_hash = hash_invite_token(p_token) and revoked_at is null
   for update;

  if not found then raise exception 'INVITE_NOT_FOUND'; end if;
  if v_invite.expires_at < now() then raise exception 'INVITE_EXPIRED'; end if;
  if v_invite.used_count >= v_invite.max_uses then raise exception 'INVITE_EXHAUSTED'; end if;

  select * into v_group from groups where id = v_invite.group_id for update;

  if exists (select 1 from group_members
              where group_id = v_group.id and user_id = v_uid) then
    -- 재가입: 상태만 복구
    update group_members set status = 'active'
     where group_id = v_group.id and user_id = v_uid;
  else
    select count(*) into v_count
      from group_members where group_id = v_group.id and status = 'active';
    if v_count >= v_group.max_members then raise exception 'GROUP_FULL'; end if;

    insert into group_members (group_id, user_id, role, status, color_hex)
    values (v_group.id, v_uid, 'member', 'active', pick_member_color(v_count));

    insert into sharing_preferences (group_id, user_id)
    values (v_group.id, v_uid)
    on conflict (group_id, user_id) do nothing;

    update group_invites set used_count = used_count + 1 where id = v_invite.id;
  end if;

  return jsonb_build_object('group_id', v_group.id, 'name', v_group.name);
end $$;

-- ── 커플 → 친구 그룹 확장 ─────────────────────────────────
create or replace function public.expand_group(p_group_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update groups
     set type = 'friends', max_members = 12
   where id = p_group_id and owner_id = auth.uid();
  if not found then raise exception 'OWNER_ONLY'; end if;
end $$;

-- ── 그룹 탈퇴 ─────────────────────────────────────────────
create or replace function public.leave_group(p_group_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if exists (select 1 from groups where id = p_group_id and owner_id = v_uid) then
    raise exception 'OWNER_CANNOT_LEAVE';  -- 오너는 그룹 삭제 또는 위임 필요
  end if;
  update group_members set status = 'left'
   where group_id = p_group_id and user_id = v_uid;
end $$;

-- ── 부트스트랩: 내 계정 + 그룹 + 멤버(동의 반영) ───────────
-- 멤버별 신체 수치는 sharing_preferences + profiles.visibility를
-- 검사해 동의된 항목만 포함하고 나머지는 null로 내려보낸다.
create or replace function public.get_bootstrap()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_group groups%rowtype;
  v_members jsonb;
  v_invite jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select g.* into v_group
    from groups g
    join group_members gm on gm.group_id = g.id
   where gm.user_id = v_uid and gm.status = 'active'
   order by gm.joined_at desc
   limit 1;

  if found then
    select jsonb_agg(m order by m -> 'joined_at') into v_members
    from (
      select jsonb_build_object(
        'user_id', gm.user_id,
        'nickname', u.nickname,
        'avatar_url', u.avatar_url,
        'role', gm.role,
        'status', gm.status,
        'color_hex', gm.color_hex,
        'joined_at', gm.joined_at,
        'sharing', to_jsonb(sp) - 'group_id' - 'user_id',
        -- 신체·대사 데이터: 본인이거나 (visibility='members' AND 항목별 동의)일 때만
        'profile', case
          when gm.user_id = v_uid then to_jsonb(p) - 'user_id'
          else jsonb_build_object(
            'sex', case when p.visibility = 'members' and sp.share_body then p.sex end,
            'age', case when p.visibility = 'members' and sp.share_body then p.age end,
            'height', case when p.visibility = 'members' and sp.share_body then p.height end,
            'activity_factor', case when p.visibility = 'members' and sp.share_body then p.activity_factor end,
            'weight', case when p.visibility = 'members' and (sp.share_weight or sp.share_body) then p.weight end,
            'body_fat', case when p.visibility = 'members' and (sp.share_body_fat or sp.share_body) then p.body_fat end,
            'skeletal_muscle', case when p.visibility = 'members' and sp.share_body then p.skeletal_muscle end,
            'visibility', p.visibility
          )
        end,
        'measurements', case
          when gm.user_id = v_uid or (p.visibility = 'members' and sp.share_body) then (
            select coalesce(jsonb_agg(jsonb_build_object(
              'id', b.id,
              'weight', b.weight,
              'body_fat', b.body_fat,
              'skeletal_muscle', b.skeletal_muscle,
              'measured_at', b.measured_at
            ) order by b.measured_at), '[]'::jsonb)
            from (
              select * from body_measurements
               where user_id = gm.user_id
               order by measured_at desc limit 12
            ) b
          )
          else '[]'::jsonb
        end
      ) as m
      from group_members gm
      join users u on u.id = gm.user_id
      left join profiles p on p.user_id = gm.user_id
      left join sharing_preferences sp
        on sp.group_id = gm.group_id and sp.user_id = gm.user_id
      where gm.group_id = v_group.id and gm.status = 'active'
    ) t;

    select jsonb_build_object(
      'id', i.id, 'expires_at', i.expires_at,
      'max_uses', i.max_uses, 'used_count', i.used_count
    ) into v_invite
    from group_invites i
    where i.group_id = v_group.id and i.revoked_at is null
      and i.expires_at > now() and i.used_count < i.max_uses
    order by i.expires_at desc limit 1;
  end if;

  return jsonb_build_object(
    'user', (select to_jsonb(u) from users u where u.id = v_uid),
    'profile', (select to_jsonb(p) - 'user_id' from profiles p where p.user_id = v_uid),
    'group', case when v_group.id is null then null else
      jsonb_build_object(
        'id', v_group.id, 'name', v_group.name, 'type', v_group.type,
        'owner_id', v_group.owner_id, 'max_members', v_group.max_members,
        'created_at', v_group.created_at
      ) end,
    'members', coalesce(v_members, '[]'::jsonb),
    'invite', v_invite
  );
end $$;

-- anon에게는 어떤 RPC도 허용하지 않음
revoke all on function public.create_group(text, public.group_type) from anon;
revoke all on function public.create_invite(uuid) from anon;
revoke all on function public.preview_invite(text) from anon;
revoke all on function public.accept_invite(text) from anon;
revoke all on function public.expand_group(uuid) from anon;
revoke all on function public.leave_group(uuid) from anon;
revoke all on function public.get_bootstrap() from anon;
