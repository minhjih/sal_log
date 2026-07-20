-- ═══════════════════════════════════════════════════════════
-- 개인 즐겨찾기 + 바레 운동 추가
--
--  · favorite_entries: 직접 입력한 음식/운동을 유저별로 저장.
--    같은 이름을 다시 쓰면 use_count가 올라가 자주 쓴 순으로 노출.
--  · exercise_catalog에 '바레' 추가 (발레 기반 토닝, MET 4.0)
-- ═══════════════════════════════════════════════════════════

-- ── 바레 ──────────────────────────────────────────────────
insert into public.exercise_catalog (name, met, body_part, sort)
values ('바레', 4.0, '하체', 19)
on conflict (name) do nothing;

-- ── 개인 즐겨찾기 ─────────────────────────────────────────
create table public.favorite_entries (
  user_id      uuid not null references public.users (id) on delete cascade,
  kind         text not null check (kind in ('food', 'workout')),
  name         text not null check (char_length(name) between 1 and 20),
  kcal         int  not null check (kcal between 0 and 5000),
  minutes      int  check (minutes between 1 and 600),   -- workout 전용
  body_part    text,                                     -- workout 전용
  use_count    int not null default 1,
  last_used_at timestamptz not null default now(),
  primary key (user_id, kind, name)
);

alter table public.favorite_entries enable row level security;

create policy "favorites: self all" on public.favorite_entries
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 사용 시 upsert + 카운트 증가 (자주 쓴 순 정렬의 근거)
create or replace function public.bump_favorite(
  p_kind text,
  p_name text,
  p_kcal int,
  p_minutes int default null,
  p_body_part text default null
)
returns void
language sql security invoker as $$
  insert into public.favorite_entries (user_id, kind, name, kcal, minutes, body_part)
  values (auth.uid(), p_kind, left(trim(p_name), 20), p_kcal, p_minutes, p_body_part)
  on conflict (user_id, kind, name) do update
    set kcal = excluded.kcal,
        minutes = coalesce(excluded.minutes, favorite_entries.minutes),
        body_part = coalesce(excluded.body_part, favorite_entries.body_part),
        use_count = favorite_entries.use_count + 1,
        last_used_at = now();
$$;

revoke all on function public.bump_favorite(text, text, int, int, text) from anon;
