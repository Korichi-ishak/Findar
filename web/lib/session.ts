import 'server-only';
import { cache } from 'react';
import { forbidden, redirect } from 'next/navigation';
import { isSupabaseConfigured } from '@/lib/env';
import { createClient } from '@/lib/supabase/server';
import type { Space, StaffRole } from '@/lib/routes';

export interface Membership {
  organization_id: string;
  role_code: 'directeur' | 'agent' | 'assistant' | string;
  kind_code: 'particulier' | 'agence' | 'promoteur' | string;
  name: string;
}

export interface Viewer {
  id: string;
  email: string | null;
  fullName: string | null;
  staffRoles: StaffRole[];
  memberships: Membership[];
  spaces: Space[];
}

/** L'utilisateur connecté, ses rôles Findar et ses organisations (une fois par requête). */
export const getViewer = cache(async (): Promise<Viewer | null> => {
  if (!isSupabaseConfigured) return null;
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const id = claims?.claims?.sub as string | undefined;
  if (!id) return null;

  const [profile, staff, members] = await Promise.all([
    supabase.from('profile').select('full_name, email').eq('id', id).maybeSingle(),
    supabase.from('staff_role_assignment').select('role_code').eq('user_id', id).is('revoked_at', null),
    supabase
      .from('organization_member')
      .select('organization_id, role_code, organization:organization_id (kind_code, name)')
      .eq('user_id', id)
      .is('removed_at', null),
  ]);

  const staffRoles = (staff.data ?? []).map((r) => r.role_code as StaffRole);
  const memberships: Membership[] = (members.data ?? []).map((m) => {
    const org = (Array.isArray(m.organization) ? m.organization[0] : m.organization) as { kind_code: string; name: string } | null;
    return { organization_id: m.organization_id, role_code: m.role_code, kind_code: org?.kind_code ?? '', name: org?.name ?? '' };
  });

  const spaces: Space[] = ['compte', 'espace'];   // tout le monde peut acheter et publier en particulier
  if (memberships.some((m) => m.kind_code === 'agence' || m.kind_code === 'promoteur')) spaces.push('pro');
  if (staffRoles.length) spaces.push('admin');

  return { id, email: profile.data?.email ?? null, fullName: profile.data?.full_name ?? null, staffRoles, memberships, spaces };
});

/** À appeler en tête de chaque layout d'espace. La base refait le contrôle (RLS). */
export async function requireSpace(space: Space, path: string) {
  const viewer = await getViewer();
  if (!viewer) redirect(`/connexion?next=${encodeURIComponent(path)}`);
  if (!viewer.spaces.includes(space)) forbidden();
  return viewer;
}

export function hasStaffRole(viewer: Viewer, roles?: StaffRole[]) {
  if (!roles?.length) return viewer.staffRoles.length > 0;
  return viewer.staffRoles.includes('super_admin') || roles.some((r) => viewer.staffRoles.includes(r));
}

export const proOrg = (v: Viewer) => v.memberships.find((m) => m.kind_code === 'agence' || m.kind_code === 'promoteur');
export const personalOrg = (v: Viewer) => v.memberships.find((m) => m.kind_code === 'particulier');
