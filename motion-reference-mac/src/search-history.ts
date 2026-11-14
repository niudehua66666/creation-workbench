import fs from 'node:fs/promises';
import path from 'node:path';
import {platformNames, type SearchPlatform} from './reference-links';
import type {SearchHistoryEntries} from './types';

export class SearchHistory {
 private writes: Promise<unknown> = Promise.resolve();

 constructor(private readonly file: string) {}

 private async read(): Promise<SearchHistoryEntries> {
  let raw: Partial<SearchHistoryEntries>;
  try {
   raw = JSON.parse(await fs.readFile(this.file, 'utf8')) ?? {};
  } catch (error) {
   if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
   raw = {};
  }
  return {
   douyin: Array.isArray(raw.douyin) ? raw.douyin.filter(term => typeof term === 'string') : [],
   bilibili: Array.isArray(raw.bilibili) ? raw.bilibili.filter(term => typeof term === 'string') : [],
   wechat: Array.isArray(raw.wechat) ? raw.wechat.filter(term => typeof term === 'string') : [],
  };
 }

 async list() {
  await this.writes;
  return this.read();
 }

 async record(platform: SearchPlatform, keyword: string) {
  const term = keyword.trim().slice(0, 120);
  if (!Object.hasOwn(platformNames, platform) || !term) throw new Error('请选择平台并输入关键词');
  const write = this.writes.then(async () => {
   const entries = await this.read();
   entries[platform] = [term, ...entries[platform].filter(previous => previous.toLowerCase() !== term.toLowerCase())];
   await fs.mkdir(path.dirname(this.file), {recursive: true});
   const temporary = this.file + '.tmp';
   await fs.writeFile(temporary, JSON.stringify(entries), {mode: 0o600});
   await fs.rename(temporary, this.file);
   return entries;
  });
  this.writes = write.catch(() => {});
  return write;
 }
}
