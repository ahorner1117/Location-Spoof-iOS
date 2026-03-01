import Foundation
import Network

/// Minimal HTTP server that exposes the same set/clear/status actions as Bonjour
/// so the iOS app can control location spoofing over the internet (e.g. via Tailscale or Cloudflare Tunnel).
@Observable
final class HTTPServer {
    private var listener: NWListener?
    private let port: UInt16
    private let queue = DispatchQueue(label: "HTTPServer")
    private weak var handler: CommandHandler?

    private(set) var isRunning = false
    private(set) var boundPort: UInt16?

    static let defaultPort: UInt16 = 8765

    init(port: UInt16 = HTTPServer.defaultPort) {
        self.port = port
    }

    func start(handler: CommandHandler) {
        self.handler = handler
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("HTTPServer: failed to create listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.listener?.port?.rawValue {
                    DispatchQueue.main.async {
                        self?.isRunning = true
                        self?.boundPort = port
                    }
                    print("HTTPServer: listening on port \(port)")
                }
            case .failed(let error):
                print("HTTPServer: failed \(error)")
                DispatchQueue.main.async { self?.isRunning = false; self?.boundPort = nil }
            case .cancelled:
                DispatchQueue.main.async { self?.isRunning = false; self?.boundPort = nil }
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.boundPort = nil
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.readRequest(connection: connection)
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func readRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                connection.cancel()
                return
            }
            guard let data = data, !data.isEmpty else {
                if isComplete { connection.cancel() }
                return
            }

            guard let request = String(data: data, encoding: .utf8) else {
                self.sendResponse(connection: connection, status: "400 Bad Request", body: "Bad request")
                return
            }

