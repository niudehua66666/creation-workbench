import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {SearchHistory} from '../src/search-history';

test('search history persists across app launches, groups terms by platform and moves repeated searches to the front', async () => {
 const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'motion-search-history-'));
 try {
  const file = path.join(directory, 'search-history.json');
  const history = new SearchHistory(file);
  assert.deepEqual(await history.list(), {douyin: [], bilibili: [], wechat: []});
  await Promise.all([
   history.record('douyin', '  影视剧方  '),
   history.record('bilibili', '其他作者'),
   history.record('douyin', '另一个账号'),
   history.record('wechat', '视频号账号'),
  ]);
  await history.record('douyin', '影视剧方');
  const reopened = new SearchHistory(file);
  assert.deepEqual(await reopened.list(), {
   douyin: ['影视剧方', '另一个账号'],
   bilibili: ['其他作者'],
   wechat: ['视频号账号'],
  });
 } finally {
  await fs.rm(directory, {recursive: true, force: true});
 }
});
