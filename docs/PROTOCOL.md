# P-125 protocol notes

## Verified instrument

The tested Yamaha USB device (vendor `0499`, product `1718`) exposed a CoreMIDI source and destination named **Digital Piano**. It returned model `P-125` and firmware `1.03` to the Smart Pianist property requests below.

Universal identity reply: `F0 7E 7F 06 02 43 00 43 21 1F 00 00 00 7F F7`.

The Smart Pianist header is `F0 43 73 01 52 25 26`. The final `25 26` bytes are part of the shared control protocol; replacing them with the instrument's universal identity model bytes did not receive a reply.

The observations below summarize hardware checks on a P-125. Automated protocol tests use inline fixtures in [ProtocolTests.swift](../Tests/P125CoreTests/ProtocolTests.swift).

## Message layout

All messages end in `F7`. Property IDs use four bytes; values are big-endian groups of seven bits. Indexes are distinct from MIDI channel numbers.

```text
Get:       HEADER 01 00 PROPERTY[4] INDEX 01 00 F7
Set:       HEADER 01 01 PROPERTY[4] INDEX 01 00 LENGTH[2] VALUE[n] F7
Info:      HEADER 00 00 PROPERTY[4] INDEX 01 00 LENGTH[2] VALUE[n] F7
Set reply: HEADER 00 01 PROPERTY[4] INDEX 01 00 00 00 LENGTH[2] VALUE[n] F7
Subscribe: HEADER 02 00 PROPERTY[4] F7
```

The two extra status bytes in a Set reply precede the length. The parser verifies manufacturer, header, action, payload size and data bytes. Realtime MIDI bytes are stripped before SysEx assembly. Partial messages, consecutive messages, interrupted messages and excessive lengths are handled explicitly.

## Observed readable properties

| Property | ID | Index | Initial observed value |
| --- | --- | --- | --- |
| Model | `0F 01 18 01` | 0 | P-125 |
| Firmware | `0F 01 0B 01` | 0 | 1.03 |
| Volume | `0C 00 00 01` | 0 / 1 / 2 | 100 / 0 / 100 |
| MIDI song volume | `0C 00 00 01` | `50` hex | 64 |
| Part active | `0C 00 01 01` | 1 / 2 | off / off |
| Pan | `0C 00 03 01` | 0 / 2 | 64 / 63 |
| Reverb send | `0C 00 04 01` | 0 / 1 / 2 | 9 / 127 / 40 |
| Octave | `0C 00 12 01` | 0 / 1 / 2 | 64 / 64 / 64 (readback limitation below) |
| Panel voice | `02 00 03 01` | 0 / 1 / 2 | 0 / 16 / 20 |
| Reverb type | `0C 01 00 01` | 0 | `00 02 18` (Recital Hall) |
| Keyboard transpose | `0A 00 00 01` | 1 | 64 (zero offset) |
| Song transpose | `0A 00 00 01` | 2 | 64 (zero offset) |
| Split point | `09 00 00 01` | 0 | MIDI note 108 |
| Master tune | `03 00 00 01` | 0 | `08 00` = 1024 (440 Hz) |

Main, Layer, Left indexes are 0, 1, 2 respectively. MIDI note names in the interface follow scientific pitch notation (MIDI 60 = C4).

### Octave readback on firmware 1.03

The initial octave values above are protocol responses, not reliable readings
of the applied octave. A Set request of raw 65 (+1) is accepted, but both the
Set acknowledgement payload and the following Get return raw 64 (0). I confirmed
that the piano's audible octave changes despite that zero response.

The utility serializes octave writes per part, associates the acknowledgement
with the requested value and retains that selection across background reads.
The selector displays the last accepted request in the current connection;
before the first request it displays an unknown value. Reset always sends raw
64, including when the cached value is already 64. Unknown octave readings
are omitted from saved setups and the original connection snapshot.

### Mixer mute

Mute uses the already supported part-volume property, writing zero while
remembering the previous level independently for indexes 0, 1, 2 and 0x50.
It does not toggle Layer/Split activation. The fader edits the remembered
level while muted; unmuting restores it. Recovery levels are saved per MIDI
endpoint, so reconnecting to an already muted piano retains the Unmute action.
A nonzero hardware update clears stale mute state. Saved setups optionally
carry mute recovery levels; older setups still decode without this field.

The tested instrument did not answer the voice-preset, voice-MIDI, touch-curve, Layer-pan, or auxiliary-audio volume queries. The P-125 panel voice index is a separate property and accepts a two-byte value from 0 through 23. A hardware test changed Main from Grand Piano to Stage E.Piano and restored Grand Piano with fresh reads at each step.

Reverb values encode `(MSB << 8) | LSB` into three seven-bit bytes. The official Yamaha table lists Off `0/0`, Recital Hall `1/24`, Concert Hall `1/4`, Chamber `2/24` and Club `3/24`. The returned Recital Hall value therefore is `00 02 18`, not `00 01 18`.

The tuning display uses `440 + (raw - 1024) / 40` Hz, following the discovered property convention. A4 = 440 is confirmed on this instrument; the full tuning range has not been checked acoustically.

## Hardware validation

The diagnostic read Main volume 100, wrote 99, freshly read 99, restored 100 and freshly read 100. This verified both a setting change and restoration on real hardware. No notes, factory reset, firmware update, or Local Control change was sent. Further controls were read successfully; not every value and mode combination has been exercised.

The keyboard transpose slider uses index 1. Index 2 controls song transposition. The dedicated
hardware regression command changed index 1 from raw 64 to 66 and back to 64
(0 to +2 semitones to 0), receiving both Set acknowledgements and fresh Get
responses. Index 2 stayed at 64 throughout. The check verifies the instrument's parameter
state; it does not measure the acoustic output. Old setups' index-2 entries
are ignored by the keyboard controls instead of being silently reinterpreted.

The app requires the model response to be exactly `P-125` before allowing writes. It sends throttled, coalesced changes, reads them back, displays unconfirmed writes as pending, and reports a timeout instead of assuming a successful change. It clears settings and queued writes on disconnection. Opening or reconnecting reads values and subscribes to updates; it does not apply defaults or a saved setup. Setups are stored in the app's local UserDefaults.


## Sources

- [Yamaha P-125/P-121 MIDI Reference](https://ca.yamaha.com/files/download/other_assets/2/1209032/p125_p121_en_mr_a0.pdf), especially pages 2–3, 7, 14–15. Plain MIDI CC/program changes generally address MIDI playback rather than panel keyboard parts.
- [ConPianist protocol definitions](https://github.com/hugbug/conpianist/blob/develop/Source/Piano/PianoMessage.cpp), used as a primary source for protocol identifiers and framing; each exposed P-125 parameter is additionally gated by a reply from the instrument.
