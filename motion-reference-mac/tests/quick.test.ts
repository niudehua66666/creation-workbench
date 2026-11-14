import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {Engine} from '../src/engine';
import {run} from '../src/process';
import {briefKey,briefText} from '../src/brief';
import {jobCategories,segmentCategories} from '../src/motion-categories';

const runtime=path.resolve('.');
test('quick workflow skips full scanning/generation, caches analysis, preserves prior replica, and exports offline',async()=>{
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'motion-quick-'));const e=new Engine(path.join(dir,'data'),runtime);await e.init();
 try{
  const input=path.join(dir,'fixture.mp4');await run(e.media.ffmpeg,['-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=320x180:rate=24:duration=2','-c:v','libx264','-pix_fmt','yuv420p',input]);
  let aiCalls=0;
  (e as any).ai=async(_job:any,prompt:string,_images:string[],schema:any,_signal:unknown,effort:string)=>{
   aiCalls++;
   assert.equal(effort,'low');
   if(aiCalls===1){
    assert.ok(schema.properties.candidates.items.required.includes('categories'));
    return {classification:{primary:'PNG',secondary:[],reason:'测试画面',suggestedAuthor:'',authorEvidence:''},candidates:[{start:0,end:2,title:'片段',reason:'图形和标题同时出现',categories:['PNG','标题','标题','无效'],confidence:'高'}]};
   }
   assert.ok(schema.properties.actions.items.required.includes('category'));
   assert.ok(prompt.includes('PNG 和标题同屏时分别写'));
   return {summary:'图形向右移动，标题淡入。',categories:['PNG'],actions:[
    {start:0,end:1.5,element:'图形',category:'PNG',motion:'从左向右移动，随后停住。'},
    {start:.5,end:1.5,element:'主标题',category:'标题',motion:'从透明变为可见。'},
   ],rhythm:'推测减速停稳。',uncertainty:'抽样之间可能存在快速变化。'};
  };
  for(const name of ['scenes','waveform','proxy'])(e.media as any)[name]=()=>{throw new Error('quick import must not call '+name);};
  (e as any).generate=()=>{throw new Error('quick path must not generate');};(e as any).render=()=>{throw new Error('quick path must not render');};
  const first=await e.importVideo(input);await e.wait();let j=await e.store.get(first.id);assert.equal(j.progress.state,'ready',j.error);assert.equal(j.author,'');assert.equal(aiCalls,1);assert.deepEqual(j.waveform,[]);
  assert.equal(j.classification?.primary,'PNG');assert.deepEqual(j.classification?.secondary,['标题']);
  assert.deepEqual(segmentCategories(j.candidates[0]),['PNG','标题']);
  assert.deepEqual(segmentCategories({category:'图表'}),['图表']);
  await e.action(j.id,'classification',{primary:'PNG',secondary:[],author:'新的实验作者'});
  j=await e.store.get(j.id);j.outputVersion=123;j.props={durationSeconds:1};j.referenceRange={start:0,end:1};
  const range={start:0,end:2};
  j.brief={key:briefKey(j,range),range,createdAt:Date.now(),summary:'旧版说明',actions:[],rhythm:'',uncertainty:''};
  assert.ok(briefText(j).includes('旧版说明'));
  await e.store.save(j);await fs.writeFile(path.join(e.store.dir(j.id),'replica.mp4'),'previous replica');
  await e.action(j.id,'brief',{start:0,end:2});await e.wait();j=await e.store.get(j.id);assert.equal(j.progress.state,'ready',j.error);assert.equal(aiCalls,2);assert.equal(j.outputVersion,123);assert.equal(await fs.readFile(path.join(e.store.dir(j.id),'replica.mp4'),'utf8'),'previous replica');assert.ok(briefText(j).includes('从左向右移动'));
  assert.deepEqual(j.brief?.categories,['PNG','标题']);
  assert.deepEqual(j.brief?.actions.map(a=>a.category),['PNG','标题']);
  assert.deepEqual(jobCategories(j),['PNG','标题']);
  assert.deepEqual(j.classification?.secondary,[]);
  assert.match(briefText(j),/类别：PNG · 标题/);
  assert.ok(briefText(j).includes('[标题] 主标题'));
  (e as any).ai=()=>{throw new Error('cached and export paths must not call AI');};
  await e.action(j.id,'brief',{start:0,end:2});await e.wait();assert.equal((await e.store.get(j.id)).progress.state,'ready');
  const destination=path.join(dir,'export');await e.exportEditing(j.id,destination);assert.equal((await e.media.probe(path.join(destination,'参考片段.mp4'))).duration,2);assert.ok((await fs.readFile(path.join(destination,'动作说明.txt'),'utf8')).includes('新的实验作者'));
  await e.action(j.id,'selection',{start:.5,end:1.5});const destination2=path.join(dir,'no-analysis');await e.exportEditing(j.id,destination2);assert.ok((await fs.readFile(path.join(destination2,'动作说明.txt'),'utf8')).includes('尚未进行 AI 分析'));assert.equal(JSON.parse(await fs.readFile(path.join(destination2,'来源.json'),'utf8')).brief,null);
  const occupied=path.join(dir,'file');await fs.writeFile(occupied,'keep');await assert.rejects(e.exportEditing(j.id,path.join(occupied,'export')));assert.equal(await fs.readFile(occupied,'utf8'),'keep');assert.equal((await fs.readdir(dir)).filter(n=>n.endsWith('.partial')).length,0);
  const reopened=new Engine(e.dataDir,runtime);await reopened.init();assert.ok((await reopened.authors.list()).includes('新的实验作者'));assert.ok((await reopened.store.get(j.id)).brief);
 }finally{await e.shutdown();await fs.rm(dir,{recursive:true,force:true});}
});
test('authors can be added before importing videos and survive restart without duplicates',async()=>{
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'motion-authors-'));try{const e=new Engine(dir,runtime);await e.init();await Promise.all([e.authors.add('新作者甲'),e.authors.add('新作者乙'),e.authors.add('新作者甲')]);const reopened=new Engine(dir,runtime);await reopened.init();const names=await reopened.authors.list();assert.ok(names.includes('影视飓风'));assert.ok(names.includes('新作者乙'));assert.equal(names.filter(n=>n==='新作者甲').length,1);await assert.rejects(e.authors.add('  '));}finally{await fs.rm(dir,{recursive:true,force:true});}
});
