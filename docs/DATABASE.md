# Base de données Findar

Postgres sur Supabase (Auth, Storage, Realtime). Le schéma reste du Postgres standard, sans PostGIS ni fonction propre à Supabase hors `auth.uid()`. On peut donc le déplacer vers un hébergeur en Algérie si la loi 18-07 l'exige.

## Règle n°1 : rien de ce qui est encore flou n'est figé dans le schéma

Beaucoup de décisions peuvent encore changer. Le schéma sépare donc ce qui est sûr de ce qui ne l'est pas.

| Ce qui peut changer | Où ça vit | Comment on le change |
|---|---|---|
| Délais, seuils, limites (48 h, 15 j, 30 j, 2 annonces, 150 m, k = 5, 8 comparables, 15 %…) | `app_setting` | `update app_setting set value = … where key = …` |
| Listes de valeurs (statuts, types de bien, catégories, rôles, pièces, raisons de signalement, lieux de proximité…) | tables `ref_*` | une ligne `insert` ou `update`. On ne supprime jamais une valeur : on passe `active = false`. |
| Comportement d'un statut (visible ? contactable ? compte dans le quota ?) | `ref_listing_status.meta` | `{"public":…, "contact":…, "counts_quota":…}` |
| Qui doit confirmer une étape du dossier (les deux, un seul, automatique) | `ref_dossier_step.meta.policy` | `both` / `one` / `auto` |
| Nouveaux équipements, papiers ou détails d'annonce, et filtres de recherche | `ref_attribute` + colonne `listing.attributes` (jsonb) | une ligne dans `ref_attribute`. La recherche le filtre aussitôt. |
| Motifs de modération des messages (numéro, CCP, WhatsApp…) | `app_setting.moderation.message_patterns` | modifier les regex |
| Prix et quotas des formules | `plan` (prix `null` = à fixer) | `update plan …` |
| Ce qu'on ne sait pas encore modéliser | colonnes `metadata` / `attributes` (jsonb) | on écrit dedans, puis on en fait une vraie colonne le jour où on filtre dessus |

`supabase/tests/20_change_without_migration.sql` le prouve : quota passé de 2 à 3, nouveau filtre « cave », nouveau statut « sous offre », visite confirmée par un seul côté, adresse donnée 48 h avant. Aucune de ces décisions n'a demandé de migration.

## Règle n°2 : les migrations ne cassent jamais l'existant

- **Fichiers `supabase/migrations/AAAAMMJJHHMMSS_nom.sql`, en ajout seul.** Une migration déjà appliquée en production ne se modifie plus. Pour changer quelque chose, on écrit une nouvelle migration.
- **Changement en trois temps (expand → migrate → contract).** On ajoute la nouvelle colonne ou table, puis on copie les données et on bascule le code. La suppression de l'ancienne vient dans une migration séparée, plus tard.
- **Pas de type `ENUM` Postgres.** Un ENUM ne se modifie pas proprement. On utilise des tables de référence avec une clé étrangère sur `code`.
- **Le front ne lit pas les tables brutes pour la recherche.** Il passe par la vue `listing_public` et les fonctions RPC (`search_listings`, `open_dossier`, `propose_visit`, `confirm_visit`, `submit_listing`…). On peut réorganiser les tables sans toucher au front si la vue garde ses colonnes. On ajoute des colonnes à une vue, on n'en retire jamais sans en créer une `_v2`.
- **Identifiants UUID partout.** Suppression douce (`deleted_at`) pour les annonces, organisations, profils et programmes.
- **Journaux en ajout seul** : `listing_event`, `dossier_event`, `audit_log`. Un trigger y interdit UPDATE et DELETE. L'historique ne se réécrit pas, il se rejoue.

## Données personnelles

Profils, adresses exactes, messages et comptes rendus de vérification vivent dans le schéma `pii`, lus par des vues `public.*` du même nom. Voir `DATA_RESIDENCY.md`. **Ajouter une colonne à une table `pii` demande de recréer sa vue** (`select *` est figé à la création de la vue).

