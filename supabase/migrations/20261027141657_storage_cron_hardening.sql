-- =====================================================================
-- Findar · 010 · Stockage de fichiers, tâches planifiées, durcissement
-- Les blocs Supabase (storage, pg_cron) sont ignorés sur un Postgres nu
-- (tests locaux, futur serveur en Algérie sans ces briques).
-- =====================================================================

-- ---------- fichiers ----------
-- listings     : photos publiques (pas de donnée personnelle), CDN possible à l'étranger
-- verification : pièces d'identité / actes, PRIVÉ, effacées dès la décision
--                (storage_purge_queue). À rediriger vers le stockage algérien.
do $outer$
begin
  if not exists (select 1 from pg_namespace where nspname = 'storage') then
    raise notice 'Pas de schéma storage : buckets ignorés';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
    ('listings', 'listings', true, 10485760, array['image/jpeg', 'image/png', 'image/webp']),
    ('verification', 'verification', false, 10485760, array['image/jpeg', 'image/png', 'application/pdf'])
  on conflict (id) do nothing;

  -- Photos : chemin « <listing_id>/<fichier> », écrites par l'annonceur ou l'équipe.
  execute $p$create policy listings_write on storage.objects for insert to authenticated
    with check (bucket_id = 'listings' and (app.can_manage_listing(((storage.foldername(name))[1])::uuid) or app.is_staff()))$p$;
  execute $p$create policy listings_delete on storage.objects for delete to authenticated
    using (bucket_id = 'listings' and (app.can_manage_listing(((storage.foldername(name))[1])::uuid) or app.is_staff()))$p$;

  -- Pièces : chemin « <case_id>/<fichier> ». Dépôt par l'annonceur, lecture par
  -- les vérificateurs, suppression par l'équipe (et la file de purge côté serveur).
  execute $p$create policy verification_upload on storage.objects for insert to authenticated
    with check (bucket_id = 'verification' and app.case_visible(((storage.foldername(name))[1])::uuid))$p$;
  execute $p$create policy verification_read on storage.objects for select to authenticated
    using (bucket_id = 'verification' and app.is_staff(array['verificateur']))$p$;
  execute $p$create policy verification_delete on storage.objects for delete to authenticated
    using (bucket_id = 'verification' and app.is_staff(array['verificateur']))$p$;
end $outer$;

-- ---------- tâches planifiées (toutes les 15 minutes) ----------
do $outer$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron indisponible : lancer app.run_scheduled_jobs() depuis un planificateur externe';
    return;
  end;
  perform cron.schedule('findar-jobs', '*/15 * * * *', 'select app.run_scheduled_jobs()');
end $outer$;

-- ---------- durcissement ----------
-- Chemin de recherche figé pour toutes nos fonctions (avertissement Supabase
-- « function_search_path_mutable ») : évite qu'un objet homonyme soit pris à
-- la place du bon.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public') and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
      and (p.proconfig is null or not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'))
  loop
    execute format('alter function %s set search_path = public, extensions, pg_temp', f.sig);
  end loop;
end $$;

-- Les fonctions internes ne sont pas appelables directement depuis l'API publique.
revoke execute on function app.run_scheduled_jobs() from public, anon, authenticated;
revoke execute on function public.approve_listing_verification(uuid, text) from anon;
revoke execute on function public.request_listing_changes(uuid, text, boolean) from anon;
