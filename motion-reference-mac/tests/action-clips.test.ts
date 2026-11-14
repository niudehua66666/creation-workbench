import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {actionClipDraft} from '../src/action-clips';
import {briefKey} from '../src/brief';
import {newJob} from '../src/core';
import {Engine} from '../src/engine';
import {run} from '../src/process';

test('two actions of the same type create separate original-video clips and a partial save can resume',async()=>{
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'motion-eagle-clips-'));
 const engine=new Engine(dir,process.cwd());
 const fetchBefore=globalThis.fetch;
 try{
  await engine.init();
  const job=newJob('原始录屏','https://example.com/source');
  job.author='小Lin说';
  job.sourceFile='original.mp4';
  job.media={duration:5,width:320,height:180,fps:25,audio:true};
  job.selection={start:1.25,end:4.75};
  job.brief={key:briefKey(job,job.selection),range:job.selection,createdAt:1,summary:'',rhythm:'',uncertainty:'',categories:['关键词'],actions:[
   {start:.5,end:1.5,element:'弹幕',motion:'文字从右向左滑动',category:'关键词'},
   {start:1.25,end:2.75,element:'财富大字',motion:'大字淡入',category:'关键词'},
  ]};
  await engine.store.save(job);
  const source=path.join(engine.store.dir(job.id),job.sourceFile);
  await run(engine.media.ffmpeg,['-loglevel','error','-f','lavfi','-i','testsrc2=size=320x180:rate=25:duration=5','-f','lavfi','-i','sine=duration=5','-c:v','libx264','-c:a','aac',source]);
  const library='/test/eagle.library';
  let currentLibrary=library;
  let failSecond=true;
  const records:{name:string;annotation:string;tags:string[];folderId:string;website:string}[]=[];
  const durations:number[]=[];
  globalThis.fetch=async(url,init)=>{
   const route=new URL(String(url));
   let data:unknown;
   switch(route.pathname){
    case '/api/library/info':data={library:{path:currentLibrary}};break;
    case '/api/folder/list':data=[{id:'target',name:'动效拆解'}];break;
    case '/api/item/list':
     assert.equal(route.searchParams.get('folders'),'target');
     data=records;
     break;
    case '/api/item/addFromPath':{
     const record=JSON.parse(String(init?.body));
     if(failSecond&&record.name.includes('财富大字'))return Response.json({status:'error',message:'测试中断'});
     const media=await engine.media.probe(record.path);
     assert.equal(media.audio,true);
     durations.push(media.duration);
     records.push(record);
     data=null;
     break;
    }
    default:assert.fail(route.pathname);
   }
   return Response.json({status:'success',data});
  };
  const drafts=job.brief.actions.map((_,index)=>actionClipDraft(job.brief!,index));
  await assert.rejects(engine.saveActionClips(job.id,2,library,drafts),/动作说明已更新/);
  currentLibrary='/another.library';
  await assert.rejects(engine.saveActionClips(job.id,1,library,drafts),/资源库已切换/);
  assert.equal(records.length,0);
  currentLibrary=library;
  await assert.rejects(engine.saveActionClips(job.id,1,library,drafts),/已确认 1 \/ 2 条.*测试中断/);
  failSecond=false;
  assert.deepEqual(await engine.saveActionClips(job.id,1,library,drafts),{library,saved:2});
  assert.equal(durations.length,2);
  assert.ok(Math.abs(durations[0]-1)<.05&&Math.abs(durations[1]-1.5)<.05);
  assert.deepEqual(records.map(record=>record.name),['小Lin说 · 关键词 · 弹幕','小Lin说 · 关键词 · 财富大字']);
  assert.match(records[0].annotation,/文字从右向左滑动[\s\S]*1\.75–2\.75 秒/);
  assert.match(records[1].annotation,/大字淡入[\s\S]*2\.5–4 秒/);
  for(const record of records){
   assert.deepEqual(record.tags,['动效拆解','关键词','文字','小Lin说']);
   assert.equal(record.folderId,'target');
   assert.equal(record.website,job.sourceUrl);
  }
  assert.deepEqual((await engine.store.get(job.id)).selection,job.selection);
 }finally{
  globalThis.fetch=fetchBefore;
  await engine.shutdown();
  await fs.rm(dir,{recursive:true,force:true});
 }
});
