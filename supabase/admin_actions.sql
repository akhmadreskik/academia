-- Admin-only updates for assessment components and permanent student deletion.
-- Run once in Supabase SQL Editor for the project used by this app.

alter table public.assessment_components enable row level security;

drop policy if exists "assessment_components_admin_update"
on public.assessment_components;

create policy "assessment_components_admin_update"
on public.assessment_components
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
