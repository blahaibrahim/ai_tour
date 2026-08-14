-- Route generation seed — three pilot cities, 35 published POIs.
--
-- GENERATED from backend/routing_tourAI-main/src/data/fixtures/*.fixture.ts.
-- Coordinates, dwell times and checkpoint radii are the reference module's
-- hand-authored fixture data, promoted to real rows: the pois table was
-- empty, so every route the app has ever shown was invented (REMAINING.md
-- §0). Descriptions and photos are deliberately left null — they are
-- backfilled by the ingestion pipeline, which sources them with licence and
-- attribution rather than having them typed in here.
--
-- Idempotent: re-running updates in place rather than duplicating.

-- regions ------------------------------------------------------------------
insert into public.regions (id, name, name_ar) values
  ('00000000-0000-4000-a000-000000000001', 'Alger', 'الجزائر'),
  ('00000000-0000-4000-a000-000000000002', 'Oran', 'وهران'),
  ('00000000-0000-4000-a000-000000000003', 'Constantine', 'قسنطينة')
on conflict (id) do update set name = excluded.name, name_ar = excluded.name_ar;

-- categories ---------------------------------------------------------------
insert into public.categories (id, key, label_en, label_fr, label_ar, icon_ref, color_hex) values
  ('00000000-0000-4000-b000-000000000001', 'historical_monument', 'Historical monuments', 'Monuments historiques', 'معالم تاريخية', 'landmark', '#8B6F47'),
  ('00000000-0000-4000-b000-000000000002', 'museum', 'Museums', 'Musées', 'متاحف', 'museum', '#5B7C99'),
  ('00000000-0000-4000-b000-000000000003', 'park_garden', 'Parks & gardens', 'Parcs et jardins', 'حدائق', 'park', '#4C8C5A'),
  ('00000000-0000-4000-b000-000000000004', 'religious_site', 'Religious sites', 'Sites religieux', 'مواقع دينية', 'mosque', '#2E7D6F'),
  ('00000000-0000-4000-b000-000000000005', 'viewpoint', 'Viewpoints', 'Points de vue', 'إطلالات', 'panorama', '#C98A3C'),
  ('00000000-0000-4000-b000-000000000006', 'cultural_venue', 'Cultural venues', 'Lieux culturels', 'أماكن ثقافية', 'theater', '#9B5D8A'),
  ('00000000-0000-4000-b000-000000000007', 'beach', 'Beaches', 'Plages', 'شواطئ', 'beach', '#3E8EA6')
on conflict (id) do update set
  key = excluded.key, label_en = excluded.label_en, label_fr = excluded.label_fr,
  label_ar = excluded.label_ar, icon_ref = excluded.icon_ref, color_hex = excluded.color_hex;

-- cities -------------------------------------------------------------------
-- bounding_box is derived from the extent of each city's own POIs, padded a
-- little. cities_config() takes its centroid, and that centroid is what the
-- app centres its map on — a null box leaves the map pointed at (0,0).
insert into public.cities (
  id, region_id, name, name_ar, name_fr, bounding_box,
  cluster_radius_meters, active_routing_provider, rollout_status
) values (
  '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-a000-000000000001', 'Algiers', 'الجزائر', 'Alger',
  st_geogfromtext('SRID=4326;POLYGON((3.032000 36.737000, 3.093000 36.737000, 3.093000 36.799000, 3.032000 36.799000, 3.032000 36.737000))'),
  500, 'graphhopper'::routing_provider, 'pilot'::rollout_status
)
on conflict (id) do update set
  region_id = excluded.region_id, name = excluded.name, name_ar = excluded.name_ar,
  name_fr = excluded.name_fr, bounding_box = excluded.bounding_box,
  cluster_radius_meters = excluded.cluster_radius_meters,
  active_routing_provider = excluded.active_routing_provider,
  rollout_status = excluded.rollout_status, deleted_at = null, updated_at = now();

insert into public.cities (
  id, region_id, name, name_ar, name_fr, bounding_box,
  cluster_radius_meters, active_routing_provider, rollout_status
) values (
  '00000000-0000-4000-a000-000000000020', '00000000-0000-4000-a000-000000000002', 'Oran', 'وهران', 'Oran',
  st_geogfromtext('SRID=4326;POLYGON((-0.670000 35.685000, -0.619000 35.685000, -0.619000 35.720000, -0.670000 35.720000, -0.670000 35.685000))'),
  600, 'graphhopper'::routing_provider, 'pilot'::rollout_status
)
on conflict (id) do update set
  region_id = excluded.region_id, name = excluded.name, name_ar = excluded.name_ar,
  name_fr = excluded.name_fr, bounding_box = excluded.bounding_box,
  cluster_radius_meters = excluded.cluster_radius_meters,
  active_routing_provider = excluded.active_routing_provider,
  rollout_status = excluded.rollout_status, deleted_at = null, updated_at = now();

insert into public.cities (
  id, region_id, name, name_ar, name_fr, bounding_box,
  cluster_radius_meters, active_routing_provider, rollout_status
) values (
  '00000000-0000-4000-a000-000000000030', '00000000-0000-4000-a000-000000000003', 'Constantine', 'قسنطينة', 'Constantine',
  st_geogfromtext('SRID=4326;POLYGON((6.545000 36.330000, 6.635000 36.330000, 6.635000 36.430000, 6.545000 36.430000, 6.545000 36.330000))'),
  400, 'graphhopper'::routing_provider, 'pilot'::rollout_status
)
on conflict (id) do update set
  region_id = excluded.region_id, name = excluded.name, name_ar = excluded.name_ar,
  name_fr = excluded.name_fr, bounding_box = excluded.bounding_box,
  cluster_radius_meters = excluded.cluster_radius_meters,
  active_routing_provider = excluded.active_routing_provider,
  rollout_status = excluded.rollout_status, deleted_at = null, updated_at = now();

-- themes -------------------------------------------------------------------
insert into public.themes (key, label_en, label_fr, label_ar, sort_order) values
  ('history', 'History', 'Histoire', 'تاريخ', 1),
  ('culture', 'Culture', 'Culture', 'ثقافة', 2),
  ('nature', 'Nature', 'Nature', 'طبيعة', 3),
  ('all', 'A bit of everything', 'Un peu de tout', 'قليل من كل شيء', 9)
on conflict (key) do update set
  label_en = excluded.label_en, label_fr = excluded.label_fr,
  label_ar = excluded.label_ar, sort_order = excluded.sort_order, is_active = true;

-- Global scope (city_id null): these mappings hold in every city until one
-- of them needs its own, at which point its rows replace the global set.
insert into public.theme_categories (theme_id, category_id, city_id)
select t.id, c.id, null
from (values
  ('history', 'historical_monument'),
  ('history', 'religious_site'),
  ('history', 'museum'),
  ('culture', 'museum'),
  ('culture', 'cultural_venue'),
  ('culture', 'religious_site'),
  ('nature', 'park_garden'),
  ('nature', 'viewpoint'),
  ('nature', 'beach'),
  ('all', 'historical_monument'),
  ('all', 'museum'),
  ('all', 'park_garden'),
  ('all', 'religious_site'),
  ('all', 'viewpoint'),
  ('all', 'cultural_venue'),
  ('all', 'beach')
) as m(theme_key, category_key)
join public.themes t on t.key = m.theme_key
join public.categories c on c.key = m.category_key
on conflict (theme_id, category_id, coalesce(city_id, '00000000-0000-0000-0000-000000000000'::uuid)) do nothing;

-- pois ---------------------------------------------------------------------
-- status = published: only published POIs are ever eligible for a route
-- (spec §10), and these are hand-authored rather than Overpass-derived, so
-- they are team_seeded and need no review pass.
insert into public.pois (
  id, city_id, category_id, name_en, name_fr, name_ar, location,
  opening_hours_raw, avg_visit_duration_minutes, checkpoint_radius_meters,
  external_ref, source, status
) values
  ('00000000-0000-4000-c000-000000000001', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000001', 'Casbah of Algiers', 'Casbah d''Alger', 'قصبة الجزائر',
   st_geogfromtext('SRID=4326;POINT(3.0588 36.7853)'),
   'Mo-Su 08:00-18:00', 45, 40,
   'fixture:00000000-0000-4000-c000-000000000001', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-c000-000000000008', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000001', 'Bastion 23', 'Palais des Raïs', 'قصر الرياس',
   st_geogfromtext('SRID=4326;POINT(3.056 36.787)'),
   'Mo-Su 09:00-16:30', 25, 30,
   'fixture:00000000-0000-4000-c000-000000000008', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-c000-000000000009', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000004', 'Ketchaoua Mosque', 'Mosquée Ketchaoua', 'مسجد كتشاوة',
   st_geogfromtext('SRID=4326;POINT(3.0607 36.7862)'),
   'Mo-Su 08:00-20:00', 20, 30,
   'fixture:00000000-0000-4000-c000-000000000009', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-c000-000000000010', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000001', 'Place des Martyrs', 'Place des Martyrs', 'ساحة الشهداء',
   st_geogfromtext('SRID=4326;POINT(3.0603 36.7846)'),
   null, 15, 35,
   'fixture:00000000-0000-4000-c000-000000000010', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-c000-000000000002', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000001', 'Martyrs'' Memorial', 'Maqam Echahid', 'مقام الشهيد',
   st_geogfromtext('SRID=4326;POINT(3.071 36.747)'),
   'Mo-Su 09:00-17:00', 30, 50,
   'fixture:00000000-0000-4000-c000-000000000002', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-c000-000000000003', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000003', 'Jardin d''Essai du Hamma', 'Jardin d''Essai du Hamma', 'حديقة التجارب',
   st_geogfromtext('SRID=4326;POINT(3.076 36.7475)'),
   'Mo-Su 09:00-17:00', 40, 35,
   'fixture:00000000-0000-4000-c000-000000000003', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-c000-000000000006', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000002', 'National Museum of Fine Arts', 'Musée National des Beaux-Arts', 'المتحف الوطني للفنون الجميلة',
   st_geogfromtext('SRID=4326;POINT(3.0715 36.7485)'),
   'Tu-Su 10:00-17:00', 30, 25,
   'fixture:00000000-0000-4000-c000-000000000006', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-c000-000000000004', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000004', 'Great Mosque of Algiers (Djamaa el Djazaïr)', 'Grande Mosquée d''Alger', 'جامع الجزائر الأعظم',
   st_geogfromtext('SRID=4326;POINT(3.083 36.7605)'),
   'Mo-Su 08:00-20:00', 30, 60,
   'fixture:00000000-0000-4000-c000-000000000004', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-c000-000000000005', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000002', 'Bardo National Museum', 'Musée National du Bardo', 'المتحف الوطني للباردو',
   st_geogfromtext('SRID=4326;POINT(3.051 36.766)'),
   'Tu-Su 10:00-17:00', 35, 25,
   'fixture:00000000-0000-4000-c000-000000000005', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-c000-000000000007', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000005', 'Notre Dame d''Afrique', 'Notre-Dame d''Afrique', 'سيدة أفريقيا',
   st_geogfromtext('SRID=4326;POINT(3.042 36.789)'),
   'Mo-Su 08:00-18:00', 25, 30,
   'fixture:00000000-0000-4000-c000-000000000007', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-c000-000000000011', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000001', 'Monument of the Dead (Pavois)', 'Monument aux Morts', 'نصب الأموات',
   st_geogfromtext('SRID=4326;POINT(3.0505 36.759)'),
   null, 10, 25,
   'fixture:00000000-0000-4000-c000-000000000011', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-c000-000000000012', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000002', 'Museum of Modern Art (MAMA)', 'Musée d''Art Moderne d''Alger (MAMA)', 'متحف الفن الحديث والمعاصر',
   st_geogfromtext('SRID=4326;POINT(3.059 36.7738)'),
   'Tu-Su 10:00-18:00', 30, 25,
   'fixture:00000000-0000-4000-c000-000000000012', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-c000-000000000013', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000003', 'Parc de la Liberté', 'Parc de la Liberté', 'حديقة الحرية',
   st_geogfromtext('SRID=4326;POINT(3.054 36.756)'),
   'Mo-Su 07:00-19:00', 20, 30,
   'fixture:00000000-0000-4000-c000-000000000013', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-c000-000000000014', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000004', 'Great Mosque of Algiers (Historic, Djamaa el Kebir)', 'Grande Mosquée d''Alger (Ancienne)', 'الجامع الكبير',
   st_geogfromtext('SRID=4326;POINT(3.0621 36.7842)'),
   'Mo-Su 06:00-21:00', 20, 25,
   'fixture:00000000-0000-4000-c000-000000000014', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-c000-000000000015', '00000000-0000-4000-a000-000000000010', '00000000-0000-4000-b000-000000000005', 'Balcon Saint-Raphaël Viewpoint', 'Balcon Saint-Raphaël', 'شرفة سان رفائيل',
   st_geogfromtext('SRID=4326;POINT(3.048 36.775)'),
   null, 15, 20,
   'fixture:00000000-0000-4000-c000-000000000015', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-d000-000000000001', '00000000-0000-4000-a000-000000000020', '00000000-0000-4000-b000-000000000001', 'Fort Santa Cruz', 'Fort Santa Cruz', 'حصن سانتا كروز',
   st_geogfromtext('SRID=4326;POINT(-0.656 35.705)'),
   'Mo-Su 09:00-17:00', 40, 50,
   'fixture:00000000-0000-4000-d000-000000000001', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-d000-000000000002', '00000000-0000-4000-a000-000000000020', '00000000-0000-4000-b000-000000000005', 'Santa Cruz Chapel & Viewpoint', 'Chapelle Santa Cruz', 'كنيسة سانتا كروز',
   st_geogfromtext('SRID=4326;POINT(-0.6555 35.7055)'),
   'Mo-Su 08:00-18:00', 20, 30,
   'fixture:00000000-0000-4000-d000-000000000002', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-d000-000000000003', '00000000-0000-4000-a000-000000000020', '00000000-0000-4000-b000-000000000006', 'Sacred Heart Cathedral (Public Library)', 'Cathédrale du Sacré-Cœur (Bibliothèque)', 'المكتبة العمومية (الكاتدرائية)',
   st_geogfromtext('SRID=4326;POINT(-0.634 35.697)'),
   'Tu-Sa 09:00-17:00', 25, 30,
   'fixture:00000000-0000-4000-d000-000000000003', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-d000-000000000004', '00000000-0000-4000-a000-000000000020', '00000000-0000-4000-b000-000000000001', 'Front de Mer Promenade', 'Front de Mer', 'الواجهة البحرية',
   st_geogfromtext('SRID=4326;POINT(-0.643 35.696)'),
   null, 20, 40,
   'fixture:00000000-0000-4000-d000-000000000004', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-d000-000000000005', '00000000-0000-4000-a000-000000000020', '00000000-0000-4000-b000-000000000006', 'Oran Regional Theatre', 'Théâtre Régional d''Oran Abdelkader Alloula', 'المسرح الجهوي عبد القادر علولة',
   st_geogfromtext('SRID=4326;POINT(-0.6365 35.6975)'),
   'Tu-Su 10:00-18:00', 20, 25,
   'fixture:00000000-0000-4000-d000-000000000005', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-d000-000000000006', '00000000-0000-4000-a000-000000000020', '00000000-0000-4000-b000-000000000001', 'Place du 1er Novembre', 'Place du 1er Novembre', 'ساحة أول نوفمبر',
   st_geogfromtext('SRID=4326;POINT(-0.6355 35.6968)'),
   null, 15, 30,
   'fixture:00000000-0000-4000-d000-000000000006', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-d000-000000000007', '00000000-0000-4000-a000-000000000020', '00000000-0000-4000-b000-000000000002', 'Ahmed Zabana National Museum', 'Musée National Ahmed Zabana', 'المتحف الوطني أحمد زبانة',
   st_geogfromtext('SRID=4326;POINT(-0.632 35.6985)'),
   'Tu-Su 09:00-17:00', 35, 25,
   'fixture:00000000-0000-4000-d000-000000000007', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-d000-000000000008', '00000000-0000-4000-a000-000000000020', '00000000-0000-4000-b000-000000000005', 'Mount Murdjadjo', 'Le Murdjadjo', 'المرجاجو',
   st_geogfromtext('SRID=4326;POINT(-0.66 35.71)'),
   null, 30, 40,
   'fixture:00000000-0000-4000-d000-000000000008', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-d000-000000000009', '00000000-0000-4000-a000-000000000020', '00000000-0000-4000-b000-000000000004', 'Pacha Mosque', 'Mosquée du Pacha', 'مسجد الباشا',
   st_geogfromtext('SRID=4326;POINT(-0.638 35.695)'),
   'Mo-Su 06:00-21:00', 15, 25,
   'fixture:00000000-0000-4000-d000-000000000009', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-d000-000000000010', '00000000-0000-4000-a000-000000000020', '00000000-0000-4000-b000-000000000003', 'Promenade de Létang', 'Promenade de Létang', 'منتزه ليتانغ',
   st_geogfromtext('SRID=4326;POINT(-0.629 35.699)'),
   'Mo-Su 07:00-20:00', 20, 30,
   'fixture:00000000-0000-4000-d000-000000000010', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-e000-000000000001', '00000000-0000-4000-a000-000000000030', '00000000-0000-4000-b000-000000000001', 'Sidi M''Cid Bridge', 'Pont de Sidi M''Cid', 'جسر سيدي مسيد',
   st_geogfromtext('SRID=4326;POINT(6.613 36.371)'),
   null, 20, 35,
   'fixture:00000000-0000-4000-e000-000000000001', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-e000-000000000002', '00000000-0000-4000-a000-000000000030', '00000000-0000-4000-b000-000000000001', 'Mellah Slimane Suspension Bridge', 'Pont Suspendu Mellah Slimane', 'الجسر المعلق ملاح سليمان',
   st_geogfromtext('SRID=4326;POINT(6.617 36.365)'),
   null, 15, 30,
   'fixture:00000000-0000-4000-e000-000000000002', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-e000-000000000003', '00000000-0000-4000-a000-000000000030', '00000000-0000-4000-b000-000000000001', 'War Memorial of Constantine', 'Monument aux Morts de Constantine', 'نصب الشهداء قسنطينة',
   st_geogfromtext('SRID=4326;POINT(6.6145 36.369)'),
   null, 10, 25,
   'fixture:00000000-0000-4000-e000-000000000003', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-e000-000000000004', '00000000-0000-4000-a000-000000000030', '00000000-0000-4000-b000-000000000001', 'Palace of Ahmed Bey', 'Palais Ahmed Bey', 'قصر أحمد باي',
   st_geogfromtext('SRID=4326;POINT(6.614 36.3635)'),
   'Tu-Su 09:00-16:30', 35, 30,
   'fixture:00000000-0000-4000-e000-000000000004', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-e000-000000000005', '00000000-0000-4000-a000-000000000030', '00000000-0000-4000-b000-000000000004', 'Emir Abdelkader Mosque', 'Mosquée Emir Abdelkader', 'مسجد الأمير عبد القادر',
   st_geogfromtext('SRID=4326;POINT(6.62 36.36)'),
   'Mo-Su 06:00-21:00', 25, 50,
   'fixture:00000000-0000-4000-e000-000000000005', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-e000-000000000006', '00000000-0000-4000-a000-000000000030', '00000000-0000-4000-b000-000000000002', 'Cirta National Museum', 'Musée National Cirta', 'المتحف الوطني سيرتا',
   st_geogfromtext('SRID=4326;POINT(6.611 36.368)'),
   'Tu-Su 09:00-17:00', 30, 25,
   'fixture:00000000-0000-4000-e000-000000000006', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-e000-000000000007', '00000000-0000-4000-a000-000000000030', '00000000-0000-4000-b000-000000000005', 'Rhumel Gorge Viewpoint', 'Gorges du Rhumel', 'أخدود الرمال',
   st_geogfromtext('SRID=4326;POINT(6.6155 36.3665)'),
   null, 20, 30,
   'fixture:00000000-0000-4000-e000-000000000007', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-e000-000000000008', '00000000-0000-4000-a000-000000000030', '00000000-0000-4000-b000-000000000001', 'Place de la Brèche', 'Place de la Brèche', 'ساحة البريش',
   st_geogfromtext('SRID=4326;POINT(6.612 36.364)'),
   null, 15, 30,
   'fixture:00000000-0000-4000-e000-000000000008', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-e000-000000000009', '00000000-0000-4000-a000-000000000030', '00000000-0000-4000-b000-000000000005', 'Mentouri University Viewpoint', 'Université des Frères Mentouri (Belvédère)', 'جامعة الإخوة منتوري',
   st_geogfromtext('SRID=4326;POINT(6.625 36.34)'),
   null, 15, 35,
   'fixture:00000000-0000-4000-e000-000000000009', 'team_seeded'::poi_source, 'published'::poi_status),
  ('00000000-0000-4000-e000-000000000010', '00000000-0000-4000-a000-000000000030', '00000000-0000-4000-b000-000000000001', 'Tiddis Roman Ruins', 'Tiddis (Castellum Tidditanorum)', 'تيديس',
   st_geogfromtext('SRID=4326;POINT(6.555 36.42)'),
   'Mo-Su 09:00-16:00', 45, 50,
   'fixture:00000000-0000-4000-e000-000000000010', 'team_seeded'::poi_source, 'published'::poi_status)
on conflict (id) do update set
  city_id = excluded.city_id, category_id = excluded.category_id,
  name_en = excluded.name_en, name_fr = excluded.name_fr, name_ar = excluded.name_ar,
  location = excluded.location, opening_hours_raw = excluded.opening_hours_raw,
  avg_visit_duration_minutes = excluded.avg_visit_duration_minutes,
  checkpoint_radius_meters = excluded.checkpoint_radius_meters,
  external_ref = excluded.external_ref, source = excluded.source,
  status = excluded.status, deleted_at = null, updated_at = now();
