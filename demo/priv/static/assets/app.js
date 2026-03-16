// LiveView bootstrap for the demo app.
// phoenix.min.js exposes window.Phoenix (with .Socket)
// phoenix_live_view.min.js exposes window.LiveView (with .LiveSocket)

window.addEventListener("DOMContentLoaded", function() {
  var csrfToken = document.querySelector("meta[name='csrf-token']");
  var token = csrfToken ? csrfToken.getAttribute("content") : "";
  var liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
    params: { _csrf_token: token },
    longPollFallbackMs: 2500
  });
  liveSocket.connect();
  window.liveSocket = liveSocket;
});
