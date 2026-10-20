// Original 120 BPM instrumental: synthesis only, no samples or third-party music.
const fs = require("node:fs");
const path = require("node:path");
const rate = 48000,
  seconds = 20,
  samples = rate * seconds;
const left = new Float32Array(samples),
  right = new Float32Array(samples);
let seed = 73121;
const noise = () => {
  seed = (seed * 1664525 + 1013904223) >>> 0;
  return (seed / 4294967296) * 2 - 1;
};
const add = (start, duration, fn, pan = 0) => {
  const first = Math.round(start * rate),
    length = Math.round(duration * rate);
  for (let i = 0; i < length && first + i < samples; i++) {
    const s = fn(i / rate, i / length);
    left[first + i] += s * Math.sqrt((1 - pan) * 0.5);
    right[first + i] += s * Math.sqrt((1 + pan) * 0.5);
  }
};
const midi = (n) => 440 * 2 ** ((n - 69) / 12);
for (let beat = 0; beat < 40; beat++) {
  const t = beat * 0.5;
  const drop = beat >= 16 && beat < 24;
  add(
    t,
    0.36,
    (s) =>
      Math.sin(2 * Math.PI * (46 * s + 7 * (1 - Math.exp(-s * 38)))) *
      Math.exp(-s * 13) *
      0.72,
  );
  if (beat % 2 === 1)
    add(
      t,
      0.18,
      (s) =>
        (noise() * 0.4 + Math.sin(2 * Math.PI * 190 * s) * 0.17) *
        Math.exp(-s * 24),
    );
  for (let h = 0; h < 2; h++)
    add(
      t + h * 0.25,
      0.065,
      (s) => noise() * 0.12 * Math.exp(-s * 65),
      h ? -0.3 : 0.3,
    );
  const bass = [38, 38, 34, 36, 38][Math.floor(beat / 8)];
  add(t + 0.015, 0.38, (s) => {
    const env = Math.min(1, s / 0.009) * Math.exp(-s * 5);
    return (
      (Math.sin(2 * Math.PI * midi(bass) * s) * 0.32 +
        Math.sin(4 * Math.PI * midi(bass) * s) * 0.06) *
      env
    );
  });
  const chord = [
    [62, 65, 69],
    [62, 65, 69],
    [58, 62, 65],
    [60, 64, 67],
    [62, 65, 69],
  ][Math.floor(beat / 8)];
  for (let k = 0; k < 2; k++) {
    const note = chord[(beat + k) % 3] + (drop ? 12 : 0);
    add(
      t + k * 0.25,
      0.35,
      (s) => {
        const hz = midi(note),
          env = Math.min(1, s / 0.005) * Math.exp(-s * 10);
        return (
          (Math.sin(2 * Math.PI * hz * s) +
            0.3 * Math.sin(4 * Math.PI * hz * s)) *
          0.115 *
          env
        );
      },
      k ? 0.25 : -0.25,
    );
  }
}
// Anticipation into each 4-second cut; soft impacts at the cut points.
for (const cut of [4, 8, 12, 16]) {
  add(cut - 0.32, 0.32, (s, p) => noise() * 0.19 * p * p, 0.1);
  add(cut, 0.8, (s) => Math.sin(2 * Math.PI * 55 * s) * Math.exp(-s * 6) * 0.3);
}
for (let k = 0; k < 3; k++)
  add(
    10.8 + k * 0.08,
    0.6,
    (s) =>
      Math.sin(2 * Math.PI * midi([81, 86, 89][k]) * s) *
      Math.exp(-s * 9) *
      0.18,
    k * 0.25 - 0.25,
  );
for (let k = 0; k < 4; k++)
  add(
    13.3 + k * 0.1,
    0.7,
    (s) =>
      Math.sin(2 * Math.PI * midi([74, 77, 81, 86][k]) * s) *
      Math.exp(-s * 7) *
      0.12,
  );
const data = Buffer.alloc(samples * 4);
let peak = 0,
  sum = 0;
for (let i = 0; i < samples; i++) {
  const fade = Math.min(
    1,
    i / (rate * 0.008),
    (samples - 1 - i) / (rate * 0.35),
  );
  for (let ch = 0; ch < 2; ch++) {
    const x =
      Math.tanh((ch ? right[i] : left[i]) * 1.3) * 0.84 * Math.max(0, fade);
    peak = Math.max(peak, Math.abs(x));
    sum += x * x;
    data.writeInt16LE(Math.round(x * 32767), i * 4 + ch * 2);
  }
}
const header = Buffer.alloc(44);
header.write("RIFF");
header.writeUInt32LE(36 + data.length, 4);
header.write("WAVE", 8);
header.write("fmt ", 12);
header.writeUInt32LE(16, 16);
header.writeUInt16LE(1, 20);
header.writeUInt16LE(2, 22);
header.writeUInt32LE(rate, 24);
header.writeUInt32LE(rate * 4, 28);
header.writeUInt16LE(4, 32);
header.writeUInt16LE(16, 34);
header.write("data", 36);
header.writeUInt32LE(data.length, 40);
const output = path.resolve(__dirname, "../public/audio");
fs.mkdirSync(output, { recursive: true });
fs.writeFileSync(
  path.join(output, "market-moves.wav"),
  Buffer.concat([header, data]),
);
console.log(
  JSON.stringify({
    seconds,
    sampleRate: rate,
    channels: 2,
    bpm: 120,
    peakDb: 20 * Math.log10(peak),
    rmsDb: 20 * Math.log10(Math.sqrt(sum / (samples * 2))),
  }),
);
