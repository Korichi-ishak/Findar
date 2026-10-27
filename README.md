# Findar

Plateforme immobilière vérifiée pour Alger.

- `supabase/` : base de données (migrations, données de référence, tests)
- `web/` : application Next.js (site public, acheteur, particulier, pro, back-office)
- `docs/ARCHITECTURE.md` : comment tout s'emboîte
- `docs/DATABASE.md` : règles pour faire évoluer la base sans la casser

## Démarrer

```bash
# 1. Base : déjà appliquée sur le projet Supabase « Findar » (stfbqtkafwiwkfchinqu).
#    Nouvelles migrations : supabase link --project-ref stfbqtkafwiwkfchinqu && supabase db push

# 2. App
cd web
cp .env.example .env.local   # URL + clé publishable (Supabase → Project Settings → API)
npm install
npm run dev
```

Premier super-admin, à lancer une fois en SQL :

```sql
insert into staff_role_assignment (user_id, role_code)
select id, 'super_admin' from auth.users where email = 'vous@findar.dz';
```

## Tester la base en local

```bash
PGHOST=… ./supabase/tests/run.sh
```
