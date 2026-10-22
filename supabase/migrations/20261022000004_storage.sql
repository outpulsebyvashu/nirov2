-- Storage buckets.
-- avatars:    private, customers write only under their own <uid>/ folder.
-- cafe-media: public read (logos, storefront photos); owners and managers
--             write under <cafe_id>/.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', false, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('cafe-media', 'cafe-media', true, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/svg+xml'])
on conflict (id) do nothing;

create policy avatars_own on storage.objects for all to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy cafe_media_read on storage.objects for select to anon, authenticated
  using (bucket_id = 'cafe-media');

create policy cafe_media_write on storage.objects for all to authenticated
  using (
    bucket_id = 'cafe-media'
    and case when (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
             then public.is_cafe_staff(((storage.foldername(name))[1])::uuid, array['owner', 'manager']::public.staff_role[])
             else false end
  )
  with check (
    bucket_id = 'cafe-media'
    and case when (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
             then public.is_cafe_staff(((storage.foldername(name))[1])::uuid, array['owner', 'manager']::public.staff_role[])
             else false end
  );
