import {execFile} from 'node:child_process';
import {access} from 'node:fs/promises';
import net from 'node:net';
import path from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {promisify} from 'node:util';
import type {TrackpadStatus, KeyboardStatus} from './types';

const run = promisify(execFile);
const states = ['ready', 'locking', 'locked', 'unlocking', 'recovery', 'unavailable'];
type Command = 'status' | 'lock' | 'unlock' | KeyboardCommand;
type KeyboardCommand = 'keyboard-status' | 'keyboard-lock' | 'keyboard-unlock' | 'keyboard-permission' | 'f3-on' | 'f3-off' | 'f4-on' | 'f4-off' | 'f4-permission';

export class TrackpadController {
 private starting?: Promise<TrackpadStatus>;
 private readonly socket: string;

 constructor(private readonly bundles: string[], home: string) {
  this.socket = path.join(home, 'Library', 'Application Support', 'TrackpadLock', 'control.sock');
 }

 private request(command: Command): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
   const socket = net.createConnection(this.socket);
   let body = '';
   const timer = setTimeout(() => socket.destroy(new Error('触控板锁响应超时')), 800);
   socket.setEncoding('utf8');
   socket.once('connect', () => socket.write(command + '\n'));
   socket.once('error', reject);
   socket.once('close', () => {clearTimeout(timer); reject(new Error('触控板锁未返回状态'));});
   socket.on('data', chunk => {
    body += chunk;
    if (body.length > 4096) {socket.destroy(new Error('触控板锁返回的状态无效'));return;}
    const line = body.indexOf('\n');
    if (line === -1) return;
    try {
     const data = JSON.parse(body.slice(0, line)) as Record<string, unknown>;
     if (typeof data.error === 'string') throw new Error(data.error);
     resolve(data);
    } catch (error) { reject(error); }
    finally { socket.destroy(); }
   });
  });
 }

 private async trackpadRequest(command: 'status' | 'lock' | 'unlock'): Promise<TrackpadStatus> {
  const data = await this.request(command);
  if (typeof data.state !== 'string' || !states.includes(data.state) || !(typeof data.shortcut === 'string' || data.shortcut === null) || !(typeof data.warning === 'string' || data.warning === null)) throw new Error('触控板锁返回的状态无效');
  return {state: data.state as TrackpadStatus['state'], shortcut: data.shortcut, warning: data.warning};
 }

 async keyboard(command: KeyboardCommand = 'keyboard-status'): Promise<KeyboardStatus> {
  try {
   if (command !== 'keyboard-status') await this.status();
   return await this.keyboardRequest(command);
  } catch (error) {
   if (command !== 'keyboard-status' || !this.isOffline(error)) throw error;
   await this.status();
   return this.keyboardRequest(command);
  }
 }

 private async keyboardRequest(command: KeyboardCommand): Promise<KeyboardStatus> {
  const data = await this.request(command);
  if (typeof data.state !== 'string' || !states.includes(data.state) || typeof data.external !== 'boolean' || typeof data.permission !== 'boolean' || typeof data.f3 !== 'boolean' || !(typeof data.warning === 'string' || data.warning === null) || !(typeof data.f3Warning === 'string' || data.f3Warning === null)) throw new Error('键盘锁返回的状态无效');
  const f4Supported=data.f4Action === 'force-quit' && typeof data.f4 === 'boolean';
  const f4Warning=typeof data.f4Warning === 'string' ? data.f4Warning : null;
  return {f4Supported,f4Permission:data.f4Permission === true,f4:f4Supported && data.f4 === true,f4Warning,state:data.state as KeyboardStatus['state'], external:data.external, permission:data.permission, warning:data.warning, f3:data.f3, f3Warning:data.f3Warning};
 }

 private async start(): Promise<TrackpadStatus> {
  for (const bundle of this.bundles) {
   if (!await access(path.join(bundle, 'Contents', 'MacOS', 'TrackpadLock')).then(() => true, () => false)) continue;
   try {
    // -j starts the menu bar app without opening or focusing its UI.
    await run('/usr/bin/open', ['-g', '-j', '-a', bundle], {timeout: 3000});
    for (let attempt = 0; attempt < 15; attempt++) {
     try { return await this.trackpadRequest('status'); }
     catch (error) {
      if (!this.isOffline(error)) throw error;
      await delay(100);
     }
    }
   } catch { /* Try the bundled copy if the installed copy did not start. */ }
  }
  throw new Error('未能连接触控板锁，请重新打开工作台后重试');
 }

 private isOffline(error: unknown) {
  const code = (error as NodeJS.ErrnoException).code;
  return code === 'ENOENT' || code === 'ECONNREFUSED';
 }

 async status(): Promise<TrackpadStatus> {
  try { return await this.trackpadRequest('status'); }
  catch (error) {
   if (!this.isOffline(error)) throw error;
   this.starting ??= this.start().finally(() => { this.starting = undefined; });
   return this.starting;
  }
 }

 async setLocked(locked: boolean) {
  await this.status();
  return this.trackpadRequest(locked ? 'lock' : 'unlock');
 }
}
