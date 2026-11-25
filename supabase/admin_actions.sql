-- Admin-only updates for assessment components and permanent student deletion.
-- Jalankan di SQL Editor proyek Supabase yang dipakai aplikasi.

alter table public.assessment_components enable row level security;

drop policy if exists "assessment_components_admin_update"
on public.assessment_components;

create policy "assessment_components_admin_update"
on public.assessment_components
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Izinkan Administrator mengedit data siswa.
alter table public.students enable row level security;

drop policy if exists "students_admin_update"
on public.students;

create policy "students_admin_update"
on public.students
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Diperlukan saat Administrator memindahkan siswa ke kelas lain.
alter table public.student_class_history enable row level security;

drop policy if exists "student_class_history_admin_update"
on public.student_class_history;

create policy "student_class_history_admin_update"
on public.student_class_history
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

create or replace function public.delete_student_permanently(p_student_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or coalesce(public.is_admin(), false) = false then
    raise exception 'Only administrators can permanently delete students.'
      using errcode = '42501';
  end if;

  perform 1
  from public.students
  where id = p_student_id
  for update;

  if not found then
    raise exception 'Student not found.' using errcode = 'P0002';
  end if;

  delete from public.grades where student_id = p_student_id;
  delete from public.attendance_records where student_id = p_student_id;
  delete from public.student_class_history where student_id = p_student_id;
  delete from public.students where id = p_student_id;
end;
$$;

revoke all on function public.delete_student_permanently(uuid) from public, anon;
grant execute on function public.delete_student_permanently(uuid) to authenticated;

notify pgrst, 'reload schema';
