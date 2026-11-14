import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {Store,newJob,validRange,normalizedCandidates,publicURL,safeRelative,hashFile} from '../src/core';
import {validateScene} from '../src/template';
import {run} from '../src/process';
import {Engine} from '../src/engine';
import {CodexClient} from '../src/codex';

const root=path.resolve('.');
const temp=()=>fs.mkdtemp(path.join(os.tmpdir(),'motion-test-'));
test('seconds-based range is independent of frame rate and rejects invalid intervals',()=>{
 assert.deepEqual(validRange(5,10,12),{start:5,end:10});
 for(const r of [[-1,3],[4,3],[0,31],[0,Infinity],[9,13],[1,1.1]])assert.throws(()=>validRange(r[0],r[1],12));
 const item={start:5,end:10,title:'测试',reason:'连续帧',category:'图表',confidence:'高'};
 assert.equal(normalizedCandidates(Array(9).fill(item),{duration:12,width:720,height:1280,fps:23.976,audio:false}).length,5);
});
test('path and URL boundaries reject traversal and private URL literals',()=>{
 assert.equal(publicURL('分享 https://www.bilibili.com/video/BV123 测试'),'https://www.bilibili.com/video/BV123');
 for(const u of ['file:///etc/passwd','http://127.0.0.1/a','http://localhost/a','http://[::1]/'])assert.throws(()=>publicURL(u));
 for(const p of ['../secret','/etc/passwd','foo/../../bar'])assert.throws(()=>safeRelative('/tmp/job',p));
});
test('restart retains results, unknown metrics, and retry action',async()=>{
 const dir=await temp();const store=new Store(dir);await store.init();const j=newJob('恢复测试');j.pendingAction='generate';j.progress.state='running';j.props={durationSeconds:5};await store.save(j);await new Store(dir).init();const saved=await store.get(j.id);assert.equal(saved.progress.state,'interrupted');assert.equal(saved.pendingAction,'generate');assert.equal(saved.metrics.views,null);assert.equal(saved.props?.durationSeconds,5);
 await fs.rm(dir,{recursive:true});
});
test('generated scene validator rejects original-video embedding and privileged access',()=>{
 validateScene("import React from 'react';export const Scene=(props:any)=><div>{props.title}</div>");
 for(const bad of ["import fs from 'node:fs';export const Scene=()=>null",'export const Scene=()=> <video src="source.mp4"/>','export const Scene=()=>{fetch("x");return null}','export const Scene=()=> import("x")'])assert.throws(()=>validateScene(bad));
});
test('cancelling a real subprocess is prompt and reported as cancellation',async()=>{
 const controller=new AbortController();const pending=run(process.execPath,['-e','setInterval(()=>{},1000)'],{signal:controller.signal});setTimeout(()=>controller.abort(),50);await assert.rejects(pending,/已取消/);
});
test('corrupt video fails without a fake successful output or damaging source',async()=>{
 const dir=await temp();const input=path.join(dir,'broken.mp4');await fs.writeFile(input,'not a video');const before=await hashFile(input);const e=new Engine(path.join(dir,'data'),root);await e.init();const j=await e.importVideo(input);await e.wait();const saved=await e.store.get(j.id);assert.equal(saved.progress.state,'failed');assert.equal(saved.outputVersion,undefined);assert.equal(await hashFile(input),before);await fs.rm(dir,{recursive:true});
});
test('Eagle unavailable returns an actionable error and preserves the preview',async()=>{
 const dir=await temp();const e=new Engine(dir,root);await e.init();const j=newJob('test');j.outputVersion=1;j.props={durationSeconds:4};j.renderedProps=JSON.stringify(j.props);await e.store.save(j);const fetchBefore=globalThis.fetch;globalThis.fetch=async()=>{throw new Error('ECONNREFUSED');};try{await assert.rejects(e.eagle(j),/Eagle 未运行/);assert.equal((await e.store.get(j.id)).outputVersion,1);}finally{globalThis.fetch=fetchBefore;await fs.rm(dir,{recursive:true});}
});
test('classification and author are stored before generating, with only the existing nine categories',async()=>{
 const dir=await temp();const e=new Engine(dir,root);await e.init();const j=newJob('分类测试');j.media={duration:10,width:1920,height:1080,fps:30,audio:false};await e.store.save(j);
 await assert.rejects(e.action(j.id,'generate',{start:5,end:10}),/分类与作者/);
 await assert.rejects(e.action(j.id,'classification',{primary:'其他动效',author:'测试作者'}),/已有九类/);
 await e.action(j.id,'classification',{primary:'文献',secondary:['关键词','关键词','文献','任意值'],author:'测试作者',note:'报告页倾斜进入，结论高亮',sourceUrl:'https://www.bilibili.com/video/BVtest'});
 await new Store(dir).init();const saved=await e.store.get(j.id);assert.equal(saved.author,'测试作者');assert.equal(saved.classification?.primary,'文献');assert.deepEqual(saved.classification?.secondary,['关键词']);assert.ok(saved.classification?.confirmedAt);assert.equal(saved.classification?.authorSource,'手工填写');assert.equal(saved.classification?.note,'报告页倾斜进入，结论高亮');
 await fs.rm(dir,{recursive:true});
});
test('Eagle asynchronous indexing is awaited and concurrent saves do not duplicate an item',async()=>{
 const dir=await temp(),e=new Engine(dir,root);await e.init();const j=newJob('Eagle 测试');j.outputVersion=1;j.props={durationSeconds:4};j.renderedProps=JSON.stringify(j.props);j.progress.finishedAt=1234;await e.store.save(j);
 const project=path.join(e.store.dir(j.id),'project');await fs.mkdir(project,{recursive:true});await fs.writeFile(path.join(project,'source.json'),'{}');await fs.writeFile(path.join(project,'props.json'),JSON.stringify(j.props));
 let count=0,reads=0,record:any;const original=globalThis.fetch;
 globalThis.fetch=async(url,init)=>{const route=String(url).split('/api/')[1];let data:any;
  if(route==='library/info')data={library:{path:'/test/library'}};
  else if(route==='folder/list')data=[{id:'folder',name:'动效拆解'}];
  else if(route==='item/addFromPath'){count++;record={id:'item',...JSON.parse(String(init?.body))};data='item';}
  else if(route.startsWith('item/list')){reads++;data=record&&reads>=3?[record]:[];}
  else throw new Error('unexpected '+route);
  return new Response(JSON.stringify({status:'success',data}),{headers:{'Content-Type':'application/json'}});
 };
 try{await Promise.all([e.eagle(j),e.eagle(j)]);assert.equal(count,1);assert.equal((await e.store.get(j.id)).eagle?.itemId,'item');assert.equal((await e.store.get(j.id)).progress.finishedAt,1234);assert.ok(record.annotation.includes('/eagle-exports/1/project'));}finally{globalThis.fetch=original;await fs.rm(dir,{recursive:true});}
});
test('missing login and exhausted quota surface distinct Codex errors',async()=>{
 const dir=await temp();const mock=path.join(dir,'mock-codex');
 const create=async(signedIn:boolean)=>fs.writeFile(mock,`#!${process.execPath}\nconst readline=require('node:readline');readline.createInterface({input:process.stdin}).on('line',l=>{const m=JSON.parse(l);if(!m.id)return;let result={};if(m.method==='account/read')result={account:${signedIn?'{type:"chatgpt"}':'null'}};if(m.method==='thread/start')result={thread:{id:'test'}};if(m.method==='turn/start'){console.log(JSON.stringify({id:m.id,error:{message:'usage limit reached'}}));return;}console.log(JSON.stringify({id:m.id,result}));});`,{mode:0o755});
 for(const signedIn of [false,true]){await create(signedIn);const c=new CodexClient(mock);try{await c.connect();await assert.rejects(c.complete({cwd:dir,prompt:'test',images:[],schema:{},signal:new AbortController().signal,onStatus:()=>{}}),signedIn?/usage limit/:/尚未登录/);}finally{c.close();}}
 await fs.rm(dir,{recursive:true});
});
