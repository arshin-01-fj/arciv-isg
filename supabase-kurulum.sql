-- ================================================================
-- GES OPERASYON — Supabase Veritabanı Kurulumu v3
-- Supabase > SQL Editor > New Query > Yapıştır > Run
-- ================================================================
--
-- Değişiklikler v3:
--   • birim ve tur → ASCII-safe lowercase enum (Türkçe karakter yok)
--   • calisan_sayisi → 0–300 arası sınır
--   • RLS → tüm politikalar yalnızca auth.uid() / uzmanlar.id üzerinden
--             (email referansı yok, UID değişmez)
-- ================================================================

-- ----------------------------------------------------------------
-- 1. UZMANLAR tablosu
--    auth.users ile bağlantı: her uzmanın bir Supabase Auth hesabı var
-- ----------------------------------------------------------------
create table if not exists uzmanlar (
  id          uuid primary key references auth.users(id) on delete cascade,
  ad_soyad    text not null,
  email       text not null,
  rol         text not null default 'uzman' check (rol in ('uzman','yonetici','admin')),
  aktif       boolean not null default true,
  created_at  timestamptz default now()
);

-- ----------------------------------------------------------------
-- 2. KAYITLAR tablosu — genişletilmiş veri modeli
-- ----------------------------------------------------------------
create table if not exists kayitlar (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  -- Kim girdi (auth.uid() ile otomatik, kullanıcı değiştiremez)
  uzman_id        uuid not null references uzmanlar(id),

  -- Saha bilgileri
  santiye         text not null default 'GES-1',   -- ileride çok santiye
  taseron         text,                             -- taşeron firma adı
  sps_kodu        text not null,                   -- 'SPS-01' ... 'SPS-96'
  sps_no          integer generated always as (
                    (regexp_match(sps_kodu, '\d+'))[1]::integer
                  ) stored,

  -- Çalışma detayı
  -- Birim ve tur: ASCII-safe lowercase — Türkçe karakter, büyük harf, boşluk kabul edilmez.
  -- Frontend'den gelen veri bu değerlerle birebir eşleşmeli, aksi hâlde DB reddeder.
  birim           text not null check (birim in ('elektrik','mekanik','altyapi','panel','diger')),
  calisan_sayisi  integer not null default 0
                    check (calisan_sayisi >= 0 and calisan_sayisi <= 300),
  tur             text not null default 'sabah' check (tur in ('sabah','oglen','aksam')),
  aciklama        text,

  -- Kayıt durumu
  aktif           boolean not null default true,   -- soft delete

  -- Zaman damgaları (kullanıcı giremez, sistem yazar)
  tarih           date not null default current_date,
  saat            text not null default to_char(now(), 'HH24:MI')
);

-- updated_at otomatik güncelle
create or replace function guncelleme_zamani()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger kayitlar_updated_at
  before update on kayitlar
  for each row execute function guncelleme_zamani();

-- ----------------------------------------------------------------
-- 3. İNDEXLER
-- ----------------------------------------------------------------
create index if not exists kayitlar_tarih_idx    on kayitlar(tarih);
create index if not exists kayitlar_santiye_idx  on kayitlar(santiye);
create index if not exists kayitlar_uzman_idx    on kayitlar(uzman_id);
create index if not exists kayitlar_sps_idx      on kayitlar(sps_kodu);

-- ----------------------------------------------------------------
-- 4. ROW LEVEL SECURITY
--    Anon key frontend'de görünür — RLS olmadan herkes her şeyi okur/yazar.
--    RLS açıkken politika yoksa hiç kimse erişemez.
-- ----------------------------------------------------------------

-- uzmanlar tablosu
alter table uzmanlar enable row level security;

-- Herkes kendi profilini okuyabilir
create policy "uzman kendi profilini okur"
  on uzmanlar for select
  using (auth.uid() = id);

-- Yönetici tüm uzmanları okuyabilir
create policy "yonetici tum uzmanlari okur"
  on uzmanlar for select
  using (
    exists (
      select 1 from uzmanlar u
      where u.id = auth.uid() and u.rol in ('yonetici','admin')
    )
  );

-- kayitlar tablosu
alter table kayitlar enable row level security;

-- SELECT: uzman kendi kayıtlarını, yönetici tümünü görür
create policy "uzman kendi kayitlarini okur"
  on kayitlar for select
  using (uzman_id = auth.uid());

create policy "yonetici tum kayitlari okur"
  on kayitlar for select
  using (
    exists (
      select 1 from uzmanlar u
      where u.id = auth.uid() and u.rol in ('yonetici','admin')
    )
  );

-- INSERT: sadece giriş yapmış uzman, sadece kendi kimliğiyle
create policy "uzman sadece kendi adina kayit girer"
  on kayitlar for insert
  with check (
    uzman_id = auth.uid()
    and exists (
      select 1 from uzmanlar u
      where u.id = auth.uid() and u.aktif = true
    )
  );

