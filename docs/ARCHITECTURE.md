# Architecture Findar · V0

## Vue d'ensemble

```
navigateur (PWA, FR / AR / EN)
   │
   ▼
Next.js 16 (App Router, Server Components, Server Actions)       web/
   │  proxy.ts : rafraîchit la session, ferme /compte /espace /pro /admin
   │  lib/session.ts : rôles Findar + organisations → espaces ouverts
   ▼
Supabase                                                         supabase/
   ├─ Auth : connexion sans mot de passe, code par SMS ou e-mail
   ├─ Postgres : tables + RLS + fonctions (RPC) + journaux
   ├─ Storage : photos (public), pièces de vérification (privé, effacées après décision)
   └─ pg_cron → app.run_scheduled_jobs() toutes les 15 min
Services externes : Chargily (CIB / EDAHABIA), Simple Virtual Tour (360°), Zoom (visio), Google Maps, SMS
```

**Principe directeur.** Les règles métier qui protègent les gens vivent dans la base, pas dans le front. Exemples : un annonceur ne se publie pas lui-même ; l'adresse n'est donnée que la veille d'une visite confirmée ; les pièces sont effacées après la décision ; les messages avec un numéro partent en modération. Si demain une appli mobile, un script ou un partenaire se branche, ces règles restent vraies.

## Les cinq espaces

| Espace | Route | Qui | Accès |
|---|---|---|---|
| Public | `/`, `/recherche`, `/annonce/[ref]`, `/prix`, `/agences`, `/estimer`, `/tarifs` | tout le monde | voit tout, sauf le contact et l'adresse |
| Acheteur | `/compte` | tout compte connecté | ses dossiers, visites, messages, favoris, alertes |
| Particulier | `/espace` | tout compte connecté | 2 annonces actives max (réglable) |
| Pro | `/pro` | membre d'une agence ou d'un promoteur | boîte de demandes commune, agenda, équipe |
| Back-office | `/admin` | équipe Findar (6 rôles cumulables) | chaque entrée du menu filtrée par rôle |

`web/lib/routes.ts` liste tous les écrans par espace. Chaque écran renvoie à sa maquette dans le prototype cliquable et porte un statut : `v0` si la page est branchée sur la base, `shell` si elle est posée mais pas encore construite.

## Contrôle d'accès en trois couches

1. **`proxy.ts`** : pas de session → redirection vers `/connexion?next=…`.
2. **Layouts d'espace** (`requireSpace`, `requireStaff`) : session sans le bon rôle → page 403.
3. **La base (RLS + fonctions `security definer`)** : la vraie barrière. Les couches 1 et 2 servent seulement à afficher une page propre.

## Parcours principaux et fonctions de la base

| Parcours | Fonction | Ce que la base garantit |
|---|---|---|
| Déposer une annonce | `ensure_personal_organization`, puis insert, puis `submit_listing` | statut `en_verification`, échéance à 2 jours ouvrés (dim.→jeu.), quota |
| Ouvrir un compte pro | `create_pro_organization` | créateur = directeur, dossier de vérification RC / agrément |
| Vérifier | décision sur `verification_document`, `verification_attempt`, `approve_listing_verification`, `request_listing_changes` | fichier effacé, motif obligatoire, le vérificateur n'est pas l'auteur |
| Contacter | `open_dossier` | un seul dossier ouvert par acheteur et par annonce, connexion requise |
| Visite | `propose_visit`, `confirm_visit` | confirmation par les deux côtés (réglable), verrou de version, adresse la veille |
| Message | insert `message` | côté calculé par la base, détection numéro / argent / contact externe |
| Accord | insert `deal` (agent Findar) | statut de l'annonce mis à jour, appel planifié à 15 jours |
| Suivi | `run_scheduled_jobs` | expirations, appels à 48 h, question des 30 jours, masquage, ouverture des communes |

## Ce qui reste branché sur des réglages

Toutes les décisions encore ouvertes sont des données, pas du code (voir `DATABASE.md`). Le back-office les expose :
- `/admin/reglages` : délais, seuils, quotas, motifs de modération ;
- `/admin/referentiels` : statuts, types, étapes, pièces, motifs ; on ajoute, on renomme, on désactive.

## Arborescence

```
findar/
├─ supabase/
│  ├─ migrations/        11 migrations, en ajout seul (mêmes versions que sur Supabase)
│  ├─ seed.sql           listes de valeurs, 57 communes d'Alger, réglages, formules (rejouable)
│  └─ tests/             base locale jetable + 62 vérifications
├─ web/
│  ├─ proxy.ts
│  ├─ app/(public)/      site public + connexion + inscription pro
│  ├─ app/compte|espace|pro|admin/
│  ├─ app/actions/       Server Actions (relais vers les RPC)
│  ├─ components/        DossierView (même écran des deux côtés), ListingForm, SpaceShell…
│  ├─ lib/               session, supabase, routes, format (centimes ↔ DA), i18n
│  └─ types/api.ts       contrat avec la base (vue listing_public, filtres)
└─ docs/
```

## Données personnelles et hébergement

- Les pièces d'identité et actes ne sont jamais conservés. Une contrainte SQL l'impose et une file de purge efface le fichier du stockage.
- Les appels de vérification ne sont pas enregistrés. On garde la checklist, le compte rendu et les captures du bien.
- **Traitement sur Supabase, stockage en Algérie.** Les données personnelles sont isolées dans le schéma `pii` et lues par des vues qui portent les règles d'accès. Le jour où le serveur algérien est prêt, ces tables deviennent distantes (`postgres_fdw`) sans changer l'application. Le détail, et ce que ce découpage ne règle pas (comptes de connexion, fichiers, journaux), est dans `DATA_RESIDENCY.md`.
- Photos et 360° sur un CDN à l'étranger : seul `web/lib/media.ts` change.

## Ce qui n'est pas encore branché

- Envoi des SMS, e-mails et push : la file `notification_delivery` est en place, l'envoyeur ne l'est pas (fournisseur SMS à choisir).
- Webhook Chargily, Simple Virtual Tour, création des liens Zoom, carte Google Maps, calcul des lieux à proximité.
- Moteur d'estimation : les règles et la table sont en place, pas le calcul.
- Écrans `shell` : disponibilités, commande 360°, paiements particulier, programmes neufs, statistiques pro, abonnement, vitrine agence, planning 360°.
