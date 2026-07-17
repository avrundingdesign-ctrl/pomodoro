/*
 * Live-Countdowns. Reine Anzeige: Die Serverzeit ist maßgeblich, der Client
 * rechnet nur den Offset zwischen Server- und Browseruhr heraus. Läuft ein
 * Timer ab, wird die Seite neu geladen — der Server löst dann alles auf.
 */
(function () {
  var serverNow = Number(document.documentElement.getAttribute("data-server-now"));
  var offset = serverNow ? serverNow - Date.now() : 0;
  var els = Array.prototype.slice.call(document.querySelectorAll("[data-ends]"));
  if (els.length === 0) return;

  var reloadScheduled = false;
  function pad(n) { return n < 10 ? "0" + n : "" + n; }

  function tick() {
    var t = Date.now() + offset;
    els.forEach(function (el) {
      var ends = Number(el.getAttribute("data-ends"));
      var remaining = ends - t;
      if (remaining <= 0) {
        el.textContent = "fertig!";
        if (!reloadScheduled) {
          reloadScheduled = true;
          setTimeout(function () { location.reload(); }, 1200);
        }
        return;
      }
      var s = Math.ceil(remaining / 1000);
      var h = Math.floor(s / 3600);
      var m = Math.floor((s % 3600) / 60);
      var sec = s % 60;
      el.textContent = h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec);
    });
  }

  tick();
  setInterval(tick, 1000);
})();
