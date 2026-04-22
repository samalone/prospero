// Mobile-friendly bar selection for the calendar view.
//
// Desktop users get the info card via CSS :hover. Keyboard users get it
// via :focus-visible. But mobile users can't hover and tapping a
// focusable div doesn't give a natural "tap again to dismiss" gesture.
//
// This script manages a `.is-selected` class on .calendar-bar:
//   - Tap an unselected bar → select it (and clear any other selection).
//   - Tap a selected bar → deselect it.
//   - Tap outside any bar → clear the selection.
//
// CSS in styles.css shows the info card when the bar is selected,
// hovered, or keyboard-focused.
(function () {
    function clearSelection() {
        for (const el of document.querySelectorAll('.calendar-bar.is-selected')) {
            el.classList.remove('is-selected');
        }
    }

    document.addEventListener('click', function (event) {
        const bar = event.target.closest('.calendar-bar');
        if (!bar) {
            clearSelection();
            return;
        }
        const wasSelected = bar.classList.contains('is-selected');
        clearSelection();
        if (!wasSelected) {
            bar.classList.add('is-selected');
        }
    });
})();
