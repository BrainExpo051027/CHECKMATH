import wave
import struct
import math
import os
import urllib.request

os.makedirs('assets/audio', exist_ok=True)

def generate_beep(filename, freq=440.0, duration=0.1, volume=32767.0):
    sample_rate = 44100.0
    num_samples = int(sample_rate * duration)
    
    with wave.open(filename, 'w') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        
        for i in range(num_samples):
            # Short envelope to avoid clicking
            env = 1.0
            if i < 100: env = i / 100.0
            if i > num_samples - 100: env = (num_samples - i) / 100.0
                
            value = int(volume * env * math.sin(2 * math.pi * freq * (i / sample_rate)))
            data = struct.pack('<h', value)
            wav_file.writeframesraw(data)

# Move sound: quick, lower pitch
generate_beep('assets/audio/move.wav', freq=350.0, duration=0.08, volume=15000.0)

# Capture sound: slightly longer, higher pitch, two beeps or chord (simplifying to higher pitch here)
generate_beep('assets/audio/capture.wav', freq=600.0, duration=0.15, volume=20000.0)

# For BGM, let's download a small royalty free ambient loop if possible, 
# or just generate a very quiet, slow sine wave to prove it works
try:
    url = "https://actions.google.com/sounds/v1/water/waves_crashing_on_rock_beach.ogg" # OGG works in flutter
    urllib.request.urlretrieve(url, "assets/audio/bgm.ogg")
except Exception as e:
    print("Could not download BGM, generating a tone instead.")
    generate_beep('assets/audio/bgm.ogg', freq=200.0, duration=2.0, volume=5000.0)

print("Audio files generated in assets/audio/")
