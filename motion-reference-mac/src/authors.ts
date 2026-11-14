import fs from 'node:fs/promises';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import type {Store} from './core';

export class Authors {
 private queue:Promise<unknown>=Promise.resolve();
 constructor(private store:Store){}
 async list(){const saved:string[]=await fs.readFile(path.join(this.store.root,'authors.json'),'utf8').then(JSON.parse).catch(()=>[]);const jobs=await this.store.list();return [...new Set(['影视飓风',...saved,...jobs.map(j=>j.author)].filter(n=>typeof n==='string'&&n.trim()).map(n=>n.trim()))].sort((a,b)=>a.localeCompare(b,'zh-CN'));}
 add(value:string):Promise<string[]>{const name=String(value??'').trim();if(!name||name.length>100)return Promise.reject(new Error('作者名称应为 1～100 个字'));const task=this.queue.catch(()=>{}).then(async()=>{const names=[...new Set([...await this.list(),name])];const file=path.join(this.store.root,'authors.json'),tmp=file+'.'+randomUUID()+'.tmp';await fs.writeFile(tmp,JSON.stringify(names,null,2));await fs.rename(tmp,file);return this.list();});this.queue=task;return task;}
}
