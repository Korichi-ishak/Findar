import { ListingForm } from '@/components/ListingForm';
import { PageHead } from '@/components/Notice';

export default function Page() {
  return (<><PageHead title="Déposer une annonce" /><ListingForm back="/espace" /></>);
}
