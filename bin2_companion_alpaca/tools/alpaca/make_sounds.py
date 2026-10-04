"""合成羊驼的叫声（纯 numpy 生成 + ffmpeg 转 .ogg），不采样任何外部素材。

为什么自己合成：CompanionDogs 的 addon 契约要求新物种注册自己的 voices，否则它按狗叫。
羊驼的公开素材授权不好确认，所以这里的每一条都是程序生成的（可复现、无版权负担）：

  alarm  = 报警哞叫（高频颤音上扬，羊驼发现威胁时的"吹哨/哞"）
  ambient= 远处的报警声（同一素材降音量，只作环境音，不吸引僵尸）
  hum    = 满足/联络的哼鸣（低频、带共振峰、慢颤音）
  spit   = 警告吐口水（带通噪声爆发 + 低频"嗤"）
  whine  = 疼痛/生病（鼻音下行）
  death  = 死亡长鸣（更低、更长的下行）
  pickup = 被抱起/放下时的轻哼
  chew   = 咀嚼循环（低频噪声脉冲串，loop=true）
  drink  = 饮水循环（带通噪声 + 共振峰上滑，loop=true）

用法：
  python make_sounds.py            # 生成全部 .ogg 到 mod 的 media/sound/
  python make_sounds.py --check    # 只检查已有产物的时长/采样率/声道/峰值
"""

import argparse
import os
import shutil
import struct
import subprocess
import sys
import wave

import numpy as np

SR = 44100
PEAK_DBFS = -1.4  # 与 base/cat 的 .ogg 相同的峰值归一化目标

SOUND_DIR_REL = os.path.join("..", "..", "Contents", "mods", "CompanionDogsAlpaca", "42", "media", "sound")


def log(msg):
    print(f"[make_sounds] {msg}", flush=True)


# ---------------------------------------------------------------- 基础工具


def t_axis(dur):
    return np.arange(int(SR * dur), dtype=np.float64) / SR


def env_ad(t, attack, decay, curve=2.0):
    """attack/decay 包络（线性起、幂次落）。"""
    a = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    d = np.clip((t[-1] - t) / max(decay, 1e-4), 0.0, 1.0) ** curve
    return a * d


def vibrato(t, rate, depth):
    return 1.0 + depth * np.sin(2 * np.pi * rate * t)


def noise(t, seed):
    rng = np.random.RandomState(seed)
    return rng.uniform(-1.0, 1.0, len(t))


def lowpass(x, cutoff):
    """一阶 IIR 低通（纯 numpy，够用）。"""
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def lowpass_fast(x, cutoff):
    """用 FFT 做低通，长素材上比逐样本 IIR 快得多。"""
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
    spec *= 1.0 / (1.0 + (freqs / max(cutoff, 1.0)) ** 2)
    return np.fft.irfft(spec, n=len(x))


def bandpass_fast(x, low, high):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
    with np.errstate(divide="ignore", invalid="ignore"):
        hp = np.where(freqs > 0, freqs / max(low, 1.0), 0.0) / (1.0 + freqs / max(low, 1.0))
        lp = 1.0 / (1.0 + (freqs / max(high, 1.0)) ** 2)
    return np.fft.irfft(spec * hp * lp, n=len(x))


def formant_tone(t, f0_curve, harmonics, formants):
    """用一组谐波 + 共振峰权重合成一个"有嗓子"的音色。

    f0_curve: 基频随时间变化的数组（Hz）
    harmonics: 谐波个数
    formants: [(中心频率, 带宽, 权重)] —— 用高斯权重模拟共振峰，比纯谐波更像动物。
    """
    phase = 2 * np.pi * np.cumsum(f0_curve) / SR
    out = np.zeros_like(t)
    for h in range(1, harmonics + 1):
        f = f0_curve * h
        w = 0.0
        for center, bw, gain in formants:
            w += gain * np.exp(-((f - center) ** 2) / (2 * bw * bw))
        out += (w / h) * np.sin(phase * h)
    return out


def normalize(x, peak_dbfs=PEAK_DBFS):
    peak = float(np.max(np.abs(x))) if len(x) else 0.0
    if peak < 1e-9:
        return x
    target = 10 ** (peak_dbfs / 20.0)
    return x * (target / peak)


def fade_edges(x, ms=8.0):
    n = int(SR * ms / 1000.0)
    if n * 2 >= len(x):
        return x
    x = x.copy()
    x[:n] *= np.linspace(0, 1, n)
    x[-n:] *= np.linspace(1, 0, n)
    return x


