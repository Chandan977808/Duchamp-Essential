//! Charger-input suspend policy for the Charging Limit Control.
//! The daemon owns `/sys/class/power_supply/battery/input_suspend`; the app
//! only sees verified state. `true` suspends charger input; every write is
//! confirmed by readback, never assumed.

pub fn valid_limit(value: i32) -> bool {
    matches!(value, 80 | 85 | 90 | 95)
}

/// The user contract is explicit: while enabled, charger input suspends once
/// the level reaches the limit and stays suspended until the level drops
/// BELOW the limit again. Disabled never suspends. Unlike the bypass release
/// band there is no hysteresis gap: below the limit means strictly
/// `capacity < limit`, exactly as selected.
pub fn suspended(enabled: bool, limit: i32, capacity: Option<i32>) -> Result<bool, String> {
    if !valid_limit(limit) {
        return Err("invalid charge limit".into());
    }
    if !enabled {
        return Ok(false);
    }
    let capacity = capacity
        .filter(|value| (0..=100).contains(value))
        .ok_or_else(|| "battery level unavailable for charge limit".to_string())?;
    Ok(capacity >= limit)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn suspends_at_the_limit_and_releases_only_below_it() {
        for limit in [80, 85, 90, 95] {
            assert_eq!(suspended(true, limit, Some(limit - 1)), Ok(false));
            assert_eq!(suspended(true, limit, Some(limit)), Ok(true));
            assert_eq!(suspended(true, limit, Some(limit + 1)), Ok(true));
        }
    }

    #[test]
    fn disabled_never_suspends_and_invalid_inputs_are_not_guessed() {
        assert_eq!(suspended(false, 80, Some(95)), Ok(false));
        for capacity in [None, Some(-1), Some(101)] {
            assert!(suspended(true, 80, capacity).is_err());
        }
        for limit in [0, 20, 50, 79, 81, 100] {
            assert!(suspended(true, limit, Some(50)).is_err());
            assert!(!valid_limit(limit));
        }
        for limit in [80, 85, 90, 95] {
            assert!(valid_limit(limit));
        }
    }
}
