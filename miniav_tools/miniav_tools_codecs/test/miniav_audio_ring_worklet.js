// The consumer end of SharedAudioRing, running on the browser's realtime audio
// thread.
//
// This is the whole point of the exercise: `process()` is called by the audio
// device, on its own high-priority thread, and it reads samples straight out of
// shared memory. Nothing here touches the main thread, so a main thread busy
// with Flutter build/raster work — or blocked outright — cannot make audio
// stutter. The only thing that can is the ring running dry, which is a producer
// problem and is counted (`underruns`) rather than guessed at.
//
// Kept in plain JS on purpose. An AudioWorkletProcessor is constructed inside
// the worklet global scope, which has no DOM, no fetch and no module loader,
// and compiling Dart into it would buy nothing: the code below is a bounded
// copy loop and must stay that way. Anything that allocates or blocks in
// `process()` is a glitch.
//
// The layout mirrors SharedAudioRing exactly. If one changes, both change.

const CONTROL_SLOTS = 16; // kControlSlots
const SLOT_WRITE = 0;
const SLOT_READ = 1;
const SLOT_CAPACITY = 2;
const SLOT_CHANNELS = 3;
const SLOT_UNDERRUNS = 5;

class MiniavAudioRingProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const buffer = options.processorOptions.buffer;
    this.control = new Int32Array(buffer, 0, CONTROL_SLOTS);
    this.pcm = new Float32Array(buffer, CONTROL_SLOTS * 4);
    this.capacity = Atomics.load(this.control, SLOT_CAPACITY);
    this.channels = Atomics.load(this.control, SLOT_CHANNELS);
    this.running = true;
    // The only main-thread interaction, and it is once per lifetime: stopping.
    this.port.onmessage = (event) => {
      if (event.data === 'stop') this.running = false;
    };
  }

  process(inputs, outputs) {
    const output = outputs[0];
    if (!output || output.length === 0) return this.running;
    const frames = output[0].length;
    const outChannels = output.length;
    const channels = this.channels;
    const capacity = this.capacity;

    const read = Atomics.load(this.control, SLOT_READ);
    // Cursors are monotonic int32 and DO wrap (~12 h at 48 kHz); `| 0` keeps
    // the two's-complement difference correct across that wrap, matching what
    // the Dart side does with toSigned(32).
    let available = (Atomics.load(this.control, SLOT_WRITE) - read) | 0;
    if (available < 0) available = 0;
    const take = frames < available ? frames : available;

    // A negative cursor still has to index forwards.
    let pos = read % capacity;
    if (pos < 0) pos += capacity;

    for (let f = 0; f < take; f++) {
      const base = pos * channels;
      for (let c = 0; c < outChannels; c++) {
        // Fewer ring channels than the device wants: repeat the last one
        // rather than emit silence, so mono into a stereo device is audible
        // on both sides instead of only the left.
        output[c][f] = this.pcm[base + (c < channels ? c : channels - 1)];
      }
      pos++;
      if (pos === capacity) pos = 0;
    }
    // Starved: emit silence for the remainder. Silence is the right failure —
    // repeating the last buffer would be a buzz, and leaving the array alone
    // would replay whatever the previous callback left there.
    for (let f = take; f < frames; f++) {
      for (let c = 0; c < outChannels; c++) output[c][f] = 0;
    }

    if (take > 0) {
      // Publish LAST: the producer may reuse everything below this cursor.
      Atomics.store(this.control, SLOT_READ, (read + take) | 0);
    }
    if (take < frames) {
      Atomics.add(this.control, SLOT_UNDERRUNS, frames - take);
    }
    return this.running;
  }
}

registerProcessor('miniav-audio-ring', MiniavAudioRingProcessor);
