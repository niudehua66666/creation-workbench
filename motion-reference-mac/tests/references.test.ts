import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {inspectLinks, searchTarget} from '../src/reference-links';
import {Engine} from '../src/engine';
import type {Job} from '../src/types';

test('share text recognizes multiple platforms, preserves Bilibili parts and strips trailing share punctuation', () => {
 const parsed = inspectLinks([
  '【文献翻页】 https://www.bilibili.com/video/BV1test/?p=2&t=8。',
  'https://www.bilibili.com/video/BV1test?p=2&spm_id_from=abc',
  'https://m.bilibili.com/video/BV1test?p=1',
  '“公开作品” https://v.douyin.com/example/，复制后打开',
  '[主页](https://space.bilibili.com/123/?from=search)',
  'https://channels.weixin.qq.com/watch/example',
  'http://127.0.0.1/local',
 ].join('\n'));
 assert.equal(parsed.links.length,5);
 assert.equal(parsed.repeated,1);
 assert.equal(parsed.invalid,1);
 assert.equal(parsed.links[0].title,'文献翻页');
 assert.equal(parsed.links[0].url,'https://www.bilibili.com/video/BV1test/?p=2&t=8');
 assert.equal(parsed.links[3].account,true);
 assert.equal(parsed.links[3].url,'https://space.bilibili.com/123/?from=search');
 assert.equal(parsed.links[4].platform,'wechat');
 assert.equal(new URL(searchTarget('bilibili','AI & 图表')!).searchParams.get('keyword'),'AI & 图表');
});

test('saving a batch stays local, repeated intake keeps job identity, and only video links are queued', async () => {
 const dir = await fs.mkdtemp(path.join(os.tmpdir(),'motion-references-'));
 const engine = new Engine(dir,path.resolve('.'));
 try {
  await engine.init();
  const downloaded:string[] = [];
  (engine as any).fetchVideo = async (job:Job) => { downloaded.push(job.id); };
  const input = [
   'https://www.douyin.com/video/123456?source=share',
   'https://space.bilibili.com/123',
   'https://channels.weixin.qq.com/watch/example',
  ].join('\n');
  const [saved,duplicate] = await Promise.all([engine.submitLinks(input,'save'),engine.submitLinks(input,'save')]);
  assert.equal(saved.added,3);
  assert.equal(saved.queued,0);
  assert.equal(duplicate.existing,3);
  assert.deepEqual(downloaded,[]);
  assert.deepEqual(duplicate.jobs.map(job=>job.id),saved.jobs.map(job=>job.id));
  const submitted = await engine.submitLinks(input,'queue');
  await engine.wait();
  assert.equal(submitted.queued,1);
  assert.deepEqual(downloaded,[saved.jobs[0].id]);
  assert.equal((await engine.store.get(saved.jobs[1].id)).referenceKind,'account');
  await assert.rejects(engine.action(saved.jobs[2].id,'fetch'), /打开来源/);
  const account = await engine.saveAccount('  测试账号  ','wechat');
  assert.equal((await engine.saveAccount('测试账号','wechat')).id,account.id);
  assert.equal((await engine.store.get(account.id)).searchPlatform,'wechat');
 } finally {
  await engine.shutdown();
  await fs.rm(dir,{recursive:true,force:true});
 }
});
