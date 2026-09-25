# M1 — Source-format pain evidence

**Recorded:** 2026-09-24
**Milestone status:** Pain captured before the asynchronous implementation.

## Setup

- The Videira M0 application was running locally with Docker Compose.
- An 85 MB QuickTime MOV sample (`LaneVids-DelbertMcClinton779.mov`) from the FFmpeg samples collection was uploaded through the browser.
- The upload completed and the video was published as Video #2.

## Observation

The published video could not be played by the browser's native video player. The application accepted and stored the original MOV file, but publishing it did not make it usable for playback.

## Why this matters

M0 serves the uploaded original directly, so the viewer's browser must support the source container and codecs. A successful upload and a `published` record therefore do not guarantee that a viewer can watch the video. This is the source-format compatibility pain that motivates M1 transcoding to a browser-friendly delivery format.

## Manual transcoding probe

A disposable FFmpeg 7.1 container attempted to convert the original to H.264/AAC MP4. FFmpeg identified a 5:56 QuickTime file containing WMV3 video and WMA2 audio. The complete conversion stopped because the container could not decode the WMA2 audio stream. A second, video-only attempt also produced no frames after WMV3 decoder errors.

The probe produced no output file, so it is evidence of an unsupported-input failure rather than a successful-transcoding timing measurement. This input gives M1 a concrete `failed` path to model and preserve for regression testing.

## Successful-transcoding time baseline

A separate synthetic MOV was uploaded as Video #3. It is a 60-second, 1280×720 H.264/AAC file (53,919,028 bytes) and plays directly in the browser. A disposable FFmpeg 7.1 container then converted the stored original to H.264/AAC MP4 using `libx264`, CRF 23, and the `medium` preset.

| Metric | Result |
| --- | --- |
| Input | 60 s MOV, 51 MB |
| Output | 60 s MP4, about 22 MB |
| Elapsed wall-clock time | 8.78 s |
| FFmpeg processing speed | 7.14× real time |

The output was discarded after the measurement; the original remained read-only. The FFmpeg image ran under amd64 emulation on an arm64 development host, so this is a local baseline rather than a portable performance claim.

## Synchronous request experiment

A temporary implementation then ran the same FFmpeg operation inside `VideosController#create`, after saving the uploaded file but before returning the redirect. Uploading the compatible sample again produced this server-side timing:

| Metric | Result |
| --- | --- |
| FFmpeg inside the request | 4.42 s |
| Complete `POST /videos` request | 4.78 s |
| Response | `302 Found`, only after FFmpeg completed |

The browser remained loading with no result until the conversion ended. This isolates the architectural pain from upload transfer time: even after Rails had received and saved the bytes, CPU-heavy processing kept the HTTP request open for another 4.42 seconds. The temporary synchronous code was removed when the asynchronous implementation began.

## Scope of this evidence

This observation demonstrates the format-compatibility problem, an unsupported-input conversion failure, and request blocking caused by successful synchronous transcoding. The asynchronous implementation must preserve both outcomes: successful work moves the video forward without delaying the upload response, while unsupported media ends in a visible `failed` state.

## Worker-crash probe

During the asynchronous implementation, a three-minute synthetic video was claimed by a worker and FFmpeg started reading it. The worker container then received `SIGKILL` before it uploaded or published an output. The durable state remained `processing`, with no `playback_file` attachment, so no partial result was exposed.

After the default five-minute heartbeat threshold, Solid Queue pruned the dead process and recorded the delivery as failed with `SolidQueue::Processes::ProcessPrunedError`; it did not execute Active Job's `retry_on` path because the Ruby process died before it could raise an exception. The domain record therefore remained `processing`. This probe identifies a separate recovery requirement: exception retries handle a live worker reporting failure, while abrupt process death needs application-level stale-work reconciliation.

## Crash-recovery result

The final implementation added a 60-second application-level processing lease, renewed every 15 seconds, plus a Solid Queue reconciliation job scheduled every minute. When deployed against the record abandoned by the probe, the reconciler found its missing heartbeat, atomically returned it to `queued`, and enqueued a new attempt. The replacement transcode completed in 11.89 seconds and left the video `ready` with exactly one `playback_file`; its processing token, job ID, start time, and heartbeat were all cleared. No manual requeue or state edit was used for the recovery.

The remaining trade-off is explicit: a database outage longer than the lease can cause duplicate CPU work even if the original worker is still alive. The fencing token prevents either attempt from overwriting the winner, so the accepted failure mode is wasted computation rather than inconsistent publication.
