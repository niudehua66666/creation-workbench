import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {Engine} from '../src/engine';
import {newJob,validRange} from '../src/core';
import {adjustRange} from '../src/range';
import {run} from '../src/process';
import type {Job} from '../src/types';
const waitFor=async(fn:()=>boolean)=>{const end=Date.now()+5000;while(!fn()){if(Date.now()>end)throw new Error('timeout');await new Promise(r=>setTimeout(r,5));}};
const job=async(e:Engine,title:string)=>{const j=newJob(title);j.media={duration:2,width:320,height:180,fps:24,audio:false};j.selection={start:0,end:1};j.classification={primary:'通屏',secondary:[],reason:'test',note:'',authorEvidence:'',authorSource:'手工填写',confirmedAt:1};await e.store.save(j);return j;};

test('queue is FIFO, can cancel waiting/running work, continues after failure, and other material can be edited/exported',async()=>{
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'motion-queue-'));const e=new Engine(path.join(dir,'data'),path.resolve('.'));await e.init();
 try{
  const a=await job(e,'a'),b=await job(e,'b'),c=await job(e,'c'),d=await job(e,'d'),local=await job(e,'local');
  let concurrent=0,max=0;const started:string[]=[];
  (e as any).quickBrief=async(j:Job,signal:AbortSignal)=>{concurrent++;max=Math.max(max,concurrent);started.push(j.title);try{if(j.title==='a')await new Promise((_,reject)=>signal.addEventListener('abort',()=>reject(new Error('abort')),{once:true}));if(j.title==='c')throw new Error('deliberate failure');}finally{concurrent--;}};
  await e.action(a.id,'brief');await waitFor(()=>started.length===1);
  await Promise.all([e.action(b.id,'brief'),e.action(c.id,'brief'),e.action(d.id,'brief')]);
  const ordered=(await e.store.list()).filter(j=>j.progress.state==='queued').sort((x,y)=>x.progress.queuePosition!-y.progress.queuePosition!);
  // Concurrent IPC scheduling can finish reads in either order; queuePosition is the accepted order.
  assert.equal(ordered.length,3);assert.deepEqual(ordered.map(j=>j.progress.queuePosition),[1,2,3]);
  await assert.rejects(e.action(a.id,'selection',{start:.2,end:.7}),/正在处理或排队/);
  await assert.rejects(e.action(b.id,'brief'),/正在处理或排队/);
  await e.action(local.id,'classification',{primary:'图表',author:'排队期间新增作者',note:'可以继续整理'});
  local.sourceFile='source.mp4';local.sha256='test';const file=path.join(e.store.dir(local.id),'source.mp4');
  await run(e.media.ffmpeg,['-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=320x180:rate=24:duration=2','-c:v','libx264','-pix_fmt','yuv420p',file]);
  await e.store.save({...await e.store.get(local.id),sourceFile:local.sourceFile,sha256:local.sha256});
  const destination=path.join(dir,'local-export');await e.exportEditing(local.id,destination);
  assert.equal((await e.store.get(a.id)).progress.state,'running');assert.ok((await fs.stat(path.join(destination,'参考片段.mp4'))).size>0);
  await e.cancel(b.id);assert.equal((await e.store.get(b.id)).progress.state,'cancelled');await e.cancel(a.id);await e.wait();
  assert.equal(max,1);assert.deepEqual(started,['a',...ordered.filter(j=>j.id!==b.id).map(j=>j.title)]);
  assert.equal((await e.store.get(a.id)).progress.state,'cancelled');assert.equal((await e.store.get(c.id)).progress.state,'failed');assert.equal((await e.store.get(d.id)).progress.state,'ready');
  assert.equal((await e.store.get(local.id)).author,'排队期间新增作者');
 }finally{await e.shutdown();await fs.rm(dir,{recursive:true,force:true});}
});

test('shutdown preserves waiting and running actions/ranges and restart allows explicit resumption',async()=>{
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'motion-restart-'));const e=new Engine(dir,path.resolve('.'));await e.init();
 try{
  const a=await job(e,'active'),b=await job(e,'waiting');let started=false;
  (e as any).quickBrief=async(_j:Job,signal:AbortSignal)=>{started=true;await new Promise((_,reject)=>signal.addEventListener('abort',()=>reject(new Error('abort')),{once:true}));};
  await e.action(a.id,'brief');await waitFor(()=>started);await e.action(b.id,'brief',{start:.3,end:1.2});await e.shutdown();
  const restored=new Engine(dir,path.resolve('.'));await restored.init();
  for(const id of [a.id,b.id]){const j=await restored.store.get(id);assert.equal(j.progress.state,'interrupted');assert.equal(j.pendingAction,'brief');}
  assert.deepEqual((await restored.store.get(b.id)).selection,{start:.3,end:1.2});
  let calls=0;(restored as any).quickBrief=async()=>{calls++;};await restored.action(b.id,'retry');await restored.wait();assert.equal(calls,1);assert.equal((await restored.store.get(b.id)).progress.state,'ready');await restored.shutdown();
 }finally{await e.shutdown();await fs.rm(dir,{recursive:true,force:true});}
});

test('timeline handles and I/O placement keep valid ranges at boundaries and for long, short, fractional-fps clips',()=>{
 for(const duration of [.2,.205,1,9.976,60,3600])for(const edge of ['start','end'] as const)for(const value of [-3,0,.1,.2,1,29.9,60,duration,duration+1]){
  const r=adjustRange({start:0,end:Math.min(8,duration)},edge,value,duration);
  assert.ok(r.start>=0&&r.end<=duration);assert.ok(r.end-r.start>=.2-1e-9&&r.end-r.start<=30+1e-9);validRange(r.start,r.end,duration);
 }
 assert.deepEqual(adjustRange({start:0,end:5},'start',10,20),{start:10,end:10.2});
 assert.deepEqual(adjustRange({start:50,end:55},'end',10,100),{start:9.8,end:10});
});
