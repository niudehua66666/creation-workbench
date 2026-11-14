const {execFileSync}=require('node:child_process');
const fs=require('node:fs'),path=require('node:path');
module.exports=async()=>{
 const root=process.cwd();
 for(const [name,args] of [['runtime/node',['--version']],['runtime/bin/ffmpeg',['-version']],['runtime/bin/yt-dlp',['--version']],['runtime/bin/ffprobe',['-version']]]){
  const executable=path.join(root,name);const output=execFileSync(executable,args,{env:{...process.env,DYLD_LIBRARY_PATH:path.dirname(executable)},timeout:30000,encoding:'utf8'});if(name.includes('ffmpeg')&&output.includes('--enable-nonfree'))throw new Error('Cannot distribute nonfree FFmpeg');console.log('Runtime OK:',name,output.split('\n')[0]);
 }
 const walk=p=>{for(const f of fs.readdirSync(p,{withFileTypes:true})){const x=path.join(p,f.name);if(f.name==='chrome-headless-shell'&&!f.isDirectory())return x;if(f.isDirectory()){const found=walk(x);if(found)return found;}}};
 const browser=walk(path.join(root,'runtime/browser'));if(!browser)throw new Error('Missing bundled Chromium');
 console.log('Runtime OK:',execFileSync(browser,['--version'],{timeout:30000,encoding:'utf8'}).trim());
};