-- UPDATE: uzman sadece kendi bugünkü kaydını düzeltebilir
create policy "uzman bugunku kaydini duzeltir"
  on kayitlar for update
  using (
    uzman_id = auth.uid()
    and tarih = current_date
  );

-- DELETE: kimse silemez (soft delete — aktif=false kullan)

-- ----------------------------------------------------------------
-- 5. FAALİYETLER tablosu  (Tablo 2 — İSG operasyon kaydı)
--
--    Tablo 1 (kayitlar)  → Nerede? Kaç kişi? Hangi birim?
--    Tablo 2 (faaliyetler) → Ne yapıldı? Kim denetledi? Uygunsuzluk var mı?
-- ----------------------------------------------------------------
create table if not exists faaliyetler (
  id                uuid primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  uzman_id          uuid not null references uzmanlar(id),
  santiye           text not null default 'GES-1',
  sps_kodu          text,                          -- null olabilir (tüm saha toplantısı vb.)

  faaliyet_tipi     text not null check (faaliyet_tipi in (
                      'toolbox','denetim','uygunsuzluk',
                      'ramak_kala','tutanak','is_durdurma',
                      'kkd_kontrol','vinc_denetim','iskele_denetim',
                      'toplanti','diger'
                    )),

  katilimci_sayisi  integer check (katilimci_sayisi >= 0 and katilimci_sayisi <= 500),
  aciklama          text,

  -- Uygunsuzluk / DÖF takibi
  durum             text not null default 'acik'
                      check (durum in ('acik','devam_ediyor','kapali')),
  oncelik           text default 'normal'
                      check (oncelik in ('dusuk','normal','yuksek','kritik')),

  -- Fotoğraf: Supabase Storage path listesi (JSON array of storage paths, NOT public URLs)
  -- Erişim signed URL ile yapılır — bucket private olmalı.
  fotograflar       jsonb default '[]'::jsonb,

  -- Kapanış alanları (uygunsuzluk/ramak_kala/is_durdurma/tutanak için)
  sorumlu_kisi      text,
  hedef_tarih       date,
  kapanis_aciklama  text,
  kapanis_fotolar   jsonb default '[]'::jsonb,  -- storage paths
  kapanis_tarihi    timestamptz,                 -- kapandığında sistem yazar

  tarih             date not null default current_date,
  saat              text not null default to_char(now(), 'HH24:MI'),
  aktif             boolean not null default true
);

create trigger faaliyetler_updated_at
  before update on faaliyetler
  for each row execute function guncelleme_zamani();

create index if not exists faaliyetler_tarih_idx   on faaliyetler(tarih);
create index if not exists faaliyetler_santiye_idx on faaliyetler(santiye);
create index if not exists faaliyetler_sps_idx     on faaliyetler(sps_kodu);
create index if not exists faaliyetler_tip_idx     on faaliyetler(faaliyet_tipi);
create index if not exists faaliyetler_durum_idx   on faaliyetler(durum);

-- RLS
alter table faaliyetler enable row level security;

create policy "uzman kendi faaliyetlerini okur"
  on faaliyetler for select
  using (uzman_id = auth.uid());

create policy "yonetici tum faaliyetleri okur"
  on faaliyetler for select
  using (
    exists (select 1 from uzmanlar u where u.id = auth.uid() and u.rol in ('yonetici','admin'))
  );

create policy "uzman kendi adina faaliyet girer"
  on faaliyetler for insert
  with check (
    uzman_id = auth.uid()
    and exists (select 1 from uzmanlar u where u.id = auth.uid() and u.aktif = true)
  );

-- UPDATE: uzman kendi bugünkü kaydını düzeltir
create policy "uzman bugunku faaliyetini gunceller"
  on faaliyetler for update
  using (uzman_id = auth.uid() and tarih = current_date);

-- UPDATE: yönetici kapanış alanlarını doldurabilir (durum → kapali, kapanis_* alanları)
create policy "yonetici kapanisi gunceller"
  on faaliyetler for update
  using (
    exists (select 1 from uzmanlar u where u.id = auth.uid() and u.rol in ('yonetici','admin'))
  );

