import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {execFileSync} from 'node:child_process';
const app=process.argv[2];
const root=app?path.resolve(app,'Contents/Resources/app'):process.cwd();
const node=path.join(root,'runtime/node');
const dir=await fs.mkdtemp(path.join(os.tmpdir(),'workbench-smoke-'));
try{
 await fs.mkdir(path.join(dir,'src'));
 await fs.symlink(path.join(root,'node_modules'),path.join(dir,'node_modules'));
 await fs.writeFile(path.join(dir,'props.json'),JSON.stringify({durationSeconds:.5}));
 await fs.writeFile(path.join(dir,'src/index.tsx'),`import React from 'react';import {Composition,registerRoot,useCurrentFrame} from 'remotion';const Scene=()=>{const f=useCurrentFrame();return <div style={{background:'#123456',width:320,height:180,color:'white',fontSize:30,paddingLeft:f}}>Workbench</div>};registerRoot(()=> <Composition id="Replica" component={Scene} durationInFrames={15} fps={30} width={320} height={180}/>);`);
 const browser=path.join(root,'runtime/browser/chrome/chrome-headless-shell');
 const output=path.join(dir,'result.mp4');
 execFileSync(node,[path.join(root,'dist/render-worker.cjs'),dir,output,browser],{stdio:'inherit',timeout:180000,cwd:dir});
 const probe=JSON.parse(execFileSync(path.join(root,'runtime/bin/ffprobe'),['-v','error','-show_streams','-show_format','-of','json',output],{encoding:'utf8'}));
 if(probe.streams[0].width!==320||probe.streams[0].height!==180||Number(probe.streams[0].nb_frames)!==15)throw new Error('Incorrect rendered output');
 if(app){for(const helper of ['Capture/截录暂存.app/Contents/MacOS/LightRecorder','Trackpad/触控板锁.app/Contents/MacOS/TrackpadLock'])await fs.access(path.join(app,'Contents/Resources',helper));}
 console.log('PASS: isolated runtime rendered and decoded 15 frames'+(app?'; bundled helpers present.':'.'));
}finally{await fs.rm(dir,{recursive:true,force:true});}
