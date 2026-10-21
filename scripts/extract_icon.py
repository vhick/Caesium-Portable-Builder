"""Extract exact, multiresolution RT_GROUP_ICON from the official upstream EXE.
Requires pefile and Pillow (on GitHub runner only). No generic icons.
"""
import sys, struct, pathlib, io
import pefile
from PIL import Image


def extract_ico(exe, out):
    pe = pefile.PE(str(exe), fast_load=False)
    if not hasattr(pe, 'DIRECTORY_ENTRY_RESOURCE'):
        pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_RESOURCE']])
    resources = pe.DIRECTORY_ENTRY_RESOURCE.entries
    groups = next((r for r in resources if r.id == 14), None)
    icons = next((r for r in resources if r.id == 3), None)
    if not groups or not icons:
        raise RuntimeError('Official executable has no group-icon resources')
    icon_by_id = {}
    for entry in icons.directory.entries:
        if not hasattr(entry, 'directory'): continue
        lang = entry.directory.entries[0]
        offset = lang.data.struct.OffsetToData
        size = lang.data.struct.Size
        icon_by_id[entry.id] = pe.get_data(offset, size)
    best = None
    for group in groups.directory.entries:
        if not hasattr(group, 'directory'): continue
        lang = group.directory.entries[0]
        raw = pe.get_data(lang.data.struct.OffsetToData, lang.data.struct.Size)
        if len(raw) < 6: continue
        reserved, kind, count = struct.unpack_from('<HHH', raw)
        if reserved != 0 or kind != 1: continue
        frames = []
        for index in range(count):
            data = raw[6 + 14*index:6 + 14*(index+1)]
            if len(data) != 14: break
            w, h, colors, zero, planes, bpp, size, rid = struct.unpack('<BBBBHHIH', data)
            if rid not in icon_by_id: continue
            blob = icon_by_id[rid]
            frames.append(((w,h,colors,zero,planes,bpp),blob))
        if frames and (best is None or len(frames) > len(best)):
            best = frames
    if not best:
        raise RuntimeError('No decodable official icon frames')
    header = struct.pack('<HHH',0,1,len(best))
    offset = 6+16*len(best)
    for data,blob in best:
        header += struct.pack('<BBBBHHII',*data,len(blob),offset)
        offset += len(blob)
    output = pathlib.Path(out)
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_bytes(header+b''.join(blob for _,blob in best))
    # Use each of the icon's own resolutions for required PortableApps UI sizes.
    icon = Image.open(io.BytesIO(output.read_bytes()))
    for size in [16,32,75,128]:
        try:
            im = icon.ico.getimage((size,size))
        except Exception:
            # Resize a *real* upstream icon frame, never use generic artwork.
            variants = icon.ico.sizes()
            preferred = max(variants, key=lambda s: s[0]*s[1])
            im = icon.ico.getimage(preferred).resize((size,size),Image.Resampling.LANCZOS)
        im.convert('RGBA').save(output.parent/('appicon_'+str(size)+'.png'))
    print('Extracted',len(best),'genuine application icon resolutions')

if __name__=='__main__':
    if len(sys.argv)!=3: raise SystemExit('Usage: extract_icon.py input.exe output.ico')
    extract_ico(sys.argv[1],sys.argv[2])
