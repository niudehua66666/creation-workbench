import {randomUUID,createHash} from 'node:crypto';
import fs from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import path from 'node:path';
import type {Job,Metrics,Media,Candidate} from './types';
import {segmentCategories} from './motion-categories';

export const freshMetrics=():Metrics=>({views:null,likes:null,published:'',captured:'',scope:'未知',traffic:'未知',source:''});
export function newJob(title:string,url=''):Job {const now=Date.now(); return {id:randomUUID(),title,sourceUrl:url,author:'',createdAt:now,metrics:freshMetrics(),candidates:[],waveform:[],markers:[],logs:[],progress:{stage:'读取视频',state:'idle',detail:'等待导入',startedAt:now,stageAt:now,updatedAt:now}};}
export function validRange(start:unknown,end:unknown,duration:number){
 if(typeof start!=='number'||typeof end!=='number'||!Number.isFinite(start)||!Number.isFinite(end)||start<0||end>duration+.01||end<=start||end-start>30+1e-9)throw new Error('请选择视频内 0.2～30 秒的片段');
 if(end-start<.2-1e-9)throw new Error('片段至少需要 0.2 秒');
 return {start,end:Math.min(end,duration)};
}
export function safeRelative(root:string,relative:string){
 if(typeof relative!=='string'||!relative||relative.includes('\0')||path.isAbsolute(relative))throw new Error('无效资源路径');
 const resolved=path.resolve(root,relative);
 if(!resolved.startsWith(path.resolve(root)+path.sep))throw new Error('资源路径超出任务目录');
 return resolved;
}
export {publicURL} from './reference-links';
export function normalizedCandidates(items:Candidate[],media:Media):Candidate[]{
 return items.flatMap(c=>{
  try{
   const range=validRange(Number(c.start),Number(c.end),media.duration);
   return [{...range,title:String(c.title).slice(0,120),reason:String(c.reason).slice(0,1000),confidence:c.confidence,categories:segmentCategories(c)}];
  }catch{return [];}
 }).slice(0,5);
}
export async function hashFile(p:string){const h=createHash('sha256');for await(const chunk of createReadStream(p))h.update(chunk);return h.digest('hex');}
export class Store {
 constructor(public root:string){}
 dir(id:string){if(!/^[0-9a-f-]{36}$/i.test(id))throw new Error('无效任务');return path.join(this.root,'jobs',id);}
 async init(){await fs.mkdir(path.join(this.root,'jobs'),{recursive:true});for(const j of await this.list()){let changed=false;if(['running','queued'].includes(j.progress.state)){j.progress.state='interrupted';j.progress.detail='上次任务已保留，点击继续处理可重新加入队列';j.progress.queuePosition=undefined;changed=true;}if(!j.progress.finishedAt&&j.progress.state!=='idle'){j.progress.finishedAt=j.outputVersion&&j.outputVersion>1e12?j.outputVersion:j.progress.updatedAt;changed=true;}if(changed)await this.save(j);}}
 async save(job:Job){const d=this.dir(job.id);await fs.mkdir(d,{recursive:true});const target=path.join(d,'job.json');const tmp=target+'.'+randomUUID()+'.tmp';await fs.writeFile(tmp,JSON.stringify(job,null,2));await fs.rename(tmp,target);}
 async get(id:string):Promise<Job>{return JSON.parse(await fs.readFile(path.join(this.dir(id),'job.json'),'utf8'));}
 async list():Promise<Job[]>{const dirs=await fs.readdir(path.join(this.root,'jobs')).catch(()=>[]);const all=await Promise.all(dirs.map(id=>this.get(id).catch(()=>null)));return all.filter((j):j is Job=>j!==null).sort((a,b)=>b.createdAt-a.createdAt);}
}