# ---------------------------------------------------------------- 各个声音


def make_hum(dur=1.7, f0=176.0):
    t = t_axis(dur)
    f = f0 * vibrato(t, 5.0, 0.022) * (1.0 + 0.05 * np.sin(2 * np.pi * 0.7 * t))
    tone = formant_tone(t, f, 9, [(320, 90, 1.0), (700, 160, 0.55), (1250, 240, 0.25)])
    breath = lowpass_fast(noise(t, 11), 900) * 0.05
    e = env_ad(t, 0.28, 0.75, 1.6)
    return normalize((tone * 0.9 + breath) * e)


def make_pickup():
    return make_hum(dur=0.42, f0=196.0)


def make_alarm(dur=0.95):
    """报警哞：基频由 330 Hz 上滑到 640 Hz，叠快速颤音（羊驼报警声的"颤"）。"""
    t = t_axis(dur)
    glide = 330.0 + 310.0 * (t / dur) ** 0.7
    f = glide * vibrato(t, 17.0, 0.10)
    tone = formant_tone(t, f, 11, [(560, 120, 1.0), (1150, 220, 0.6), (2100, 320, 0.3)])
    e = env_ad(t, 0.06, 0.55, 2.2)
    return normalize(tone * e)


def make_ambient_alarm():
    return make_alarm() * 0.30


def make_spit(dur=0.42):
    t = t_axis(dur)
    n = noise(t, 23)
    hiss = bandpass_fast(n, 1400.0, 5200.0) * np.exp(-t / 0.075)
    chuff = lowpass_fast(noise(t, 29), 420.0) * np.exp(-t / 0.11) * 0.7
    thump = np.sin(2 * np.pi * 92.0 * t) * np.exp(-t / 0.05) * 0.35
    return normalize((hiss + chuff + thump) * 0.9)


def make_whine(dur=1.0):
    t = t_axis(dur)
    f = 620.0 - 330.0 * (t / dur) ** 0.8
    f = f * vibrato(t, 7.5, 0.03)
    tone = formant_tone(t, f, 12, [(900, 200, 1.0), (1800, 380, 0.5), (2900, 520, 0.22)])
    e = env_ad(t, 0.10, 0.6, 1.8)
    return normalize(tone * e)


def make_death(dur=1.6):
    t = t_axis(dur)
    f = 300.0 - 190.0 * (t / dur) ** 1.2
    f = f * vibrato(t, 4.2, 0.05)
    tone = formant_tone(t, f, 10, [(420, 130, 1.0), (950, 260, 0.45), (1700, 400, 0.2)])
    trem = 1.0 + 0.18 * np.sin(2 * np.pi * 9.0 * t)
    e = env_ad(t, 0.12, 1.1, 1.5)
    return normalize(tone * trem * e)


def make_chew(dur=2.4, beats=7):
    """咀嚼循环：一串低通噪声"咔嚓"，间距略微不规则，循环首尾能量低。"""
    t = t_axis(dur)
    out = np.zeros_like(t)
    rng = np.random.RandomState(41)
    for b in range(beats):
        start = dur * (b + 0.12 * rng.uniform(-1, 1)) / beats
        # 起点必须夹在 [0, len-1]：随机抖动会把第 0/最后一下推到数组外（负下标切片长度为 0 会广播报错）
        idx = max(0, min(int(start * SR), len(t) - 1))
        n = min(int(0.16 * SR), len(t) - idx)
        if n <= 0:
            continue
        seg = np.arange(n) / SR
        crunch = lowpass_fast(rng.uniform(-1, 1, n), 2400.0) * np.exp(-seg / 0.035)
        out[idx:idx + n] += crunch
    return normalize(out * 0.8)


def make_drink(dur=2.2, laps=6):
    """饮水循环：带通噪声"啜"+ 共振峰上滑，模拟舌头卷水。"""
    t = t_axis(dur)
    out = np.zeros_like(t)
    rng = np.random.RandomState(53)
    for b in range(laps):
        start = dur * (b + 0.5) / laps
        idx = max(0, min(int(start * SR), len(t) - 1))
        n = min(int(0.24 * SR), len(t) - idx)
        if n <= 0:
            continue
        seg_t = np.arange(n) / SR
        f = 300.0 + 900.0 * seg_t / 0.24
        lap = formant_tone(seg_t, f, 6, [(700, 220, 1.0), (1600, 400, 0.4)])
        lap = lap * np.exp(-seg_t / 0.08)
        lap += bandpass_fast(rng.uniform(-1, 1, n), 900.0, 3000.0) * np.exp(-seg_t / 0.05) * 0.25
        out[idx:idx + n] += lap
    return normalize(out * 0.85)


