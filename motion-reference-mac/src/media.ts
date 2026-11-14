import fs from 'node:fs/promises';
import path from 'node:path';
import {run} from './process';
import type {Media} from './types';
export class MediaTools {
 constructor(public ffmpeg:string,public ffprobe:string){}
 async probe(file:string,signal?:AbortSignal):Promise<Media>{const {stdout}=await run(this.ffprobe,['-v','error','-show_format','-show_streams','-of','json',file],{signal,timeout:30_000});const info=JSON.parse(stdout);const v=info.streams.find((s:any)=>s.codec_type==='video');if(!v)throw new Error('文件中没有可读取的视频轨道');const rate=(v.avg_frame_rate||v.r_frame_rate||'30/1').split('/').map(Number);const rotation=Math.abs(Number(v.tags?.rotate??v.side_data_list?.find((s:any)=>s.rotation!==undefined)?.rotation??0));const rotated=rotation%180===90;const duration=Number(info.format.duration??v.duration);if(!Number.isFinite(duration)||duration<=0)throw new Error('无法读取视频时长');return {duration,width:rotated?v.height:v.width,height:rotated?v.width:v.height,fps:Math.min(120,Math.max(1,rate[0]/(rate[1]||1)||30)),audio:info.streams.some((s:any)=>s.codec_type==='audio'),videoCodec:v.codec_name,audioCodec:info.streams.find((s:any)=>s.codec_type==='audio')?.codec_name};}
 async ff(args:string[],duration:number,signal:AbortSignal,onProgress:(done:number,total:number)=>void){await run(this.ffmpeg,['-hide_banner','-loglevel','error','-nostdin','-y',...args,'-progress','pipe:1','-nostats'],{signal,onLine:l=>{if(l.startsWith('out_time_us='))onProgress(Math.min(duration,Number(l.split('=')[1])/1e6),duration);}});}
 async proxy(input:string,out:string,duration:number,signal:AbortSignal,progress:(n:number,t:number)=>void){await this.ff(['-i',input,'-map','0:v:0','-map','0:a?','-vf',"scale=w='min(1280,iw)':h='min(1280,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",'-c:v','libx264','-preset','veryfast','-crf','21','-pix_fmt','yuv420p','-c:a','aac','-movflags','+faststart',out],duration,signal,progress);}
 async clip(input:string,out:string,start:number,end:number,signal:AbortSignal,progress:(n:number,t:number)=>void){await this.ff(['-ss',String(start),'-i',input,'-t',String(end-start),'-map','0:v:0','-map','0:a?','-vf','scale=trunc(iw/2)*2:trunc(ih/2)*2','-c:v','libx264','-preset','veryfast','-crf','17','-pix_fmt','yuv420p','-c:a','aac','-movflags','+faststart',out],end-start,signal,progress);}
 async scenes(input:string,signal:AbortSignal){const {stderr}=await run(this.ffmpeg,['-hide_banner','-nostdin','-i',input,'-an','-vf',"scale=320:-2,select='gt(scene,0.22)',showinfo",'-f','null','-'],{signal});return [...stderr.matchAll(/pts_time:([\d.]+)/g)].map(m=>Number(m[1])).slice(0,200);}
 async overview(input:string,directory:string,duration:number,signal:AbortSignal,progress:(n:number,t:number)=>void){
  const count=Math.min(12,Math.max(2,Math.ceil(duration*2)));const times=Array.from({length:count},(_,i)=>i*(Math.max(0,duration-.05))/(count-1));
  await fs.mkdir(directory,{recursive:true});
  for(let i=0;i<times.length;i++){const t=times[i];await run(this.ffmpeg,['-hide_banner','-loglevel','error','-nostdin','-y','-ss',String(t),'-i',input,'-an','-vf',`scale=400:225:force_original_aspect_ratio=decrease,pad=400:255:(ow-iw)/2:0:color=0x111720,drawtext=fontfile=/System/Library/Fonts/Menlo.ttc:text='t=${t.toFixed(3)} s':x=8:y=232:fontsize=16:fontcolor=white`,'-frames:v','1',path.join(directory,`sample-${String(i+1).padStart(3,'0')}.jpg`)],{signal});progress(i+1,times.length);}
  const page=path.join(directory,'sheet-0.jpg');await run(this.ffmpeg,['-hide_banner','-loglevel','error','-nostdin','-y','-start_number','1','-i',path.join(directory,'sample-%03d.jpg'),'-vf',`tile=4x3:nb_frames=${count}:padding=4:color=0x111720`,'-frames:v','1',page],{signal});return {pages:[page],interval:duration/(count-1)};
 }
 async sceneSamples(input:string,directory:string,cuts:number[],duration:number,signal:AbortSignal,progress:(n:number,t:number)=>void){
  if(!cuts.length)return [];await fs.mkdir(directory,{recursive:true});const chosen=cuts.filter((_,i)=>i%Math.max(1,Math.ceil(cuts.length/8))===0).slice(0,8);
  const times=[...new Set(chosen.flatMap(t=>[Math.max(0,t-.15),Math.min(duration-.05,t+.2),Math.min(duration-.05,t+.7)]))].sort((a,b)=>a-b);
  for(let i=0;i<times.length;i++){const t=times[i];await run(this.ffmpeg,['-hide_banner','-loglevel','error','-nostdin','-y','-ss',String(t),'-i',input,'-an','-vf',`scale=400:225:force_original_aspect_ratio=decrease,pad=400:255:(ow-iw)/2:0:color=0x111720,drawtext=fontfile=/System/Library/Fonts/Menlo.ttc:text='cut  t=${t.toFixed(3)} s':x=8:y=232:fontsize=16:fontcolor=white`,'-frames:v','1',path.join(directory,`cut-${String(i+1).padStart(3,'0')}.jpg`)],{signal});progress(i+1,times.length);}
  const pages:string[]=[];for(let offset=0;offset<times.length;offset+=12){const file=path.join(directory,`sheet-${offset/12}.jpg`);await run(this.ffmpeg,['-hide_banner','-loglevel','error','-nostdin','-y','-start_number',String(offset+1),'-i',path.join(directory,'cut-%03d.jpg'),'-vf',`tile=4x3:nb_frames=${Math.min(12,times.length-offset)}:padding=4:color=0x111720`,'-frames:v','1',file],{signal});pages.push(file);}return pages;
 }
 async frames(input:string,directory:string,duration:number,dense:boolean,signal:AbortSignal,progress:(n:number,t:number)=>void,maxFrames=96){
  await fs.mkdir(directory,{recursive:true});const interval=dense?Math.max(.1,duration/maxFrames):Math.max(.5,duration/48);const framePattern=path.join(directory,'frame-%04d.jpg');
  const expected=Math.max(1,Math.round(duration/interval));
  await run(this.ffmpeg,['-hide_banner','-loglevel','error','-nostdin','-y','-i',input,'-an','-vf',`fps=1/${interval},scale=480:-2`,'-q:v','3',framePattern,'-progress','pipe:1','-nostats'],{signal,onLine:l=>{if(l.startsWith('frame='))progress(Number(l.split('=')[1]),expected);}});
  const files=(await fs.readdir(directory)).filter(n=>/^frame-\d+\.jpg$/.test(n)).sort();const pages:string[]=[];
  // Label each tile with a frame-derived local timestamp before making contact sheets.
  const font='/System/Library/Fonts/Menlo.ttc';
  for(let offset=0;offset<files.length;offset+=12){
   const count=Math.min(12,files.length-offset);const sheet=path.join(directory,`sheet-${Math.floor(offset/12)}.jpg`);
   const filter=`setpts=PTS+${offset*interval}/TB,scale=400:225:force_original_aspect_ratio=decrease,pad=400:255:(ow-iw)/2:0:color=0x111720,drawtext=fontfile='${font}':text='%{eif\\:n+${offset}\\:d}  t=%{pts\\:flt} s':x=8:y=232:fontsize=16:fontcolor=white,tile=4x3:nb_frames=${count}:padding=4:color=0x111720`;
   await run(this.ffmpeg,['-hide_banner','-loglevel','error','-nostdin','-y','-framerate',String(1/interval),'-start_number',String(offset+1),'-i',framePattern,'-vf',filter,'-frames:v','1',sheet],{signal});pages.push(sheet);
  }
  progress(files.length,files.length);return {pages,files:files.map(n=>path.join(directory,n)),interval,times:files.map((_,i)=>+(i*interval).toFixed(3))};
 }
 async waveform(input:string,directory:string,audio:boolean,signal:AbortSignal){if(!audio)return [];const pcm=path.join(directory,'waveform.pcm');await run(this.ffmpeg,['-hide_banner','-loglevel','error','-y','-nostdin','-i',input,'-vn','-ac','1','-ar','4000','-f','s16le',pcm],{signal});const b=await fs.readFile(pcm);const count=Math.floor(b.length/2);const bins=Math.min(600,count);const values:number[]=[];for(let n=0;n<bins;n++){const a=Math.floor(n*count/bins),z=Math.floor((n+1)*count/bins);let sum=0;for(let i=a;i<z;i++){const v=b.readInt16LE(i*2)/32768;sum+=v*v;}values.push(Math.sqrt(sum/Math.max(1,z-a)));}await fs.unlink(pcm);const max=Math.max(.001,...values);return values.map(v=>v/max);}
}
