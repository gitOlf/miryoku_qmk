// Native QMK callbacks, compiled only for the opt-in profile.
#ifdef MIRYOKU_TIMELESS_HRM
#include QMK_KEYBOARD_H
#include "action_tapping.h"

// Fail clearly on the older core in this fork instead of silently ignoring
// unsupported feature defines. Update/rebase the QMK core before enabling.
_Static_assert(sizeof(&get_chordal_hold) > 0, "QMK Chordal Hold support required");
_Static_assert(sizeof(&get_flow_tap_term) > 0, "QMK Flow Tap support required");
_Static_assert(sizeof(&get_speculative_hold) > 0, "QMK Speculative Hold support required");

uint16_t get_tapping_term(uint16_t keycode, keyrecord_t *record) {
    return IS_QK_MOD_TAP(keycode) ? TAPPING_TERM : 100;
}

bool get_permissive_hold(uint16_t keycode, keyrecord_t *record) {
    return IS_QK_MOD_TAP(keycode);
}

bool get_chordal_hold(uint16_t keycode, keyrecord_t *record, uint16_t other_keycode, keyrecord_t *other_record) {
    return !IS_QK_MOD_TAP(keycode) || get_chordal_hold_default(record, other_record);
}

uint16_t get_flow_tap_term(uint16_t keycode, keyrecord_t *record, uint16_t prev_keycode) {
    // Preserve QMK's normal flow eligibility rules, but exclude thumb layer-taps.
    return IS_QK_MOD_TAP(keycode) && is_flow_tap_key(keycode) && is_flow_tap_key(prev_keycode)
        ? FLOW_TAP_TERM : 0;
}
#endif
