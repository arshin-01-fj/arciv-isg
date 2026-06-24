-- ================================================================
-- GPS KONUM GÜNCELLEMESİ
-- Supabase > SQL Editor > New Query > Yapıştır > Run
-- Mevcut tabloları bozmaz, nullable kolon ekler.
-- ================================================================

-- 1. KAYITLAR tablosuna GPS alanları ekle
alter table kayitlar
  add column if not exists latitude          numeric(10,7),
  add column if not exists longitude         numeric(10,7),
  add column if not exists location_accuracy numeric(8,2),
  add column if not exists location_timestamp timestamptz;

-- 2. FAALİYETLER tablosuna GPS alanları ekle (açılış kaydı)
alter table faaliyetler
  add column if not exists latitude          numeric(10,7),
  add column if not exists longitude         numeric(10,7),
  add column if not exists location_accuracy numeric(8,2),
  add column if not exists location_timestamp timestamptz;

-- 3. Kapanış GPS alanları (faaliyetler tablosuna — kapanış anı)
alter table faaliyetler
  add column if not exists kapanis_latitude          numeric(10,7),
  add column if not exists kapanis_longitude         numeric(10,7),
  add column if not exists kapanis_location_accuracy numeric(8,2),
  add column if not exists kapanis_location_timestamp timestamptz;

-- ================================================================
-- Doğrulama: Kolonların eklendiğini kontrol et
-- ================================================================
select column_name, data_type
from information_schema.columns
where table_name in ('kayitlar','faaliyetler')
  and column_name like '%lat%' or column_name like '%lon%' or column_name like '%location%'
order by table_name, column_name;
