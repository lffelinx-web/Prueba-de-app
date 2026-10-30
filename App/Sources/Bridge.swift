import UIKit

/// JavaScript injected into the page. The HTML file itself is left untouched.
enum Bridge {
    static let downloadHandler = "descarga"
    static let themeHandler = "tema"

    /// WKWebView ignores `<a download>` on blob URLs, which is how the page exports CSV and
    /// Excel files. Blobs are tracked as they are created and handed to the app instead.
    static let downloads = """
    (function () {
      var blobs = new Map();
      var create = URL.createObjectURL.bind(URL);
      var revoke = URL.revokeObjectURL.bind(URL);
      URL.createObjectURL = function (obj) {
        var url = create(obj);
        if (obj instanceof Blob) blobs.set(url, obj);
        return url;
      };
      URL.revokeObjectURL = function (url) { blobs.delete(url); revoke(url); };

      function send(anchor) {
        var blob = anchor && anchor.hasAttribute('download') ? blobs.get(anchor.href) : null;
        if (!blob) return false;
        var name = anchor.getAttribute('download') || 'archivo';
        var reader = new FileReader();
        reader.onload = function () {
          window.webkit.messageHandlers.\(downloadHandler).postMessage({
            nombre: name, datos: String(reader.result).split(',')[1] || ''
          });
        };
        reader.readAsDataURL(blob);
        return true;
      }

      var click = HTMLAnchorElement.prototype.click;
      HTMLAnchorElement.prototype.click = function () {
        if (!send(this)) click.call(this);
      };
      document.addEventListener('click', function (event) {
        var anchor = event.target && event.target.closest ? event.target.closest('a[download]') : null;
        if (send(anchor)) event.preventDefault();
      }, true);
    })();
    """

    /// Lets the page's env(safe-area-inset-bottom) work and reports its background colour so
    /// the area around the web view and the status bar follow the light/dark theme.
    static let layout = """
    (function () {
      var meta = document.querySelector('meta[name=viewport]');
      if (meta && meta.content.indexOf('viewport-fit') < 0) meta.content += ', viewport-fit=cover';

      var timer = null;
      function report() {
        clearTimeout(timer);
        // Wait for the page's 0.2s background transition to finish.
        timer = setTimeout(function () {
          window.webkit.messageHandlers.\(themeHandler).postMessage(getComputedStyle(document.body).backgroundColor);
        }, 250);
      }
      var observer = new MutationObserver(report);
      observer.observe(document.documentElement, { attributes: true });
      observer.observe(document.body, { attributes: true });
      report();
    })();
    """
}

extension UIColor {
    /// Parses `rgb(r, g, b)` / `rgba(r, g, b, a)` as returned by getComputedStyle.
    convenience init?(cssRGB css: String) {
        let parts = css.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Double($0) }
        guard parts.count >= 3 else { return nil }
        if parts.count >= 4, parts[3] == 0 { return nil }
        self.init(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: 1)
    }

    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: nil)
        return 0.299 * r + 0.587 * g + 0.114 * b < 0.5
    }
}
