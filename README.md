# Shuffle Run — movement runner concept

A native SwiftUI macOS prototype using only procedural shapes, text, and system symbols. No downloaded art, models, audio, dependencies, or camera uploads.

## Run

Open `poc game.xcodeproj` in Xcode. Select the **poc game** scheme and **My Mac**, then press **⌘R**. Requires macOS 14 or later. Accept camera permission, place your Mac securely facing you, and frame your head, torso, and hips. Both shoulders and hips must remain visible; knees, ankles, and feet may stay outside the frame. Camera mode uses the macOS default camera (built-in, USB webcam, or Continuity Camera). Choose **Try cursor demo** to test without a camera.

Cursor demo: hover in the **left, center, or right third of the play frame** to select a lane. Hold the requested lane for 0.8 seconds during calibration. During gameplay the runner switches immediately to the hovered lane, with no simulated travel delay. Wait for MOVE NOW, then change lanes. Agility measures time from that signal to correct lane entry; coordination measures lane-entry timing relative to the obstacle. Actual cursor travel speed remains diagnostic. For arm cues, move your cursor into the target on the beat; the cyan marker follows the cursor. No arrow keys are needed. Leaving the actual window (including while dragging) freezes timing, calibration, travel, scoring, and boss time. Returning continues the same cue; a manual/background pause still requires Resume. Moving across the header or sidebar stays inside the window and does not trigger the automatic pause. Clicks remain an optional arm-target shortcut. If camera access is denied, enable the app in **System Settings → Privacy & Security → Camera**, then restart it. Camera access is included in the app sandbox entitlements.

Calibration requires center → left box → right box → center, holding each position for 0.8 seconds. Cursor Demo uses cursor-selected lanes to simulate the same calibration. It cannot bypass calibration. During play, follow the left, right, and center shuffle cues and touch the arm targets on the beat. Jump, duck, and the old reach gesture have been replaced by arm targets. Keep at least one wrist visible during an arm cue. Left/right/center move the runner; arm cues show your mirrored skeleton and hand markers against a placeholder target. Approaching wireframe obstacles block the unsafe lanes and reach the player at the ideal dodge beat. The lane cue identifies the safe lane; WAIT precedes the MOVE NOW window. World geometry uses placeholder primitives.

Pause freezes timing. Losing torso/hip tracking freezes scoring and active time. Backgrounding pauses the game and stops capture; foregrounding requires Resume. Restart returns to the mode picker and clears progress when starting another calibration.

## Two input modes

Choose **Vision camera** on Mac for camera control with shoulders and hips visible, or **iPhone IMU sensors** for the phone controller. Cursor Demo remains available for local testing.

### Connect iPhone IMU

1. Run the project on **My Mac**, then choose **iPhone IMU sensors**. The Mac shows its local address including port and a six-digit pairing code.
2. In Xcode select the same **poc game** scheme and your **physical iPhone** as the destination. Choose your signing team if Xcode requests it, and run. iOS 17+ opens the motion companion; macOS 14+ opens the game.
3. Keep both devices on the same trusted Wi-Fi. Allow Local Network access on both devices and motion access on iPhone if requested. Enter the Mac address and code on iPhone, then Connect. If the host name does not resolve, substitute the Mac's local IPv4 address and retain the displayed port.
4. Secure iPhone upright at your waist, screen outward. Keep facing the Mac and keep the companion in the foreground. On Mac confirm that you are standing at center, then shuffle left, right, and back to center, stopping briefly after each trip.
5. Follow the Mac's timing bar. The iPhone displays the current movement instruction. A disconnect, invalid orientation, or wrong-way shuffle pauses play; return to center before pressing Resume. Interrupted calibration starts again from center.

IMU mode currently uses **left/right/center shuffle cues only**, including in boss arenas. Vision mode also supports timed arm targets. A waist-mounted phone does not provide wrist tracking for target contact.

The phone samples Core Motion at a requested 50 Hz and detects lateral acceleration bursts. The first calibration shuffle establishes the lateral sign. Travel ends at the last active sample before a 250 ms quiet interval. Sampling gaps, very brief impulses, invalid orientation, and movements longer than four seconds are discarded. This is an unvalidated movement-event heuristic: constant-speed motion, foot impacts, or torso rotation can cause errors. It cannot verify distance or physical box arrival; each correctly directed completed movement is assigned to the requested target.

