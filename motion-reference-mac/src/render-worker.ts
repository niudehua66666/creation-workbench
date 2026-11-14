import fs from 'node:fs/promises';
import path from 'node:path';
import {bundle} from '@remotion/bundler';
import {selectComposition,renderMedia} from '@remotion/renderer';
const [project,output,browser]=process.argv.slice(2);
const report=(data:unknown)=>process.stdout.write(JSON.stringify(data)+'\n');
async function main(){
 const props=JSON.parse(await fs.readFile(path.join(project,'props.json'),'utf8'));
 const serveUrl=await bundle({entryPoint:path.join(project,'src','index.tsx'),outDir:path.join(project,'.bundle'),onProgress:n=>report({phase:'bundle',done:n,total:100})});
 const comp=await selectComposition({serveUrl,id:'Replica',inputProps:props,browserExecutable:browser||undefined});
 const result=await renderMedia({serveUrl,composition:comp,inputProps:props,codec:'h264',outputLocation:output,browserExecutable:browser||undefined,concurrency:2,crf:18,imageFormat:'jpeg',timeoutInMilliseconds:45_000,onProgress:p=>report({phase:'render',done:p.renderedFrames,total:comp.durationInFrames,progress:p.progress})});
 report({phase:'done',output,frames:comp.durationInFrames,result:!!result});
}
main().catch(e=>{process.stderr.write(String(e.stack??e));process.exit(1);});
