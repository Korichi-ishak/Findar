// Carte des écrans par espace. Chaque entrée renvoie à l'écran du prototype
// cliquable (champ `proto`) qui sert de maquette. `status` dit où en est le
// code : 'v0' = branché sur la base, 'shell' = page posée, à construire.

export type Space = 'compte' | 'espace' | 'pro' | 'admin';
export type StaffRole = 'verificateur' | 'photographe' | 'moderateur' | 'commercial' | 'comptabilite' | 'super_admin';

export interface NavItem {
  href: string;
  label: string;
  proto: string;
  status: 'v0' | 'shell';
  group?: string;
  staff?: StaffRole[];      // admin : rôles qui voient l'entrée (super_admin voit tout)
}

export const SPACES: Record<Space, { title: string; items: NavItem[] }> = {
  compte: {
    title: 'Mon compte',
    items: [
      { href: '/compte', label: 'Tableau de bord', proto: 'dossiers', status: 'v0' },
      { href: '/compte/dossiers', label: 'Mes demandes et visites', proto: 'dossiers', status: 'v0' },
      { href: '/compte/favoris', label: 'Favoris', proto: 'favoris', status: 'v0' },
      { href: '/compte/alertes', label: 'Recherches sauvegardées', proto: 'alertes', status: 'v0' },
      { href: '/compte/notifications', label: 'Notifications', proto: 'notifications', status: 'v0' },
      { href: '/compte/profil', label: 'Profil et données', proto: 'profil', status: 'shell' },
    ],
  },
  espace: {
    title: 'Espace particulier',
    items: [
      { href: '/espace', label: 'Mes annonces', proto: 'mes-annonces', status: 'v0' },
      { href: '/espace/annonces/nouvelle', label: 'Déposer une annonce', proto: 'deposer', status: 'v0' },
      { href: '/espace/demandes', label: 'Demandes reçues', proto: 'demandes', status: 'v0' },
      { href: '/espace/disponibilites', label: 'Mes disponibilités', proto: 'disponibilites', status: 'shell' },
      { href: '/espace/visite-360', label: 'Commander une visite 360°', proto: 'commande-360', status: 'shell' },
      { href: '/espace/paiements', label: 'Paiements', proto: 'paiements', status: 'shell' },
    ],
  },
  pro: {
    title: 'Espace pro',
    items: [
      { href: '/pro', label: 'Tableau de bord', proto: 'pro-tableau', status: 'v0' },
      { href: '/pro/annonces', label: 'Annonces', proto: 'pro-annonces', status: 'v0' },
      { href: '/pro/demandes', label: 'Boîte de demandes commune', proto: 'pro-demandes', status: 'v0' },
      { href: '/pro/agenda', label: 'Agenda des visites', proto: 'pro-agenda', status: 'v0' },
      { href: '/pro/programmes', label: 'Programmes neufs', proto: 'pro-programme', status: 'shell' },
      { href: '/pro/equipe', label: 'Équipe', proto: 'pro-equipe', status: 'v0' },
      { href: '/pro/statistiques', label: 'Statistiques', proto: 'pro-stats', status: 'shell' },
      { href: '/pro/abonnement', label: 'Abonnement', proto: 'pro-abonnement', status: 'shell' },
      { href: '/pro/profil', label: 'Vitrine de l\'agence', proto: 'pro-profil', status: 'shell' },
    ],
  },
  admin: {
    title: 'Back-office Findar',
    items: [
      { href: '/admin', label: 'Vue d\'ensemble', proto: 'bo-stats', status: 'v0' },
      { href: '/admin/verification', label: 'File de vérification', proto: 'bo-verif', status: 'v0', group: 'Opérations', staff: ['verificateur', 'photographe'] },
      { href: '/admin/appels', label: 'Appels de confirmation', proto: 'bo-appels', status: 'v0', group: 'Opérations', staff: ['verificateur', 'commercial'] },
      { href: '/admin/planning', label: 'Planning 360° et visio', proto: 'bo-planning', status: 'shell', group: 'Opérations', staff: ['verificateur', 'photographe'] },
      { href: '/admin/moderation', label: 'Modération', proto: 'bo-moderation', status: 'v0', group: 'Opérations', staff: ['moderateur'] },
      { href: '/admin/comptes', label: 'Comptes et agences', proto: 'bo-comptes', status: 'v0', group: 'Commercial', staff: ['commercial'] },
      { href: '/admin/paiements', label: 'Paiements et virements', proto: 'bo-paiements', status: 'v0', group: 'Commercial', staff: ['comptabilite'] },
      { href: '/admin/reglages', label: 'Réglages', proto: 'bo-reglages', status: 'v0', group: 'Plateforme', staff: ['super_admin'] },
      { href: '/admin/referentiels', label: 'Listes de valeurs', proto: 'bo-reglages', status: 'v0', group: 'Plateforme', staff: ['super_admin'] },
    ],
  },
};

export const PUBLIC_NAV = [
  { href: '/recherche?category=vente', label: 'Acheter' },
  { href: '/recherche?category=location', label: 'Louer' },
  { href: '/recherche?category=neuf', label: 'Neuf' },
  { href: '/estimer', label: 'Estimer' },
  { href: '/prix', label: 'Prix au m²' },
  { href: '/agences', label: 'Agences' },
];
