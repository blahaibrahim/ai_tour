-- The 8 curated locations, ported from lib/models/location_data.dart and
-- inserted with is_curated = true (docs/backend/02, docs/backend/12).
-- Applied once via MCP execute_sql against the remote project; committed
-- here so it's reproducible against a fresh database.

insert into public.regions (id, sort_order) values
  ('algiers-casbah', 1),
  ('constantine', 2),
  ('djemila-timgad', 3),
  ('tassili-sahara', 4),
  ('kabylie', 5)
on conflict (id) do nothing;

insert into public.region_translations (region_id, locale, name) values
  ('algiers-casbah', 'en', 'Algiers & the Casbah'),
  ('constantine', 'en', 'Constantine'),
  ('djemila-timgad', 'en', 'Djemila & Timgad'),
  ('tassili-sahara', 'en', 'Tassili n''Ajjer / Sahara'),
  ('kabylie', 'en', 'Kabylie mountains & coast')
on conflict (region_id, locale) do nothing;

insert into public.locations (id, region_id, category, geog, is_curated, interest_score) values
  ('casbah',   'algiers-casbah',  'Old town',       st_setsrid(st_makepoint(3.0608, 36.7853), 4326)::geography, true, 100),
  ('martyrs',  'algiers-casbah',  'Monument',       st_setsrid(st_makepoint(3.0665, 36.7527), 4326)::geography, true, 100),
  ('sidimcid', 'constantine',     'Bridge',         st_setsrid(st_makepoint(6.6147, 36.3705), 4326)::geography, true, 100),
  ('ahmedbey', 'constantine',     'Palace',         st_setsrid(st_makepoint(6.6088, 36.3646), 4326)::geography, true, 100),
  ('djemila',  'djemila-timgad',  'Roman ruins',    st_setsrid(st_makepoint(5.7358, 36.3214), 4326)::geography, true, 100),
  ('timgad',   'djemila-timgad',  'Roman ruins',    st_setsrid(st_makepoint(6.4675, 35.4842), 4326)::geography, true, 100),
  ('tassili',  'tassili-sahara',  'Desert plateau',  st_setsrid(st_makepoint(9.4842, 24.5544), 4326)::geography, true, 100),
  ('gouraya',  'kabylie',         'Coastal peak',   st_setsrid(st_makepoint(5.0921, 36.7628), 4326)::geography, true, 100)
on conflict (id) do nothing;

insert into public.location_translations (location_id, locale, name, blurb) values
  ('casbah', 'en', 'Casbah of Algiers',
    'A UNESCO-listed maze of Ottoman-era alleys, tiled courtyards and sea views tumbling down the hillside.'),
  ('martyrs', 'en', 'Maqam Echahid',
    'Three palm-frond concrete shells rising over the bay, Algiers'' memorial to independence.'),
  ('sidimcid', 'en', 'Sidi M''Cid Bridge',
    'A suspension bridge slung 175m over the Rhumel gorge, the signature view of the City of Bridges.'),
  ('ahmedbey', 'en', 'Ahmed Bey Palace',
    'Marble courtyards and painted ceilings inside the last Ottoman bey''s residence.'),
  ('djemila', 'en', 'Djemila',
    'A Roman market town scattered across a mountain ridge, its forum still catching the evening light.'),
  ('timgad', 'en', 'Timgad',
    'A grid-planned Roman colony known as the Pompeii of Africa, arch and colonnade intact.'),
  ('tassili', 'en', 'Tassili n''Ajjer',
    'Sandstone spires and 8,000-year-old rock art scattered across a Saharan plateau.'),
  ('gouraya', 'en', 'Yemma Gouraya',
    'A clifftop shrine over the Bay of Bejaia, with the Kabylie coastline unrolling below.')
on conflict (location_id, locale) do nothing;

with inserted_tasks as (
  insert into public.location_tasks (location_id, type, points)
  select v.location_id, v.type::public.task_type, 30
  from (values
    ('casbah', 'mascot'),
    ('martyrs', 'video'),
    ('sidimcid', 'video'),
    ('ahmedbey', 'scan'),
    ('djemila', 'scan'),
    ('timgad', 'video'),
    ('tassili', 'mascot'),
    ('gouraya', 'video')
  ) as v(location_id, type)
  returning id, location_id
)
insert into public.location_task_translations (task_id, locale, label)
select it.id, 'en', v.label
from inserted_tasks it
join (values
  ('casbah', 'A fennec is hiding in one of these alleys — find it and photograph it'),
  ('martyrs', 'Film a slow pan across the three palm shells'),
  ('sidimcid', 'Capture a short clip crossing the bridge'),
  ('ahmedbey', 'Scan the painted ceiling medallion'),
  ('djemila', 'Scan the forum''s inscription stone'),
  ('timgad', 'Film Trajan''s Arch from below'),
  ('tassili', 'A fennec is hiding on the plateau — find it and photograph it'),
  ('gouraya', 'Film the coastline from the shrine')
) as v(location_id, label) on v.location_id = it.location_id;
