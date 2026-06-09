// Calendar interactivity: tz cookie, tap-to-select for mobile, and
// per-bar day/night shading override.
//
// The CSS in styles.css draws the track's day/night band from CSS custom
// properties --sunrise / --sunset. Each .calendar-bar carries data-sunrise /
// data-sunset with that pattern's own solar times for the day (as % of
// day, 0–100). When a bar is hovered, focused, or tap-selected, we copy
// those values onto the enclosing .calendar-day-track — the gradient
// re-resolves, and the caption swaps to that bar's pattern name. On
// mouse leave / blur / deselect we clear the override, which falls back
// to --sunrise-default / --sunset-default (the reference location).
(function () {
    // --- tz cookie ---------------------------------------------------
    //
    // Forward the browser's IANA timezone to the server so it can pick a
    // representative lat/lon for the default shading. Set once, persistent
    // for a year, scoped to the current path so sibling apps on the same
    // domain don't see it. No geolocation permission is involved.
    function setTzCookieIfMissing() {
        const hasCookie = document.cookie
            .split(';')
            .some(c => c.trim().startsWith('tz='));
        if (hasCookie) return;
        try {
            const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
            if (!tz) return;
            // Derive a path prefix from the current location so the cookie
            // matches the app's mount path (e.g., /prospero or /) without
            // needing the server to inject it.
            const pathPrefix = window.location.pathname.split('/')[1]
                ? '/' + window.location.pathname.split('/')[1]
                : '/';
            document.cookie =
                'tz=' + encodeURIComponent(tz) +
                '; path=' + pathPrefix +
                '; max-age=31536000' +
                '; samesite=lax';
        } catch (e) {
            // Intl not available — fine, the server will use its default.
        }
    }
    setTzCookieIfMissing();

    // --- tap-to-select ----------------------------------------------
    //
    // Desktop users get the info card via CSS :hover. Keyboard users get
    // it via :focus-visible. Mobile users can't hover and tapping a
    // focusable div doesn't give a natural "tap again to dismiss"
    // gesture, so we manage a .is-selected class explicitly.
    function clearSelection() {
        for (const el of document.querySelectorAll('.calendar-bar.is-selected')) {
            el.classList.remove('is-selected');
        }
    }

    document.addEventListener('click', function (event) {
        const bar = event.target.closest('.calendar-bar');
        if (!bar) {
            clearSelection();
            clearShadingOverride();
            return;
        }
        const wasSelected = bar.classList.contains('is-selected');
        clearSelection();
        if (wasSelected) {
            // Tapping a selected bar dismisses the overlay — blur
            // releases the tap-focus some mobile browsers leave on
            // the bar, which would otherwise keep the card visible.
            bar.blur();
            clearShadingOverride();
        } else {
            bar.classList.add('is-selected');
            applyShadingOverride(bar);
        }
    });

    // --- shading override -------------------------------------------
    //
    // Copy a bar's data-sunrise/data-sunset onto its enclosing track as
    // --sunrise/--sunset so the gradient in styles.css re-resolves to
    // that pattern's real day/night boundaries. Also update the caption
    // to name the pattern whose sun we're currently showing.
    function captionValueEl() {
        return document.querySelector(
            '#calendar-shading-caption .calendar-shading-label-value'
        );
    }

    function applyShadingOverride(bar) {
        const sunrise = bar.dataset.sunrise;
        const sunset = bar.dataset.sunset;
        const track = bar.closest('.calendar-day-track');
        // Empty strings are the server-side sentinel for "we don't have
        // solar data for this pattern on this day" — leave the default.
        if (track && sunrise && sunset) {
            track.style.setProperty('--sunrise', sunrise);
            track.style.setProperty('--sunset', sunset);
        }
        const label = bar.dataset.locationLabel;
        const captionValue = captionValueEl();
        if (label && captionValue) {
            captionValue.textContent = label;
        }
    }

    function clearShadingOverride() {
        for (const track of document.querySelectorAll('.calendar-day-track')) {
            track.style.removeProperty('--sunrise');
            track.style.removeProperty('--sunset');
        }
        const captionValue = captionValueEl();
        if (captionValue && captionValue.dataset.defaultLabel) {
            captionValue.textContent = captionValue.dataset.defaultLabel;
        }
    }

    // Hover + keyboard focus. Delegated on document so dynamically
    // inserted bars (htmx swaps the calendar every 30 min) also work.
    document.addEventListener('mouseover', function (event) {
        const bar = event.target.closest('.calendar-bar');
        if (bar) applyShadingOverride(bar);
    });
    document.addEventListener('mouseout', function (event) {
        const bar = event.target.closest('.calendar-bar');
        if (!bar) return;
        // Only clear when the mouse has actually left the bar (not moved
        // into a child like the label span or info card).
        const to = event.relatedTarget;
        if (to && bar.contains(to)) return;
        // If a tap-selection is active, keep that override instead.
        const selected = document.querySelector('.calendar-bar.is-selected');
        if (selected) {
            applyShadingOverride(selected);
        } else {
            clearShadingOverride();
        }
    });
    document.addEventListener('focusin', function (event) {
        const bar = event.target.closest('.calendar-bar');
        if (bar) applyShadingOverride(bar);
    });
    document.addEventListener('focusout', function (event) {
        const bar = event.target.closest('.calendar-bar');
        if (!bar) return;
        const selected = document.querySelector('.calendar-bar.is-selected');
        if (selected && selected !== bar) {
            applyShadingOverride(selected);
        } else if (!selected) {
            clearShadingOverride();
        }
    });

    // --- refresh on return ------------------------------------------
    //
    // The calendar polls every 30 min via htmx (`hx-trigger="every
    // 1800s, refresh"`), but iOS suspends background tabs and pauses JS
    // timers, so a page left open on an iPad shows stale data when the
    // user comes back days later. When the page becomes visible again —
    // or is restored from Safari's back/forward cache (pageshow with
    // persisted=true, which doesn't fire visibilitychange) — we ask
    // htmx to re-fetch by dispatching the `refresh` event the trigger
    // listens for. We requery #calendar-content each time because htmx
    // swaps in a fresh element (outerHTML) on every load.
    //
    // A threshold avoids refetching on a brief tab switch: the server
    // pulls live forecasts for every pattern on each load, so we only
    // refresh when the data could plausibly be stale.
    const REFRESH_AFTER_MS = 5 * 60 * 1000;
    let lastLoad = Date.now();

    document.body.addEventListener('htmx:afterSwap', function (event) {
        if (event.target && event.target.id === 'calendar-content') {
            lastLoad = Date.now();
        }
    });

    function maybeRefreshOnReturn() {
        if (document.visibilityState !== 'visible') return;
        if (Date.now() - lastLoad < REFRESH_AFTER_MS) return;
        const el = document.querySelector('#calendar-content');
        if (el && window.htmx) window.htmx.trigger(el, 'refresh');
    }

    document.addEventListener('visibilitychange', maybeRefreshOnReturn);
    window.addEventListener('pageshow', function (event) {
        if (event.persisted) maybeRefreshOnReturn();
    });
})();