A local TCP connection carries only movement events, status, clock-sync messages, and instructions. A per-session code limits acceptance to the paired phone; this prototype connection is **not encrypted**, so use a trusted local network. No sensor recording is saved. Clock offset is estimated with ping/pong exchanges using the lowest observed round-trip time. Scoring uses mapped sensor timestamps, not receipt time. A 650 ms processing allowance accommodates stop detection and delivery without widening the scored arrival window. Local Network permissions, actual packet latency, and movement accuracy need physical-device testing.

## Movement Skills mode

Use the **Movement Skills** setup on the welcome screen. Choose Vision, Cursor simulation, or iPhone IMU estimate, then select the **Shuffle only** or **Shuffle + hand targets** radio option. Combined tasks are enabled only for Vision. Existing modes keep their previous calibration and scoring.

Setup only establishes center/left/right positions. Route calibration happens during normal gameplay: the first three completed, tracked reposition movements for each directed route establish that route's median baseline. Waiting and the 100ms lane-confirmation hold are excluded; arrival is timestamped at the initial crossing. Incomplete movements and interrupted tasks do not create baseline samples. IMU uses the existing stop detector's completed burst duration. Each route baseline locks after three samples and remains fixed for the session. There are no separate route trials or trial-reset instructions.

Learning attempts still contribute to obstacle accuracy, hand-task outcomes, combo, and points, but are excluded from agility averages. The sidebar shows learned routes and sample progress. Agility is marked as learning until an eligible scored movement exists; boss qualification waits for all six route baselines. The low-performance difficulty reduction is withheld while baselines are being learned. Later waves use learned route references for spacing, with initial lane-setup estimates used for routes still learning.

The game reuses consecutive obstacle waves without beat windows. Combined tasks add one second of spacing per obstacle. Once a lane arrival is confirmed, a fixed target appears near the assigned shoulder. Match the target color to your tracked hand marker (blue = anatomical left, pink = anatomical right) while holding the clear lane, then stay clear until obstacle passage. Assignments use shuffled left/right pairs. The first contact is the only hand attempt: wrong-hand contact fails it, and a parked hand must leave and re-enter. Both wrists, shoulders, and hips must remain visible for combined tasks; no finger or leg landmarks are required.

Movement agility is `min(1, routeReferenceSeconds / measuredMovementSeconds)`, averaged over the last 20 eligible reposition attempts after their route baseline is ready. Uncompleted required movements with a ready baseline contribute zero. Already occupying the clear lane contributes no agility sample. A subsequent collision or hand error does not erase a completed movement measurement. Cursor simulation uses continuous horizontal pointer position mapped onto the calibrated lanes; it does not use snapped avatar travel to calculate agility. Raw movement duration remains visible.

Combined coordination uses the last 20 completed obstacles:
- **Task accuracy (50%):** half credit for avoiding the obstacle, half for correct-hand contact while in the required lane.
- **Combined control (30%):** correct-hand contact with no observed lane exit between target appearance and contact.
- **Consistency (20%):** the fraction of adjacent attempt pairs where both attempts have full task accuracy and combined control. Until two attempts exist, show “Collecting samples” and prevent boss qualification.

Shuffle-only displays dodge accuracy and a separate successful-pair consistency diagnostic. Performance uses 50% movement agility and 50% coordination (combined) or dodge accuracy (shuffle only). Existing time-based difficulty, zone caps, balanced evaluation groups, and boss thresholds apply to these mode-specific metrics. The boss display uses the same formula. Combined success for combo/points requires both the dodge and the controlled hand task.

Tracking interruptions discard and restart the active task without scoring it; the assigned hand is retained. Cursor exit freezes the current task exactly. Manual IMU resume recenters and restarts the current task. Collision and hand-contact checks use observation timestamps; late movement cannot rescue a collision. Camera/cursor arrival confirmation may complete during the existing delivery grace (at least 100 ms in this mode) but is credited only when the initial crossing was before obstacle passage.

