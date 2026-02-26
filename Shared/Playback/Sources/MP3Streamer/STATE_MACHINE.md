# MP3Streamer State Machine

How the streamer, HTTP client, decoder, and audio player interact.

## Component Interaction

```mermaid
stateDiagram-v2
    direction TB

    state "MP3Streamer (StreamingAudioState)" as Streamer {
        [*] --> idle
        idle --> connecting : play()
        connecting --> buffering : HTTP .connected
        buffering --> playing : buffer threshold reached
        playing --> stalled : player .stalled event
        stalled --> playing : buffer threshold reached
        playing --> idle : stop()
        buffering --> idle : stop()
        connecting --> idle : stop()
        stalled --> idle : stop()
        playing --> error : HTTP .error / player .error
        buffering --> error : HTTP .error
        connecting --> error : connect() throws
        error --> idle : stop()
        error --> connecting : play() [calls stop() first]
        stalled --> connecting : play() [calls stop() first]
        connecting --> connecting : play() [calls stop() first]
        buffering --> connecting : play() [calls stop() first]
        playing --> playing : play() [no-op]
        paused --> playing : play() [resume]
        playing --> paused : pause()

        state "Reconnect Logic" as Reconnect {
            playing --> reconnecting : HTTP .disconnected
            buffering --> reconnecting : HTTP .disconnected
            stalled --> reconnecting : HTTP .disconnected
            reconnecting --> connecting : backoff timer fires
        }

        note right of idle
            .disconnected events are
            IGNORED in connecting,
            reconnecting, idle, paused,
            and error states
        end note
    }
```

## HTTP Client Events

```mermaid
stateDiagram-v2
    [*] --> disconnected
    disconnected --> connected : connect()
    connected --> streaming : data arrives
    streaming --> disconnected : disconnect() / network loss
    connected --> disconnected : disconnect()
```

Events emitted: `.connected`, `.data(Data)`, `.disconnected`, `.error(Error)`

## Audio Engine Player

```mermaid
stateDiagram-v2
    [*] --> stopped
    stopped --> playing : play()
    playing --> stopped : stop()
    playing --> paused : pause()
    paused --> playing : play()
```

`stop()` sets `isPlaying = false` before draining the scheduling queue via `schedulingQueue.sync {}`, then calls `playerNode.stop()` inside that sync block. The `scheduleBuffers()` async block guards on `isPlaying` as defense-in-depth.

Events emitted: `.started`, `.stopped`, `.paused`, `.stalled`, `.recoveredFromStall`, `.needsMoreBuffers`, `.error(Error)`

## Decoder Lifecycle

```mermaid
stateDiagram-v2
    [*] --> waiting
    waiting --> decoding : decode\(data)
    decoding --> waiting : yields PCM buffer
    decoding --> [*] : stop() replaces decoder
```

On `stop()`, the decoder is replaced with a fresh instance. The old decoder's `deinit` calls `bufferContinuation.finish()`, terminating its `AsyncStream` and discarding up to 32 stale PCM buffers.

## Data Flow

```mermaid
flowchart LR
    Server["HTTP Server"]
    HTTP["HTTPStreamClient"]
    Decoder["MP3StreamDecoder"]
    Streamer["MP3Streamer"]
    Player["AudioEnginePlayer"]
    Queue["PCMBufferQueue"]

    Server -- "MP3 bytes" --> HTTP
    HTTP -- ".data(Data)" --> Streamer
    HTTP -- ".connected / .disconnected / .error" --> Streamer
    Streamer -- "decode(data:)" --> Decoder
    Decoder -- "decodedBufferStream<br>(PCM buffers)" --> Streamer
    Streamer -- "enqueue<br>(buffering/stalled)" --> Queue
    Queue -- "dequeueAll" --> Streamer
    Streamer -- "scheduleBuffer()<br>(playing: direct)" --> Player
    Streamer -- "scheduleBuffers()<br>(from queue)" --> Player
    Player -- ".stalled / .recoveredFromStall<br>.needsMoreBuffers / .error" --> Streamer
    Streamer -- "connect() / disconnect()" --> HTTP
    Streamer -- "play() / stop()" --> Player
    Streamer -- "reset() / replace" --> Decoder
```

## PlayerStateBox (AudioEnginePlayer internal)

Thread-safe atomic state inside `AudioEnginePlayer` that drives stall detection and the scheduling queue guard.

```mermaid
stateDiagram-v2
    state "isPlaying" as IP {
        [*] --> false_p
        false_p --> true_p : play()
        true_p --> false_p : stop() / pause()
    }

    state "isStalled" as IS {
        [*] --> false_s
        false_s --> true_s : setStalledIfPlaying()<br>[count == 0 && isPlaying]
        true_s --> false_s : clearStalledIfSet()<br>[new buffers arrive]
    }
```

The `stop()` sequence depends on this ordering:
1. `stateBox.isPlaying = false` -- in-flight scheduling blocks see this immediately
2. `schedulingQueue.sync { playerNode.stop() }` -- drains queue, then clears buffers
3. `scheduleBuffers()` guards on `stateBox.isPlaying` as defense-in-depth

## State Mapping

`StreamingAudioState` (internal, 9 cases) is projected to `PlayerState` (public, 5 cases) for consumers.

```mermaid
flowchart LR
    subgraph "StreamingAudioState (MP3Streamer)"
        idle["idle"]
        paused["paused"]
        connecting["connecting"]
        buffering["buffering"]
        reconnecting["reconnecting"]
        playing_s["playing"]
        stalled_s["stalled"]
        error_s["error"]
    end

    subgraph "PlayerState (public API)"
        ps_idle["idle"]
        ps_loading["loading"]
        ps_playing["playing"]
        ps_stalled["stalled"]
        ps_error["error"]
    end

    idle --> ps_idle
    paused --> ps_idle
    connecting --> ps_loading
    buffering --> ps_loading
    reconnecting --> ps_loading
    playing_s --> ps_playing
    stalled_s --> ps_stalled
    error_s --> ps_error
```

## Reconnect Guard

The `.disconnected` handler only triggers `attemptReconnect()` from these states:

| State | Reconnect? | Reason |
|-------|-----------|--------|
| `.playing` | Yes | Unexpected disconnect during playback |
| `.buffering` | Yes | Connection lost while buffering |
| `.stalled` | Yes | Connection lost while stalled |
| `.connecting` | No | Stale event from stop()/play() cycle |
| `.reconnecting` | No | Already reconnecting |
| `.idle` | No | Intentional stop |
| `.paused` | No | User paused |
| `.error` | No | Already in error handling |
