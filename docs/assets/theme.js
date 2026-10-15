(function () {
  var root = document.documentElement, KEY = "theme";
  function saved() { try { return localStorage.getItem(KEY); } catch (e) { return null; } }
  function set(t) { root.setAttribute("data-theme", t); }
  set(saved() || (matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark"));

  document.addEventListener("DOMContentLoaded", function () {
    var b = document.querySelector(".theme-toggle");
    if (!b) return;
    function paint() {
      var dark = root.getAttribute("data-theme") === "dark";
      b.textContent = dark ? "\u2600" : "\u263E";
      b.setAttribute("aria-label", dark ? "Switch to light theme" : "Switch to dark theme");
      b.title = b.getAttribute("aria-label");
    }
    b.addEventListener("click", function () {
      var t = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
      set(t);
      try { localStorage.setItem(KEY, t); } catch (e) {}
      paint();
    });
    paint();
  });
})();
