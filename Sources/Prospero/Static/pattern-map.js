// Pattern editor map picker.
//
// Wires up a Leaflet map that lets the user pick a lat/lng and select
// a NOAA tide station by clicking a pin. Reads initial state from, and
// writes back into, the existing form inputs:
//   #latitude, #longitude, #tide_station, #location_name
// so the map stays in sync with any defaults or manual edits.

(function () {
    'use strict';

    const container = document.getElementById('pattern-map');
    if (!container) return;

    const latInput = document.getElementById('latitude');
    const lngInput = document.getElementById('longitude');
    const stationInput = document.getElementById('tide_station');
    const locationNameInput = document.getElementById('location_name');

    const defaultCenter = [41.6, -71.4];       // Narragansett Bay
    const defaultZoom = 9;
    const stationsURL = container.dataset.stationsUrl;

    // Read initial state from the form fields so defaults, existing
    // pattern values, and the map all stay consistent with a single
    // source of truth.
    const initialLat = parseFloat(latInput && latInput.value);
    const initialLng = parseFloat(lngInput && lngInput.value);
    const initialStation = (stationInput && stationInput.value) || '';
    const hasInitialLocation = Number.isFinite(initialLat) && Number.isFinite(initialLng);

    const map = L.map(container).setView(
        hasInitialLocation ? [initialLat, initialLng] : defaultCenter,
        hasInitialLocation ? 11 : defaultZoom
    );

    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(map);

    // ── Forecast location: orange teardrop pin. Draggable.
    const locationIcon = L.divIcon({
        className: 'pattern-location-marker',
        iconSize: [22, 30],
        iconAnchor: [11, 28],   // tip of the pin sits on the point
        html: '<div class="pattern-location-pin"></div>'
    });

    let locationMarker = null;
    function setLocation(lat, lng, opts) {
        opts = opts || {};
        const rounded = {
            lat: Math.round(lat * 10000) / 10000,
            lng: Math.round(lng * 10000) / 10000,
        };
        if (latInput) latInput.value = rounded.lat;
        if (lngInput) lngInput.value = rounded.lng;
        if (locationMarker) {
            locationMarker.setLatLng([rounded.lat, rounded.lng]);
        } else {
            locationMarker = L.marker([rounded.lat, rounded.lng], {
                icon: locationIcon,
                draggable: true,
                zIndexOffset: 1000,
            }).addTo(map);
            locationMarker.on('dragend', function () {
                const p = locationMarker.getLatLng();
                setLocation(p.lat, p.lng, { skipPan: true });
            });
        }
        if (!opts.skipPan && !opts.fromUser) {
            map.panTo([rounded.lat, rounded.lng]);
        }
    }

    if (hasInitialLocation) {
        setLocation(initialLat, initialLng, { skipPan: true });
    }

    // Clicking the map (not a pin) drops / moves the location marker.
    map.on('click', function (e) {
        setLocation(e.latlng.lat, e.latlng.lng, { skipPan: true, fromUser: true });
    });

    // ── Tide stations: small blue dots, darker/larger when selected.
    //
    // Two sizes so the hitbox is generous (20px) while the visible dot
    // stays compact. Selected keeps the same palette — just bolder —
    // so it's distinct from the orange forecast-location pin.
    const stationIcon = L.divIcon({
        className: 'pattern-station-marker',
        iconSize: [20, 20],
        iconAnchor: [10, 10],
        html: '<div class="pattern-station-dot"></div>'
    });
    const selectedStationIcon = L.divIcon({
        className: 'pattern-station-marker pattern-station-marker-selected',
        iconSize: [22, 22],
        iconAnchor: [11, 11],
        html: '<div class="pattern-station-dot pattern-station-dot-selected"></div>'
    });

    let selectedStationMarker = null;
    function selectStation(station, marker) {
        if (stationInput) stationInput.value = station.id;
        if (!locationMarker) {
            setLocation(station.lat, station.lng, { skipPan: true });
        }
        if (locationNameInput
            && (!locationNameInput.value || locationNameInput.dataset.autofilled === 'true')) {
            locationNameInput.value = station.name;
            locationNameInput.dataset.autofilled = 'true';
        }
        if (selectedStationMarker) {
            selectedStationMarker.setIcon(stationIcon);
        }
        marker.setIcon(selectedStationIcon);
        selectedStationMarker = marker;
    }

    if (stationsURL) {
        fetch(stationsURL, { credentials: 'same-origin' })
            .then(function (r) { return r.ok ? r.json() : []; })
            .then(function (stations) {
                stations.forEach(function (s) {
                    if (!Number.isFinite(s.lat) || !Number.isFinite(s.lng)) return;
                    const isInitial = s.id === initialStation;
                    const marker = L.marker([s.lat, s.lng], {
                        icon: isInitial ? selectedStationIcon : stationIcon,
                        title: s.name + (s.state ? ' (' + s.state + ')' : ''),
                    }).addTo(map);
                    if (isInitial) {
                        selectedStationMarker = marker;
                    }
                    marker.on('click', function (e) {
                        L.DomEvent.stopPropagation(e);
                        // Use the existing selectStation, but preserve
                        // any location_name the user typed manually — only
                        // auto-fill if it was previously autofilled.
                        selectStation(s, marker);
                    });
                    marker.bindTooltip(s.name + (s.state ? ' (' + s.state + ')' : ''));
                });
            })
            .catch(function (err) {
                console.warn('Tide stations fetch failed', err);
            });
    }
})();
