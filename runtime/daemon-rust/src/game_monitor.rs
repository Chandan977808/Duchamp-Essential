use super::run_process_with_timeout;
use serde_json::json;
use std::{fs, time::Duration};

fn surface(args: &[&str]) -> Option<String> {
    let output =
        run_process_with_timeout("/system/bin/dumpsys", args, Duration::from_millis(650)).ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).into_owned())
}

fn layer_name(line: &str) -> Option<&str> {
    let line = line.trim();
    if let Some(entry) = line.strip_prefix("RequestedLayerState{") {
        // Android 16/17 may wrap --list entries in RequestedLayerState and
        // append parent metadata. --latency expects only the layer name.
        let end = entry.find(" parentId=").or_else(|| entry.rfind('}'))?;
        let name = entry[..end].trim();
        (!name.is_empty()).then_some(name)
    } else {
        (!line.is_empty()).then_some(line)
    }
}

fn layer_candidates<'a>(list: &'a str, package: &str) -> Vec<&'a str> {
    let belongs = |line: &str| {
        line.split(|c: char| !(c.is_ascii_alphanumeric() || c == '_' || c == '.'))
            .any(|s| s == package)
    };
    let candidates: Vec<_> = list
        .lines()
        .filter_map(layer_name)
        .filter(|s| {
            belongs(s)
                && !s.contains("ActivityRecord")
                && !s.contains("InputSink")
                && !s.contains("leash")
                && !s.contains("Background for")
        })
        .collect();

    // Prefer the app's BLAST SurfaceView, but keep lower-priority surfaces as
    // fallbacks: on some Android builds the preferred layer has no latency
    // history even while another app-owned surface is presenting frames.
    let mut ordered = Vec::new();
    for rank in 0..4 {
        let mut matching = candidates.iter().copied().filter(|s| {
            let priority = if s.contains("SurfaceView") && s.contains("BLAST") {
                0
            } else if s.contains("SurfaceView") {
                1
            } else if s.starts_with("VRI-") || s.contains("BLAST") {
                2
            } else {
                3
            };
            priority == rank
        });
        if let Some(first) = matching.next() {
            // Avoid guessing between multiple layers at the same priority.
            if matching.next().is_none() {
                ordered.push(first);
            }
        }
    }
    ordered
}

fn present_timestamps(output: &str) -> Vec<i64> {
    output
        .lines()
        .skip(1)
        .filter_map(|row| row.split_whitespace().nth(1)?.parse::<i64>().ok())
        .filter(|&t| t > 0 && t != i64::MAX)
        .collect()
}

pub(super) fn sample(package: &str) -> String {
    if package.is_empty()
        || package.len() > 255
        || !package
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"._".contains(&b))
    {
        return "ERR invalid package".into();
    }
    let times = surface(&["SurfaceFlinger", "--list"])
        .map(|list| {
            // --latency can return only its refresh-period header for a valid
            // layer with no recorded frames. Try the next app-owned surface
            // instead of treating that empty buffer as the game's FPS.
            for name in layer_candidates(&list, package).into_iter().take(3) {
                if let Some(output) = surface(&["SurfaceFlinger", "--latency", name]) {
                    let timestamps = present_timestamps(&output);
                    if !timestamps.is_empty() {
                        return timestamps;
                    }
                }
            }
            Vec::new()
        })
        .unwrap_or_default();
    let cpu = fs::read_to_string("/proc/stat").ok().and_then(|s| {
        let ticks: Vec<u64> = s
            .lines()
            .next()?
            .strip_prefix("cpu ")?
            .split_whitespace()
            .take(8)
            .map(str::parse)
            .collect::<Result<_, _>>()
            .ok()?;
        (ticks.len() == 8).then(|| [ticks.iter().sum::<u64>(), ticks[3] + ticks[4]])
    });
    let gpu = fs::read_to_string("/sys/kernel/ged/hal/gpu_utilization")
        .ok()
        .and_then(|s| s.split_whitespace().next()?.parse::<u32>().ok())
        .filter(|v| *v <= 100);
    format!("OK {}", json!({"present":times,"cpu":cpu,"gpu":gpu}))
}

#[cfg(test)]
mod tests {
    use super::{layer_candidates, present_timestamps};

    #[test]
    fn unwraps_android17_requested_layer_state() {
        let list = "RequestedLayerState{e7b0cc0 SurfaceView[com.pubg.imobile/com.epicgames.ue4.GameActivity](BLAST)#2487 parentId=2486}";
        assert_eq!(
            layer_candidates(list, "com.pubg.imobile"),
            vec!["e7b0cc0 SurfaceView[com.pubg.imobile/com.epicgames.ue4.GameActivity](BLAST)#2487"]
        );
    }

    #[test]
    fn prefers_blast_but_keeps_fallback_surfaces() {
        let list = concat!(
            "RequestedLayerState{blast SurfaceView[com.game/Main](BLAST)#1 parentId=9}\n",
            "RequestedLayerState{view SurfaceView[com.game/Main]#2 parentId=9}\n",
            "RequestedLayerState{vri VRI-com.game/Main#3 parentId=9}"
        );
        assert_eq!(
            layer_candidates(list, "com.game"),
            vec![
                "blast SurfaceView[com.game/Main](BLAST)#1",
                "view SurfaceView[com.game/Main]#2",
                "vri VRI-com.game/Main#3"
            ]
        );
    }

    #[test]
    fn rejects_ambiguous_layers_and_package_prefixes() {
        let list = "SurfaceView[com.game.beta/Main]#1\nSurfaceView[com.game/Main]#2";
        assert_eq!(
            layer_candidates(list, "com.game"),
            vec!["SurfaceView[com.game/Main]#2"]
        );
        let ambiguous = "SurfaceView[com.game/Main]#2\nSurfaceView[com.game/Video]#4";
        assert!(layer_candidates(ambiguous, "com.game").is_empty());
    }

    #[test]
    fn reads_actual_present_timestamps_not_refresh_period() {
        let output = "8333333\n0 1000000000 900000000\n0 1016666666 916666666\n";
        assert_eq!(present_timestamps(output), vec![1000000000, 1016666666]);
        assert!(present_timestamps("8333333\n").is_empty());
    }
}
