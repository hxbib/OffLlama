import sys, time, datetime
from faster_whisper import WhisperModel
wav, out, startseg = sys.argv[1], sys.argv[2], int(sys.argv[3])
# segment 0 wall time: 2026-10-26 15:19:21Z = 11:19:21 ET
base = datetime.datetime(2026,10,26,11,19,21) + datetime.timedelta(seconds=startseg*3)
m = WhisperModel("medium.en", device="cpu", compute_type="int8", cpu_threads=8)
import wave, numpy as np
wf=wave.open(wav); audio=np.frombuffer(wf.readframes(wf.getnframes()),dtype=np.int16).astype(np.float32)/32768
segs, info = m.transcribe(audio, beam_size=5, vad_filter=True, condition_on_previous_text=False,
  initial_prompt="Meta Global AI Developer Hackathon kickoff. Cerebral Valley. Llama, Muse Spark, SAM 3.1, Meta Model API, Discord, judging criteria.")
t0=time.time()
with open(out,"w") as f:
  for s in segs:
    w=(base+datetime.timedelta(seconds=s.start)).strftime("%H:%M:%S")
    st=startseg*3+s.start
    f.write(f"[{w} ET | +{int(st//3600)}:{int(st%3600//60):02d}:{int(st%60):02d}] {s.text.strip()}\n"); f.flush()
print("done", time.time()-t0)
