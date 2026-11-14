import test from 'node:test';
import assert from 'node:assert/strict';
import {run} from '../src/process';
import {CodexClient} from '../src/codex';
import {MediaTools} from '../src/media';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

test('timed-out subprocess cannot report success after handling TERM',async()=>{
 await assert.rejects(run(process.execPath,['-e',"process.on('SIGTERM',()=>process.exit(0));setInterval(()=>{},100)"],{timeout:500}),/超时/);
});
test('missing Codex gives install guidance without hanging',async()=>{
 const c=new CodexClient('/nonexistent/workbench-test-codex');
 try{await assert.rejects(c.connect(),/未找到 Codex/);}finally{c.close();}
});
test('short videos and repeated frame extraction produce usable current frames',async()=>{
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'workbench-media-'));
 const media=new MediaTools(path.resolve('runtime/bin/ffmpeg'),path.resolve('runtime/bin/ffprobe'));
 const signal=new AbortController().signal;
 try{
  const input=path.join(dir,'short.mp4');
  await run(media.ffmpeg,['-v','error','-f','lavfi','-i','testsrc2=size=320x180:rate=30:duration=0.2','-c:v','libx264',input]);
  const target=path.join(dir,'frames');
  await fs.mkdir(target);await fs.writeFile(path.join(target,'frame-9999.jpg'),'stale');
  const result=await media.frames(input,target,.2,false,signal,()=>{});
  assert.ok(result.files.length>=1);assert.ok(result.pages.length>=1);
  assert.ok(!result.files.some(p=>p.endsWith('9999.jpg')));
 }finally{await fs.rm(dir,{recursive:true,force:true});}
});
