# Isolated motion capability probe

This is a non-capturing, standalone Watch target. It is not included in Little Lift's project, package or refresh script. It checks API compilation and free Personal Team provisioning without modifying the logger or recording any health/motion data.

Run `python3 Experiments/MotionProbe/generate.py` from the repository root to regenerate its project. To reproduce signing, build its MotionProbe scheme for watchOS with an explicit private `DEVELOPMENT_TEAM` and a distinct `MOTION_PROBE_BUNDLE_ID`; never substitute Little Lift's identity. Keep resulting provisioning/device metadata in ignored local output. The initial probe build and signature check succeeded; it was not installed or run.

See [the findings](../../docs/motion-feasibility.md). A successful signature does not establish background collection or sensor accuracy. There is deliberately no Start Capture action here.