-- ----------------------------------------------------------------
-- 6. STORAGE — Private bucket (Supabase Dashboard'dan yapılır)
--
--    Supabase → Storage → New Bucket
--    İsim    : faaliyetler
--    Public  : ❌ KAPALI  ← kritik
--
--    Ardından Storage > Policies'e git ve şu politikaları ekle:
--
--    INSERT: giriş yapan uzman yükleyebilir
--      bucket_id = 'faaliyetler'
--      AND auth.role() = 'authenticated'
--
--    SELECT: giriş yapan kullanıcı okuyabilir (signed URL üretmek için)
--      bucket_id = 'faaliyetler'
--      AND auth.role() = 'authenticated'
--
--    Frontend'de fotoğraf gösterimi:
--      const { data } = await sb.storage
--        .from('faaliyetler')
--        .createSignedUrl(path, 3600);   -- 1 saatlik geçici URL
--      img.src = data.signedUrl;
--
--    Veritabanında saklanan: storage path ('fotograflar/dosya.jpg')
--    Veritabanında SAKLANMAYAN: URL (URL değişebilir, path sabit kalır)
-- ----------------------------------------------------------------

-- ----------------------------------------------------------------
-- 7. SPS POZİSYONLARI — Harita konumlandırma tablosu
--
--    x_pct, y_pct: saha planı görselinin üzerindeki konum (0–100 %)
--    Admin harita-tanimla.html aracıyla bir kez doldurur,
--    dashboard otomatik okur.
-- ----------------------------------------------------------------
create table if not exists sps_pozisyonlari (
  sps_kodu  text primary key,   -- 'SPS-01' ... 'SPS-96'
  x_pct     numeric(5,2) not null check (x_pct between 0 and 100),
  y_pct     numeric(5,2) not null check (y_pct between 0 and 100),
  updated_at timestamptz default now()
);

-- 96 satırı başlangıçta oluştur (konumlar sonradan doldurulur)
insert into sps_pozisyonlari (sps_kodu, x_pct, y_pct)
select
  'SPS-' || lpad(n::text, 2, '0'),
  -- Varsayılan: 12×8 grid (harita tanımlanana kadar düzgün dizilir)
  round(((( n - 1) % 12) * 100.0 / 11)::numeric, 2),
  round((floor(( n - 1) / 12) * 100.0 / 7)::numeric, 2)
from generate_series(1, 96) n
on conflict (sps_kodu) do nothing;

-- RLS: herkes okuyabilir, sadece admin yazabilir
alter table sps_pozisyonlari enable row level security;

create policy "herkes sps konumlarini okur"
  on sps_pozisyonlari for select
  using (auth.role() = 'authenticated');

create policy "admin sps konumlarini gunceller"
  on sps_pozisyonlari for update
  using (
    exists (select 1 from uzmanlar u where u.id = auth.uid() and u.rol = 'admin')
  );

-- ----------------------------------------------------------------
-- 8. REALTIME
-- ----------------------------------------------------------------
alter publication supabase_realtime add table kayitlar;
alter publication supabase_realtime add table faaliyetler;

-- ----------------------------------------------------------------
-- 6. ÖRNEK UZMAN KAYDI
--    Supabase Auth'tan davet ettikten sonra buraya ekleyin:
--    INSERT INTO uzmanlar (id, ad_soyad, email, rol)
--    VALUES ('auth-user-uuid-buraya', 'Cumali Yılmaz', 'cumali@firma.com', 'uzman');
--
--    Yönetici için rol='yonetici' kullanın.
-- ----------------------------------------------------------------

-- ----------------------------------------------------------------
-- 7. ANON KEY GÜVENLİK TESTİ  (canlıya almadan önce çalıştır)
--
--    Tarayıcı konsolundan veya Postman'dan şunu dene:
--
--    fetch('https://PROJE.supabase.co/rest/v1/kayitlar', {
--      method: 'POST',
--      headers: {
--        'apikey': 'anon-key',
--        'Authorization': 'Bearer anon-key',
--        'Content-Type': 'application/json'
--      },
--      body: JSON.stringify({
--        uzman_id: 'sahte-uuid-00000000-0000-0000-0000-000000000000',
--        sps_kodu: 'SPS-01', birim: 'elektrik',
--        calisan_sayisi: 99, tur: 'sabah',
--        tarih: '2026-01-01', saat: '08:00', santiye: 'GES-1'
--      })
--    })
--
--    Beklenen yanıt: 401 Unauthorized veya 403 Forbidden
--    Eğer 201 Created dönerse RLS eksik demektir — politikaları kontrol et.
-- ----------------------------------------------------------------

-- ----------------------------------------------------------------
-- 8. MEVCUT TABLO GÜNCELLEMESİ  (v2'den v3'e geçiş için)
--    Tablo zaten kuruluysa bu ALTER komutlarını çalıştır:
--
-- alter table kayitlar
--   drop constraint if exists kayitlar_birim_check,
--   drop constraint if exists kayitlar_tur_check,
--   drop constraint if exists kayitlar_calisan_sayisi_check;
--
-- alter table kayitlar
--   add constraint kayitlar_birim_check
--     check (birim in ('elektrik','mekanik','altyapi','panel','diger')),
--   add constraint kayitlar_tur_check
--     check (tur in ('sabah','oglen','aksam')),
--   add constraint kayitlar_calisan_sayisi_check
--     check (calisan_sayisi >= 0 and calisan_sayisi <= 300);
--
-- update kayitlar set birim = lower(birim);  -- mevcut verileri normalize et
-- ----------------------------------------------------------------
