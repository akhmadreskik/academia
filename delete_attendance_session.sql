create or replace function public.delete_attendance_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'administrator' and p.is_active = true
  ) then
    raise exception 'Only administrators can delete attendance sessions.'
      using errcode = '42501';
  end if;

  perform 1
  from public.attendance_sessions
  where id = p_session_id
  for update;

  if not found then
    raise exception 'Attendance session not found.' using errcode = 'P0002';
  end if;

  delete from public.attendance_records where session_id = p_session_id;
  delete from public.attendance_sessions where id = p_session_id;
end;
$$;

revoke all on function public.delete_attendance_session(uuid) from public, anon;
grant execute on function public.delete_attendance_session(uuid) to authenticated;
