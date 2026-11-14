import {spawn} from 'node:child_process';
import path from 'node:path';
export class Cancelled extends Error {constructor(){super('已取消，已完成的成果仍保留');}}
export function run(executable:string,args:string[],opts:{cwd?:string;signal?:AbortSignal;onLine?:(line:string)=>void;env?:NodeJS.ProcessEnv;timeout?:number;detached?:boolean}={}):Promise<{stdout:string;stderr:string}>{
 return new Promise((resolve,reject)=>{
  if(opts.signal?.aborted){reject(new Cancelled());return;}
  const env=opts.env??{...process.env,...(/ffmpeg|ffprobe/.test(path.basename(executable))?{DYLD_LIBRARY_PATH:path.dirname(executable)}:{})};
  const child=spawn(executable,args,{cwd:opts.cwd,env,stdio:['ignore','pipe','pipe'],detached:opts.detached??true});let stdout='',stderr='',tail='',settled=false,timedOut=false,killer:NodeJS.Timeout|undefined;
  const kill=()=>{try{opts.detached===false?child.kill('SIGTERM'):process.kill(-child.pid!,'SIGTERM');}catch{}killer=setTimeout(()=>{try{opts.detached===false?child.kill('SIGKILL'):process.kill(-child.pid!,'SIGKILL');}catch{}},1200);};
  const abort=()=>kill();opts.signal?.addEventListener('abort',abort,{once:true});
  const timeout=setTimeout(()=>{timedOut=true;kill();},opts.timeout??30*60*1000);
  const finish=(error?:Error)=>{if(settled)return;settled=true;clearTimeout(timeout);if(killer)clearTimeout(killer);opts.signal?.removeEventListener('abort',abort);error?reject(error):resolve({stdout,stderr});};
  child.stdout.on('data',b=>{const s=b.toString();stdout=(stdout+s).slice(-8_000_000);tail+=s;const lines=tail.split(/\r?\n/);tail=lines.pop()!;for(const l of lines)opts.onLine?.(l);});
  child.stderr.on('data',b=>{stderr=(stderr+b.toString()).slice(-100_000);});
  child.on('error',finish);child.on('close',(code)=>{if(tail)opts.onLine?.(tail);finish(opts.signal?.aborted?new Cancelled():timedOut?new Error('处理超时，请缩短素材后重试'):code===0?undefined:new Error(stderr.slice(-3000)||stdout.slice(-3000)||`处理程序退出：${code}`));});
 });
}
