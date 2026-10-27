'use server';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

export async function createProOrganization(fd: FormData) {
  const supabase = await createClient();
  const { error } = await supabase.rpc('create_pro_organization', {
    p_kind: String(fd.get('kind')), p_name: String(fd.get('name')), p_commune: String(fd.get('commune') ?? '') || null,
  });
  if (error) throw new Error(error.message);
  redirect('/pro');
}
