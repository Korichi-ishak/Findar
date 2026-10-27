# Données personnelles : traiter sur Supabase, stocker en Algérie

## Décision

Supabase fait le traitement : API, règles d'accès, calculs, tâches planifiées. Les données personnelles seront **stockées** sur un serveur en Algérie dès qu'il existera. D'ici là, la base Supabase ne doit contenir **que des données de test**.

## Ce qui est déjà en place

Toutes les données personnelles sont regroupées dans le schéma `pii`. Il n'est jamais exposé par l'API.

| Table `pii.*` | Contenu |
|---|---|
| `profile` | nom, e-mail, téléphone, préférences |
| `property_location` | adresse exacte, coordonnées GPS précises |
| `message` | conversations acheteur ↔ annonceur |
| `verification_attempt` | comptes rendus de visio, captures du bien |

Le front lit et écrit ces tables par des **vues** qui portent le même nom dans `public` (`public.profile`, `public.message`…). Les règles d'accès sont **dans les vues** (filtre + `WITH CHECK OPTION`) et dans le trigger `app.pii_guard`, **pas dans la RLS**. C'est voulu : la RLS ne s'applique pas aux tables distantes, alors que ces règles-là continueront de marcher quand les tables seront en Algérie.

Ce qui reste dans `public` ne contient pas de données personnelles : annonces, biens (position floutée à 150 m), statuts, organisations, journaux. Le dossier (`dossier`) relie un acheteur à une annonce par un identifiant, sans nom ni contact.

L'outil de contrôle de Supabase (Advisors) signale les 4 vues en « Security Definer View » : c'est attendu, et c'est la raison ci-dessus.

## Le jour où le serveur algérien est prêt

1. Sur le serveur algérien (Postgres 15 ou plus), créer le schéma `pii` avec les mêmes tables. Les triggers ne sont pas nécessaires là-bas : ils restent côté Supabase.
2. Sur Supabase :
   ```sql
   create extension postgres_fdw;
   create server algerie foreign data wrapper postgres_fdw options (host '…', dbname 'findar', port '5432', sslmode 'require');
   create user mapping for postgres server algerie options (user '…', password '…');   -- mot de passe dans Vault
   create schema pii_dz;
   import foreign schema pii from server algerie into pii_dz;
   ```
3. Recopier les données (`insert into pii_dz.x select * from pii.x`), vérifier les comptes.
4. Dans une seule migration : renommer `pii` en `pii_old` et `pii_dz` en `pii`, recréer les triggers `pii_guard` / `message_defaults` / `property_location_blur` sur les tables distantes, puis recréer les 4 vues. Les vues portent le même nom, donc l'application ne change pas.
5. Rejouer `supabase/tests`, puis supprimer `pii_old` (effacement définitif hors d'Algérie).

## Ce que ce découpage ne règle pas (à trancher avec le client)

- **Les comptes de connexion.** Supabase Auth garde l'e-mail et le téléphone dans `auth.users`, sur ses serveurs (Francfort). On ne peut pas les déplacer avec `postgres_fdw`. Il y a deux solutions :
  - (a) auto-héberger Supabase Auth (GoTrue, open source) sur le serveur algérien ;
  - (b) auto-héberger **tout Supabase** en Algérie. C'est la solution la plus simple : on garde le même code, les mêmes migrations, et tout est stocké en Algérie.
- **Les pièces de vérification.** Elles passent par Supabase Storage (privé) le temps de la décision, puis sont effacées. Pour un stockage strictement en Algérie, elles doivent être envoyées directement au stockage algérien.
- **Les journaux Supabase.** Ils gardent quelques jours les adresses IP et les requêtes.
- **Le transfert lui-même.** Faire traiter des données personnelles à l'étranger (même sans les y garder) est, selon la loi 18-07, un transfert qui peut demander une autorisation de l'ANPDP. Je ne suis pas juriste : à valider avec un avocat avant d'ouvrir aux vrais utilisateurs.