SOUNDS = {
    "CDAlpacaAlarm": make_alarm,
    "CDAlpacaAlarmAmbient": make_ambient_alarm,
    "CDAlpacaHum": make_hum,
    "CDAlpacaSpit": make_spit,
    "CDAlpacaWhine": make_whine,
    "CDAlpacaDeath": make_death,
    "CDAlpacaPickup": make_pickup,
    "CDAlpacaChew": make_chew,
    "CDAlpacaDrink": make_drink,
}


# ---------------------------------------------------------------- 落盘


def write_wav(path, x):
    x = np.clip(x, -1.0, 1.0)
    pcm = (x * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def to_ogg(wav_path, ogg_path, ffmpeg):
    """编码成 .ogg（Vorbis）。

    优先 libvorbis；本机 homebrew 的 ffmpeg 9 没编进 libvorbis，所以回退到 ffmpeg 自带的
    实验性 vorbis 编码器（`-strict -2`）。两者在 FMOD 眼里都是普通 ogg/vorbis。
    """
    attempts = [
        [ffmpeg, "-y", "-loglevel", "error", "-i", wav_path,
         "-c:a", "libvorbis", "-q:a", "5", "-ac", "1", "-ar", str(SR), ogg_path],
        # ffmpeg 自带的 vorbis 编码器只支持 2 声道，所以回退时用立体声（内容仍是单声道信号）
        [ffmpeg, "-y", "-loglevel", "error", "-i", wav_path,
         "-c:a", "vorbis", "-strict", "-2", "-q:a", "5", "-ac", "2", "-ar", str(SR), ogg_path],
    ]
    last = None
    for cmd in attempts:
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode == 0:
            return cmd[cmd.index("-c:a") + 1]
        last = r
    raise RuntimeError(f"no usable vorbis encoder: {last.stderr.strip() if last else '?'}")


def check(outdir, ffprobe):
    bad = 0
    for name in SOUNDS:
        p = os.path.join(outdir, name + ".ogg")
        if not os.path.isfile(p):
            log(f"MISSING {name}.ogg")
            bad += 1
            continue
        out = subprocess.run([ffprobe, "-v", "error", "-show_entries",
                              "stream=channels,sample_rate,duration", "-of", "default=nw=1", p],
                             capture_output=True, text=True).stdout.strip().replace("\n", " ")
        size = os.path.getsize(p)
        log(f"OK  {name}.ogg  {out}  {size} bytes")
    log(f"check: {len(SOUNDS) - bad}/{len(SOUNDS)} ok")
    return 1 if bad else 0


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    outdir = os.path.abspath(os.path.join(here, SOUND_DIR_REL))
    ap = argparse.ArgumentParser(description="synthesize the alpaca voice set")
    ap.add_argument("--outdir", default=outdir)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    ffmpeg = shutil.which("ffmpeg")
    ffprobe = shutil.which("ffprobe")
    if not ffmpeg:
        log("ERROR: ffmpeg not found in PATH")
        return 2

    if args.check:
        if not ffprobe:
            log("ERROR: ffprobe not found in PATH")
            return 2
        return check(args.outdir, ffprobe)

    os.makedirs(args.outdir, exist_ok=True)
    tmp = os.path.join(args.outdir, "_tmp.wav")
    for name, fn in SOUNDS.items():
        x = fade_edges(fn())
        write_wav(tmp, x)
        ogg = os.path.join(args.outdir, name + ".ogg")
        to_ogg(tmp, ogg, ffmpeg)
        dur = len(x) / SR
        peak = 20 * np.log10(max(float(np.max(np.abs(x))), 1e-9))
        rms = 20 * np.log10(max(float(np.sqrt(np.mean(x ** 2))), 1e-9))
        log(f"{name:22s} {dur:4.2f}s peak={peak:6.2f} dBFS rms={rms:6.2f} dBFS -> {os.path.getsize(ogg)} bytes")
    if os.path.isfile(tmp):
        os.remove(tmp)
    log(f"wrote {len(SOUNDS)} ogg files into {args.outdir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