            let (method, path, body) = self.parseRequest(request)
            print("HTTPServer: \(method) \(path)")
            self.dispatch(method: method, path: path, body: body) { response, contentType in
                print("HTTPServer: responding \(contentType) (\(response.count) bytes)")
                self.sendResponse(connection: connection, status: "200 OK", body: response, contentType: contentType)
            }
        }
    }

    private func parseRequest(_ raw: String) -> (method: String, path: String, body: String?) {
        var method = "GET"
        var path = "/"
        var body: String?

        let lines = raw.components(separatedBy: "\r\n")
        if let first = lines.first {
            let parts = first.split(separator: " ", maxSplits: 2)
            if parts.count >= 2 {
                method = String(parts[0]).uppercased()
                path = String(parts[1]).split(separator: "?").first.map(String.init) ?? "/"
            }
        }

        if let idx = lines.firstIndex(where: { $0.isEmpty }),
           idx + 1 < lines.count {
            body = lines[(idx + 1)...].joined(separator: "\r\n")
        }

        return (method, path, body)
    }

    private func dispatch(method: String, path: String, body: String?, completion: @escaping (String, String) -> Void) {
        var pathNorm = path.hasSuffix("/") ? String(path.dropLast()) : path
        if pathNorm.isEmpty { pathNorm = "/" }

        switch (method, pathNorm) {
        case ("GET", "/dashboard"):
            completion(Self.dashboardHTML, "text/html; charset=utf-8")

        case ("GET", "/"), ("GET", "/status"):
            guard let handler = handler else {
                completion(encodeJSON(["status": "error", "message": "Not ready"]), "application/json")
                return
            }
            let response = handler.statusResponse()
            completion(encodeResponse(response), "application/json")

        case ("POST", "/set"):
            guard let handler = handler else {
                completion(encodeJSON(["status": "error", "message": "Not ready"]), "application/json")
                return
            }
            guard let body = body,
                  let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lat = json["lat"] as? Double,
                  let lng = json["lng"] as? Double else {
                completion(encodeJSON(["status": "error", "message": "Missing lat/lng in JSON body"]), "application/json")
                return
            }
            var responseBody: String?
            let sem = DispatchSemaphore(value: 0)
            Task { @MainActor in
                let response = await handler.setLocationAPI(lat: lat, lng: lng)
                responseBody = self.encodeResponse(response)
                sem.signal()
            }
            sem.wait()
            completion(responseBody ?? "{}", "application/json")

        case ("POST", "/clear"):
            guard let handler = handler else {
                completion(encodeJSON(["status": "error", "message": "Not ready"]), "application/json")
                return
            }
            var responseBody: String?
            let sem = DispatchSemaphore(value: 0)
            Task { @MainActor in
                let response = await handler.clearLocationAPI()
                responseBody = self.encodeResponse(response)
                sem.signal()
            }
            sem.wait()
            completion(responseBody ?? "{}", "application/json")

        default:
            completion(encodeJSON([
                "status": "error",
                "message": "Not found. Use GET /dashboard, GET /status, POST /set, POST /clear"
            ]), "application/json")
        }
    }

    private func encodeResponse(_ r: SpoofResponse) -> String {
        var dict: [String: Any] = ["status": r.status]
        if let s = r.spoofing { dict["spoofing"] = s }
        if let lat = r.lat { dict["lat"] = lat }
        if let lng = r.lng { dict["lng"] = lng }
        if let m = r.message { dict["message"] = m }
        if let d = r.device { dict["device"] = d }
        return encodeJSON(dict)
    }

    private func encodeJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"status\":\"error\",\"message\":\"Encoding error\"}"
        }
        return str
    }

    // MARK: - Dashboard HTML

    static let dashboardHTML: String = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    <title>Location Spoof</title>
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body { font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif; background:#111; color:#eee; height:100vh; display:flex; flex-direction:column; }
    #map { flex:1; min-height:0; }
    .panel { padding:12px 16px; background:#1a1a1a; border-top:1px solid #333; }
    .status-row { display:flex; align-items:center; gap:8px; margin-bottom:8px; font-size:14px; }
    .dot { width:10px; height:10px; border-radius:50%; flex-shrink:0; }
    .dot.green { background:#34c759; }
    .dot.red { background:#ff3b30; }
    .dot.orange { background:#ff9500; }
    .coords { font-family:ui-monospace,monospace; font-size:13px; color:#aaa; margin-bottom:8px; min-height:18px; }
    .search-row { display:flex; gap:8px; margin-bottom:8px; }
    .search-row input { flex:1; padding:8px 12px; border-radius:8px; border:1px solid #444; background:#222; color:#eee; font-size:14px; outline:none; }
    .search-row input:focus { border-color:#0a84ff; }
    .search-row button { padding:8px 14px; border-radius:8px; border:none; background:#333; color:#eee; font-size:14px; cursor:pointer; }
    .btn-row { display:flex; gap:8px; }
    .btn { flex:1; padding:12px; border-radius:10px; border:none; font-size:15px; font-weight:600; cursor:pointer; transition:opacity 0.2s; }
    .btn:disabled { opacity:0.4; cursor:not-allowed; }
    .btn-spoof { background:#34c759; color:#fff; }
    .btn-clear { background:#ff3b30; color:#fff; }
    .error { color:#ff3b30; font-size:13px; margin-top:6px; }
    .leaflet-container { background:#222; }
    </style>
    </head>
    <body>
    <div id="map"></div>
    <div class="panel">
      <div class="status-row">
        <span class="dot" id="statusDot"></span>
        <span id="statusText">Connecting...</span>
      </div>
      <div class="coords" id="coords">Tap the map to select a location</div>
      <div class="search-row">
        <input type="text" id="searchInput" placeholder="Search location..." autocomplete="off">
        <button onclick="searchLocation()">Go</button>
      </div>
      <div class="btn-row">
        <button class="btn btn-spoof" id="btnSpoof" disabled onclick="spoofLocation()">Spoof Location</button>
        <button class="btn btn-clear" id="btnClear" disabled onclick="clearLocation()">Clear</button>
      </div>
      <div class="error" id="error"></div>
    </div>
    <script>
    const map = L.map('map', { zoomControl: true }).setView([37.7749, -122.4194], 12);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap'
    }).addTo(map);

    let marker = null;
    let selectedLat = null;
    let selectedLng = null;
    let spoofMarker = null;

    map.on('click', function(e) {
      selectedLat = e.latlng.lat;
      selectedLng = e.latlng.lng;
      if (marker) map.removeLayer(marker);
      marker = L.marker(e.latlng, { draggable: true }).addTo(map);
      marker.on('dragend', function(ev) {
        selectedLat = ev.target.getLatLng().lat;
        selectedLng = ev.target.getLatLng().lng;
        updateCoords();
      });
      updateCoords();
      document.getElementById('btnSpoof').disabled = false;
    });

    function updateCoords() {
      document.getElementById('coords').textContent =
        selectedLat.toFixed(6) + ', ' + selectedLng.toFixed(6);
    }

    async function searchLocation() {
      const q = document.getElementById('searchInput').value.trim();
      if (!q) return;
      try {
        const r = await fetch('https://nominatim.openstreetmap.org/search?format=json&limit=1&q=' + encodeURIComponent(q));
        const data = await r.json();
        if (data.length > 0) {
          const lat = parseFloat(data[0].lat);
          const lng = parseFloat(data[0].lon);
          selectedLat = lat;
          selectedLng = lng;
          map.setView([lat, lng], 15);
          if (marker) map.removeLayer(marker);
          marker = L.marker([lat, lng], { draggable: true }).addTo(map);
          marker.on('dragend', function(ev) {
            selectedLat = ev.target.getLatLng().lat;
            selectedLng = ev.target.getLatLng().lng;
            updateCoords();
          });
          updateCoords();
          document.getElementById('btnSpoof').disabled = false;
        }
      } catch(e) { showError('Search failed: ' + e.message); }
    }

    document.getElementById('searchInput').addEventListener('keydown', function(e) {
      if (e.key === 'Enter') searchLocation();
    });

    async function spoofLocation() {
      if (selectedLat === null) return;
      document.getElementById('btnSpoof').disabled = true;
      document.getElementById('error').textContent = '';
      try {
        const r = await fetch('/set', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ lat: selectedLat, lng: selectedLng })
        });
        const data = await r.json();
        if (data.status === 'ok') {
          pollStatus();
        } else {
          showError(data.message || 'Spoof failed');
          document.getElementById('btnSpoof').disabled = false;
        }
      } catch(e) {
        showError('Request failed: ' + e.message);
        document.getElementById('btnSpoof').disabled = false;
      }
    }

    async function clearLocation() {
      document.getElementById('btnClear').disabled = true;
      document.getElementById('error').textContent = '';
      try {
        const r = await fetch('/clear', { method: 'POST' });
        const data = await r.json();
        if (data.status !== 'ok') showError(data.message || 'Clear failed');
        pollStatus();
      } catch(e) {
        showError('Request failed: ' + e.message);
      }
    }

    function showError(msg) {
      document.getElementById('error').textContent = msg;
    }

    async function pollStatus() {
      try {
        const r = await fetch('/status');
        const data = await r.json();
        const dot = document.getElementById('statusDot');
        const text = document.getElementById('statusText');

        if (data.spoofing) {
          dot.className = 'dot green';
          text.textContent = 'Spoofing active';
          document.getElementById('btnClear').disabled = false;
          if (data.lat && data.lng) {
            if (spoofMarker) map.removeLayer(spoofMarker);
            spoofMarker = L.circleMarker([data.lat, data.lng], {
              radius: 8, color: '#34c759', fillColor: '#34c759', fillOpacity: 0.8
            }).addTo(map);
          }
        } else {
          dot.className = 'dot orange';
          text.textContent = 'Connected, idle';
          document.getElementById('btnClear').disabled = true;
          if (spoofMarker) { map.removeLayer(spoofMarker); spoofMarker = null; }
        }
        if (selectedLat !== null) document.getElementById('btnSpoof').disabled = false;
      } catch(e) {
        document.getElementById('statusDot').className = 'dot red';
        document.getElementById('statusText').textContent = 'Disconnected';
        document.getElementById('btnSpoof').disabled = true;
        document.getElementById('btnClear').disabled = true;
      }
    }

    pollStatus();
    setInterval(pollStatus, 5000);
    </script>
    </body>
    </html>
    """

    private func sendResponse(connection: NWConnection, status: String, body: String, contentType: String = "application/json") {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
