#!/usr/bin/env python3
"""Prepare pinned release runtimes and their notices; does not launch the app."""
from pathlib import Path
import os,sys,subprocess,urllib.request,hashlib,shutil,tempfile,json
root=Path(__file__).resolve().parent.parent
os.chdir(root)
subprocess.run([sys.executable,'scripts/build-media.py'],check=True)
prefix=Path(tempfile.gettempdir())/('creation-workbench-media-'+str(os.getuid()))
cache=root/'.cache/distribution';cache.mkdir(parents=True,exist_ok=True)
licenses=root/'runtime/licenses';licenses.mkdir(parents=True,exist_ok=True)
def download(url,dest):
 if not dest.exists():
  tmp=dest.with_suffix(dest.suffix+'.download');subprocess.run(['curl','-fL','--retry','3','--connect-timeout','20','-o',str(tmp),url],check=True);tmp.replace(dest)
version='2026.10.26';base='https://github.com/yt-dlp/yt-dlp/releases/download/'+version+'/'
download(base+'yt-dlp_macos',cache/'yt-dlp')
download(base+'SHA2-256SUMS',licenses/'yt-dlp-SHA256SUMS.txt')
expected=next(line.split()[0] for line in (licenses/'yt-dlp-SHA256SUMS.txt').read_text().splitlines() if line.split()[-1]=='yt-dlp_macos')
if hashlib.sha256((cache/'yt-dlp').read_bytes()).hexdigest()!=expected:raise RuntimeError('yt-dlp checksum mismatch')
(cache/'yt-dlp').chmod(0o755)
nodeVersion=subprocess.check_output(['node','--version'],text=True).strip()
download('https://raw.githubusercontent.com/nodejs/node/'+nodeVersion+'/LICENSE',licenses/'Node-LICENSE.txt')
for source,name in [('LICENSE','yt-dlp-LICENSE.txt'),('THIRD_PARTY_LICENSES.txt','yt-dlp-THIRD_PARTY_LICENSES.txt')]:
 download('https://raw.githubusercontent.com/yt-dlp/yt-dlp/'+version+'/'+source,licenses/name)
for source,name in [('.cache/media-build/ffmpeg/COPYING.GPLv2','FFmpeg-GPLv2.txt'),('.cache/media-build/ffmpeg/LICENSE.md','FFmpeg-LICENSE.md'),('.cache/media-build/x264/COPYING','x264-COPYING.txt'),('.cache/media-build/freetype/docs/FTL.TXT','FreeType-FTL.txt'),('.cache/media-build/harfbuzz/COPYING','HarfBuzz-COPYING.txt'),('node_modules/remotion/LICENSE.md','Remotion-LICENSE.md'),('../LICENSE','CreationWorkbench-LICENSE.txt'),('../THIRD_PARTY.md','THIRD_PARTY.md')]:
 shutil.copyfile(root/source,licenses/name)
env=dict(os.environ,WORKBENCH_FFMPEG=str(prefix/'bin/ffmpeg'),WORKBENCH_FFPROBE=str(prefix/'bin/ffprobe'),WORKBENCH_YTDLP=str(cache/'yt-dlp'))
subprocess.run(['node','scripts/prepare-runtime.mjs'],env=env,check=True)
manifest={}
for name in ['node','bin/ffmpeg','bin/ffprobe','bin/yt-dlp']:
 p=root/'runtime'/name;manifest[name]={'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
manifest['node']['version']=nodeVersion
manifest['bin/yt-dlp']['version']=version
manifest['bin/yt-dlp']['upstream']=base+'yt-dlp_macos'
(licenses/'runtime-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
release=root/'release';release.mkdir(exist_ok=True)
sourceBundle=cache/'MediaSources';sourceBundle.mkdir(exist_ok=True)
for source in (root/'.cache/media-build/sources').iterdir():shutil.copyfile(source,sourceBundle/source.name)
shutil.copyfile(root/'scripts/build-media.py',sourceBundle/'build-media.py')
(sourceBundle/'BUILD.txt').write_text('Unmodified upstream archives for the bundled FFmpeg and linked libraries.\nBuild recipe: motion-reference-mac/scripts/build-media.py in the accompanying application source.\nSHA-256 and upstream URLs: manifest.json.\nFFmpeg: GPL-2.0-or-later; x264: GPL-2.0-or-later; FreeType: FreeType License; HarfBuzz: MIT.\n')
shutil.make_archive(str(release/'CreationWorkbench-MediaSources'),'gztar',cache,'MediaSources')
print('Distribution runtime and media source archive ready.')
