-- ═══════════════════════════════════════════════════════════
-- sal-log · Storage 버킷 + Realtime
--
--  clips  : 브이로그 영상/썸네일. 경로 규칙 <group_id>/<user_id>/<uuid>.<ext>
--           업로드는 본인 폴더에만, 조회는 그룹 멤버만 (재생은 signed URL).
--  inbody : 인바디 검사지 원본. 경로 규칙 <user_id>/<uuid>.jpg — 본인 전용.
-- ═══════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('clips',  'clips',  false, 52428800, array['video/mp4', 'video/quicktime', 'image/jpeg']),
  ('inbody', 'inbody', false, 10485760, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do nothing;

-- ── clips 버킷 ────────────────────────────────────────────
create policy "clips storage: member read"
on storage.objects for select to authenticated
using (
  bucket_id = 'clips'
  and public.is_member(((storage.foldername(name))[1])::uuid, auth.uid())
);

create policy "clips storage: self upload"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'clips'
  and (storage.foldername(name))[2] = auth.uid()::text
  and public.is_member(((storage.foldername(name))[1])::uuid, auth.uid())
);

create policy "clips storage: self delete"
on storage.objects for delete to authenticated
using (
  bucket_id = 'clips'
  and (storage.foldername(name))[2] = auth.uid()::text
);

-- ── inbody 버킷 (본인 전용) ───────────────────────────────
create policy "inbody storage: self all"
on storage.objects for all to authenticated
using (
  bucket_id = 'inbody' and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'inbody' and (storage.foldername(name))[1] = auth.uid()::text
);

-- ── Realtime: 클립/기록/멤버 변경을 그룹원에게 푸시 ────────
alter publication supabase_realtime add table public.clips;
alter publication supabase_realtime add table public.food_logs;
alter publication supabase_realtime add table public.workout_logs;
alter publication supabase_realtime add table public.group_members;
alter publication supabase_realtime add table public.sharing_preferences;
