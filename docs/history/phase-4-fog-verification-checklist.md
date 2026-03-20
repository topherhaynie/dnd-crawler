# Phase 4 Fog Verification Checklist

Use this checklist after fog architecture changes to validate performance, stability, and packet safety.

## Preconditions

1. Run a debug build.
2. Start DM process and at least one Player display process.
3. Load a medium map (roughly 2k x 2k or larger) with wall geometry.
4. Ensure fog is enabled and tokens are present.

## Telemetry Expectations

1. Fog overlay logs rebuild and delta timings from `FogOverlay`.
2. DM logs fog delta/full-sync counts.
3. NetworkManager logs fog packet byte totals and counts.
4. No repeated outbound pressure warnings under normal play.

## Visual Consistency Checks

1. Move player tokens to trigger DM-side LOS updates (live lights in `FogSystem`).
2. Apply DM fog brush reveal and hide edits repeatedly.
3. Confirm player and DM fog shapes match visually for same framing.

## Transport Safety Checks

1. Verify `map_loaded` and `map_updated` payloads do not include large fog arrays.
2. Verify frequent fog updates use `fog_delta` plus periodic `fog_updated`.
3. Simulate packet loss/order issues (disconnect/reconnect player) and verify recovery on next full sync.

## Stress Scenario

1. Hold movement input for 60 seconds while rotating camera zoom/pan.
2. During movement, alternate DM fog tool between reveal brush and hide rectangle every 2-3 seconds.
3. Observe frame behavior for both DM and Player windows.
4. Expected:
   1. No websocket outbound OOM or runaway queue behavior.
   2. Fog updates remain responsive.
   3. No major frame-time spikes on camera micro-movement.
   4. Fog edges remain smooth at normal zoom levels.

## Pass/Fail Criteria

1. Pass if all visual-consistency, transport, and stress checks complete with no critical warnings.
2. Fail if DM/player fog diverges persistently or outbound pressure repeats continuously.