## Vue d'ensemble des tables

**Identités**
- `profile` : créé automatiquement à l'inscription.
- `organization` : un particulier est une organisation de type `particulier` avec un seul membre, donc une annonce appartient toujours à une organisation.
- `organization_member` : rôles directeur / agent / assistant, boîte commune.
- `staff_role_assignment` : les 6 rôles Findar, cumulables.

**Annonces**
- `property` : le bien physique. Sa position publique est floutée automatiquement.
- `property_location` : l'adresse exacte, protégée.
- `listing` : l'annonce.
- `listing_media`, `listing_poi` (proximité précalculée), `listing_event`.
- `favorite`, `saved_search`, `waitlist`.
- Neuf : `program`, `program_typology`, `program_lot`, `program_update`, `program_payment_step`.

**Vérification**
- `verification_case` : un dossier par annonce, organisation ou programme.
- `verification_document` : **le fichier est effacé dès la décision**. On garde seulement le type, la décision, l'agent et la date. Une contrainte SQL interdit une pièce décidée qui garderait son fichier. `storage_purge_queue` liste les objets à effacer du stockage.
- `verification_attempt` : visio ou tournage, checklist en jsonb, captures, empreinte des faits.
- `tour`, `photo_mission` : 360° via Simple Virtual Tour.

**Contact et visites**
- `dossier`, `dossier_event` (la source de vérité), `availability_rule`.
- `visit` : verrou de version contre le double clic. Adresse libérée X heures avant la visite.
- `message` : modération automatique.
- `questionnaire_answer`, `offer` (sans engagement).
- `deal` : prix convenu privé, posé par un agent.
- `confirmation_call` : appels Findar à 48 h et à 15 jours.

**Argent et opérations**
- `plan`, `subscription`, `payment` (Chargily ou virement avec justificatif), `invoice`, `boost`.
- `notification` + `notification_delivery` (file d'envoi rejouable).
- `report`, `estimate_run` (chaque estimation est rejouable), `audit_log`.

## Règles de sécurité appliquées par la base (RLS)

Toutes les tables ont la RLS activée. Ces règles valent même si le front est contourné :

- Un visiteur voit les annonces publiques, jamais l'adresse exacte, et jamais le nom d'un particulier.
- L'annonceur ne peut ni se publier, ni poser le badge, ni passer à « réservée » ou « vendue ». Seul un agent Findar le peut.
- L'acheteur voit l'adresse seulement entre sa libération (la veille de la visite confirmée) et le lendemain de la visite.
- Le « côté » d'un message ou d'une confirmation (acheteur, vendeur, Findar) est calculé depuis la session, jamais envoyé par le client.
- Un vérificateur ne peut pas vérifier sa propre annonce.
- Le prix convenu n'est visible que des deux parties et de l'équipe Findar. Les moyennes publiques ne sortent qu'à partir de 5 biens.

## Tâches planifiées

`app.run_scheduled_jobs()` (pg_cron toutes les 15 min, ou une fonction serveur) :
- expire les propositions de visite ;
- crée l'appel Findar 48 h après chaque visite ;
- pose la question des 30 jours, puis masque l'annonce au bout de 7 jours sans réponse ;
- ouvre une commune quand elle atteint son seuil d'annonces vérifiées.

## Tester en local

```bash
PGHOST=… ./supabase/tests/run.sh
```

Le script recrée une base vide, imite le schéma `auth` de Supabase, rejoue toutes les migrations, puis rejoue `seed.sql` deux fois pour vérifier qu'il est idempotent. Il lance ensuite les tests (62 vérifications : visibilité, adresse, quotas, journaux, modération, changements sans migration).

## Montants

Tout est stocké **en dinars (DA), entier** (`price_dzd bigint`). L'affichage en centimes (1 DA = 100 centimes, « 3 200 millions ») se fait dans le front. À la saisie, l'unité est obligatoire (réglage `price.input_units`).
