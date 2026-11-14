#!/usr/bin/env python3
"""Build a pinned, redistributable FFmpeg with matching source archives retained."""
from pathlib import Path
import os,sys,json,hashlib,urllib.request,subprocess,tarfile,tempfile
root=Path(__file__).resolve().parent.parent
build=root/'.cache/media-build'; sources=build/'sources'; sources.mkdir(parents=True,exist_ok=True)
# pkg-config escapes non-ASCII prefixes; use an ASCII-only temporary prefix.
prefix=Path(tempfile.gettempdir())/('creation-workbench-media-'+str(os.getuid()));prefix.mkdir(exist_ok=True)
env=dict(os.environ,PATH=str(prefix/'bin')+':'+str(build/'tools/bin')+':'+os.environ['PATH'],PKG_CONFIG_PATH=str(prefix/'lib/pkgconfig'),MACOSX_DEPLOYMENT_TARGET='15.0',PKG_CONFIG_ALLOW_SYSTEM_LIBS='1',PKG_CONFIG_ALLOW_SYSTEM_CFLAGS='1')
def run(args,cwd):
 print('RUN',args,flush=True)
 result=subprocess.run(args,cwd=cwd,env=env)
 if result.returncode and (cwd/'ffbuild/config.log').exists():print((cwd/'ffbuild/config.log').read_text(errors='replace')[-12000:],flush=True)
 result.check_returncode()
for item in json.loads((root/'scripts/media/sources.json').read_text()):
 archive=sources/item['file']
 if not archive.exists():urllib.request.urlretrieve(item['url'],archive)
 if hashlib.sha256(archive.read_bytes()).hexdigest()!=item['sha256']:raise RuntimeError('Checksum mismatch: '+item['file'])
 name=item['file'].split('.')[0];dest=build/name
 if not dest.exists():
  dest.mkdir()
  run(['tar','xf',str(archive),'--strip-components=1','-C',str(dest)],build)
if not (build/'tools/bin/meson').exists():
 run([sys.executable,'-m','venv',str(build/'tools')],build)
 run([str(build/'tools/bin/pip'),'install','meson==1.11.2','ninja==1.13.2'],build)
jobs='4'
if not (prefix/'bin/pkg-config').exists():
 d=build/'pkgconf';run(['./configure','--prefix='+str(prefix),'--disable-shared'],d);run(['make','-j'+jobs],d);run(['make','install'],d);(prefix/'bin/pkg-config').symlink_to('pkgconf')
if not (prefix/'lib/libfreetype.a').exists():
 d=build/'freetype';run(['./configure','--prefix='+str(prefix),'--disable-shared','--with-harfbuzz=no','--with-bzip2=no','--with-png=no','--with-brotli=no','--with-zlib=no'],d);run(['make','-j'+jobs],d);run(['make','install'],d)
if not (prefix/'include/harfbuzz/hb-ft.h').exists():
 d=build/'harfbuzz';run(['meson','setup','--reconfigure','build','--prefix='+str(prefix),'--libdir=lib','--default-library=static','--buildtype=release','-Dtests=disabled','-Ddocs=disabled','-Dutilities=disabled','-Dglib=disabled','-Dgobject=disabled','-Dcairo=disabled','-Dfreetype=enabled','-Dicu=disabled'],d);run(['meson','compile','-C','build','-j',jobs],d);run(['meson','install','-C','build'],d)
if not (prefix/'lib/libx264.a').exists():
 d=build/'x264';run(['./configure','--prefix='+str(prefix),'--enable-static','--enable-pic','--disable-cli','--disable-opencl'],d);run(['make','-j'+jobs],d);run(['make','install'],d)
d=build/'ffmpeg'
# GitHub source archives have no VERSION file; avoid inheriting this app's git hash.
(d/'VERSION').write_text('8.1.1\n')
run(['./configure','--prefix='+str(prefix),'--enable-gpl','--enable-libx264','--enable-libfreetype','--enable-libharfbuzz','--disable-shared','--enable-static','--disable-autodetect','--enable-zlib','--disable-ffplay','--disable-doc','--disable-debug','--disable-network','--pkg-config-flags=--static','--extra-libs=-lc++','--extra-version=creation-workbench'],d)
run(['make','-j'+jobs],d);run(['make','install'],d)
print('FFmpeg ready:',prefix/'bin/ffmpeg')
