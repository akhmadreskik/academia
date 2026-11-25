-- Admin-only updates for assessment components and permanent student deletion.

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

-- Kebijakan update untuk riwayat kelas.
alter table public.student_class_history enable row level security;

drop policy if exists "student_class_history_admin_update"
on public.student_class_history;

create policy "student_class_history_admin_update"
on public.student_class_history
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Pindahkan siswa dan perbarui riwayat kelas dalam satu fungsi.
create or replace function public.transfer_student_class(
  p_student_id uuid,
  p_new_class_id uuid,
  p_start_date date default current_date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old_class uuid;
begin
  if auth.uid() is null or coalesce(public.is_admin(), false) = false then
    raise exception 'Only administrators can transfer students.'
      using errcode = '42501';
  end if;

  select current_class_id into v_old_class
  from public.students
  where id = p_student_id
  for update;

  if not found then
    raise exception 'Student not found.' using errcode = 'P0002';
  end if;

  if not exists (
    select 1 from public.classes
    where id = p_new_class_id and is_active = true
  ) then
    raise exception 'Target class is missing or inactive.'
      using errcode = '23503';
  end if;

  if v_old_class is distinct from p_new_class_id then
    update public.student_class_history
       set end_date = p_start_date - 1
     where student_id = p_student_id and end_date is null;

    insert into public.student_class_history(student_id, class_id, start_date, recorded_by)
    values (p_student_id, p_new_class_id, p_start_date, auth.uid());

    update public.students
       set current_class_id = p_new_class_id
     where id = p_student_id;
  end if;
end;
$$;

revoke all on function public.transfer_student_class(uuid, uuid, date)
from public, anon;

grant execute on function public.transfer_student_class(uuid, uuid, date)
to authenticated;

-- Hapus siswa dan data akademik terkait secara permanen.
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

revoke all on function public.delete_student_permanently(uuid)
from public, anon;

grant execute on function public.delete_student_permanently(uuid)
to authenticated;

notify pgrst, 'reload schema';
