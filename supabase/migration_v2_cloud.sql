-- ACADEMIA v2.0 cloud migration
-- Run only after the original schema.sql has been applied.
-- Atomic class transfer RPC.
create or replace function public.transfer_student_class(
  p_student_id uuid,
  p_new_class_id uuid,
  p_start_date date default current_date
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare v_old_class uuid;
begin
  select current_class_id into v_old_class
  from public.students where id=p_student_id for update;
  if not found then raise exception 'Student not found'; end if;
  if not exists(select 1 from public.classes where id=p_new_class_id and is_active=true)
  then raise exception 'Target class is missing or inactive'; end if;
  if v_old_class is distinct from p_new_class_id then
    update public.student_class_history
       set end_date=p_start_date-1
     where student_id=p_student_id and end_date is null;
    insert into public.student_class_history(student_id,class_id,start_date,recorded_by)
    values(p_student_id,p_new_class_id,p_start_date,auth.uid());
    update public.students set current_class_id=p_new_class_id where id=p_student_id;
  end if;
end;
$$;
grant execute on function public.transfer_student_class(uuid,uuid,date) to authenticated;

-- Private bucket for student photos and supporting documents.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('academia-student-documents','academia-student-documents',false,5242880,
       array['image/jpeg','image/png','application/pdf'])
on conflict(id) do nothing;

drop policy if exists "academia_docs_read_authenticated" on storage.objects;
create policy "academia_docs_read_authenticated"
on storage.objects for select to authenticated
using(bucket_id='academia-student-documents');

drop policy if exists "academia_docs_insert_authenticated" on storage.objects;
create policy "academia_docs_insert_authenticated"
on storage.objects for insert to authenticated
with check(bucket_id='academia-student-documents');

drop policy if exists "academia_docs_update_authenticated" on storage.objects;
create policy "academia_docs_update_authenticated"
on storage.objects for update to authenticated
using(bucket_id='academia-student-documents')
with check(bucket_id='academia-student-documents');

drop policy if exists "academia_docs_delete_admin" on storage.objects;
create policy "academia_docs_delete_admin"
on storage.objects for delete to authenticated
using(bucket_id='academia-student-documents' and public.is_admin());

-- Enable Realtime publication for key tables, if not already included.
do $$ begin
  alter publication supabase_realtime add table public.students;
exception when duplicate_object then null;
when undefined_object then null;
end $$;
do $$ begin
  alter publication supabase_realtime add table public.classes;
exception when duplicate_object then null;
when undefined_object then null;
end $$;
