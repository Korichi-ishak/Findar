-- =====================================================================
-- Findar · 011 · Droits d'exécution des fonctions de l'API
-- Postgres donne EXECUTE à tout le monde par défaut : on ferme, puis on
-- rouvre fonction par fonction. Un visiteur non connecté n'appelle que
-- la recherche et les prix du marché.
-- =====================================================================
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated, service_role', f.sig);
    if f.proname in ('search_listings', 'market_price_m2') then
      execute format('grant execute on function %s to anon', f.sig);
    end if;
  end loop;
end $$;

-- Les nouvelles fonctions du schéma public sont fermées aux visiteurs par défaut.
alter default privileges in schema public revoke execute on functions from public, anon;