The weights and additional one-second hand allowance are prototype tuning values. Vision estimates torso/hip and wrist movement; cursor and waist IMU cannot measure full multi-segment coordination. References are stored for the current session and cleared on restart.

## Obstacle Dodge mode

Choose **Obstacle Dodge · Vision**, **Obstacle Dodge · iPhone IMU**, or **Obstacle Dodge · cursor** from the welcome screen. All use the existing center → left → right → center calibration. Vision requires shoulders and hips; arm targets are not included in this mode.

Each obstacle blocks two lanes and leaves one clear. Move into the clear lane whenever you choose and be there when the obstacle reaches the runner. Early movement is allowed. There is no beat window, WAIT/MOVE NOW gate, or Perfect/Great timing grade. Entering a clear lane does not finish an obstacle: leaving it before passage can still cause a collision. Both hits and dodges advance the wave; hits reset the combo.

Multiple obstacles are visible ahead. Waves contain `3 + floor(5D)` obstacles, with two extra during bosses (3–8 in practice, up to 10 in bosses). Consecutive safe lanes differ. With calibrated route time `b`, each physical gap is `max(0.55, b × (1.5 − 0.4D) + 0.35)` seconds; the first obstacle gets another 0.8 seconds of preview. Higher difficulty increases the count and shortens gaps and between-wave recovery. Tracking delivery allowance does not add gaps between obstacles.

The HUD shows **Agility · Response** and **Obstacles Avoided**. Successful dodges earn response agility `min(1, calibratedRouteSeconds / max(0.001, responseSeconds))`, measured from the current obstacle becoming active to first entry into its clear lane. Starting the active obstacle already in the clear lane gives a zero-second response. The avoidance metric is the fraction of obstacles avoided. Collisions contribute zero to both metrics. The existing time/difficulty progression, balanced mastery groups, boss gates, and 50/50 runner performance formula use these mode-specific metrics.

Collision decisions use the latest lane observation timestamped at or before obstacle passage. Late movement cannot rescue an earlier collision during Vision/IMU delivery grace. IMU still estimates lane arrival from a completed movement; it cannot independently confirm a physical lane. Cursor exits freeze the wave exactly; manual pauses and tracking interruptions restart the current obstacle without scoring a partial movement. iPhone IMU Resume recenters the player and starts a new wave. Restarting a regular runner or Slice & Punch session clears Obstacle Dodge mode.

## Slice & Punch mode

Choose **Slice & Punch · Vision** for a separate hand-only game mode, or **Slice & Punch · demo** for keyboard input. This mode replaces shuffle/arm-target cues with five hand actions:

| Cue | Action | Demo key |
| --- | --- | --- |
| Slice up | Sweep an open hand upward | W |
| Slice down | Sweep an open hand downward | S |
| Punch up | Extend a closed fist upward | I |
| Punch left | Extend a closed fist toward screen left | J |
| Punch right | Extend a closed fist toward screen right | L |

Either hand may strike; directions follow the mirrored screen. Keep shoulders, hips, elbows, wrists, and fingers visible. Knees and feet are optional. Hand calibration asks for both open hands in chest-height guard, both fists in guard, then open guard again; hold each for 0.8 seconds. Keep your palms/fingers visible to the camera. The demo simulates these holds automatically and provides clickable action buttons as well as keys.

Vision hand-pose landmarks are matched to the body's wrists. Finger-tip distance relative to finger middle-joint distance estimates open palm versus fist. The detector measures wrist motion relative to its shoulder, normalized by shoulder width, so torso translation alone cannot trigger a strike. Slices require predominantly vertical open-hand travel; punches require a fist, increasing reach, and an elbow angle near full extension. Both require a minimum stroke distance and movement speed. Return to your calibrated guard for at least 150ms between actions. Missing/uncertain hands pause scoring and reset the partial stroke.

