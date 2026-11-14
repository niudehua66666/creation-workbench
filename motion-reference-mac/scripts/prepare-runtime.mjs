import {ensureBrowser} from '@remotion/renderer';
import {mkdir, cp, copyFile, chmod} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

process.chdir(fileURLToPath(new URL('..', import.meta.url)));
function executable(name, variable) {
 const candidate=process.env[variable] || execFileSync('/usr/bin/which',[name],{encoding:'utf8'}).trim();
 if(!candidate) throw new Error(`Install ${name} or set ${variable} to its executable path`);
 execFileSync(candidate,['--version'],{stdio:'ignore',timeout:30000});
 return candidate;
}
// FFmpeg uses -version rather than --version.
const ffmpeg=process.env.WORKBENCH_FFMPEG || execFileSync('/usr/bin/which',['ffmpeg'],{encoding:'utf8'}).trim();
execFileSync(ffmpeg,['-version'],{stdio:'ignore',timeout:30000});
const ytdlp=executable('yt-dlp','WORKBENCH_YTDLP');
await mkdir('runtime/browser',{recursive:true});
await mkdir('runtime/bin',{recursive:true});
for(const [source,destination] of [[process.execPath,'runtime/node'],[ffmpeg,'runtime/bin/ffmpeg'],[ytdlp,'runtime/bin/yt-dlp']]) {
 await copyFile(source,destination);
 await chmod(destination,0o755);
}
const browser=await ensureBrowser({});
await cp(path.dirname(browser.path),'runtime/browser/chrome',{recursive:true});
console.log('Local runtime prepared. Verify redistribution licenses and dynamic libraries before distributing a binary.');
