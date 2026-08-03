create index locations_region_idx on public.locations (region_id) where region_id is not null;
