// Custom range slider with "no limit" endpoints.
//
// Progressive enhancement: finds every `.range-slider` container, reads
// its configuration from data attributes, and renders a track + one
// or two thumbs. Writes back into hidden form inputs so the backend
// sees standard URL-encoded values.
//
// Container markup:
//
//   <div class="range-slider"
//        data-min="0" data-max="110" data-step="1"
//        data-unit="°F"
//        data-mode="range"                  (default: "range"; "value" for duration)
//        data-low-input="temperature_min"   (id of hidden input, omit for single-max)
//        data-high-input="temperature_max"  (omit for single-min)
//        data-label-any="Any temperature"
//        data-label-below="Below {high}{unit}"
//        data-label-above="Above {low}{unit}"
//        data-label-between="{low}–{high}{unit}"
//        data-label-value="{value} hr">
//   </div>
//
// `range` mode: thumb at `min` (low) or `max` (high) means "no limit"
// and the corresponding input gets an empty string. Other positions
// set the input to that numeric value.
//
// `value` mode: always has a concrete value. No "no limit" endpoints.
// Used for things like required duration where "no minimum" isn't a
// meaningful state.

(function () {
    'use strict';

    // Format a number using the slider's step to decide decimals: step
    // ≥ 1 → integer; step < 1 → one decimal place. Keeps things tidy
    // without pulling in a real number-formatter.
    function formatValue(v, step) {
        if (step >= 1) return String(Math.round(v));
        return (Math.round(v * 10) / 10).toFixed(1);
    }

    // Format an hour 0–23 as a 12-hour clock string ("8 AM", "12 PM").
    function formatHour12(v) {
        const h = Math.round(v);
        if (h === 0) return '12 AM';
        if (h === 12) return 'noon';
        if (h < 12) return h + ' AM';
        return (h - 12) + ' PM';
    }

    function formatWithMode(v, step, format) {
        if (format === 'hour12') return formatHour12(v);
        return formatValue(v, step);
    }

    function substitute(template, vars) {
        return template
            .replace(/\{low\}/g, vars.low || '')
            .replace(/\{high\}/g, vars.high || '')
            .replace(/\{value\}/g, vars.value || '')
            .replace(/\{unit\}/g, vars.unit || '');
    }

    function init(el) {
        const min = parseFloat(el.dataset.min);
        const max = parseFloat(el.dataset.max);
        const step = parseFloat(el.dataset.step) || 1;
        const unit = el.dataset.unit || '';
        const mode = el.dataset.mode || 'range';
        const format = el.dataset.format || '';   // e.g. "hour12"

        const lowInput = el.dataset.lowInput ? document.getElementById(el.dataset.lowInput) : null;
        const highInput = el.dataset.highInput ? document.getElementById(el.dataset.highInput) : null;

        if (!lowInput && !highInput) {
            console.warn('range-slider: no data-low-input or data-high-input', el);
            return;
        }

        // Current state. In range mode, an empty input == "no limit" for
        // that side; we render the thumb at the corresponding extreme.
        // In value mode there is no "empty" state — a missing input just
        // means "start at the low end."
        function readInput(inp, fallback) {
            const raw = inp && inp.value && inp.value.trim();
            if (!raw) return { value: fallback, empty: mode !== 'value' };
            const n = parseFloat(raw);
            if (!Number.isFinite(n)) return { value: fallback, empty: mode !== 'value' };
            return { value: n, empty: false };
        }

        let lowState = lowInput ? readInput(lowInput, min) : { value: min, empty: true };
        let highState = highInput ? readInput(highInput, max) : { value: max, empty: true };

        // --- Build UI ------------------------------------------------------

        el.innerHTML = '';  // clear any placeholder content

        const label = document.createElement('div');
        label.className = 'range-slider-label';
        label.setAttribute('aria-live', 'polite');
        el.appendChild(label);

        const track = document.createElement('div');
        track.className = 'range-slider-track';
        el.appendChild(track);

        // Muted-gradient layer beneath the fill. A sibling (not the
        // track itself) so the CSS `filter: saturate(...)` that mutes
        // it can't leak to the fill or the thumbs.
        const trackBg = document.createElement('div');
        trackBg.className = 'range-slider-track-bg';
        track.appendChild(trackBg);

        const fill = document.createElement('div');
        fill.className = 'range-slider-fill';
        track.appendChild(fill);

        function makeThumb(side) {
            const t = document.createElement('div');
            t.className = 'range-slider-thumb range-slider-thumb-' + side;
            t.setAttribute('role', 'slider');
            t.setAttribute('tabindex', '0');
            t.setAttribute('aria-valuemin', String(min));
            t.setAttribute('aria-valuemax', String(max));
            return t;
        }

        let lowThumb = null, highThumb = null;
        if (lowInput) {
            lowThumb = makeThumb('low');
            track.appendChild(lowThumb);
        }
        if (highInput) {
            highThumb = makeThumb('high');
            track.appendChild(highThumb);
        }

        // --- Render --------------------------------------------------------

        function valueToPct(v) {
            if (max === min) return 0;
            return ((v - min) / (max - min)) * 100;
        }

        function render() {
            const lowPct = lowThumb ? valueToPct(lowState.value) : 0;
            const highPct = highThumb ? valueToPct(highState.value) : 100;

            if (lowThumb) {
                lowThumb.style.left = lowPct + '%';
                lowThumb.setAttribute('aria-valuenow', String(lowState.value));
                lowThumb.setAttribute(
                    'aria-valuetext',
                    lowState.empty ? 'no minimum' : formatValue(lowState.value, step) + ' ' + unit
                );
            }
            if (highThumb) {
                highThumb.style.left = highPct + '%';
                highThumb.setAttribute('aria-valuenow', String(highState.value));
                highThumb.setAttribute(
                    'aria-valuetext',
                    highState.empty ? 'no maximum' : formatValue(highState.value, step) + ' ' + unit
                );
            }

            // Fill semantics:
            // - value mode: progress-bar style, 0 → thumb.
            // - range mode: highlight the *allowed* band. For dual, that's
            //   between the thumbs. For single-max, 0 → thumb (up to X%).
            //   For single-min, thumb → 100% (X ft or more).
            let fillLeft, fillRight;
            if (mode === 'value') {
                const v = lowThumb ? lowState.value : highState.value;
                fillLeft = 0;
                fillRight = valueToPct(v);
            } else {
                fillLeft = lowThumb ? lowPct : 0;
                fillRight = highThumb ? highPct : 100;
            }
            // clip-path keeps the fill's gradient aligned with the track's
            // gradient in screen coordinates — the fill is always full-width
            // but clipped to the active band. `inset(top right bottom left)`.
            const clipRight = Math.max(0, 100 - fillRight);
            const clipLeft = Math.max(0, fillLeft);
            fill.style.clipPath =
                'inset(0 ' + clipRight + '% 0 ' + clipLeft + '%)';

            // Write back to hidden inputs.
            if (lowInput) {
                lowInput.value = (mode === 'range' && lowState.empty)
                    ? ''
                    : formatValue(lowState.value, step);
            }
            if (highInput) {
                highInput.value = (mode === 'range' && highState.empty)
                    ? ''
                    : formatValue(highState.value, step);
            }

            // Update label.
            label.textContent = buildLabel();
        }

        function buildLabel() {
            const fmt = v => formatWithMode(v, step, format);

            if (mode === 'value') {
                const v = lowThumb ? lowState.value : highState.value;
                return substitute(
                    el.dataset.labelValue || '{value}{unit}',
                    { value: fmt(v), unit: unit }
                );
            }
            const lowEmpty = !lowThumb || lowState.empty;
            const highEmpty = !highThumb || highState.empty;
            if (lowEmpty && highEmpty) {
                return el.dataset.labelAny || 'Any';
            }
            // Single-max pinned at the floor ("Below 0%") or single-min
            // pinned at the ceiling reads as nonsensical — just show the
            // bare value (e.g. "0%").
            if (lowEmpty && !lowThumb && highState.value === min) {
                return fmt(highState.value) + unit;
            }
            if (highEmpty && !highThumb && lowState.value === max) {
                return fmt(lowState.value) + unit;
            }
            if (lowEmpty) {
                return substitute(
                    el.dataset.labelBelow || 'Below {high}{unit}',
                    { high: fmt(highState.value), unit: unit }
                );
            }
            if (highEmpty) {
                return substitute(
                    el.dataset.labelAbove || 'Above {low}{unit}',
                    { low: fmt(lowState.value), unit: unit }
                );
            }
            return substitute(
                el.dataset.labelBetween || '{low}–{high}{unit}',
                { low: fmt(lowState.value), high: fmt(highState.value), unit: unit }
            );
        }

        // --- Interaction ---------------------------------------------------

        function snap(v) {
            const stepped = Math.round((v - min) / step) * step + min;
            return Math.max(min, Math.min(max, stepped));
        }

        function setLow(v) {
            v = snap(v);
            if (highThumb) v = Math.min(v, highState.value);
            lowState.value = v;
            // "Empty" (no minimum) when parked at `min`, only in range mode.
            lowState.empty = (mode === 'range') && (Math.abs(v - min) < step / 2);
            render();
        }

        function setHigh(v) {
            v = snap(v);
            if (lowThumb) v = Math.max(v, lowState.value);
            highState.value = v;
            highState.empty = (mode === 'range') && (Math.abs(v - max) < step / 2);
            render();
        }

        function positionToValue(clientX) {
            const rect = track.getBoundingClientRect();
            if (rect.width <= 0) return min;
            const pct = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
            return min + pct * (max - min);
        }

        function bindThumb(thumb, side) {
            const isLow = side === 'low';
            const setter = isLow ? setLow : setHigh;

            thumb.addEventListener('pointerdown', function (e) {
                if (e.button !== undefined && e.button !== 0) return;
                e.preventDefault();
                thumb.setPointerCapture(e.pointerId);
                thumb.classList.add('range-slider-thumb-active');
                setter(positionToValue(e.clientX));

                function onMove(ev) { setter(positionToValue(ev.clientX)); }
                function onUp(ev) {
                    thumb.releasePointerCapture(ev.pointerId);
                    thumb.classList.remove('range-slider-thumb-active');
                    thumb.removeEventListener('pointermove', onMove);
                    thumb.removeEventListener('pointerup', onUp);
                    thumb.removeEventListener('pointercancel', onUp);
                }
                thumb.addEventListener('pointermove', onMove);
                thumb.addEventListener('pointerup', onUp);
                thumb.addEventListener('pointercancel', onUp);
            });

            thumb.addEventListener('keydown', function (e) {
                let handled = true;
                const cur = isLow ? lowState.value : highState.value;
                const big = Math.max(step, (max - min) / 10);
                switch (e.key) {
                    case 'ArrowLeft':
                    case 'ArrowDown':
                        setter(cur - step); break;
                    case 'ArrowRight':
                    case 'ArrowUp':
                        setter(cur + step); break;
                    case 'PageDown':
                        setter(cur - big); break;
                    case 'PageUp':
                        setter(cur + big); break;
                    case 'Home':
                        setter(min); break;
                    case 'End':
                        setter(max); break;
                    default:
                        handled = false;
                }
                if (handled) e.preventDefault();
            });
        }

        if (lowThumb) bindThumb(lowThumb, 'low');
        if (highThumb) bindThumb(highThumb, 'high');

        // Tap on the track: move whichever thumb is closer.
        track.addEventListener('pointerdown', function (e) {
            // If the target is a thumb, let its handler take over.
            if (e.target.classList.contains('range-slider-thumb')) return;
            const v = positionToValue(e.clientX);
            if (!lowThumb) { setHigh(v); highThumb.focus(); return; }
            if (!highThumb) { setLow(v); lowThumb.focus(); return; }
            const distLow = Math.abs(v - lowState.value);
            const distHigh = Math.abs(v - highState.value);
            if (distLow <= distHigh) { setLow(v); lowThumb.focus(); }
            else { setHigh(v); highThumb.focus(); }
        });

        render();
    }

    document.querySelectorAll('.range-slider').forEach(init);
})();
