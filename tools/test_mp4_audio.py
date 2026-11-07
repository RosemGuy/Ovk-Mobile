"""Check MP4 metadata inspection against actual AAC, Opus and silent files."""
from pathlib import Path
import ctypes
import struct
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
class Info(ctypes.Structure):
    _fields_=[('valid',ctypes.c_int),('audioTracks',ctypes.c_uint),('codecCount',ctypes.c_uint),('codecs',(ctypes.c_char*5)*4),('objectType',ctypes.c_uint),('audioObjectType',ctypes.c_uint)]
with tempfile.TemporaryDirectory(prefix='ovk-mp4-audio-') as directory:
    work=Path(directory)
    subprocess.run(['cc','-std=c99','-Wall','-Wextra','-Werror','-shared','-fPIC',str(root/'OpenVK/OVKMP4Audio.c'),'-o',str(work/'inspect.so')],check=True)
    library=ctypes.CDLL(str(work/'inspect.so')); inspect=library.OVKInspectMP4Audio
    inspect.argtypes=[ctypes.c_void_p,ctypes.c_size_t]; inspect.restype=Info
    extract=library.OVKExtractMP4Audio; extract.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_char_p]; extract.restype=ctypes.c_int
    def read(data):
        result=inspect(data,len(data))
        return result.valid,result.audioTracks,[bytes(result.codecs[i]).rstrip(b'\0').decode('ascii') for i in range(result.codecCount)]
    def box(kind,body):return struct.pack('>I',len(body)+8)+kind+body
    # Valid container with malformed child, extended sizes, empty and truncated metadata.
    for data in [b'',b'not mp4',box(b'moov',b'bad'),struct.pack('>I4sQ',1,b'moov',2),box(b'moov',box(b'trak',box(b'mdia',box(b'stsd',b'\0'*4+struct.pack('>I',2)))) )]:
        assert read(data)[0]==0
    for kind,codec in [('aac','mp4a'),('libmp3lame','mp4a'),('libopus','Opus'),(None,None)]:
        output=work/((kind or 'silent')+'.mp4')
        args=['ffmpeg','-v','error','-f','lavfi','-i','color=size=32x32:rate=10:duration=0.2']
        if kind:args+=['-f','lavfi','-i','sine=frequency=440:duration=0.2','-c:a',kind]
        args+=['-c:v','libx264','-t','0.2','-y',str(output)]
        subprocess.run(args,check=True)
        data=output.read_bytes(); result=read(data)
        assert result==(1,1,[codec]) if kind else result==(1,0,[]),result
        expected=2 if kind=='aac' else (1 if kind=='libmp3lame' else 0)
        audio=work/('extracted-'+(kind or 'silent')+('.aac' if expected==2 else '.mp3'))
        assert extract(data,len(data),str(audio).encode())==expected, (kind,inspect(data,len(data)).objectType)
        if expected:
            # Chunk offsets must stay inside the actual file, including malicious tables.
            damaged=bytearray(data); offset=damaged.rfind(b'stco'); assert offset>=0
            damaged[offset+12:offset+16]=b'\xff'*4
            broken=work/'broken-audio'; assert extract(bytes(damaged),len(damaged),str(broken).encode())==0
            assert not broken.exists()
            assert extract(data[:-10],len(data)-10,str(broken).encode())==0
            subprocess.run(['ffmpeg','-v','error','-i',str(audio),'-f','null','-'],check=True)
        else: assert not audio.exists()
    assert read((root/'OpenVK/AboutSecret.mp4').read_bytes())==(1,1,['mp4a'])
print('PASS: raw MP4 audio (AAC/MP3 demux and decode, Opus rejection, video-only, bundled movie and malformed boxes)')
