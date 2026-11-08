// Opt-in native QMK tap-hold profile. Requires current QMK core support.
#pragma once

#ifdef MIRYOKU_TIMELESS_HRM
#    undef TAPPING_TERM
#    define TAPPING_TERM 250
#    define TAPPING_TERM_PER_KEY
#    undef IGNORE_MOD_TAP_INTERRUPT
#    define PERMISSIVE_HOLD_PER_KEY
#    define FLOW_TAP_TERM 150
#    define CHORDAL_HOLD
#    define SPECULATIVE_HOLD

// Callback implementation scopes decisions to mod-taps, preserving thumb
// layer-tap timing. Define in custom_config.h only after updating QMK core.
#endif
