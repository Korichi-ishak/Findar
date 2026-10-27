-- =====================================================================
-- Findar · données de référence et réglages
-- Rejouable à volonté :
--   * référentiels : libellés et meta mis à jour depuis ce fichier,
--     mais active / sort réglés depuis le back-office sont conservés ;
--   * réglages (app_setting) : jamais écrasés s'ils existent déjà.
-- =====================================================================

create or replace function pg_temp.lbl(fr text, ar text default null, en text default null) returns jsonb
language sql immutable as $$ select jsonb_strip_nulls(jsonb_build_object('fr', fr, 'ar', ar, 'en', en)) $$;

-- Insère / met à jour une ligne de référence.
create or replace function pg_temp.ref(tbl text, code text, label jsonb, sort int, meta jsonb default '{}') returns void
language plpgsql as $$
begin
  execute format('insert into public.%I (code, label, sort, meta) values ($1, $2, $3, $4)
                  on conflict (code) do update set label = excluded.label, meta = excluded.meta', tbl)
  using code, label, sort, meta;
end $$;

-- ---------- catégories et types ----------
select pg_temp.ref('ref_category', c, pg_temp.lbl(fr, ar, en), s) from (values
  ('vente', 'Acheter', 'شراء', 'Buy', 10),
  ('location', 'Louer', 'كراء', 'Rent', 20),
  ('location_vacances', 'Location vacances', 'كراء موسمي', 'Holiday rental', 30),
  ('neuf', 'Neuf', 'جديد', 'New build', 40),
  ('terrain', 'Terrain', 'أرض', 'Land', 50),
  ('local_pro', 'Local / bureau', 'محل / مكتب', 'Commercial', 60)
) v(c, fr, ar, en, s);

select pg_temp.ref('ref_property_type', c, pg_temp.lbl(fr, ar, en), s, jsonb_build_object('categories', cats)) from (values
  ('appartement', 'Appartement', 'شقة', 'Apartment', 10, '["vente","location","location_vacances","neuf"]'::jsonb),
  ('villa', 'Villa', 'فيلا', 'Villa', 20, '["vente","location","location_vacances","neuf"]'),
  ('niveau_villa', 'Niveau de villa', 'طابق فيلا', 'Villa floor', 30, '["vente","location","location_vacances"]'),
  ('duplex', 'Duplex', 'دوبلكس', 'Duplex', 40, '["vente","location","neuf"]'),
  ('studio', 'Studio', 'استوديو', 'Studio', 50, '["vente","location","location_vacances"]'),
  ('carcasse', 'Carcasse', 'هيكل', 'Shell', 60, '["vente"]'),
  ('terrain', 'Terrain', 'أرض', 'Land', 70, '["terrain"]'),
  ('local', 'Local commercial', 'محل تجاري', 'Shop', 80, '["local_pro"]'),
  ('bureau', 'Bureau', 'مكتب', 'Office', 90, '["local_pro"]'),
  ('hangar', 'Hangar / entrepôt', 'مستودع', 'Warehouse', 100, '["local_pro"]'),
  ('immeuble', 'Immeuble', 'عمارة', 'Building', 110, '["vente"]')
) v(c, fr, ar, en, s, cats);

-- ---------- statuts d'annonce ----------
-- public : visible dans la recherche · contact : on peut demander une visite
-- counts_quota : compte dans la limite d'annonces actives
select pg_temp.ref('ref_listing_status', c, pg_temp.lbl(fr, ar, en), s,
  jsonb_build_object('public', pub, 'contact', con, 'counts_quota', q, 'owner_can_set', own)) from (values
  ('brouillon', 'Brouillon', 'مسودة', 'Draft', 10, false, false, false, true),
  ('en_verification', 'En vérification', 'قيد التحقق', 'Under review', 20, false, false, true, true),
  ('verification_bien', 'Vérification du bien', 'معاينة العقار', 'Property check', 30, false, false, true, false),
  ('a_corriger', 'À corriger', 'للتصحيح', 'Needs changes', 40, false, false, true, false),
  ('disponible', 'Disponible', 'متاح', 'Available', 50, true, true, true, false),
  ('reservee', 'Réservée', 'محجوز', 'Reserved', 60, true, false, true, false),
  ('compromis_signe', 'Compromis signé', 'وعد بالبيع موقع', 'Under contract', 70, false, false, true, false),
  ('vendue_findar', 'Vendue / louée via Findar', 'بيع / كراء عبر Findar', 'Closed via Findar', 80, false, false, false, false),
  ('vendue_ailleurs', 'Vendue ailleurs', 'بيع خارج المنصة', 'Closed elsewhere', 90, false, false, false, false),
  ('retiree', 'Retirée', 'مسحوب', 'Withdrawn', 100, false, false, false, true),
  ('suspendue', 'Suspendue', 'معلق', 'Suspended', 110, false, false, false, false)
) v(c, fr, ar, en, s, pub, con, q, own);

-- ---------- organisations et rôles ----------
select pg_temp.ref('ref_org_kind', c, pg_temp.lbl(fr, ar, en), s) from (values
  ('particulier', 'Particulier', 'خاص', 'Private seller', 10),
  ('agence', 'Agence immobilière', 'وكالة عقارية', 'Agency', 20),
  ('promoteur', 'Promoteur', 'مرقي عقاري', 'Developer', 30)
) v(c, fr, ar, en, s);

select pg_temp.ref('ref_member_role', c, pg_temp.lbl(fr, ar, en), s, jsonb_build_object('permissions', p)) from (values
  ('directeur', 'Directeur', 'مدير', 'Director', 10, '["*"]'::jsonb),
  ('agent', 'Agent', 'وكيل', 'Agent', 20, '["listings.write","inbox","visits","agenda"]'),
  ('assistant', 'Assistant', 'مساعد', 'Assistant', 30, '["inbox","visits","agenda"]')
) v(c, fr, ar, en, s, p);

select pg_temp.ref('ref_staff_role', c, pg_temp.lbl(fr, ar, en), s) from (values
  ('verificateur', 'Vérificateur', 'مدقق', 'Verifier', 10),
  ('photographe', 'Photographe 360', 'مصور 360', '360 photographer', 20),
  ('moderateur', 'Modérateur', 'مشرف', 'Moderator', 30),
  ('commercial', 'Commercial', 'تجاري', 'Sales', 40),
  ('comptabilite', 'Comptabilité', 'محاسبة', 'Accounting', 50),
  ('super_admin', 'Super-admin', 'مدير عام', 'Super admin', 60)
) v(c, fr, ar, en, s);

-- ---------- vérification ----------
select pg_temp.ref('ref_document_type', c, pg_temp.lbl(fr, ar, en), s, jsonb_build_object('for', f, 'required', r)) from (values
  ('piece_identite', 'Pièce d''identité', 'بطاقة التعريف', 'ID', 10, '["particulier"]'::jsonb, true),
  ('acte_propriete', 'Acte de propriété / livret foncier', 'عقد الملكية / الدفتر العقاري', 'Title deed', 20, '["particulier"]', true),
  ('fredha', 'Frédha + accord des cohéritiers', 'الفريضة + موافقة الورثة', 'Inheritance deed + heirs'' consent', 30, '["particulier"]', false),
  ('procuration', 'Procuration', 'وكالة', 'Power of attorney', 40, '["particulier"]', false),
  ('registre_commerce', 'Registre du commerce', 'السجل التجاري', 'Trade register', 50, '["agence","promoteur"]', true),
  ('agrement', 'Agrément d''agence', 'اعتماد الوكالة', 'Agency licence', 60, '["agence"]', true),
  ('mandat', 'Mandat du propriétaire', 'تفويض المالك', 'Owner''s mandate', 70, '["agence"]', true),
  ('permis_construire', 'Permis de construire', 'رخصة البناء', 'Building permit', 80, '["promoteur"]', true)
) v(c, fr, ar, en, s, f, r);

select pg_temp.ref('ref_verification_method', c, pg_temp.lbl(fr, ar, en), s, m) from (values
  ('visite_360', 'Visite 360° Findar', 'جولة 360 من Findar', 'Findar 360 tour', 10, '{"badge":"Vérifié 360°","paid_for":["particulier"]}'::jsonb),
  ('visio', 'Appel vidéo avec un agent', 'مكالمة فيديو مع وكيل', 'Video call with an agent', 20, '{"badge":"Vérifié en visio","tool":"zoom","recording":false}'),
  ('documents', 'Documents seuls', 'وثائق فقط', 'Documents only', 30, '{"badge":null,"for":["organization"]}')
) v(c, fr, ar, en, s, m);

select pg_temp.ref('ref_verification_outcome', c, pg_temp.lbl(fr, ar, en), s) from (values
  ('conforme', 'Conforme', 'مطابق', 'Matches', 10),
  ('ecarts_mineurs', 'Écarts mineurs corrigés', 'فروقات بسيطة', 'Minor differences', 20),
  ('non_conforme', 'Non conforme', 'غير مطابق', 'Does not match', 30),
  ('absent', 'Annonceur absent', 'غياب المعلن', 'No-show', 40),
  ('a_replanifier', 'À replanifier', 'إعادة البرمجة', 'Reschedule', 50)
) v(c, fr, ar, en, s);

-- ---------- étapes du dossier : qui confirme (both | one | auto) ----------
select pg_temp.ref('ref_dossier_step', c, pg_temp.lbl(fr, ar, en), s, m) from (values
  ('contact', 'Demande de contact', 'طلب تواصل', 'Contact request', 10, '{"policy":"auto"}'::jsonb),
  ('visite_demandee', 'Visite proposée', 'زيارة مقترحة', 'Visit proposed', 20, '{"policy":"both","expires_hours":24}'),
  ('visite_confirmee', 'Visite confirmée', 'زيارة مؤكدة', 'Visit confirmed', 30, '{"policy":"both"}'),
  ('visite_faite', 'Visite faite', 'تمت الزيارة', 'Visit done', 40, '{"policy":"both"}'),
  ('questionnaire', 'Questionnaire après visite', 'استبيان بعد الزيارة', 'After-visit survey', 50, '{"policy":"both","after_hours":24}'),
  ('offre', 'Offre', 'عرض', 'Offer', 60, '{"policy":"both","binding":false}'),
  ('reservation', 'Réservation', 'حجز', 'Reservation', 70, '{"policy":"both","confirmed_by_findar_call":true}'),
  ('compromis', 'Compromis', 'وعد بالبيع', 'Preliminary contract', 80, '{"policy":"both","confirmed_by_findar_call":true}'),
  ('conclu', 'Conclu', 'منتهية', 'Closed', 90, '{"policy":"both","confirmed_by_findar_call":true}')
) v(c, fr, ar, en, s, m);

select pg_temp.ref('ref_questionnaire_answer', c, pg_temp.lbl(fr, ar, en), s, jsonb_build_object('side', side)) from (values
  ('interesse', 'Toujours intéressé', 'ما زلت مهتما', 'Still interested', 10, 'buyer'),
  ('offre_prevue', 'Je vais faire une offre', 'سأقدم عرضا', 'Will make an offer', 20, 'buyer'),
  ('pas_interesse', 'Pas intéressé', 'غير مهتم', 'Not interested', 30, 'buyer'),
  ('non_venu_vendeur', 'L''annonceur n''était pas là', 'المعلن لم يحضر', 'Seller no-show', 40, 'buyer'),
  ('toujours_dispo', 'Bien toujours disponible', 'العقار ما زال متاحا', 'Still available', 50, 'seller'),
  ('accord_en_cours', 'Accord en cours', 'اتفاق قيد الإنجاز', 'Deal in progress', 60, 'seller'),
  ('vendu_ailleurs', 'Vendu / loué ailleurs', 'بيع خارج المنصة', 'Closed elsewhere', 70, 'seller'),
  ('non_venu_acheteur', 'Le visiteur n''est pas venu', 'الزائر لم يحضر', 'Buyer no-show', 80, 'seller')
) v(c, fr, ar, en, s, side);

-- ---------- proximité ----------
select pg_temp.ref('ref_poi_kind', c, pg_temp.lbl(fr, ar, en), s, jsonb_build_object('google_types', g, 'default_max_m', d)) from (values
  ('ecole', 'École', 'مدرسة', 'School', 10, '["school","primary_school","secondary_school"]'::jsonb, 800),
  ('mosquee', 'Mosquée', 'مسجد', 'Mosque', 20, '["mosque"]', 500),
  ('plage', 'Plage', 'شاطئ', 'Beach', 30, '["beach"]', 2000),
  ('transport', 'Transport (métro, tram, bus)', 'نقل', 'Transit', 40, '["subway_station","light_rail_station","bus_station","train_station"]', 600),
  ('marche', 'Marché / supérette', 'سوق', 'Market', 50, '["supermarket","grocery_store","market"]', 500),
  ('sante', 'Santé (pharmacie, clinique)', 'صحة', 'Health', 60, '["pharmacy","hospital","doctor"]', 800),
  ('universite', 'Université', 'جامعة', 'University', 70, '["university"]', 2000),
  ('parc', 'Parc / espace vert', 'حديقة', 'Park', 80, '["park"]', 800)
) v(c, fr, ar, en, s, g, d);

select pg_temp.ref('ref_report_reason', c, pg_temp.lbl(fr, ar, en), s) from (values
  ('fausse_annonce', 'Annonce fausse ou déjà vendue', 'إعلان مزيف أو مباع', 'Fake or sold', 10),
  ('prix_trompeur', 'Prix trompeur', 'سعر مضلل', 'Misleading price', 20),
  ('demande_argent', 'Demande d''argent avant visite', 'طلب مال قبل الزيارة', 'Asked for money before visit', 30),
  ('contact_externe', 'Pousse à contacter hors Findar', 'يدفع للتواصل خارج المنصة', 'Pushes off-platform contact', 40),
  ('comportement', 'Comportement inapproprié', 'سلوك غير لائق', 'Inappropriate behaviour', 50),
  ('photos', 'Photos ne correspondant pas', 'صور غير مطابقة', 'Photos do not match', 60),
  ('autre', 'Autre', 'أخرى', 'Other', 99)
) v(c, fr, ar, en, s);

-- ---------- attributs (équipements, papiers, détails) ----------
insert into public.ref_attribute (code, label, value_type, options, categories, group_code, filterable, sort) values
  ('papiers', pg_temp.lbl('Papiers', 'الوثائق', 'Paperwork'), 'choice',
     '[{"code":"acte","label":{"fr":"Acte notarié","ar":"عقد موثق"}},{"code":"livret_foncier","label":{"fr":"Livret foncier","ar":"دفتر عقاري"}},{"code":"decision","label":{"fr":"Décision","ar":"قرار"}},{"code":"acte_sous_seing","label":{"fr":"Acte sous seing privé","ar":"عقد عرفي"}},{"code":"fredha","label":{"fr":"Frédha","ar":"فريضة"}}]',
     '{vente,terrain,local_pro}', 'papiers', true, 10),
  ('promesse_vente', pg_temp.lbl('Promesse de vente possible', 'وعد بالبيع ممكن'), 'bool', null, '{vente}', 'papiers', true, 20),
  ('credit_possible', pg_temp.lbl('Éligible au crédit', 'قابل للقرض', 'Mortgage eligible'), 'bool', null, '{vente,neuf}', 'papiers', true, 30),
  ('ascenseur', pg_temp.lbl('Ascenseur', 'مصعد', 'Lift'), 'bool', null, '{}', 'immeuble', true, 40),
  ('parking', pg_temp.lbl('Parking / garage', 'موقف / مرآب', 'Parking'), 'bool', null, '{}', 'immeuble', true, 50),
  ('gardien', pg_temp.lbl('Gardien / résidence fermée', 'حارس / إقامة مغلقة', 'Gated / caretaker'), 'bool', null, '{}', 'immeuble', true, 60),
  ('citerne', pg_temp.lbl('Citerne / bâche à eau', 'خزان ماء', 'Water tank'), 'bool', null, '{}', 'equipement', true, 70),
  ('gaz_ville', pg_temp.lbl('Gaz de ville', 'غاز المدينة', 'Mains gas'), 'bool', null, '{}', 'equipement', true, 80),
  ('chauffage', pg_temp.lbl('Chauffage central', 'تدفئة مركزية', 'Central heating'), 'bool', null, '{}', 'equipement', true, 90),
  ('climatisation', pg_temp.lbl('Climatisation', 'تكييف', 'Air conditioning'), 'bool', null, '{}', 'equipement', true, 100),
  ('meuble', pg_temp.lbl('Meublé', 'مفروش', 'Furnished'), 'bool', null, '{location,location_vacances}', 'location', true, 110),
  ('vue_mer', pg_temp.lbl('Vue sur mer', 'إطلالة على البحر', 'Sea view'), 'bool', null, '{}', 'detail', true, 120),
  ('balcon', pg_temp.lbl('Balcon / terrasse', 'شرفة', 'Balcony / terrace'), 'bool', null, '{}', 'detail', true, 130),
  ('jardin', pg_temp.lbl('Jardin', 'حديقة', 'Garden'), 'bool', null, '{}', 'detail', true, 140),
  ('piscine', pg_temp.lbl('Piscine', 'مسبح', 'Pool'), 'bool', null, '{}', 'detail', true, 150),
  ('orientation', pg_temp.lbl('Orientation', 'الاتجاه', 'Facing'), 'choice',
     '[{"code":"nord","label":{"fr":"Nord"}},{"code":"sud","label":{"fr":"Sud"}},{"code":"est","label":{"fr":"Est"}},{"code":"ouest","label":{"fr":"Ouest"}}]',
     '{}', 'detail', false, 160),
  ('etat', pg_temp.lbl('État', 'الحالة', 'Condition'), 'choice',
     '[{"code":"neuf","label":{"fr":"Neuf"}},{"code":"bon","label":{"fr":"Bon état"}},{"code":"a_rafraichir","label":{"fr":"À rafraîchir"}},{"code":"a_renover","label":{"fr":"À rénover"}}]',
     '{}', 'detail', true, 170),
  ('famille_uniquement', pg_temp.lbl('Famille uniquement', 'للعائلات فقط', 'Families only'), 'bool', null, '{location,location_vacances}', 'location', true, 180),
  ('facade', pg_temp.lbl('Façade (m)', 'الواجهة (م)', 'Frontage (m)'), 'number', null, '{terrain,local_pro}', 'detail', false, 190)
on conflict (code) do update set label = excluded.label, options = excluded.options, categories = excluded.categories,
  group_code = excluded.group_code;

-- ---------- géographie : wilaya 16 et ses 57 communes ----------
insert into public.wilaya (code, label) values ('16', pg_temp.lbl('Alger', 'الجزائر', 'Algiers'))
on conflict (code) do update set label = excluded.label;

insert into public.commune (wilaya_code, slug, label, lat, lng, meta)
select '16', slug, pg_temp.lbl(fr, ar), lat, lng, case when pilot then '{"pilot_candidate": true}'::jsonb else '{}'::jsonb end
from (values
  ('alger-centre', 'Alger-Centre', 'الجزائر الوسطى', null::float8, null::float8, false),
  ('sidi-mhamed', 'Sidi M''Hamed', 'سيدي امحمد', null, null, false),
  ('el-madania', 'El Madania', 'المدنية', null, null, false),
  ('belouizdad', 'Belouizdad', 'بلوزداد', null, null, false),
  ('bab-el-oued', 'Bab El Oued', 'باب الوادي', null, null, false),
  ('bologhine', 'Bologhine', 'بولوغين', null, null, false),
  ('casbah', 'Casbah', 'القصبة', null, null, false),
  ('oued-koriche', 'Oued Koriche', 'وادي قريش', null, null, false),
  ('bir-mourad-rais', 'Bir Mourad Raïs', 'بئر مراد رايس', null, null, false),
  ('el-biar', 'El Biar', 'الأبيار', 36.7690, 3.0310, true),
  ('bouzareah', 'Bouzaréah', 'بوزريعة', null, null, false),
  ('birkhadem', 'Birkhadem', 'بئر خادم', null, null, false),
  ('el-harrach', 'El Harrach', 'الحراش', null, null, false),
  ('baraki', 'Baraki', 'براقي', null, null, false),
  ('oued-smar', 'Oued Smar', 'وادي السمار', null, null, false),
  ('bourouba', 'Bourouba', 'بوروبة', null, null, false),
  ('hussein-dey', 'Hussein Dey', 'حسين داي', null, null, false),
  ('kouba', 'Kouba', 'القبة', 36.7270, 3.0850, true),
  ('bachdjerrah', 'Bachdjerrah', 'باش جراح', null, null, false),
  ('dar-el-beida', 'Dar El Beïda', 'الدار البيضاء', null, null, false),
  ('bab-ezzouar', 'Bab Ezzouar', 'باب الزوار', 36.7210, 3.1830, true),
  ('ben-aknoun', 'Ben Aknoun', 'بن عكنون', 36.7580, 3.0110, true),
  ('dely-ibrahim', 'Dely Ibrahim', 'دالي إبراهيم', 36.7530, 2.9840, true),
  ('el-hammamet', 'El Hammamet', 'الحمامات', null, null, false),
  ('rais-hamidou', 'Raïs Hamidou', 'الرايس حميدو', null, null, false),
  ('djasr-kasentina', 'Djasr Kasentina', 'جسر قسنطينة', null, null, false),
  ('el-mouradia', 'El Mouradia', 'المرادية', null, null, false),
  ('hydra', 'Hydra', 'حيدرة', 36.7440, 3.0360, true),
  ('mohammadia', 'Mohammadia', 'المحمدية', null, null, false),
  ('bordj-el-kiffan', 'Bordj El Kiffan', 'برج الكيفان', 36.7480, 3.1930, true),
  ('el-magharia', 'El Magharia', 'المقارية', null, null, false),
  ('beni-messous', 'Beni Messous', 'بني مسوس', null, null, false),
  ('les-eucalyptus', 'Les Eucalyptus', 'الكاليتوس', null, null, false),
  ('birtouta', 'Birtouta', 'بئر توتة', null, null, false),
  ('tessala-el-merdja', 'Tessala El Merdja', 'تسالة المرجة', null, null, false),
  ('ouled-chebel', 'Ouled Chebel', 'أولاد شبل', null, null, false),
  ('sidi-moussa', 'Sidi Moussa', 'سيدي موسى', null, null, false),
  ('ain-taya', 'Aïn Taya', 'عين طاية', null, null, false),
  ('bordj-el-bahri', 'Bordj El Bahri', 'برج البحري', null, null, false),
  ('el-marsa', 'El Marsa', 'المرسى', null, null, false),
  ('hraoua', 'H''raoua', 'هراوة', null, null, false),
  ('rouiba', 'Rouïba', 'الرويبة', null, null, false),
  ('reghaia', 'Réghaïa', 'الرغاية', null, null, false),
  ('ain-benian', 'Aïn Benian', 'عين البنيان', null, null, false),
  ('staoueli', 'Staouéli', 'سطاوالي', null, null, false),
  ('zeralda', 'Zéralda', 'زرالدة', null, null, false),
  ('mahelma', 'Mahelma', 'المعالمة', null, null, false),
  ('rahmania', 'Rahmania', 'الرحمانية', null, null, false),
  ('souidania', 'Souidania', 'السويدانية', null, null, false),
  ('cheraga', 'Chéraga', 'الشراقة', 36.7670, 2.9590, true),
  ('ouled-fayet', 'Ouled Fayet', 'أولاد فايت', null, null, false),
  ('el-achour', 'El Achour', 'العاشور', null, null, false),
  ('draria', 'Draria', 'الدرارية', null, null, false),
  ('douera', 'Douéra', 'الدويرة', null, null, false),
  ('baba-hassen', 'Baba Hassen', 'بابا حسن', null, null, false),
  ('khraicia', 'Khraïcia', 'خرايسية', null, null, false),
  ('saoula', 'Saoula', 'السحاولة', null, null, false)
) v(slug, fr, ar, lat, lng, pilot)
on conflict (slug) do update set label = excluded.label,
  lat = coalesce(public.commune.lat, excluded.lat), lng = coalesce(public.commune.lng, excluded.lng);

-- ---------- formules (prix encore à fixer : null) ----------
insert into public.plan (code, label, org_kinds, price_dzd, period, quotas, sort, meta) values
  ('essentiel', pg_temp.lbl('Essentiel', 'أساسي', 'Essential'), '{agence}', null, 'mois', '{}', 10, '{"to_decide": true}'),
  ('pro', pg_temp.lbl('Pro', 'احترافي', 'Pro'), '{agence}', null, 'mois', '{}', 20, '{"to_decide": true}'),
  ('premium', pg_temp.lbl('Premium', 'مميز', 'Premium'), '{agence}', null, 'mois', '{}', 30, '{"to_decide": true}'),
  ('sur_devis', pg_temp.lbl('Sur devis', 'حسب الطلب', 'Custom'), '{agence,promoteur}', null, 'devis', '{}', 40, '{}'),
  ('tour_360_unite', pg_temp.lbl('Visite 360° à l''unité', 'جولة 360 للوحدة', 'Single 360 tour'), '{particulier}', null, 'unite', '{}', 50, '{"to_decide": true}')
on conflict (code) do update set label = excluded.label, org_kinds = excluded.org_kinds;

-- ---------- réglages (jamais écrasés s'ils existent) ----------
insert into public.app_setting (key, value, description, is_public) values
  ('calendar.weekend_dow', '[5,6]', 'Jours non ouvrés (0 = dimanche). Vendredi et samedi.', false),
  ('verification.sla_working_days', '2', 'Délai de vérification promis (jours ouvrés).', true),
  ('verification.delete_documents_on_decision', 'true', 'Les pièces sont supprimées dès la décision (ne pas désactiver sans avis juridique).', false),
  ('listing.reverify_price_change_pct', '20', 'Écart de prix (%) qui demande une reconfirmation par un agent.', false),
  ('listing.reverify_on_material_change', 'true', 'Le badge tombe si surface, pièces, étage ou type changent.', false),
  ('listing.inactivity_days', '30', 'Jours sans activité avant de demander à l''annonceur.', false),
  ('listing.inactivity_grace_days', '7', 'Jours pour répondre avant que l''annonce soit masquée.', false),
  ('listing.inactivity_hide_status', '"suspendue"', 'Statut appliqué quand l''annonceur ne répond pas.', false),
  ('quota.particulier.active_listings', '2', 'Annonces actives max pour un particulier.', true),
  ('visit.address_release_hours_before', '24', 'L''adresse exacte est donnée X heures avant la visite confirmée.', true),
  ('map.blur_radius_m', '150', 'Rayon de floutage de la position publique (mètres).', true),
  ('status.call_after_visit_hours', '48', 'Appel Findar après une visite.', false),
  ('status.call_after_reservation_days', '15', 'Appel Findar après une réservation.', false),
  ('status.questionnaire_after_hours', '24', 'Questionnaire envoyé après la visite.', false),
  ('reminders.sms_hours', '2', 'Relance SMS si pas de réponse (heures).', false),
  ('reminders.call_hours', '24', 'Appel d''un agent si pas de réponse (heures).', false),
  ('reminders.close_hours', '48', 'Fermeture + 3 annonces similaires si pas de réponse (heures).', false),
  ('notifications.max_per_day', '3', 'Notifications max par jour et par personne (hors sécurité).', false),
  ('messages.retention_months', '12', 'Durée de conservation des conversations.', false),
  ('moderation.message_patterns', '{"phone": "(\\+?213|0)[\\s.-]*[5-7]([\\s.-]*[0-9]){8}", "money": "(ccp|baridi ?mob|rip|rib|versement|acompte|avance|arrhes)", "external_contact": "(whats ?app|viber|telegram|messenger|instagram|snap|facebook|gmail|@[a-z0-9-]+\\.[a-z]{2,})"}',
     'Motifs qui envoient un message en modération (regex, insensible à la casse).', false),
  ('estimate.min_comparables', '8', 'Comparables minimum pour afficher une estimation.', true),
  ('estimate.max_error_pct', '15', 'Précision testée maximale pour afficher une fourchette (%).', true),
  ('insights.min_sample', '5', 'Taille minimum d''un groupe pour publier une moyenne (k-anonymat).', true),
  ('commune.open_threshold', '30', 'Annonces vérifiées pour ouvrir une commune au public.', true),
  ('commune.gate_enabled', 'true', 'Ne montrer que les communes ouvertes (false pendant les tests).', false),
  ('price.input_units', '["DA", "centimes"]', 'Unités proposées à la saisie (unité obligatoire). Stockage toujours en DA.', true),
  ('locales', '["fr", "ar", "en"]', 'Langues disponibles.', true)
on conflict (key) do nothing;
