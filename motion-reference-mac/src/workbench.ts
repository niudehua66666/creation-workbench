import {execFile} from 'node:child_process';
import fs from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import {promisify} from 'node:util';
import {publicURL} from './reference-links';
import type {CaptureAction, CaptureTool, InstalledTool, RecorderControls, ToolBookmark} from './types';

const run = promisify(execFile);
const applicationDirectories = ['/Applications', path.join(os.homedir(), 'Applications'), '/System/Applications'];
const captureBundles = ['截录暂存.app', '轻录.app'];
const recorderCommands = {record:'r', screenshot:'c', shelf:'p', settings:'t'} as const;
const recorderSocket = path.join(os.homedir(), 'Library', 'Application Support', 'LightRecorder', 'workbench.sock');

function recorderRequest(command: 's' | typeof recorderCommands[CaptureAction]): Promise<string> {
 return new Promise((resolve, reject) => {
  const socket = net.createConnection(recorderSocket);
  let reply = '';
  socket.setEncoding('utf8');
  socket.setTimeout(1500, () => socket.destroy(new Error('截录暂存响应超时')));
  socket.once('error', reject);
  socket.once('connect', () => socket.write(command));
  socket.on('data', chunk => {
   reply += chunk;
   if (reply.length > 32) {
    socket.destroy(new Error('截录暂存返回的状态无效'));
   } else if (reply.endsWith('\n')) {
    resolve(reply.slice(0,-1));
    socket.destroy();
   }
  });
  socket.once('close', () => reject(new Error('截录暂存连接已关闭')));
 });
}

async function recorderControls(): Promise<RecorderControls | undefined> {
 const [recording, screenshot, shelf] = (await recorderRequest('s')).split(' ');
 if ((recording === 'idle' || recording === 'starting' || recording === 'recording' || recording === 'busy') &&
     (screenshot === '0' || screenshot === '1')) {
  return {recording, canScreenshot: screenshot === '1', unifiedShelf: shelf === 'shelf'};
 }
}

export async function controlRecorder(action: CaptureAction) {
 let reply: string;
 try { reply = await recorderRequest(recorderCommands[action]); }
 catch { throw new Error('无法连接截录暂存。请重新打开工具。'); }
 if (reply === 'invalid') throw new Error('请更新到截录暂存 2.0 或更新版本。');
 if (reply !== 'ok') throw new Error('截录暂存正在处理上一项操作，请稍后重试。');
}

export async function installedTools(): Promise<InstalledTool[]> {
 const directories = await Promise.all(applicationDirectories.map(async directory => {
  const entries = await fs.readdir(directory, {withFileTypes: true}).catch(() => []);
  return entries.filter(entry => entry.name.endsWith('.app') && (entry.isDirectory() || entry.isSymbolicLink()))
   .map(entry => ({name: entry.name.slice(0,-4), path: path.join(directory,entry.name)}));
 }));
 return directories.flat().sort((a,b) => a.name.localeCompare(b.name,'zh-CN'));
}

export async function captureStatus(startMissing = false): Promise<CaptureTool> {
 const [applications, processes] = await Promise.all([
  installedTools(),
  run('/bin/ps', ['-ax', '-o', 'comm='], {maxBuffer: 1024 * 1024}),
 ]);
 const running = new Set(processes.stdout.split('\n').map(line => line.trim()));
 const installed = captureBundles.flatMap(bundle => applications.filter(app => path.basename(app.path) === bundle));
 if (!installed.length) return {status:'missing'};
 if (installed.some(app => running.has(path.join(app.path,'Contents','MacOS','LightRecorder')))) {
  const controls = await recorderControls().catch(() => undefined);
  return {status:'ready', controls};
 }
 if (!startMissing) return {status:'stopped'};
 try {
  await run('/usr/bin/open',['-g','-j','-a',installed[0].path,'--args','--background'],{timeout:8000});
  return {status:'starting'};
 } catch {
  return {status:'stopped'};
 }
}

export class ToolBookmarks {
 private pending: Promise<unknown> = Promise.resolve();

 constructor(private readonly file: string) {}

 private async read(): Promise<ToolBookmark[]> {
  try {
   const entries: unknown = JSON.parse(await fs.readFile(this.file,'utf8'));
   if (!Array.isArray(entries)) throw new Error('工具收藏格式有误');
   return entries;
  } catch (error) {
   if ((error as NodeJS.ErrnoException).code === 'ENOENT') return [];
   throw error;
  }
 }

 async list() {
  await this.pending;
  return this.read();
 }

 private update(change: (items:ToolBookmark[]) => ToolBookmark[]) {
  const write = this.pending.then(async () => {
   const result = change(await this.read());
   await fs.mkdir(path.dirname(this.file),{recursive:true});
   const temporary = this.file + '.tmp';
   await fs.writeFile(temporary,JSON.stringify(result),{mode:0o600});
   await fs.rename(temporary,this.file);
   return result;
  });
  this.pending = write.catch(() => {});
  return write;
 }

 save(rawName: string, rawUrl: string) {
  const url = publicURL(rawUrl);
  const name = rawName.trim().slice(0,100) || new URL(url).hostname;
  return this.update(items => [{name,url}, ...items.filter(item => item.url !== url)]);
 }

 remove(url: string) {
  return this.update(items => items.filter(item => item.url !== url));
 }
}
