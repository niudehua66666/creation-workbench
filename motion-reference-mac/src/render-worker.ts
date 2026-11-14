import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {bundle} from '@remotion/bundler';
import {selectComposition,renderFrames} from '@remotion/renderer';
import {run} from './process';
const [project,output,browser]=process.argv.slice(2);
const report=(data:unknown)=>process.stdout.write(JSON.stringify(data)+'\n');
async function main(){
 const props=JSON.parse(await fs.readFile(path.join(project,'props.json'),'utf8'));
 const serveUrl=await bundle({entryPoint:path.join(project,'src','index.tsx'),outDir:path.join(project,'.bundle'),onProgress:n=>report({phase:'bundle',done:n,total:100})});
 const binariesDirectory=path.resolve(__dirname,'../runtime/bin');
 const comp=await selectComposition({serveUrl,id:'Replica',inputProps:props,browserExecutable:browser||undefined,binariesDirectory});
 const frames=await fs.mkdtemp(path.join(os.tmpdir(),'workbench-render-'));
 try{
  // Generated scenes contain graphics only: render with Chromium, encode with our
  // own source-built FFmpeg. No second native media runtime is distributed.
  await renderFrames({serveUrl,composition:comp,inputProps:props,outputDir:frames,browserExecutable:browser||undefined,binariesDirectory,
   concurrency:2,imageFormat:'jpeg',jpegQuality:95,timeoutInMilliseconds:45_000,muted:true,
   onStart:()=>{},onFrameUpdate:done=>report({phase:'render',done,total:comp.durationInFrames})});
  await run(path.join(binariesDirectory,'ffmpeg'),['-hide_banner','-loglevel','error','-nostdin','-y','-framerate',String(comp.fps),'-pattern_type','glob','-i',path.join(frames,'*.jpeg'),'-frames:v',String(comp.durationInFrames),'-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',output],{detached:false});
  report({phase:'done',output,frames:comp.durationInFrames});
 }finally{await fs.rm(frames,{recursive:true,force:true});}
}
main().catch(e=>{process.stderr.write(String(e.stack??e));process.exit(1);});