Strikes use the visible beat timing window. In this mode **strike speed** replaces shuffle agility: `min(1, 0.65 / detectedStrokeSeconds)`. **Strike timing** uses the same ±100ms full-credit region and linear falloff to the window edge as shuffle arrival timing. Incorrect actions and timeouts score zero. The difficulty and boss formulas retain their weights and thresholds, applied to hand metrics. Each evaluation window needs at least two samples of each of the five actions. Bosses use hand-action sequences.

All targets and effects are procedural placeholders. This is a webcam gesture prototype: it does not measure punch force or forward depth, and fist recognition can fail when fingers are occluded. Actual detection quality requires live-camera testing. The iPhone IMU companion remains shuffle-only.

## Scoring and progression

Shuffle positions are **left, center, right**. Preview the obstacle during **WAIT**, then respond to **MOVE NOW** and arrive as the obstacle reaches you. Cursor demo lane changes remain immediate. Cursor speed is displayed in play-frame lane widths per second for diagnostics and does not determine agility.

- Each shuffle freezes calibrated route time `b = secondsPerLane × routeUnits`, window half-width `w = max(0.30, 0.50 − 0.20D, b + 0.25)`, and ideal arrival `beat = max(1.5, 1.4b + 0.4)`. The movement window opens at `beat − w` and closes at `beat + w`. The obstacle reaches the player at `beat`; the timing bar marks that moment. Longer routes get more time. The 0.25-second allowance is adjustable prototype tuning.
- **Agility A** averages shuffle response scores. `responseSeconds = arrivalTime − windowOpenTime` is stored separately from movement travel time. Valid arrivals earn `min(1, (w + 0.10) / max(0.001, responseSeconds))`. This gives full credit through the ideal timing region. Preview waiting never enters response time. Early arrivals and timeouts earn zero; entering early immediately fails that obstacle. Holding a target lane cannot subsequently earn credit.
- **Coordination C** averages shuffle arrival precision and arm-touch grades. With `error = arrivalTime − beat`, shuffle precision is `clamp(1 − max(0, abs(error) − 0.10)/(w − 0.10), 0, 1)`. Each shuffle or touch has equal weight. Arm touches do not contribute to agility and keep their existing 1.5-second beat, difficulty-based half-window, and Perfect/Great/Good/Bad grades.
- Lane boundaries lie halfway between calibrated center and each side. The avatar, POSITION indicator, and arrival detection share these boundaries. Side lanes extend outward, so overshooting still counts. Passing through center toward a requested side is not another shuffle. New arrival requires actual departure and prior presence outside the target lane.
- Camera calibration measures center → left → right → center travel, excluding target holds and waiting. Cursor calibration measures pointer travel normalized by horizontal distance (one third of the play frame is one lane), also excluding holds and waiting. Without usable samples the baseline is one second per lane. Missing or interrupted cursor travel cannot produce a diagnostic speed; observable arrival still earns response and coordination scores.
- Vision timestamps observations before inference and permits up to 300ms processing/delivery without extending the scored window. IMU uses the estimated end-of-movement timestamp, with delivery allowance for its stop detector. All three inputs share the same shuffle scoring function. IMU remains an estimate of arrival, not physical lane verification.
- Arm touches contribute to coordination, combo, and points. Perfect/Great/Good keep the combo; Bad and timeouts reset it. The legacy reaction field remains internal for compatibility; runner performance and the runner HUD no longer use it.
- Displayed A/C use the last 20 scored steps, with A calculated from shuffles and C from shuffle plus arm-touch steps.
- `T = min(1, zoneActiveSeconds / 180)`; runner `P = 0.5A + 0.5C`; `D = clamp(0.7T + 0.3P, 0, zoneCap)`. Zone caps start at 0.55 and rise by 0.15 up to 1. After 10 samples, either skill below 75% applies a 0.75 difficulty multiplier. Higher difficulty increases consecutive cue counts and reduces recovery gaps. Separate Slice & Punch mode retains `P = 0.4A + 0.4C + 0.2R` and its strike speed/timing behavior.
- Balanced evaluation groups require ≥10 scored steps, ≥4 left, ≥4 right, and ≥2 center arrivals or timeouts. Average agility ≥80% and coordination ≥85% must both pass. Failed groups reset consistency.
- Boss entry requires ≥60 active zone seconds, rolling A≥80%, C≥85%, two consecutive passed groups, and reliable tracking. A five-second recovery and readiness button precede the arena.
- Sentinel / 01 lasts 30 active seconds. Runner pass requires `0.5A + 0.5C ≥ 0.85`, A≥80%, and C≥80%. The displayed boss score uses the same performance function. Pending steps at arena end are excluded. Success advances the zone; failure returns to practice. Both reset practice time and mastery groups.
- Cursor exits freeze the current cue and resume the same timing. Manual pauses and tracking loss discard interrupted movement and reissue without scoring a partial trip. IMU Resume requires recentering.

