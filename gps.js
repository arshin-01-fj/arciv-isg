/**
 * GES Operasyon — GPS Konum Modülü
 * Tüm formlarda ortak kullanılır.
 * Sadece kullanıcı kayıt oluştururken anlık konum alır.
 * Arka planda sürekli takip YAPILMAZ.
 */

const GPS = {
  veri: null,  // { latitude, longitude, location_accuracy, location_timestamp }

  HATALAR: {
    1: 'Konum izni verilmeden kayıt oluşturulamaz.\nLütfen tarayıcı adres çubuğundaki kilit simgesine tıklayıp konum iznini açın.',
    2: 'Cihaz konum bilgisi alamadı.\nLütfen GPS\'in açık olduğundan emin olun.',
    3: 'Konum alma zaman aşımına uğradı.\nAçık bir alanda tekrar deneyin.',
    0: 'Bu tarayıcı konum özelliğini desteklemiyor.\nGüncel bir mobil tarayıcı kullanın.'
  },

  /**
   * Anlık konum alır. Promise döner.
   * Başarılı → { latitude, longitude, location_accuracy, location_timestamp }
   * Başarısız → hata mesajı fırlatır
   */
  al() {
    return new Promise((resolve, reject) => {
      if (!navigator.geolocation) {
        reject(new Error(this.HATALAR[0]));
        return;
      }

      navigator.geolocation.getCurrentPosition(
        (pos) => {
          this.veri = {
            latitude:           parseFloat(pos.coords.latitude.toFixed(7)),
            longitude:          parseFloat(pos.coords.longitude.toFixed(7)),
            location_accuracy:  parseFloat(pos.coords.accuracy.toFixed(2)),
            location_timestamp: new Date(pos.timestamp).toISOString()
          };
          resolve(this.veri);
        },
        (err) => {
          this.veri = null;
          reject(new Error(this.HATALAR[err.code] || 'Bilinmeyen konum hatası.'));
        },
        {
          enableHighAccuracy: true,  // GPS öncelikli
          timeout: 12000,            // 12 saniye zaman aşımı
          maximumAge: 30000          // 30 sn içindeki önbellek kabul
        }
      );
    });
  },

  /**
   * UI bileşenini günceller.
   * durumElId: "Konum Durumu" span elementi
   * dogrulukElId: "Doğruluk" span elementi
   * butonElId: "Konum Al" butonu
   */
  async baslat(durumElId, dogrulukElId, butonElId) {
    const durumEl   = document.getElementById(durumElId);
    const dogrulukEl = document.getElementById(dogrulukElId);
    const butonEl   = document.getElementById(butonElId);

    durumEl.textContent     = '📡 Konum alınıyor...';
    durumEl.className       = 'text-blue-600 font-medium';
    dogrulukEl.textContent  = '';
    if (butonEl) { butonEl.disabled = true; butonEl.textContent = '⏳ Bekleniyor...'; }

    try {
      const konum = await this.al();
      durumEl.textContent    = '✅ Konum alındı';
      durumEl.className      = 'text-green-600 font-semibold';
      dogrulukEl.textContent = `Doğruluk: ±${Math.round(konum.location_accuracy)} metre`;
      if (butonEl) { butonEl.disabled = false; butonEl.textContent = '🔄 Yenile'; }
      return konum;
    } catch (err) {
      durumEl.textContent    = '❌ Konum alınamadı';
      durumEl.className      = 'text-red-600 font-semibold';
      dogrulukEl.textContent = '';
      if (butonEl) { butonEl.disabled = false; butonEl.textContent = '📍 Tekrar Dene'; }
      alert(err.message);
      throw err;
    }
  },

  /** Google Maps linki üret */
  mapsLink(lat, lng) {
    return `https://www.google.com/maps?q=${lat},${lng}`;
  }
};
