import 'server-only';
import { forbidden } from 'next/navigation';
import { getViewer, hasStaffRole } from '@/lib/session';
import type { StaffRole } from '@/lib/routes';

/** Garde de page du back-office. La base refait le contrôle à chaque requête. */
export async function requireStaff(roles?: StaffRole[]) {
  const viewer = await getViewer();
  if (!viewer || !hasStaffRole(viewer, roles)) forbidden();
  return viewer;
}
