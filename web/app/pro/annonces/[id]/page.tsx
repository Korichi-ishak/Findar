import { ListingManage } from '@/components/ListingManage';

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  return <ListingManage id={(await params).id} back="/pro" />;
}