These are adjustable prototype scoring standards. Agility is relative to calibrated movement allowance, not an absolute speed benchmark.

## Implementation and limits

`BodyTracker.swift` runs AVFoundation capture and `VNDetectHumanBodyPoseRequest` on a serial background queue, publishing joint snapshots to the main actor. Tracking requires confident left/right shoulders, left/right hips, and hip/root detections. Knee and ankle joints are excluded from the captured joint snapshot and skeleton overlay. Calibration uses shoulder-to-hip height, and shuffle timing continues to use the hip/root position. At least one confident wrist is needed for arm targets; finger classification is unnecessary in this mode. The display uses mirrored camera coordinates in a resizable Mac window. A live mirrored camera image appears inside the game and calibration frames behind the body markers and targets, with a smaller preview in the sidebar. It preserves the camera aspect ratio with letterboxing; image, landmarks, and target coordinates share the same viewport. Each preview comes from the same frame as its joint observations. No video is persisted.

Arm targets use the body-pose wrist landmark as the visible hand contact marker. Each target is fixed at a reachable position to the left or right of the latest shoulder center, at shoulder or upper-chest height, and scales with torso size. The target and hand markers share exactly the same mirrored coordinate mapping. The shrinking outer ring reaches the target at the beat; the inner target turns green during the timing window. Move either marker into the target. Contact uses a swept wrist segment and interpolated first-contact time, so a quick swipe through a target between camera frames can still register. A hand already inside a newly displayed target must leave and re-enter. Missing wrists reset partial contacts; losing all wrists during an arm cue freezes and reissues it without a miss. Targets appear one at a time, including inside boss sequences.

| Arm contact timing (absolute error from beat) | Feedback | Coordination contribution |
| --- | --- | --- |
| ≤100ms | Perfect | 100% |
| >100ms to 200ms | Great | 85% |
| >200ms, inside current timing window | Good | 60% |
| Outside timing window, or no touch before deadline | Bad | 0% |

Body-only Vision processes every available frame; Slice & Punch retains alternate-frame processing. Shuffles use identical lane boundaries for the avatar and scoring. These are prototype webcam heuristics. Restart and recalibrate after changing camera framing. Recognition, target reachability, mirrored directions, lighting, clothing, and occlusion still need live testing on your Mac. Movement sequences are ordered; simultaneous shuffle-and-touch combinations are not yet implemented.

Apple API reference: https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest

## Verification

Mac build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project 'poc game.xcodeproj' -scheme 'poc game' -destination 'platform=macOS' -configuration Debug -derivedDataPath /tmp/shuffle-mac-build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

Standalone progression checks (macOS Swift):

```sh
swiftc -module-cache-path /tmp/shuffle-module-cache 'poc game/GameModel.swift' Tests/ProgressionChecks.swift -o /tmp/shuffle-progression-checks
/tmp/shuffle-progression-checks
```

Checks cover calibrated response normalization, arrival timing independent of travel speed, center returns, intermediate crossings, duplicate prevention, tracking interruption, timeouts, boss gates and pass/fail, instant demo arrivals, calibration, caps, and restart. Additional regressions cover shared avatar/arrival boundaries, overshoot, duplicate prevention within a lane, Vision delivery latency, arm target contact, swept fast swipes, parked hands, all timing grades, coordination aggregation, and wrist-loss recovery. Camera recognition needs live testing with your Mac and room setup.

IMU checks:

```sh
swiftc -module-cache-path /tmp/shuffle-module-cache 'poc game/GameModel.swift' 'poc game/ShuffleDetector.swift' Tests/IMUChecks.swift -o /tmp/shuffle-imu-checks
/tmp/shuffle-imu-checks
```

Connection checks (local loopback; no iPhone required):

```sh
swiftc -module-cache-path /tmp/shuffle-module-cache 'poc game/IMUConnection.swift' Tests/IMUConnectionChecks.swift -o /tmp/shuffle-connection-checks
/tmp/shuffle-connection-checks
```

Hand action checks:

```sh
swiftc -module-cache-path /tmp/shuffle-module-cache 'poc game/GameModel.swift' 'poc game/HandGestures.swift' 'poc game/BodyTracker.swift' Tests/HandGestureChecks.swift -o /tmp/shuffle-hand-checks
/tmp/shuffle-hand-checks
```

Torso tracking checks:

```sh
swiftc -module-cache-path /tmp/shuffle-module-cache 'poc game/GameModel.swift' 'poc game/HandGestures.swift' 'poc game/BodyTracker.swift' Tests/TorsoTrackingChecks.swift -o /tmp/shuffle-torso-checks
/tmp/shuffle-torso-checks
```


Arm target checks:

```sh
swiftc -module-cache-path /tmp/shuffle-module-cache 'poc game/GameModel.swift' Tests/ArmTouchChecks.swift -o /tmp/shuffle-arm-checks
/tmp/shuffle-arm-checks
```


Cursor demo checks:

```sh
swiftc -module-cache-path /tmp/shuffle-module-cache 'poc game/GameModel.swift' Tests/CursorDemoChecks.swift -o /tmp/shuffle-cursor-checks
/tmp/shuffle-cursor-checks
```


Cursor speed checks:

```sh
swiftc -module-cache-path /tmp/shuffle-module-cache 'poc game/GameModel.swift' Tests/CursorSpeedChecks.swift -o /tmp/shuffle-cursor-speed-checks
/tmp/shuffle-cursor-speed-checks
```

Obstacle timing checks:

```sh
swiftc -module-cache-path /tmp/shuffle-module-cache 'poc game/GameModel.swift' Tests/ObstacleTimingChecks.swift -o /tmp/shuffle-obstacle-checks
/tmp/shuffle-obstacle-checks
```

These cover preview waiting, calibrated route windows, equivalent Vision/IMU/cursor scoring, early and late arrivals, exact window boundaries, the full-credit plateau, consecutive cues, interruption, cursor pause, timeout, difficulty and boss performance, and preservation of hand-mode weights.

Obstacle Dodge checks:

```sh
swiftc -module-cache-path /tmp/shuffle-module-cache 'poc game/GameModel.swift' Tests/ObstacleDodgeChecks.swift -o /tmp/shuffle-dodge-checks
/tmp/shuffle-dodge-checks
```

Checks cover early movement without immediate scoring, physical collision-time position, leaving clear lanes, late corrections, timestamped delivery, continuous wave schedules, difficulty-based counts and spacing, boss waves, cursor pause, IMU direction and duplicate events, mastery gates, and mode isolation.

Movement Skills checks:

```sh
swiftc -module-cache-path /tmp/shuffle-module-cache 'poc game/GameModel.swift' Tests/MovementSkillsChecks.swift -o /tmp/movement-skills-checks
/tmp/movement-skills-checks
```

These verify in-game learning of six route medians, warm-up exclusion, stable references, waiting exclusion and backdated arrival confirmation, movement scoring independent of later errors, eligible-sample history, wrist identity and single contact attempts, lane maintenance, consistency, combined spacing, IMU calibration, cursor travel, progression, and mode isolation. The torso tracking checks also cover combined-task wrist loss and recovery.

Boss consistency setting: **Require 2 consecutive groups** is available on the welcome screen and in the boss-readiness sidebar. It defaults to on and keeps its choice across restarts within the app session. Turning it off bypasses only the two-group boss-entry requirement; minimum practice time, skill thresholds, reliable tracking, and Movement Skills baseline readiness still apply. Evaluation groups continue to be measured. The separate consistency component of the coordination score is unaffected. Changes are checked when the current wave/sequence ends.
